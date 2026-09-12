extends "res://Scripts/AI/State.gd"


func get_name() -> String:
	return "ApproachEnemy"


func enter() -> void:
	owner.sensors.reset_unreachable()


func physics_update(_delta: float) -> String:
	# Recover a weapon before continuing to fight.
	var unarmed_transition := _transition_if_unarmed()
	if unarmed_transition:
		return unarmed_transition

	var enemy: Node2D = owner.sensors.nearest_enemy

	if not enemy or not owner.sensors.is_valid_target(enemy):
		return "Idle"

	if owner.sensors.is_target_unreachable():
		return "Idle"

	var dist: float = owner.actor.global_position.distance_to(enemy.global_position)

	# Low health and enemy close: retreat.
	var health_ratio: float = owner.health.current_health / owner.health.max_health
	if health_ratio <= owner.low_health_ratio and dist <= owner.retreat_range:
		return "Retreat"

	# In range: attack.
	if _is_in_attack_range(enemy):
		var dx: float = enemy.global_position.x - owner.actor.global_position.x
		if dx != 0.0:
			owner.actor.facing_direction = sign(dx)
		return "Attack"

	# Move toward enemy.
	var move_target: Vector2 = owner.pathfinder.get_move_target(enemy.global_position)
	var cmd: Dictionary = owner.navigator.navigate_to(move_target)
	owner.move_direction = cmd.move_direction
	owner.wants_jump = cmd.wants_jump
	owner.wants_drop = cmd.wants_drop

	# While approaching, face the direction we are moving or the enemy.
	var approach_dx: float = move_target.x - owner.actor.global_position.x
	if abs(approach_dx) > 4.0:
		owner.actor.facing_direction = sign(approach_dx)

	return ""


func _is_in_attack_range(enemy: Node2D) -> bool:
	var attack_reach: float = owner.attack_range

	if owner.weapon_holder and owner.weapon_holder.is_holding_weapon():
		var weapon: WeaponBase = owner.weapon_holder.current_weapon
		if weapon:
			attack_reach = max(attack_reach, weapon.get_attack_range())

	return owner.actor.global_position.distance_to(enemy.global_position) <= attack_reach


func _transition_if_unarmed() -> String:
	if owner.weapon_holder and owner.weapon_holder.is_holding_weapon():
		return ""
	if owner.sensors.nearest_weapon:
		return "SeekWeapon"
	return "Retreat"
