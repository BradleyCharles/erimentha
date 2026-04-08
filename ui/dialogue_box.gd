extends CanvasLayer

## RPG dialogue box. Sits at the bottom of the screen and reads from
## pre-rendered JSON dialogue trees produced by the LLM pipeline.
##
## Scene structure to build in the editor:
##   DialogueBox  (CanvasLayer, layer = 10)
##     Add this node to the group "dialogue_box" so NPCs can find it.
##   └── Panel  (PanelContainer)
##         anchors: left=0, top=0.72, right=1, bottom=1
##         (covers roughly the bottom 28 % of the screen)
##       └── VBox  (VBoxContainer, separation=8, margin=12 all sides)
##           ├── NameLabel   (Label, font_size=28, font=Xolonium)
##           ├── TextLabel   (RichTextLabel, bbcode=true, fit_content=false,
##           │                custom_min_size=(0,110), scroll_active=false)
##           ├── Divider     (HSeparator)
##           └── Responses   (VBoxContainer, separation=4)
##   └── TypingTimer  (Timer, one_shot=true)
##         Connect timeout → _on_typing_timer_timeout
##
## Usage:
##   dialogue_box.open(nodes_dict, "greeting", "Mira")
##   The box closes itself when a response has "next": null,
##   or when the NPC calls close() on player exit.


signal closed

@onready var _panel      : PanelContainer = $Panel
@onready var _name_label : Label          = $Panel/VBox/NameLabel
@onready var _text_label : RichTextLabel  = $Panel/VBox/TextLabel
@onready var _responses  : VBoxContainer  = $Panel/VBox/Responses
@onready var _timer      : Timer          = $TypingTimer

const TYPING_SPEED := 0.028   # seconds per character

var _nodes      : Dictionary = {}
var _current    : Dictionary = {}
var _full_text  : String     = ""
var _char_index : int        = 0
var _is_typing  : bool       = false
var _npc_name   : String     = ""


# ── Public API ────────────────────────────────────────────────────────────────

## Opens the dialogue box and begins at start_node_id.
## nodes should be the "nodes" dictionary from the NPC's JSON file.
func open(nodes: Dictionary, start_node_id: String, npc_name: String = "") -> void:
	_nodes    = nodes
	_npc_name = npc_name
	_panel.show()
	_go_to(start_node_id)


## Closes the dialogue box and clears state.
## Called by NPC when the player walks away.
func close() -> void:
	_timer.stop()
	_is_typing = false
	_clear_responses()
	_panel.hide()
	closed.emit()


func is_open() -> bool:
	return _panel.visible


# ── Navigation ────────────────────────────────────────────────────────────────

func _go_to(node_id: String) -> void:
	if not _nodes.has(node_id):
		close()
		return
	_current          = _nodes[node_id]
	_name_label.text  = _npc_name
	_clear_responses()
	_start_typeout(_current.get("text", "..."))


# ── Typeout ───────────────────────────────────────────────────────────────────

func _start_typeout(text: String) -> void:
	_full_text  = text
	_char_index = 0
	_is_typing  = true
	_text_label.text = ""
	_timer.wait_time = TYPING_SPEED
	_timer.start()


func _on_typing_timer_timeout() -> void:
	if _char_index >= _full_text.length():
		_is_typing = false
		_show_responses()
		return
	_text_label.text = _full_text.substr(0, _char_index + 1)
	_char_index += 1
	_timer.start()


func _skip_typing() -> void:
	_timer.stop()
	_char_index      = _full_text.length()
	_text_label.text = _full_text
	_is_typing       = false
	_show_responses()


# ── Responses ─────────────────────────────────────────────────────────────────

func _show_responses() -> void:
	_clear_responses()
	var list: Array = _current.get("responses", [])
	for r in list:
		var lbl := Label.new()
		lbl.text = "[%d]  %s" % [r.get("key", 0), r.get("text", "")]
		lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
		_responses.add_child(lbl)


func _clear_responses() -> void:
	for child in _responses.get_children():
		child.queue_free()


# ── Input ─────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not _panel.visible:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	get_viewport().set_input_as_handled()

	# Any key skips the typeout
	if _is_typing:
		_skip_typing()
		return

	# Number keys 1–4 select a response
	const KEY_MAP := { KEY_1: 1, KEY_2: 2, KEY_3: 3, KEY_4: 4 }
	var chosen: int = KEY_MAP.get(event.keycode, -1)
	if chosen == -1:
		return

	for r in _current.get("responses", []):
		if r.get("key", -1) == chosen:
			_handle_response(r)
			return


func _handle_response(r: Dictionary) -> void:
	var action : String = r.get("action", "")
	var next           = r.get("next", null)   # null = end conversation

	# Built-in actions that the LLM pipeline can embed in any response
	match action:
		"end_day":
			close()
			SceneManager.end_day()
			return
		"go_to_field":
			close()
			SceneManager.go_to_field()
			return
		"go_to_town":
			close()
			SceneManager.go_to_town()
			return

	if next == null:
		close()
	else:
		_go_to(str(next))
