extends Node

## SceneManager — autoload singleton (name it "SceneManager" in Project > Autoload).
##
## Responsibilities:
##   - Holds all persistent game state (day, kills, bounties, flags)
##   - Drives scene transitions with a loading screen
##   - Launches end-of-day and chronicle Python pipelines as subprocesses
##   - Polls for pipeline completion and handles crash/timeout gracefully
##
## Pipeline modes:
##   "eod"       end_of_day.py  -- triggered by end_day()
##   "chronicle" chronicle.py   -- triggered by trigger_chronicle() (Ctrl+R in town)


# ── Game State ────────────────────────────────────────────────────────────────

var day             : int    = 1
var player_name     : String = "Hunter"

var monsters_killed_today   : Dictionary        = {}
var monsters_killed_history : Array[Dictionary] = []
var active_bounties         : Array             = []

var flags : Dictionary = {
	"met_mira":                 false,
	"met_aldric":               false,
	"met_gareth":               false,
	"first_bounty_accepted":    false,
	"first_bounty_completed":   false,
	"player_slept_at_inn":      false,
	"aldric_warned_about_east": false,
}


# ── Scene Paths ───────────────────────────────────────────────────────────────

const FIELD_SCENE := "res://world/field.tscn"
const TOWN_SCENE  := "res://world/town.tscn"

const AREA_NAMES : Dictionary = {
	FIELD_SCENE: "The Ashfield",
	TOWN_SCENE:  "Thornwall",
}


# ── Pipeline Config ───────────────────────────────────────────────────────────

const POLL_INTERVAL    : float  = 3.0
const PIPELINE_TIMEOUT : float  = 180.0
const PYTHON_EXE       : String = "python3"

const PIPELINE_SCRIPTS : Dictionary = {
	"eod":       "pipeline/end_of_day.py",
	"chronicle": "pipeline/chronicle.py",
}

const PIPELINE_FLAGS : Dictionary = {
	"eod": {
		"ready":   "pipeline_ready.flag",
		"failed":  "pipeline_failed.flag",
		"crashed": "pipeline_crashed.flag",
	},
	"chronicle": {
		"ready":   "pipeline_chronicle_ready.flag",
		"failed":  "pipeline_chronicle_failed.flag",
		"crashed": "pipeline_chronicle_crashed.flag",
	},
}

const PIPELINE_OVERLAY_TEXT : Dictionary = {
	"eod":       "The night passes",
	"chronicle": "The guild scribes are at work",
}


# ── Internal State ────────────────────────────────────────────────────────────

var _loading_packed  := preload("res://ui/loading_screen.tscn")
var _transitioning   := false

var _pipeline_mode    : String = ""
var _pipeline_pid     : int    = -1
var _poll_elapsed     : float  = 0.0
var _timeout_elapsed  : float  = 0.0
var _pipeline_running : bool   = false

var _dot_timer   : float  = 0.0
var _dot_count   : int    = 0
var _base_text   : String = ""

var _overlay       : CanvasLayer = null
var _overlay_label : Label       = null

var _project_path : String = ""


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_project_path = ProjectSettings.globalize_path("res://")
	set_process(false)


func _process(delta: float) -> void:
	if not _pipeline_running:
		return

	_poll_elapsed    += delta
	_timeout_elapsed += delta
	_dot_timer       += delta

	if _dot_timer >= 0.5:
		_dot_timer = 0.0
		_dot_count = (_dot_count + 1) % 4
		if _overlay_label:
			_overlay_label.text = _base_text + ".".repeat(_dot_count)

	if _timeout_elapsed >= PIPELINE_TIMEOUT:
		_on_pipeline_result(
			"crashed",
			"Pipeline timed out after %d seconds." % int(PIPELINE_TIMEOUT)
		)
		return

	if _poll_elapsed >= POLL_INTERVAL:
		_poll_elapsed = 0.0
		_check_flags()


# ── Public API ────────────────────────────────────────────────────────────────

func go_to_field() -> void:
	_transition_to(FIELD_SCENE)


func go_to_town() -> void:
	_transition_to(TOWN_SCENE)


func record_kill(monster_type: String) -> void:
	monsters_killed_today[monster_type] = \
		monsters_killed_today.get(monster_type, 0) + 1


func set_flag(key: String, value: bool) -> void:
	flags[key] = value


func get_flag(key: String) -> bool:
	return flags.get(key, false)


# ── End Day ───────────────────────────────────────────────────────────────────

func end_day() -> void:
	monsters_killed_history.append(monsters_killed_today.duplicate())
	monsters_killed_today.clear()
	day += 1
	_expire_bounties()
	_write_game_state()
	_start_pipeline("eod")


# ── Chronicle Trigger ─────────────────────────────────────────────────────────

## Called from town.gd on Ctrl+R.
## Generates the weekly chronicle and rumor list without advancing the day.
## Player stays in town after completion.
func trigger_chronicle() -> void:
	if _pipeline_running:
		push_warning("SceneManager: pipeline already running -- ignoring chronicle trigger.")
		return
	_write_game_state()
	_start_pipeline("chronicle")


# ── Bounty expiry ─────────────────────────────────────────────────────────────

func _expire_bounties() -> void:
	active_bounties = active_bounties.filter(
		func(b): return not (b.get("day_expires", INF) < day)
	)


# ── Game state serialisation ──────────────────────────────────────────────────

