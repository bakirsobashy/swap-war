extends "res://Scripts/AI/State.gd"

## Close the distance to the enemy — but only to the stand-off point, not the
## enemy's face: melee edges in at 75% of reach, ranged holds 65% of the
## weapon's effective range so kiting has room to work. Movement is fully
## executor-owned (no_route degrades to a brief direct charge). Facing writes
## are gone — the controller's facing_intent owns facing.

const DIRECT_STEER_TIME := 1.2


var _direct_steer_clock := 0.0


func get_name() -> String:
	return "ApproachEnemy"


func enter() -> void:
	_direct_steer_clock = 0.0


func physics_update(delta: float) -> String:
	# Recover a weapon before continuing to fight (it may have broken mid-swap).
	var unarmed_transition := _transition_if_unarmed()
	if unarmed_transition:
		return unarmed_transition

	var enemy: Node2D = owner.sensors.nearest_enemy
	if not enemy or not owner.sensors.is_valid_target(enemy):
		return "Idle"

	var dist: float = owner.actor.global_position.distance_to(enemy.global_position)

	# Low health and enemy close: disengage.
	if owner.health_ratio() <= owner.retreat_health_ratio \
			and dist <= owner.retreat_range:
		return "Retreat"

	# In reach: hand over to the exchange state.
	if dist <= owner.attack_reach():
		return "Attack"

	var rc: StringName = owner.nav_to(_standoff_point(enemy))
	if rc != &"ok":
		_direct_steer_clock += delta
		if _direct_steer_clock > DIRECT_STEER_TIME:
			return "Idle"
		# Unroutable enemy (isolated ledge): charge straight at it for a
		# while, then let the hub re-decide. No active goal, so this write
		# survives the executor.
		owner.move_direction = signf(enemy.global_position.x
				- owner.actor.global_position.x)
		return ""
	_direct_steer_clock = 0.0
	return ""


## Where this AI wants to STAND: standoff-distance away from the enemy, on our
## side of the line between us. Only reached while still outside attack
## reach, so the point always lies between the two bodies.
func _standoff_point(enemy: Node2D) -> Vector2:
	var to_us: Vector2 = owner.actor.global_position - enemy.global_position
	var dir: Vector2 = to_us.normalized() if to_us.length() > 1.0 else Vector2.LEFT
	return enemy.global_position + dir * owner.combat_standoff()


## Unarmed mid-approach (weapon broke): the hub rules apply — a known weapon
## wins, a close enemy means evade, otherwise back to the hub for Patrol.
func _transition_if_unarmed() -> String:
	if owner.is_armed():
		return ""
	if owner.sensors.best_weapon != null:
		return "SeekWeapon"
	var enemy: Node2D = owner.sensors.nearest_enemy
	if enemy and owner.sensors.is_valid_target(enemy) \
			and owner.actor.global_position.distance_to(enemy.global_position) <= owner.retreat_range:
		return "Retreat"
	return "Idle"