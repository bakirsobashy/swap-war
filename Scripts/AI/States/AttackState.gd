extends "res://Scripts/AI/State.gd"

const MIN_TIME: float = 0.25
const ATTACK_COOLDOWN: float = 0.35

var _state_timer: float = 0.0
var _attack_timer: float = 0.0


func get_name() -> String:
	return "Attack"


func enter() -> void:
	owner.move_direction = 0.0
	owner.wants_jump = false
	owner.wants_drop = false
	owner.wants_attack = false
	_state_timer = MIN_TIME
	_attack_timer = 0.0


func physics_update(delta: float) -> String:
	_state_timer -= delta
	_attack_timer -= delta

	# Recover a weapon before continuing to fight.
	var unarmed_transition := _transition_if_unarmed()
	if unarmed_transition:
		return unarmed_transition

	var enemy: Node2D = owner.sensors.nearest_enemy
	if not enemy or not owner.sensors.is_valid_target(enemy):
		return "Idle"

	# Always face the enemy.
	var dx: float = enemy.global_position.x - owner.actor.global_position.x
	if dx != 0.0:
		owner.actor.facing_direction = sign(dx)

	var dist: float = owner.actor.global_position.distance_to(enemy.global_position)

	# Low health and enemy close: retreat.
	var health_ratio: float = owner.health.current_health / owner.health.max_health
	if health_ratio <= owner.low_health_ratio and dist <= owner.retreat_range:
		return "Retreat"

	# If the enemy left attack range, chase again.
	if not _is_in_attack_range(enemy):
		if _state_timer <= 0.0:
			return "ApproachEnemy"
		return ""

	# Keep attacking at intervals while in range.
	if owner.ai_attack_enabled and _attack_timer <= 0.0:
		owner.wants_attack = true
		_attack_timer = ATTACK_COOLDOWN
	else:
		owner.wants_attack = false

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