func _write_game_state() -> void:
	var path := _project_path + "game_state.json"

	# Preserve pipeline-owned fields (npc_facts)
	var npc_facts : Dictionary = {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file:
		var parser := JSON.new()
		if parser.parse(file.get_as_text()) == OK:
			npc_facts = parser.get_data().get("npc_facts", {})
		file.close()

	var state : Dictionary = {
		"meta": {
			"schema_version": "1.0",
			"day":            day,
		},
		"player_name":  player_name,
		"world_state":  {
			"monsters_killed_today":   monsters_killed_today,
			"monsters_killed_history": monsters_killed_history,
		},
		"active_bounties": active_bounties,
		"flags":           flags,
		"npc_facts":       npc_facts,
	}

	var out := FileAccess.open(path, FileAccess.WRITE)
	if out:
		out.store_string(JSON.stringify(state, "\t"))
		out.close()
		print("SceneManager: game_state.json written (day %d)" % day)
	else:
		push_error("SceneManager: could not write game_state.json")


# ── Pipeline launch ───────────────────────────────────────────────────────────

func _start_pipeline(mode: String) -> void:
	_pipeline_mode = mode
	_base_text     = PIPELINE_OVERLAY_TEXT.get(mode, "Working")
	_clear_flags(mode)
	_show_overlay(_base_text)
	_launch_pipeline(mode)


func _launch_pipeline(mode: String) -> void:
	var script        :String= _project_path + PIPELINE_SCRIPTS[mode]
	_pipeline_pid      = OS.create_process(PYTHON_EXE, [script])
	_pipeline_running  = true
	_poll_elapsed      = 0.0
	_timeout_elapsed   = 0.0
	_dot_timer         = 0.0
	_dot_count         = 0
	set_process(true)
	print("SceneManager: %s pipeline launched (pid %d)" % [mode, _pipeline_pid])


# ── Flag file helpers ─────────────────────────────────────────────────────────

func _flag_path(name: String) -> String:
	return _project_path + name


func _clear_flags(mode: String) -> void:
	var names : Dictionary = PIPELINE_FLAGS.get(mode, {})
	for key in names:
		var path := _flag_path(names[key])
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _check_flags() -> void:
	var names : Dictionary = PIPELINE_FLAGS.get(_pipeline_mode, {})
	if FileAccess.file_exists(_flag_path(names.get("ready", ""))):
		_on_pipeline_result("ready", "")
	elif FileAccess.file_exists(_flag_path(names.get("failed", ""))):
		_on_pipeline_result("failed", _read_flag(names.get("failed", "")))
	elif FileAccess.file_exists(_flag_path(names.get("crashed", ""))):
		_on_pipeline_result("crashed", _read_flag(names.get("crashed", "")))


func _read_flag(name: String) -> String:
	var f := FileAccess.open(_flag_path(name), FileAccess.READ)
	if f:
		var text := f.get_as_text()
		f.close()
		return text
	return ""


# ── Pipeline result handler ───────────────────────────────────────────────────

func _on_pipeline_result(status: String, message: String) -> void:
	_pipeline_running = false
	set_process(false)

	match status:
		"ready", "failed":
			if status == "failed":
				print("SceneManager: pipeline finished with warnings: ", message)
			else:
				print("SceneManager: %s pipeline complete." % _pipeline_mode)
			_dismiss_overlay()
			_reload_all_dialogue()
			if _pipeline_mode == "eod":
				go_to_town()
			# Chronicle: overlay dismissed, player stays in town.

		"crashed":
			push_error("SceneManager: pipeline crashed -- " + message)
			_show_crash_message(message)


# ── Overlay ───────────────────────────────────────────────────────────────────

func _show_overlay(message: String) -> void:
	_overlay       = CanvasLayer.new()
	_overlay.layer = 200
	get_tree().root.add_child(_overlay)

	var bg     := ColorRect.new()
	bg.color    = Color(0.0, 0.0, 0.0, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(bg)

	_overlay_label                      = Label.new()
	_overlay_label.set_anchors_preset(Control.PRESET_CENTER)
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_overlay_label.text                 = message
	_overlay_label.add_theme_font_size_override("font_size", 48)

	var font_path := "res://fonts/almendra.regular.ttf"
	if ResourceLoader.exists(font_path):
		_overlay_label.add_theme_font_override("font", load(font_path))

	_overlay.add_child(_overlay_label)


func _dismiss_overlay() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay       = null
		_overlay_label = null


func _show_crash_message(_message: String) -> void:
	if _overlay_label:
		_overlay_label.text = (
			"Something went wrong preparing the next day.\n"
			+ "The world continues as it was.\n\n"
			+ "[Press any key to continue]"
		)
		_overlay_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))

	await _wait_for_keypress()
	_dismiss_overlay()
	_reload_all_dialogue()
	if _pipeline_mode == "eod":
		go_to_town()


func _wait_for_keypress() -> void:
	while true:
		await get_tree().process_frame
		if Input.is_anything_pressed():
			break


# ── Dialogue reload ───────────────────────────────────────────────────────────

func _reload_all_dialogue() -> void:
	for npc in get_tree().get_nodes_in_group("npc"):
		if npc.has_method("reload_dialogue"):
			npc.reload_dialogue()


# ── Scene transition ──────────────────────────────────────────────────────────

func _transition_to(scene_path: String) -> void:
	if _transitioning:
		return
	_transitioning = true

	var area_name := AREA_NAMES.get(scene_path, "") as String
	var ls        := _loading_packed.instantiate()
	get_tree().root.add_child(ls)

	await ls.run_enter(area_name)
	get_tree().change_scene_to_file(scene_path)
	await ls.run_exit()
	ls.queue_free()
	_transitioning = false
