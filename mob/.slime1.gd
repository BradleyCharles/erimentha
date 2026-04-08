extends RigidBody2D

# ── Constants ────────────────────────────────────────────────────────────────

const ASSET_BASE   := "res://assets/Slime1/Without_shadow/"
const IDLE_FRAMES  := 6
const IDLE_FPS     := 8.0

# Uncomment each group when the matching asset folder is ready:
# const WALK_FRAMES   := 6
# const RUN_FRAMES    := 6
# const ATTACK_FRAMES := 6
# const HURT_FRAMES   := 4
# const DEATH_FRAMES  := 5
# const WALK_FPS    := 8.0
# const RUN_FPS     := 12.0
# const ATTACK_FPS  := 15.0
# const HURT_FPS    := 10.0
# const DEATH_FPS   := 10.0

const MOB_RADIUS: float = 30.0

# ── Exports ───────────────────────────────────────────────────────────────────

@export var min_speed: float = 60.0
@export var max_speed: float = 120.0

# ── Node refs ─────────────────────────────────────────────────────────────────

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D

# ── State ─────────────────────────────────────────────────────────────────────

var wander_speed: float = 0.0
var wander_timer: Timer
var is_moving: bool = false
var viewport_rect: Rect2
var facing: String = "down"   # "down" | "up" | "right" | "left"

# var is_hurt: bool      = false   # Uncomment when hurt system is added
# var is_dead: bool      = false   # Uncomment when death system is added
# var is_attacking: bool = false   # Uncomment when attack system is added


func _ready() -> void:
	viewport_rect = get_viewport_rect()
	wander_speed  = randf_range(min_speed, max_speed)
	add_to_group("ground_mobs")

	_build_sprite_frames()

	_sprite.animation_finished.connect(_on_animation_finished)

	wander_timer          = Timer.new()
	wander_timer.one_shot = true
	wander_timer.timeout.connect(_on_wander_timeout)
	add_child(wander_timer)

	_begin_move()


# ── Sprite setup ──────────────────────────────────────────────────────────────

func _build_sprite_frames() -> void:
	var sf  := SpriteFrames.new()
	sf.remove_animation("default")

	var idle_dir := ASSET_BASE + "slime1_idle/"

	# Idle – down  (idle_down0.png … idle_down5.png)
	_add_anim(sf, "idle_down", idle_dir, "idle_down", IDLE_FRAMES, IDLE_FPS, true)

	# Idle – up    (idle_up0.png … idle_up5.png)
	_add_anim(sf, "idle_up",   idle_dir, "idle_up",   IDLE_FRAMES, IDLE_FPS, true)

	# Idle – right (idle_right0.png … idle_right5.png)
	_add_anim(sf, "idle_right", idle_dir, "idle_right", IDLE_FRAMES, IDLE_FPS, true)
	# Idle – left reuses idle_right frames with h_flip = true (see _play_idle)

	# ── Walk (uncomment when slime1_walk/ assets are ready) ──────────────────
	# var walk_dir := ASSET_BASE + "slime1_walk/"
	# _add_anim(sf, "walk_down",  walk_dir, "walk_down",  WALK_FRAMES, WALK_FPS, true)
	# _add_anim(sf, "walk_up",    walk_dir, "walk_up",    WALK_FRAMES, WALK_FPS, true)
	# _add_anim(sf, "walk_right", walk_dir, "walk_right", WALK_FRAMES, WALK_FPS, true)
	# walk_left reuses walk_right with h_flip = true

	# ── Run (uncomment when slime1_run/ assets are ready) ────────────────────
	# var run_dir := ASSET_BASE + "slime1_run/"
	# _add_anim(sf, "run_down",  run_dir, "run_down",  RUN_FRAMES, RUN_FPS, true)
	# _add_anim(sf, "run_up",    run_dir, "run_up",    RUN_FRAMES, RUN_FPS, true)
	# _add_anim(sf, "run_right", run_dir, "run_right", RUN_FRAMES, RUN_FPS, true)
	# run_left reuses run_right with h_flip = true

	# ── Attack (uncomment when slime1_attack/ assets are ready) ──────────────
	# var atk_dir := ASSET_BASE + "slime1_attack/"
	# _add_anim(sf, "attack_down",  atk_dir, "attack_down",  ATTACK_FRAMES, ATTACK_FPS, false)
	# _add_anim(sf, "attack_up",    atk_dir, "attack_up",    ATTACK_FRAMES, ATTACK_FPS, false)
	# _add_anim(sf, "attack_right", atk_dir, "attack_right", ATTACK_FRAMES, ATTACK_FPS, false)
	# attack_left reuses attack_right with h_flip = true

	# ── Hurt (uncomment when slime1_hurt/ assets are ready) ──────────────────
	# var hurt_dir := ASSET_BASE + "slime1_hurt/"
	# _add_anim(sf, "hurt_down",  hurt_dir, "hurt_down",  HURT_FRAMES, HURT_FPS, false)
	# _add_anim(sf, "hurt_up",    hurt_dir, "hurt_up",    HURT_FRAMES, HURT_FPS, false)
	# _add_anim(sf, "hurt_right", hurt_dir, "hurt_right", HURT_FRAMES, HURT_FPS, false)
	# hurt_left reuses hurt_right with h_flip = true

	# ── Death (uncomment when slime1_death/ assets are ready) ────────────────
	# var death_dir := ASSET_BASE + "slime1_death/"
	# _add_anim(sf, "death", death_dir, "death", DEATH_FRAMES, DEATH_FPS, false)

	_sprite.sprite_frames = sf


