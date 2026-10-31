extends "res://Scripts/AI/State.gd"

## Close the distance to the enemy — but only to the stand-off point, not the
## enemy's face: melee edges in at 75% of reach, ranged holds 65% of the
## weapon's effective range so kiting has room to work. Movement is fully
## executor-owned (no_route degrades to a brief direct charge). Facing writes
## are gone — the controller's facing_intent owns facing.

const DIRECT_STEER_TIME := 1.2
const FEET_DOWN := 31.0          # capsule bottom below the body origin (executor's convention)
const EDGE_PAD := 12.0           # keep stand points off the very lip of a platform


var _direct_steer_clock := 0.0
## Set once a gun's lane has stayed blocked during this approach: from then
## on it heads for the enemy's platform and keeps that goal until Attack. A
## lane flickering at the top of a hop used to flip the goal mid-air at full
## speed — and carried the body into the spikes beside the old stand-off.
var _lane_seek := false


func get_name() -> String:
	return "ApproachEnemy"


func enter() -> void:
	_direct_steer_clock = 0.0
	_lane_seek = false


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
	if owner.should_retreat(dist):
		return "Retreat"

	# In reach: hand over to the exchange state — on the ground only (Attack
	# cancels the route, and mid-jump that drops the body short: into the
	# gap or the spikes it was clearing). A gun also needs a lane; in range
	# behind cover means keep moving until one opens.
	var in_reach: bool = dist <= owner.attack_reach()
	if in_reach and owner.actor.is_grounded() \
			and (not owner.is_ranged_armed() or owner.sensors.has_los_to_enemy):
		return "Attack"
	# In reach on the move (mid-jump, or a lane that only opens at the top of
	# a hop): strike anyway when it would land — the route keeps the legs.
	if in_reach and owner.ai_attack_enabled:
		owner.wants_attack = owner.attack_ready(enemy)

	if owner.is_ranged_armed() and owner.los_blocked():
		_lane_seek = true
	var rc: StringName = owner.nav_to(_approach_point(enemy))
	if rc != &"ok":
		_direct_steer_clock += delta
		if _direct_steer_clock > DIRECT_STEER_TIME:
			return "Idle"
		# Unroutable enemy (isolated ledge): charge straight at it for a
		# while, then let the hub re-decide. No active goal, so this write
		# survives the executor.
		owner.move_direction = owner.safe_move(signf(enemy.global_position.x
				- owner.actor.global_position.x))
		return ""
	_direct_steer_clock = 0.0
	return ""


## Where to go. A gun with a working lane holds its stand-off on the line
## between us (any level — kiting room). Melee, or a gun hunting for a lane,
## goes to the enemy's own platform.
func _approach_point(enemy: Node2D) -> Vector2:
	if owner.is_ranged_armed() and not _lane_seek:
		return _line_standoff_point(enemy)
	return _platform_standoff_point(enemy)


## Standoff-distance away from the enemy, on our side of the line between
## us. Only reached while still outside attack reach, so the point always
## lies between the two bodies.
func _line_standoff_point(enemy: Node2D) -> Vector2:
	var to_us: Vector2 = owner.actor.global_position - enemy.global_position
	var dir: Vector2 = to_us.normalized() if to_us.length() > 1.0 else Vector2.LEFT
	return enemy.global_position + dir * owner.combat_standoff()


## Standoff-distance beside the enemy on OUR side, clamped onto the platform
## it stands on. A point on the bare line could fall off a ledge lip onto the
## floor below: the route "arrived" right under the enemy and the AI parked
## there, out of reach, forever.
func _platform_standoff_point(enemy: Node2D) -> Vector2:
	var ex: float = enemy.global_position.x
	var side: float = signf(owner.actor.global_position.x - ex)
	if side == 0.0:
		side = 1.0
	var want_x: float = ex + side * owner.combat_standoff()
	var graph = owner.nav_graph()
	if graph == null:
		return Vector2(want_x, enemy.global_position.y)
	var pid: int = graph.platform_below(enemy.global_position + Vector2(0.0, FEET_DOWN))
	if pid < 0:
		return enemy.global_position     # over a pit: chase the body itself
	var P = graph.platforms[pid]
	var pad: float = minf(EDGE_PAD, P.width() * 0.25)
	return Vector2(clampf(want_x, P.x_min + pad, P.x_max - pad), P.y_top - 8.0)


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
