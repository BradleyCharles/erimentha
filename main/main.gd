extends Node

@export var mob_scene: PackedScene

var score: int = 0
var active_mobs: int = 0
var game_active: bool = false

const MAX_MOBS: int = 10


func _ready():
	$Player.mob_killed.connect(_on_player_mob_killed)
	$Player.fly_caught.connect(_on_player_fly_caught)


func new_game():
	game_active = false
	get_tree().call_group("mobs", "queue_free")
	active_mobs = 0
	score = 0
	$Player.start($StartPosition.position)
	$HUD.update_score(score)
	$HUD.show_message("Get Ready")
	$Music.play()
	$StartTimer.start()


func game_over():
	if not game_active:
		return
	game_active = false
	$Music.stop()
	$DeathSound.play()
	get_tree().call_group("mobs", "queue_free")
	active_mobs = 0
	$HUD.show_score_entry(score)


func _on_player_fly_caught():
	if not game_active:
		return
	game_active = false
	score += 10
	$HUD.update_score(score)
	$Music.stop()
	$DeathSound.play()
	get_tree().call_group("mobs", "queue_free")
	active_mobs = 0
	$HUD.show_score_entry(score)


func _on_start_timer_timeout():
	game_active = true
	for i in MAX_MOBS:
		_spawn_mob()


func _spawn_mob():
	if not game_active or active_mobs >= MAX_MOBS:
		return
	var mob = mob_scene.instantiate()
	var vp = get_viewport().get_visible_rect()
	mob.position = Vector2(
		randf_range(100.0, vp.size.x - 100.0),
		randf_range(100.0, vp.size.y - 100.0)
	)
	add_child(mob)
	active_mobs += 1


func _on_player_mob_killed(mob_body: Node):
	var points = 10 if mob_body.is_in_group("flying_mobs") else 1
	mob_body.queue_free()
	active_mobs -= 1
	score += points
	$HUD.update_score(score)
	var timer = get_tree().create_timer(randf_range(3.0, 10.0))
	timer.timeout.connect(_spawn_mob)


# Kept for scene signal compatibility
func _on_mob_timer_timeout():
	pass

func _on_score_timer_timeout():
	pass
