extends "res://Scripts/AI/State.gd"


func get_name() -> String:
	return "Idle"


func physics_update(_delta: float) -> String:
	owner.move_direction = 0.0
	owner.wants_jump = false
	owner.wants_drop = false
	owner.wants_attack = false

	var has_weapon: bool = owner.weapon_holder != null and owner.weapon_holder.is_holding_weapon()
	var has_weapon_pickup: bool = owner.sensors.nearest_weapon != null
	var enemy: Node2D = owner.sensors.nearest_enemy
	var enemy_valid: bool = owner.sensors.is_valid_target(enemy)

	if not has_weapon:
		if has_weapon_pickup:
			return "SeekWeapon"
		if enemy_valid:
			return "Retreat"

	if enemy_valid:
		return "ApproachEnemy"

	return ""
