extends Node

## The Ashfield — monster hunting area.
## This script drives the field scene (world/field.tscn).
## It replaces the old main/main.gd for the RPG build.
##
## Scene structure (build in editor):
##   Field  (Node, script = field.gd)
##   ├── Background      (ColorRect, anchors=full, color=dark green placeholder)
##   │
##   │   ── Terrain placeholders (implied treeline / irregular edges) ──────────
##   ├── TerrainNW       (ColorRect, dark olive, top-left corner block)
##   ├── TerrainNE       (ColorRect, dark olive, top-right corner block)
##   ├── TerrainSE       (ColorRect, dark olive, bottom-right corner block)
##   │       These give the clearing its irregular shape visually.
##   │       Replace with TileMap art in a later phase.
##   │
##   ├── TownEntrance    (Area2D)  ← area_entered connected to _on_entrance_entered
##   │   │   Placed near the south edge of the world, clearly visible.
##   │   ├── CollisionShape2D  (RectangleShape2D, ~200×60)
##   │   └── EntryMarker  (ColorRect, bright gold/yellow, same size as shape)
##   │         Label child: "⟵ Thornwall" or similar
##   │
##   ├── MobContainer    (Node2D — mobs are spawned as children here)
##   │
##   ├── Player          (instance of Player/player.tscn)
##   │   └── Camera2D
##   │         enabled = true
##   │         (no limits — free follow as designed)
##   │
##   └── DayLabel        (Label, top-left anchor, font_size=32)


@export var slime1_scene : PackedScene
## Logical size of the playable field world in pixels.
@export var world_size   : Vector2 = Vector2(3840.0, 2160.0)

const MAX_MOBS   : int   = 14
const MOB_MARGIN : float = 180.0   # min distance from world edge for mob spawns

var _active_mobs : int = 0

@onready var _player        = $Player
@onready var _entrance      : Area2D  = $TownEntrance
@onready var _mob_container : Node2D  = $MobContainer
@onready var _day_label     : Label   = $DayLabel


func _ready() -> void:
	# Give the player the world bounds so it clamps within the field
	_player.set_world_bounds(Rect2(Vector2.ZERO, world_size))
	# Spawn in the upper-center of the field (away from the south entrance)
	_player.start(Vector2(world_size.x * 0.5, world_size.y * 0.35))

	_player.mob_killed.connect(_on_mob_killed)
	_entrance.area_entered.connect(_on_entrance_entered)

	_day_label.text = "Day  %d" % SceneManager.day

	_spawn_initial_mobs()


# ── Spawning ──────────────────────────────────────────────────────────────────

func _spawn_initial_mobs() -> void:
	for _i in MAX_MOBS:
		_spawn_mob()


func _spawn_mob() -> void:
	if slime1_scene == null:
		push_error("Field: slime1_scene export not set.")
		return
	if _active_mobs >= MAX_MOBS:
		return

	var mob = slime1_scene.instantiate()

	# Set the mob's world bounds to match the field
	if mob.has_method("set_world_size"):
		mob.set_world_size(world_size)

	mob.position = Vector2(
		randf_range(MOB_MARGIN, world_size.x - MOB_MARGIN),
		randf_range(MOB_MARGIN, world_size.y - MOB_MARGIN)
	)

	_mob_container.add_child(mob)
	_active_mobs += 1


# ── Events ────────────────────────────────────────────────────────────────────

func _on_mob_killed(mob_body: Node) -> void:
	var monster_type: String = mob_body.get_meta("monster_type", "unknown")
	SceneManager.record_kill(monster_type)
	mob_body.queue_free()
	_active_mobs -= 1
	# Respawn a replacement after a short delay
	var t := get_tree().create_timer(randf_range(5.0, 14.0))
	t.timeout.connect(_spawn_mob)


func _on_entrance_entered(area: Area2D) -> void:
	if _is_player(area):
		SceneManager.go_to_town()


# ── Helpers ───────────────────────────────────────────────────────────────────

func _is_player(area: Area2D) -> bool:
	return area.is_in_group("player") or area.get_parent().is_in_group("player")
