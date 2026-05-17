extends Node2D

const BIRD_SCENE := preload("res://scenes/bird.tscn")

func _ready() -> void:
	add_to_group("obstacle")
	var num_birds = 5 + randi() % 5
	for i in range(num_birds):
		var bird = BIRD_SCENE.instantiate()
		bird.global_position = global_position + Vector2(i * 20, randf() * 30 - 15)
		get_parent().add_child(bird)
	queue_free()