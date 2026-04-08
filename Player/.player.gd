extends Area2D

signal hit
signal mob_killed(mob_body: Node)
signal fly_caught

@export var speed: float = 500.0

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _body_shape: CollisionShape2D = $CollisionShape2D
@onready var _sword: Area2D = $SwordHitbox

var screen_size: Vector2
var facing: Vector2 = Vector2.RIGHT
var is_attacking: bool = false
var is_dying: bool = false
var _death_signal: String = ""

# Sprite sheet rows: Down=0, Left=1, Right=2, Up=3
const ROW_DOWN  = 0
const ROW_LEFT  = 1
const ROW_RIGHT = 2
const ROW_UP    = 3
const FRAME_SIZE = 64


func _ready():
	screen_size = get_viewport_rect().size
	_build_sprite_frames()
	_sprite.frame_changed.connect(_on_frame_changed)
	_sprite.animation_finished.connect(_on_animation_finished)
	_sword.body_entered.connect(_on_sword_hit)
	hide()


# ── Sprite sheet setup ──────────────────────────────────────────────────────

func _make_atlas(sheet: Texture2D, col: int, row: int) -> AtlasTexture:
	var a = AtlasTexture.new()
	a.atlas = sheet
	a.region = Rect2(col * FRAME_SIZE, row * FRAME_SIZE, FRAME_SIZE, FRAME_SIZE)
	return a


func _add_anim(sf: SpriteFrames, anim: String, sheet: Texture2D,
			   row: int, count: int, fps: float, loop: bool) -> void:
	sf.add_animation(anim)
	sf.set_animation_loop(anim, loop)
	sf.set_animation_speed(anim, fps)
	for i in count:
		sf.add_frame(anim, _make_atlas(sheet, i, row))


func _build_sprite_frames() -> void:
	var base := "res://assets/Swordsman_lvl1/Without_shadow/"
	var idle_tex  : Texture2D = load(base + "Swordsman_lvl1_Idle_without_shadow.png")
	var walk_tex  : Texture2D = load(base + "Swordsman_lvl1_Walk_without_shadow.png")
	var atk_tex   : Texture2D = load(base + "Swordsman_lvl1_attack_without_shadow.png")
	var hurt_tex  : Texture2D = load(base + "Swordsman_lvl1_Hurt_without_shadow.png")
	var death_tex : Texture2D = load(base + "Swordsman_lvl1_Death_without_shadow.png")

	var sf := SpriteFrames.new()
	sf.remove_animation("default")

	# Idle — 12 frames, looping
	_add_anim(sf, "idle",       idle_tex, ROW_RIGHT, 12, 8.0,  true)
	_add_anim(sf, "idle_up",    idle_tex, ROW_UP,    12, 8.0,  true)
	_add_anim(sf, "idle_down",  idle_tex, ROW_DOWN,  12, 8.0,  true)

	# Walk — 6 frames, looping
	_add_anim(sf, "walk",       walk_tex, ROW_RIGHT,  6, 8.0,  true)
	_add_anim(sf, "walk_up",    walk_tex, ROW_UP,     6, 8.0,  true)
	_add_anim(sf, "walk_down",  walk_tex, ROW_DOWN,   6, 8.0,  true)

	# Attack — 8 frames, one-shot
	_add_anim(sf, "attack",       atk_tex, ROW_RIGHT, 8, 20.0, false)
	_add_anim(sf, "attack_up",    atk_tex, ROW_UP,    8, 20.0, false)
	_add_anim(sf, "attack_down",  atk_tex, ROW_DOWN,  8, 20.0, false)

	# Hurt — 5 frames, one-shot
	_add_anim(sf, "hurt",  hurt_tex,  ROW_RIGHT, 5, 12.0, false)

	# Death — 7 frames, one-shot
	_add_anim(sf, "death", death_tex, ROW_RIGHT, 7, 10.0, false)

	_sprite.sprite_frames = sf
	_sprite.play("idle")


# ── Game loop ───────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if is_dying:
		return

	var velocity := Vector2.ZERO
	if Input.is_action_pressed("move_right"):  velocity.x += 1
	if Input.is_action_pressed("move_left"):   velocity.x -= 1
	if Input.is_action_pressed("move_down"):   velocity.y += 1
	if Input.is_action_pressed("move_up"):     velocity.y -= 1

	if velocity.length() > 0:
		velocity = velocity.normalized() * speed
		facing = velocity.normalized()

	if Input.is_action_just_pressed("attack") and not is_attacking:
		_start_attack()

	position += velocity * delta
	position = position.clamp(Vector2.ZERO, screen_size)

	if not is_attacking:
		_update_animation(velocity)


func _update_animation(velocity: Vector2) -> void:
	var anim: String
	var flip := false

	if velocity.length() == 0:
		if abs(facing.y) > abs(facing.x):
			anim = "idle_up" if facing.y < 0 else "idle_down"
		else:
			anim = "idle"
			flip = facing.x < 0
	else:
		if abs(velocity.y) > abs(velocity.x):
			anim = "walk_up" if velocity.y < 0 else "walk_down"
		else:
			anim = "walk"
			flip = velocity.x < 0

	_sprite.flip_h = flip
	if _sprite.animation != anim:
		_sprite.play(anim)
	elif not _sprite.is_playing():
		_sprite.play()


# ── Attack ──────────────────────────────────────────────────────────────────

func _start_attack() -> void:
	is_attacking = true
	_sword.position = facing.normalized() * 65.0

	var anim: String
	if abs(facing.y) > abs(facing.x):
		anim = "attack_up" if facing.y < 0 else "attack_down"
		_sprite.flip_h = false
	else:
		anim = "attack"
		_sprite.flip_h = facing.x < 0

	_sprite.play(anim)


func _on_frame_changed() -> void:
	if not is_attacking:
		return
	var f := _sprite.frame
	_sword.monitoring = (f >= 2 and f <= 6)


func _on_animation_finished() -> void:
	var anim := _sprite.animation
	if anim in ["attack", "attack_up", "attack_down"]:
		is_attacking = false
		_sword.monitoring = false
		_update_animation(Vector2.ZERO)
	elif anim == "hurt":
		_sprite.flip_h = false
		_sprite.play("death")
	elif anim == "death":
		if _death_signal == "hit":
			hit.emit()
		elif _death_signal == "fly_caught":
			fly_caught.emit()
		_death_signal = ""


# ── Collision ───────────────────────────────────────────────────────────────

func _on_body_entered(body: Node2D) -> void:
	if is_dying:
		return
	if body.is_in_group("flying_mobs"):
		call_deferred("_start_dying", "fly_caught")
	elif body.is_in_group("ground_mobs"):
		call_deferred("_start_dying", "hit")


func _start_dying(signal_name: String) -> void:
	if is_dying:
		return
	is_dying = true
	_death_signal = signal_name
	is_attacking = false
	_sword.monitoring = false
	_body_shape.set_deferred("disabled", true)
	_sprite.flip_h = false
	_sprite.play("hurt")


func _on_sword_hit(body: Node2D) -> void:
	if is_dying:
		return
	if body.is_in_group("flying_mobs") or body.is_in_group("ground_mobs"):
		mob_killed.emit(body)


# ── Public API ──────────────────────────────────────────────────────────────

func start(pos: Vector2) -> void:
	is_dying = false
	is_attacking = false
	_death_signal = ""
	facing = Vector2.RIGHT
	_body_shape.disabled = false
	_sword.monitoring = false
	_sprite.flip_h = false
	_sprite.play("idle")
	position = pos
	show()
