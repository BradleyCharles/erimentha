extends RigidBody2D

var mob_type: String = ""
var wander_speed: float = 0.0
var wander_timer: Timer
var is_moving: bool = false
var viewport_rect: Rect2

const MOB_RADIUS: float = 40.0

func _ready():
	viewport_rect = get_viewport_rect()
	wander_speed = randf_range(80.0, 160.0)

	# Apply mob type (set externally before add_child)
	if mob_type == "":
		mob_type = ["walk", "swim"].pick_random()
	$AnimatedSprite2D.animation = mob_type
	$AnimatedSprite2D.play()

	if mob_type == "fly":
		add_to_group("flying_mobs")
	else:
		add_to_group("ground_mobs")

	# Programmatic wander timer
	wander_timer = Timer.new()
	wander_timer.one_shot = true
	wander_timer.timeout.connect(_on_wander_timeout)
	add_child(wander_timer)

	# Randomly start moving or pausing so mobs don't all move in sync
	if randf() < 1:
		_begin_move()
	else:
		_begin_pause()


func _begin_pause():
	is_moving = false
	linear_velocity = Vector2.ZERO
	wander_timer.wait_time = randf_range(1.0, 4.0)
	wander_timer.start()


func _begin_move():
	is_moving = true
	var angle = randf() * TAU
	linear_velocity = Vector2(cos(angle), sin(angle)) * wander_speed
	wander_timer.wait_time = randf_range(1.0, 3.0)
	wander_timer.start()


func _on_wander_timeout():
	if is_moving:
		_begin_pause()
	else:
		_begin_move()


func _integrate_forces(state: PhysicsDirectBodyState2D):
	var pos = state.transform.origin
	var hit_wall = false

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
		var t = state.transform
		t.origin = pos
		state.transform = t
		if is_moving:
			call_deferred("_begin_pause")


# Kept to avoid signal errors if the notifier is still connected — mobs no longer auto-despawn
func _on_visible_on_screen_notifier_2d_screen_exited():
	pass