# Load sequential frames from individual PNG files.
# Files must follow the pattern: <folder><prefix><index>.png
func _add_anim(sf: SpriteFrames, anim_name: String, folder: String,
			   prefix: String, count: int, fps: float, loop: bool) -> void:
	sf.add_animation(anim_name)
	sf.set_animation_loop(anim_name, loop)
	sf.set_animation_speed(anim_name, fps)
	for i in count:
		var tex := load(folder + prefix + str(i) + ".png") as Texture2D
		sf.add_frame(anim_name, tex)


# ── Animation helpers ─────────────────────────────────────────────────────────

func _play_idle() -> void:
	match facing:
		"down":
			_sprite.flip_h = false
			_sprite.play("idle_down")
		"up":
			_sprite.flip_h = false
			_sprite.play("idle_up")
		"right":
			_sprite.flip_h = false
			_sprite.play("idle_right")
		"left":
			_sprite.flip_h = true
			_sprite.play("idle_right")


# ── Future animation helpers (uncomment each when assets are ready) ───────────

# func _play_walk() -> void:
# 	match facing:
# 		"down":  _sprite.flip_h = false; _sprite.play("walk_down")
# 		"up":    _sprite.flip_h = false; _sprite.play("walk_up")
# 		"right": _sprite.flip_h = false; _sprite.play("walk_right")
# 		"left":  _sprite.flip_h = true;  _sprite.play("walk_right")

# func _play_run() -> void:
# 	match facing:
# 		"down":  _sprite.flip_h = false; _sprite.play("run_down")
# 		"up":    _sprite.flip_h = false; _sprite.play("run_up")
# 		"right": _sprite.flip_h = false; _sprite.play("run_right")
# 		"left":  _sprite.flip_h = true;  _sprite.play("run_right")

# func _start_attack() -> void:
# 	if is_dead or is_attacking:
# 		return
# 	is_attacking = true
# 	match facing:
# 		"down":  _sprite.flip_h = false; _sprite.play("attack_down")
# 		"up":    _sprite.flip_h = false; _sprite.play("attack_up")
# 		"right": _sprite.flip_h = false; _sprite.play("attack_right")
# 		"left":  _sprite.flip_h = true;  _sprite.play("attack_right")

# func take_hurt() -> void:
# 	if is_dead or is_hurt:
# 		return
# 	is_hurt = true
# 	match facing:
# 		"down":  _sprite.flip_h = false; _sprite.play("hurt_down")
# 		"up":    _sprite.flip_h = false; _sprite.play("hurt_up")
# 		"right": _sprite.flip_h = false; _sprite.play("hurt_right")
# 		"left":  _sprite.flip_h = true;  _sprite.play("hurt_right")

# func take_death() -> void:
# 	if is_dead:
# 		return
# 	is_dead = true
# 	linear_velocity = Vector2.ZERO
# 	set_physics_process(false)
# 	_sprite.flip_h = false
# 	_sprite.play("death")


# ── Wander ────────────────────────────────────────────────────────────────────

func _begin_pause() -> void:
	is_moving = false
	linear_velocity = Vector2.ZERO
	_play_idle()
	wander_timer.wait_time = randf_range(1.0, 4.0)
	wander_timer.start()


func _begin_move() -> void:
	is_moving = true
	var angle := randf() * TAU
	linear_velocity = Vector2(cos(angle), sin(angle)) * wander_speed
	_update_facing(linear_velocity)
	wander_timer.wait_time = randf_range(1.0, 3.0)
	wander_timer.start()

	# Replace _play_idle() with _play_walk() once walk assets are ready
	_play_idle()
	# _play_walk()


func _update_facing(vel: Vector2) -> void:
	if vel.length_squared() < 1.0:
		return
	if abs(vel.x) >= abs(vel.y):
		facing = "right" if vel.x >= 0.0 else "left"
	else:
		facing = "down" if vel.y >= 0.0 else "up"


func _on_wander_timeout() -> void:
	if is_moving:
		_begin_pause()
	else:
		_begin_move()


# ── Physics / boundary ────────────────────────────────────────────────────────

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	var pos     := state.transform.origin
	var hit_wall := false

	if pos.x < MOB_RADIUS:
		pos.x = MOB_RADIUS
		state.linear_velocity.x = 0.0
		hit_wall = true
	elif pos.x > viewport_rect.size.x - MOB_RADIUS:
		pos.x = viewport_rect.size.x - MOB_RADIUS
		state.linear_velocity.x = 0.0
		hit_wall = true

	if pos.y < MOB_RADIUS:
		pos.y = MOB_RADIUS
		state.linear_velocity.y = 0.0
		hit_wall = true
	elif pos.y > viewport_rect.size.y - MOB_RADIUS:
		pos.y = viewport_rect.size.y - MOB_RADIUS
		state.linear_velocity.y = 0.0
		hit_wall = true

	if hit_wall:
		var t := state.transform
		t.origin = pos
		state.transform = t
		if is_moving:
			call_deferred("_begin_pause")


# ── Animation callbacks ───────────────────────────────────────────────────────

func _on_animation_finished() -> void:
	pass
	# Uncomment each block when its system is implemented:

	# -- Attack --
	# if is_attacking:
	# 	is_attacking = false
	# 	_play_idle()

	# -- Hurt --
	# if is_hurt:
	# 	is_hurt = false
	# 	_play_idle()

	# -- Death --
	# if is_dead:
	# 	queue_free()
