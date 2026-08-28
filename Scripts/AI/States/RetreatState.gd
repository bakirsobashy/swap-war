extends "res://Scripts/AI/State.gd"


func get_name() -> String:
	return "Retreat"


func physics_update(_delta: float) -> String:
	var threat: Node2D = owner.sensors.nearest_enemy

	if not threat or not owner.sensors.is_valid_target(threat):
		return "Idle"

	var dx: float = threat.global_position.x - owner.actor.global_position.x
	var away: float = -sign(dx)
	owner.actor.facing_direction = away

	var run_target: Vector2 = owner.actor.global_position + Vector2(away * 100.0, 0.0)
	var move_target: Vector2 = owner.pathfinder.get_move_target(run_target)
	var cmd: Dictionary = owner.navigator.navigate_to(move_target)

	owner.move_direction = away
	owner.wants_jump = cmd.wants_jump
	owner.wants_drop = false
	owner.wants_attack = false

	# If we are unarmed and a weapon is nearby, grab it on the way.
	if owner.sensors.nearest_weapon and owner.weapon_holder and not owner.weapon_holder.is_holding_weapon():
		return "SeekWeapon"

	# Health recovered and enemy is far enough: stop retreating.
	var health_ratio: float = owner.health.current_health / owner.health.max_health
	if health_ratio > owner.low_health_ratio and abs(dx) > owner.retreat_safe_distance:
		return "Idle"

	return ""
