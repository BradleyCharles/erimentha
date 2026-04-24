extends Node

## Thornwall -- the town scene.
## Ctrl+R triggers the chronicle pipeline (developer/demo tool).


@export var world_size: Vector2 = Vector2(4800.0, 2700.0)

@onready var _player     = $Player
@onready var _field_exit : Area2D = $FieldExit
@onready var _day_label  : Label  = $DayLabel


func _ready() -> void:
	_player.set_world_bounds(Rect2(Vector2.ZERO, world_size))
	_player.start(Vector2(world_size.x * 0.5, world_size.y * 0.80))
	_field_exit.area_entered.connect(_on_field_exit_entered)
	_day_label.text = "Day  %d" % SceneManager.day
	_reload_all_dialogue()


# ── Input ─────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R and event.ctrl_pressed:
			get_viewport().set_input_as_handled()
			print("Town: Ctrl+R pressed -- triggering chronicle pipeline.")
			SceneManager.trigger_chronicle()


# ── Events ────────────────────────────────────────────────────────────────────

func _on_field_exit_entered(area: Area2D) -> void:
	if _is_player(area):
		SceneManager.go_to_field()


# ── Internal ──────────────────────────────────────────────────────────────────

func _reload_all_dialogue() -> void:
	for npc in get_tree().get_nodes_in_group("npc"):
		if npc.has_method("reload_dialogue"):
			npc.reload_dialogue()


func _is_player(area: Area2D) -> bool:
	return area.is_in_group("player") or area.get_parent().is_in_group("player")
