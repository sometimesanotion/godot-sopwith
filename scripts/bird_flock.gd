extends Area2D

const BIRD_SCENE := preload("res://scenes/bird.tscn")
const FLOCK_SCATTER_RADIUS := 80.0
const DRIFT_SPEED := 30.0
const TERRAIN_LENGTH := 16384.0
const EDGE_MARGIN := 500.0

var scatter_triggered: bool = false
var drift_direction: int = 1

func _ready() -> void:
	add_to_group("obstacle")
	add_to_group("destructible")
	add_to_group("flock")
	area_entered.connect(_on_area_entered)
	drift_direction = 1 if randf() < 0.5 else -1

func _on_area_entered(area: Area2D) -> void:
	if scatter_triggered:
		return
	if area.has_method("get_avatar_data") or area.is_in_group("player") or area.is_in_group("destructible"):
		scatter_from(global_position)

func _physics_process(_delta: float) -> void:
	var bodies = get_overlapping_bodies()
	for body in bodies:
		if scatter_triggered:
			return
		if body.has_method("get_avatar_data") or body.is_in_group("player") or body.is_in_group("destructible"):
			scatter_from(global_position)
			return

	if not scatter_triggered:
		global_position.x += drift_direction * DRIFT_SPEED * _delta
		if global_position.x > TERRAIN_LENGTH - EDGE_MARGIN:
			drift_direction = -1
		elif global_position.x < EDGE_MARGIN:
			drift_direction = 1

func scatter_from(pos: Vector2) -> void:
	if scatter_triggered:
		return
	scatter_triggered = true
	var num_birds = 5 + randi() % 5
	for i in range(num_birds):
		var bird = BIRD_SCENE.instantiate()
		bird.global_position = global_position + Vector2(i * 20 - 40, randf() * 30 - 15)
		bird.move_direction = Vector2(100 + randf() * 40, randf() * 20 - 10)
		get_parent().add_child(bird)
		bird.scatter_from(pos)
	queue_free()

func take_damage(amount: float, attacker: Node) -> void:
	scatter_from(global_position)