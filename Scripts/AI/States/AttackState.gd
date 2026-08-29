extends "res://Scripts/AI/State.gd"

const MIN_TIME: float = 0.25

var _timer: float = 0.0


func get_name() -> String:
	return "Attack"


func enter() -> void:
	owner.move_direction = 0.0
	owner.wants_jump = false
	owner.wants_drop = false

	if owner.ai_attack_enabled:
		owner.wants_attack = true

	_timer = MIN_TIME


func physics_update(delta: float) -> String:
	_timer -= delta

	var enemy: Node2D = owner.sensors.nearest_enemy
	if not enemy or not owner.sensors.is_valid_target(enemy):
		return "Idle"

	var dx: float = enemy.global_position.x - owner.actor.global_position.x
	if dx != 0.0:
		owner.actor.facing_direction = sign(dx)

	var dist: float = owner.actor.global_position.distance_to(enemy.global_position)
	var health_ratio: float = owner.health.current_health / owner.health.max_health
	if health_ratio <= owner.low_health_ratio and dist <= owner.retreat_range:
		return "Retreat"

	if _timer <= 0.0 and not _is_in_attack_range(enemy):
		return "ApproachEnemy"

	return ""


func _is_in_attack_range(enemy: Node2D) -> bool:
	var attack_reach: float = owner.attack_range

	if owner.weapon_holder and owner.weapon_holder.is_holding_weapon():
		var weapon: WeaponBase = owner.weapon_holder.current_weapon
		if weapon:
			attack_reach = max(attack_reach, weapon.get_attack_range())

	return owner.actor.global_position.distance_to(enemy.global_position) <= attack_reach
