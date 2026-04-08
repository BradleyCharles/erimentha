extends CanvasLayer

## Full-screen transition overlay used by SceneManager.
##
## Scene structure to build in the editor:
##   LoadingScreen  (CanvasLayer, layer = 128)
##   ├── Overlay    (ColorRect)
##   │     anchors_preset = 15  (full rect)
##   │     color = Color(0, 0, 0, 1)
##   │     modulate.a = 0          ← start invisible
##   └── Label      (Label)
##         anchors_preset = 8  (center)
##         horizontal_alignment = CENTER
##         vertical_alignment   = CENTER
##         font_size = 52
##         visible = false
##         (optionally load Xolonium-Regular.ttf as the font override)


@onready var _overlay : ColorRect = $Overlay
@onready var _label   : Label     = $Label

const TYPE_INTERVAL := 0.04   # seconds between characters while typing


# ── Public API (awaitable) ────────────────────────────────────────────────────

## Fades the screen to black, then types out the area name.
## SceneManager awaits this before calling change_scene_to_file().
func run_enter(area_name: String) -> void:
	_label.text    = ""
	_label.visible = false
	_overlay.modulate.a = 0.0

	# Fade to black
	var tw := create_tween()
	tw.tween_property(_overlay, "modulate:a", 1.0, 0.4)
	await tw.finished

	# Type out "Now Entering\n<name>"
	if area_name != "":
		_label.visible = true
		await _typeout("Now Entering\n" + area_name)
		await get_tree().create_timer(0.55).timeout


## Fades back from black after the scene has changed.
## SceneManager awaits this before freeing the loading screen.
func run_exit() -> void:
	var tw := create_tween()
	tw.tween_property(_overlay, "modulate:a", 0.0, 0.45)
	await tw.finished


# ── Internal ──────────────────────────────────────────────────────────────────

func _typeout(text: String) -> void:
	_label.text = ""
	for i in text.length():
		_label.text = text.substr(0, i + 1)
		await get_tree().create_timer(TYPE_INTERVAL).timeout
