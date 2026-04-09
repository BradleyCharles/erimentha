extends Node2D

## Base script for all NPCs — named characters and background wanderers.
##
## Scene structure for npc_base.tscn (build once, reuse for every NPC):
##   NPC  (Node2D, script = npc_base.gd)
##   ├── AnimatedSprite2D
##   ├── DetectionArea  (Area2D)
##   │     collision_layer = 0  (doesn't push anything)
##   │     collision_mask  = 2  (scans player layer — set player to layer 2)
##   │     Connect: area_entered → _on_area_entered
##   │     Connect: area_exited  → _on_area_exited
##   │   └── CollisionShape2D  (CircleShape2D — radius driven by detection_radius export)
##   └── NameLabel  (Label)
##         offset = Vector2(0, -60) so it floats above the sprite
##         horizontal_alignment = CENTER
##         visible = false by default
##
## Collision layer convention (set in Project Settings > Physics > 2D):
##   Layer 1 — mobs
##   Layer 2 — player
##   Layer 3 — NPC detection
##   Layer 4 — world / terrain (future)


# ── Exports ───────────────────────────────────────────────────────────────────

@export var npc_id          : String = ""
@export var npc_name        : String = "Villager"
## Path to the NPC's pre-rendered dialogue JSON, e.g. "res://dialogue/innkeeper_day1.json"
@export_file("*.json") var dialogue_file: String = ""
@export var detection_radius: float  = 160.0
## True for anonymous background NPCs that wander but carry no dialogue.
@export var is_wanderer     : bool   = false


# ── Node refs ─────────────────────────────────────────────────────────────────

@onready var _sprite    : AnimatedSprite2D = $AnimatedSprite2D
@onready var _detection : Area2D           = $DetectionArea
@onready var _name_lbl  : Label            = $NameLabel


# ── State ─────────────────────────────────────────────────────────────────────

var _dialogue_nodes  : Dictionary = {}
var _dialogue_box    : Node       = null
var _player_in_range : bool       = false

# Wander (background NPCs only)
var _wander_dir   : Vector2 = Vector2.ZERO
var _wander_timer : float   = 0.0
const WANDER_SPEED : float  = 38.0


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	
	_build_sprite_frames()
	# Wire detection signals
	_detection.area_entered.connect(_on_area_entered)
	_detection.area_exited.connect(_on_area_exited)

	# Resize the detection circle to match the exported radius
	var shape := _detection.get_node("CollisionShape2D")
	if shape and shape.shape is CircleShape2D:
		(shape.shape as CircleShape2D).radius = detection_radius

	_name_lbl.text    = npc_name
	_name_lbl.visible = false

	_load_dialogue()

	if is_wanderer:
		_pick_wander_direction()
	else:
		_try_play("idle_down")


func _process(delta: float) -> void:
	if not is_wanderer:
		return
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_pick_wander_direction()
	position += _wander_dir * WANDER_SPEED * delta


# ── Dialogue loading ──────────────────────────────────────────────────────────

func _load_dialogue() -> void:
	if dialogue_file == "":
		return
	var file := FileAccess.open(dialogue_file, FileAccess.READ)
	if file == null:
		push_warning("NPC '%s': dialogue file not found — %s" % [npc_name, dialogue_file])
		return
	var json := JSON.new()
	var err  := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_warning("NPC '%s': failed to parse dialogue JSON (line %d)" \
			% [npc_name, json.get_error_line()])
		return
	var data := json.get_data() as Dictionary
	_dialogue_nodes = data.get("nodes", {})
	# Allow the JSON to override the inspector name (useful for day-specific names)
	if data.has("npc_name"):
		npc_name = data["npc_name"]
		_name_lbl.text = npc_name


## Reload dialogue at the start of each new day without re-instantiating the NPC.
func reload_dialogue() -> void:
	_dialogue_nodes = {}
	_load_dialogue()


# ── Proximity detection ───────────────────────────────────────────────────────

func _on_area_entered(area: Area2D) -> void:
	if not _is_player_area(area):
		return
	_player_in_range    = true
	_name_lbl.visible   = true
	_open_dialogue()


func _on_area_exited(area: Area2D) -> void:
	if not _is_player_area(area):
		return
	_player_in_range  = false
	_name_lbl.visible = false
	_close_dialogue()


func _is_player_area(area: Area2D) -> bool:
	return area.is_in_group("player") or area.get_parent().is_in_group("player")


# ── Dialogue ──────────────────────────────────────────────────────────────────

func _open_dialogue() -> void:
	if _dialogue_nodes.is_empty() or is_wanderer:
		return
	_dialogue_box = get_tree().get_first_node_in_group("dialogue_box")
	if _dialogue_box == null:
		push_warning("NPC '%s': no node in group 'dialogue_box' found in scene." % npc_name)
		return
	_dialogue_box.open(_dialogue_nodes, "greeting", npc_name)


func _close_dialogue() -> void:
	if _dialogue_box != null and _dialogue_box.is_open():
		_dialogue_box.close()
	_dialogue_box = null


# ── Wander ────────────────────────────────────────────────────────────────────

func _pick_wander_direction() -> void:
	_wander_timer = randf_range(2.5, 6.0)
	# 30 % chance to pause briefly
	if randf() < 0.30:
		_wander_dir = Vector2.ZERO
		_try_play("idle_down")
		return
	var angle   := randf() * TAU
	_wander_dir  = Vector2(cos(angle), sin(angle))
	# Flip sprite to match horizontal direction
	_sprite.flip_h = _wander_dir.x < 0.0
	_try_play("walk_down" if abs(_wander_dir.y) > abs(_wander_dir.x) else "walk_right")


# ── Helpers ───────────────────────────────────────────────────────────────────

func _try_play(anim: String) -> void:
	if _sprite.sprite_frames and _sprite.sprite_frames.has_animation(anim):
		_sprite.play(anim)
		
# ── Sprite setup ──────────────────────────────────────────────────────────────

const FRAME_SIZE := 64
const ROW_DOWN   := 0
const ROW_RIGHT  := 2

func _build_sprite_frames() -> void:
	var base     := "res://assets/Swordsman_lvl1/Without_shadow/"
	var idle_tex : Texture2D = load(base + "Swordsman_lvl1_Idle_without_shadow.png")

	var sf := SpriteFrames.new()
	sf.remove_animation("default")

	_add_anim(sf, "idle_down",  idle_tex, ROW_DOWN,  12, 8.0, true)
	_add_anim(sf, "idle_right", idle_tex, ROW_RIGHT, 12, 8.0, true)
	# idle_left reuses idle_right with flip_h = true (handled in _try_play)

	_sprite.sprite_frames = sf


func _add_anim(sf: SpriteFrames, anim: String, sheet: Texture2D,
			   row: int, count: int, fps: float, loop: bool) -> void:
	sf.add_animation(anim)
	sf.set_animation_loop(anim, loop)
	sf.set_animation_speed(anim, fps)
	for i in count:
		var a := AtlasTexture.new()
		a.atlas  = sheet
		a.region = Rect2(i * FRAME_SIZE, row * FRAME_SIZE, FRAME_SIZE, FRAME_SIZE)
		sf.add_frame(anim, a)		
