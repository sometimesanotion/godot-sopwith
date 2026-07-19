extends CharacterBody2D

var speed: float = 800.0
var lifetime: float = 2.0
var damage: float = 20.0

var _bullet_owner: Node = null
var _range_percent: float = 0.5
var _max_range: float = 3000.0

func _ready() -> void:
	lifetime = 0.7
	set_meta("bullet", true)

func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0:
		queue_free()
		return

	var motion := transform.x * speed * delta
	var collision := move_and_collide(motion)
	if collision:
		_handle_collision(collision)

func _handle_collision(collision: KinematicCollision2D) -> void:
	var collider = collision.get_collider()
	if collider and collider.has_method("take_damage"):
		if collider == _bullet_owner:
			queue_free()
			return

		if collider.is_in_group("ground_target") and _bullet_owner and _bullet_owner.is_in_group("ground_target"):
			if collider.get("is_enemy") == true and _bullet_owner.get("is_enemy") == true:
				queue_free()
				return

		var dodge_chance: float = 0.0
		var is_dodging: bool = false
		
		if collider.has_method("is_dodging"):
			is_dodging = collider.is_dodging()
			if is_dodging and collider.has_method("get_dodge_chance"):
				dodge_chance = collider.get_dodge_chance()
		
		if not is_dodging:
			var ai_node = collider.get_node_or_null("EnemyAI")
			if ai_node and ai_node.has_method("is_dodging"):
				is_dodging = ai_node.is_dodging()
				if is_dodging and ai_node.has_method("get_dodge_chance"):
					dodge_chance = ai_node.get_dodge_chance()
		
		if is_dodging and randf() < dodge_chance:
			queue_free()
			return
		
		if not is_instance_valid(_bullet_owner):
			queue_free()
			return

		collider.take_damage(damage, _bullet_owner)
		_award_player_score(collider)

	queue_free()

## Applies score for a player's bullet striking something.  Called after damage
## is dealt.  Enemy-plane hits are scored (scaled by damage) by Biplane.take_damage
## itself, so they are not handled here.  Shooting harmless wildlife penalises the
## player (-10 bird, -50 cow / bird flock).  The wildlife penalties use a
## per-instance flag so a multi-hit creature (e.g. a cow) is only scored once
## rather than farmed across many bullets.
func _award_player_score(collider: Node) -> void:
	if not GameManager or not _bullet_owner or not _bullet_owner.is_in_group("player"):
		return

	if collider.is_in_group("bird"):
		if not collider.get("scored_by_player"):
			collider.set("scored_by_player", true)
			GameManager.add_score(0, -10)
		return

	if collider is Cow or collider.is_in_group("flock"):
		if not collider.get("scored_by_player"):
			collider.set("scored_by_player", true)
			GameManager.add_score(0, -50)
		return

func assign_owner(owner: Node2D, range_percent: float = 0.5) -> void:
	_bullet_owner = owner
	_range_percent = range_percent

func get_bullet_owner() -> Node:
	return _bullet_owner