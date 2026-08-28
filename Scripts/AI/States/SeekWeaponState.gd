extends "res://Scripts/AI/State.gd"


func get_name() -> String:
	return "SeekWeapon"


func physics_update(_delta: float) -> String:
	var weapon: Weapon = owner.sensors.nearest_weapon

	if not weapon or not is_instance_valid(weapon) or weapon.is_held():
		return "Idle"

	var move_target: Vector2 = owner.pathfinder.get_move_target(weapon.global_position)
	var cmd: Dictionary = owner.navigator.navigate_to(move_target)
	owner.move_direction = cmd.move_direction
	owner.wants_jump = cmd.wants_jump
	owner.wants_drop = cmd.wants_drop

	# If we picked the weapon up, decide what to do next.
	if owner.weapon_holder and owner.weapon_holder.is_holding_weapon():
		if owner.sensors.nearest_enemy:
			return "ApproachEnemy"
		return "Idle"

	# If a hostile enemy gets too close while we are unarmed, run.
	var enemy: Node2D = owner.sensors.nearest_enemy
	if enemy and owner.sensors.is_valid_target(enemy):
		var dist: float = owner.actor.global_position.distance_to(enemy.global_position)
		if dist < owner.retreat_range:
			return "Retreat"

	return ""
