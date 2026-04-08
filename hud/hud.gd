extends CanvasLayer

signal start_game

const HIGH_SCORES_FILE = "user://highscores.cfg"
const MAX_HIGH_SCORES = 5

var high_scores: Array = []  # Array of {name: String, score: int}
var pending_score: int = 0

# Score entry UI (built programmatically)
var score_entry_panel: PanelContainer
var final_score_label: Label
var initials_input: LineEdit
var submit_btn: Button
var high_scores_label: Label
var initials_row: Control
var _font: FontFile


func _ready():
	_font = load("res://fonts/Xolonium-Regular.ttf")
	_load_high_scores()
	_create_score_entry_ui()


# ── High score persistence ──────────────────────────────────────────────────

func _load_high_scores():
	var config = ConfigFile.new()
	if config.load(HIGH_SCORES_FILE) == OK:
		high_scores = config.get_value("scores", "list", [])


func _save_high_scores():
	var config = ConfigFile.new()
	config.set_value("scores", "list", high_scores)
	config.save(HIGH_SCORES_FILE)


func _insert_score(initials: String, score: int):
	high_scores.append({"name": initials.to_upper(), "score": score})
	high_scores.sort_custom(func(a, b): return a.score > b.score)
	if high_scores.size() > MAX_HIGH_SCORES:
		high_scores.resize(MAX_HIGH_SCORES)
	_save_high_scores()


# ── Score entry UI ──────────────────────────────────────────────────────────

func _make_label(text: String, size: int, bold: bool = false) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	return lbl


func _create_score_entry_ui():
	score_entry_panel = PanelContainer.new()
	# Center on 1920×1080
	score_entry_panel.anchor_left   = 0.5
	score_entry_panel.anchor_top    = 0.5
	score_entry_panel.anchor_right  = 0.5
	score_entry_panel.anchor_bottom = 0.5
	score_entry_panel.offset_left   = -350.0
	score_entry_panel.offset_top    = -420.0
	score_entry_panel.offset_right  =  350.0
	score_entry_panel.offset_bottom =  420.0
	score_entry_panel.hide()
	add_child(score_entry_panel)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	score_entry_panel.add_child(vbox)

	# Title
	vbox.add_child(_make_label("GAME OVER", 64))

	# Final score
	final_score_label = _make_label("Score: 0", 48)
	vbox.add_child(final_score_label)

	vbox.add_child(HSeparator.new())

	# Initials row (hidden after submission)
	initials_row = VBoxContainer.new()
	initials_row.add_theme_constant_override("separation", 12)
	vbox.add_child(initials_row)

	initials_row.add_child(_make_label("Enter Initials:", 40))

	initials_input = LineEdit.new()
	initials_input.max_length = 3
	initials_input.placeholder_text = "AAA"
	initials_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	initials_input.add_theme_font_override("font", _font)
	initials_input.add_theme_font_size_override("font_size", 56)
	initials_input.custom_minimum_size = Vector2(220, 75)
	initials_input.text_changed.connect(_on_initials_changed)
	initials_input.text_submitted.connect(_on_initials_submitted)
	initials_row.add_child(initials_input)

	submit_btn = Button.new()
	submit_btn.text = "SUBMIT"
	submit_btn.add_theme_font_override("font", _font)
	submit_btn.add_theme_font_size_override("font_size", 40)
	submit_btn.custom_minimum_size = Vector2(220, 60)
	submit_btn.pressed.connect(_on_submit_pressed)
	initials_row.add_child(submit_btn)

	vbox.add_child(HSeparator.new())

	# High scores
	vbox.add_child(_make_label("HIGH SCORES", 40))

	high_scores_label = _make_label("", 36)
	vbox.add_child(high_scores_label)


# ── Input handlers ──────────────────────────────────────────────────────────

func _on_initials_changed(new_text: String):
	# Force uppercase, only allow letters
	var filtered = ""
	for ch in new_text.to_upper():
		if ch >= "A" and ch <= "Z":
			filtered += ch
	if filtered != new_text.to_upper() or new_text != new_text.to_upper():
		initials_input.text = filtered
		initials_input.caret_column = filtered.length()


func _on_initials_submitted(_text: String):
	_do_submit()


func _on_submit_pressed():
	_do_submit()


func _do_submit():
	var initials = initials_input.text.strip_edges().to_upper()
	if initials.length() == 0:
		initials = "???"
	while initials.length() < 3:
		initials += "_"
	_insert_score(initials, pending_score)
	_show_results()


func _show_results():
	initials_row.hide()
	_refresh_scores_display()
	await get_tree().create_timer(3.5).timeout
	score_entry_panel.hide()
	$Message.text = "Dodge the Creeps!"
	$Message.show()
	await get_tree().create_timer(1.0).timeout
	$StartButton.show()


func _refresh_scores_display():
	if high_scores.is_empty():
		high_scores_label.text = "No scores yet"
		return
	var text = ""
	for i in high_scores.size():
		var e = high_scores[i]
		text += "%d.  %s  %d\n" % [i + 1, e.name, e.score]
	high_scores_label.text = text.strip_edges()


# ── Public API (called from main.gd / scene signals) ───────────────────────

func show_score_entry(score: int):
	pending_score = score
	final_score_label.text = "Score: %d  (+10 fly bonus!)" % score if score % 10 == 0 and score > 0 else "Score: %d" % score
	initials_input.text = ""
	initials_row.show()
	_refresh_scores_display()
	score_entry_panel.show()
	initials_input.grab_focus()


func show_message(text):
	$Message.text = text
	$Message.show()
	$MessageTimer.start()


func show_game_over():
	show_message("Game Over")
	await $MessageTimer.timeout
	$Message.text = "Dodge the Creeps!"
	$Message.show()
	await get_tree().create_timer(1.0).timeout
	$StartButton.show()


func update_score(score):
	$ScoreLabel.text = str(score)


func _on_start_button_pressed():
	$StartButton.hide()
	score_entry_panel.hide()
	start_game.emit()


func _on_message_timer_timeout():
	$Message.hide()
