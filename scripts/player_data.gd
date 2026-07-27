class_name PlayerData
extends RefCounted

var avatar_id: int = 0
var score: int = 0
var spare_planes: int = 3
var is_player: bool = true
var is_active: bool = false

func reset() -> void:
	spare_planes = 3
	is_active = false
	is_player = false
	score = 0

func set_avatar_id(aid: int) -> void:
	avatar_id = aid
