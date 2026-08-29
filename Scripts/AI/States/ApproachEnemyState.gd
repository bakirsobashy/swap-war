extends "res://Scripts/AI/State.gd"


func get_name() -> String:
	return "ApproachEnemy"


func enter() -> void:
	owner.sensors.reset_unreachable()


func physics_update(_delta: float) -> String:
	var enemy: Node2D = owner.sensors.nearest_enemy

	if not enemy or not owner.sensors.is_valid_target(enemy):
		return "Idle"

	if owner.sensors.is_target_unreachable():
		return "Idle"

	var move_target: Vector2 = owner.pathfinder.get_move_target(enemy.global_position)
	var cmd: Dictionary = owner.navigator.navigate_to(move_target)
	owner.move_direction = cmd.move_direction
	owner.wants_jump = cmd.wants_jump
	owner.wants_drop = cmd.wants_drop

	var dist: float = owner.actor.global_position.distance_to(enemy.global_position)

	# Low health and enemy close: retreat.
	var health_ratio: float = owner.health.current_health / owner.health.max_health
	if health_ratio <= owner.low_health_ratio and dist <= owner.retreat_range:
		return "Retreat"

	# In range and facing the enemy: attack.
	var dx: float = enemy.global_position.x - owner.actor.global_position.x
	var facing_enemy: bool = sign(dx) == owner.actor.facing_direction
	if facing_enemy and _is_in_attack_range(enemy):
		return "Attack"

	return ""


func _is_in_attack_range(enemy: Node2D) -> bool:
	var attack_reach: float = owner.attack_range

	if owner.weapon_holder and owner.weapon_holder.is_holding_weapon():
		var weapon: WeaponBase = owner.weapon_holder.current_weapon
		if weapon:
			attack_reach = max(attack_reach, weapon.get_attack_range())

	return owner.actor.global_position.distance_to(enemy.global_position) <= attack_reach
