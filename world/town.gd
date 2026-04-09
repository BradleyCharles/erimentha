extends Node

## Thornwall — the town scene.
##
## Layout (place nodes in editor):
##
##   World size: 4800 × 2700  (set world_size export)
##
##   Landmarks (approximate world positions):
##     Dragon Roost Inn       — center ~(2400, 580)   direction: North
##     Monster Hunters Guild  — center ~(820, 1350)   direction: West
##     Gareth the Blacksmith  — center ~(2400, 1350)  direction: Center
##     Field Exit marker      — center ~(,)  direction: East
##
## Scene structure (build in editor):
##   Town  (Node, script = town.gd)
##   ├── Background      (ColorRect, anchors=full, earthy brown/grey placeholder)
##   │
##   │   ── Building placeholders ──────────────────────────────────────────────
##   ├── InnBuilding     (ColorRect ~280×200, muted blue, pos ~(2260,460))
##   │   └── Label "Dragon Roost Inn"
##   ├── GuildBuilding   (ColorRect ~260×180, dark red, pos ~(690,1260))
##   │   └── Label "Monster Hunters Guild"
##   ├── SmithBuilding   (ColorRect ~200×180, dark grey, pos ~(2300,1260))
##   │   └── Label "Gareth's Smithy"
##   │
##   │   ── NPCs (instances of npc_base.tscn) ─────────────────────────────────
##   ├── InnKeeper       (npc_base, npc_name="Mira", dialogue=innkeeper_day1.json)
##   │     position ~(2400, 700)
##   ├── BountyGiver     (npc_base, npc_name="Commander Aldric",
##   │     dialogue=bounty_giver_day1.json, position ~(820, 1380))
##   ├── Gareth          (npc_base, npc_name="Gareth",
##   │     dialogue=gareth_day1.json, position ~(2400, 1420))
##   ├── Wanderer1       (npc_base, is_wanderer=true, position ~(1800, 1200))
##   ├── Wanderer2       (npc_base, is_wanderer=true, position ~(2900, 1500))
##   ├── Wanderer3       (npc_base, is_wanderer=true, position ~(2200, 900))
##   │
##   │   ── Field exit ──────────────────────────────────────────────────────────
##   ├── FieldExit       (Area2D)  ← area_entered → _on_field_exit_entered
##   │   ├── CollisionShape2D  (RectangleShape2D ~200×60)
##   │   └── ExitMarker  (ColorRect, bright gold, same size)
##   │         Label child: "⟶ The Ashfield"
##   │
##   ├── Player          (instance of Player/player.tscn)
##   │   └── Camera2D  (enabled=true)
##   │
##   ├── DialogueBox     (instance of ui/dialogue_box.tscn)
##   │     Add to group "dialogue_box"
##   │
##   └── DayLabel        (Label, top-left anchor, font_size=32)


@export var world_size: Vector2 = Vector2(4800.0, 2700.0)

@onready var _player      = $Player
@onready var _field_exit  : Area2D = $FieldExit
@onready var _day_label   : Label  = $DayLabel


func _ready() -> void:
	_player.set_world_bounds(Rect2(Vector2.ZERO, world_size))
	# Spawn near the south (field-side) entrance so the arrival feels natural
	_player.start(Vector2(world_size.x * 0.5, world_size.y * 0.80))

	_field_exit.area_entered.connect(_on_field_exit_entered)

	_day_label.text = "Day  %d" % SceneManager.day

	# Reload all NPC dialogue at scene entry so day-appropriate JSON is used.
	# This becomes meaningful in Phase 4 once the LLM pipeline generates daily files.
	_reload_all_dialogue()


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
