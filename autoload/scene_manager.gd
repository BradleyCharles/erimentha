extends Node

## SceneManager — autoload singleton (name it "SceneManager" in Project > Autoload).
##
## Responsibilities:
##   - Holds all persistent game state (day, kills, bounties)
##   - Drives scene transitions with a loading screen
##   - Provides a Phase 3 hook (end_day) where the LLM pipeline will be invoked


# ── Game State ────────────────────────────────────────────────────────────────

var day: int = 1

## Kills recorded during the current in-game day.  { "slime1": 3, ... }
var monsters_killed_today: Dictionary = {}

## One entry per completed day — preserved across scene changes.
var monsters_killed_history: Array[Dictionary] = []

## Populated by the LLM pipeline in Phase 4.
var active_bounties: Array = []


# ── Scene Paths ───────────────────────────────────────────────────────────────

const FIELD_SCENE := "res://world/field.tscn"
const TOWN_SCENE  := "res://world/town.tscn"

## Display names shown on the loading screen for each destination.
const AREA_NAMES: Dictionary = {
	FIELD_SCENE: "The Ashfield",
	TOWN_SCENE:  "Thornwall"
}


# ── Transition Internals ──────────────────────────────────────────────────────

var _loading_packed := preload("res://ui/loading_screen.tscn")
var _transitioning  := false


# ── Public API ────────────────────────────────────────────────────────────────

func go_to_field() -> void:
	_transition_to(FIELD_SCENE)


func go_to_town() -> void:
	_transition_to(TOWN_SCENE)


func record_kill(monster_type: String) -> void:
	monsters_killed_today[monster_type] = \
		monsters_killed_today.get(monster_type, 0) + 1


func end_day() -> void:
	## Closes out the current day and advances the day counter.
	## Phase 3 hook: this is where game_state.json will be written
	## and the Python LLM pipeline will be triggered before the
	## player regains control.
	monsters_killed_history.append(monsters_killed_today.duplicate())
	monsters_killed_today.clear()
	day += 1
	# TODO Phase 3: write game_state.json, await pipeline completion,
	#              then reload dialogue JSONs before going to field.
	go_to_field()


# ── Internal ──────────────────────────────────────────────────────────────────

func _transition_to(scene_path: String) -> void:
	if _transitioning:
		return
	_transitioning = true

	var area_name := AREA_NAMES.get(scene_path, "") as String
	var ls = _loading_packed.instantiate()
	get_tree().root.add_child(ls)

	await ls.run_enter(area_name)          # fade to black + typeout text
	get_tree().change_scene_to_file(scene_path)
	await ls.run_exit()                    # fade back to game
	ls.queue_free()
	_transitioning = false
