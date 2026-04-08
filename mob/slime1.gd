extends RigidBody2D

# ── Constants ────────────────────────────────────────────────────────────────

const ASSET_BASE   := "res://assets/Slime1/Without_shadow/"
const IDLE_FRAMES  := 6
const IDLE_FPS     := 8.0

const MOB_RADIUS: float = 30.0

# ── Exports ───────────────────────────────────────────────────────────────────

@export var min_speed: float = 60.0
@export var max_speed: float = 120.0
## Set by the spawning scene to confine the mob within the correct world.
@export var world_size: Vector2 = Vector2(3840.0, 2160.0)

# ── Node refs ─────────────────────────────────────────────────────────────────

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D

# ── State ─────────────────────────────────────────────────────────────────────

var wander_speed: float = 0.0
var wander_timer: Timer
var is_moving: bool = false
var viewport_rect: Rect2   # repurposed as "world_rect" — kept as Rect2 for _integrate_forces
var facing: String = "down"


func _ready() -> void:
	# Tag this mob so SceneManager.record_kill() gets the right type string
	set_meta("monster_type", "slime1")

	viewport_rect = Rect2(Vector2.ZERO, world_size)
	wander_speed  = randf_range(min_speed, max_speed)
	add_to_group("ground_mobs")

	_build_sprite_frames()
	_sprite.animation_finished.connect(_on_animation_finished)

	wander_timer          = Timer.new()
	wander_timer.one_shot = true
	wander_timer.timeout.connect(_on_wander_timeout)
	add_child(wander_timer)

	_begin_move()


## Called by field.gd after instantiation to match the scene's world size.
func set_world_size(size: Vector2) -> void:
	world_size    = size
	viewport_rect = Rect2(Vector2.ZERO, world_size)


# ── Sprite setup ──────────────────────────────────────────────────────────────

func _build_sprite_frames() -> void:
	var sf  := SpriteFrames.new()
	sf.remove_animation("default")

	var idle_dir := ASSET_BASE + "slime1_idle/"

	_add_anim(sf, "idle_down",  idle_dir, "idle_down",  IDLE_FRAMES, IDLE_FPS, true)
	_add_anim(sf, "idle_up",    idle_dir, "idle_up",    IDLE_FRAMES, IDLE_FPS, true)
	_add_anim(sf, "idle_right", idle_dir, "idle_right", IDLE_FRAMES, IDLE_FPS, true)

	_sprite.sprite_frames = sf


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
	_play_idle()


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
	var pos      := state.transform.origin
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
