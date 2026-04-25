extends Node

@export var world_size: Vector2 = Vector2(4800.0, 2700.0)

@onready var _player     = $Player
@onready var _field_exit : Area2D = $FieldExit
@onready var _day_label  : Label  = $DayLabel


func _ready() -> void:
	_player.set_world_bounds(Rect2(Vector2.ZERO, world_size))
	_player.start(Vector2(world_size.x * 0.5, world_size.y * 0.80))
	_field_exit.area_entered.connect(_on_field_exit_entered)
	_day_label.text = "Day  %d" % SceneManager.day
	_apply_world_registry()
	_reload_all_dialogue()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R and event.ctrl_pressed:
			get_viewport().set_input_as_handled()
			SceneManager.trigger_chronicle()


func _on_field_exit_entered(area: Area2D) -> void:
	if _is_player(area):
		SceneManager.go_to_field()


func _apply_world_registry() -> void:
	## Read world_registry.json and configure each named NPC node
	## with the correct npc_id and display_name for this world instance.
	var path := ProjectSettings.globalize_path("res://") + "world_registry.json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("town.gd: world_registry.json not found -- using inspector values.")
		return

	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		push_warning("town.gd: failed to parse world_registry.json")
		file.close()
		return
	file.close()

	var registry : Dictionary = parser.get_data()
	var town_npcs : Dictionary = registry\
		.get("towns", {})\
		.get("thornwall", {})\
		.get("npcs", {})

	if town_npcs.is_empty():
		push_warning("town.gd: no NPCs found in registry for thornwall.")
		return

	for npc in get_tree().get_nodes_in_group("npc"):
		var role : String = npc.get("npc_role") if npc.get("npc_role") != null else ""
		if role == "" or not town_npcs.has(role):
			continue

		var entry : Dictionary = town_npcs[role]
		npc.npc_id   = entry.get("npc_id",       npc.npc_id)
		npc.npc_name = entry.get("display_name",  npc.npc_name)

		# Sync the name label
		if npc.has_node("NameLabel"):
			npc.get_node("NameLabel").text = npc.npc_name

		print("town.gd: configured %s -> %s (%s)" \
			% [role, npc.npc_name, npc.npc_id])


func _reload_all_dialogue() -> void:
	for npc in get_tree().get_nodes_in_group("npc"):
		if npc.has_method("reload_dialogue"):
			npc.reload_dialogue()


func _is_player(area: Area2D) -> bool:
	return area.is_in_group("player") or area.get_parent().is_in_group("player")
