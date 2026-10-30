extends "res://Scripts/AI/State.gd"

## Fetch the best-scored weapon. The route runs via the nav executor; the
## PickupArea component does the actual grab on overlap. No route (weapon on
## an isolated prop): direct-steer at it briefly, then bounce through the hub
## so a better opportunity can take over.

const DIRECT_STEER_TIME := 1.2
const UNREACHABLE_BAN := 8.0


var _direct_steer_clock := 0.0


func get_name() -> String:
	return "SeekWeapon"


func enter() -> void:
	_direct_steer_clock = 0.0


func physics_update(delta: float) -> String:
	# Do not cast to WeaponBase here: if the cached weapon was freed since the
	# last sensors refresh, a typed assignment would throw "invalid previously
	# freed instance". Validate first, then use.
	var weapon = owner.sensors.best_weapon

	if not weapon or not is_instance_valid(weapon) or weapon.is_held():
		return "Idle"

	# Picked it up (or grabbed some other drop on the way) — the hub decides
	# what comes next: fight, retreat, patrol.
	if owner.is_armed():
		return "Idle"

	# A hostile this close while we are unarmed outranks the fetch — running
	# for a sword with an enemy on our heels is how unarmed AIs die.
	var enemy: Node2D = owner.sensors.nearest_enemy
	if enemy and owner.sensors.is_valid_target(enemy) \
			and _dist_to(enemy) < owner.retreat_range:
		return "Retreat"

	# nav_to is throttled per-tick by the controller; while the goal is fresh
	# it is a no-op returning &"ok" and the executor keeps driving.
	var rc: StringName = owner.nav_to(weapon.global_position)
	if rc != &"ok":
		_direct_steer_clock += delta
		if _direct_steer_clock > DIRECT_STEER_TIME:
			# Unreachable: drop it from scoring for a while, or the hub picks
			# the same weapon again and this loops forever.
			owner.sensors.blacklist_weapon(weapon, UNREACHABLE_BAN)
			owner.sensors.best_weapon = null
			return "Idle"
		# No route and no active goal — the state's write survives (the
		# executor only overwrites inputs while a goal is running).
		owner.move_direction = owner.safe_move(signf(weapon.global_position.x
				- owner.actor.global_position.x))
		return ""
	_direct_steer_clock = 0.0
	return ""


func _dist_to(other: Node2D) -> float:
	return owner.actor.global_position.distance_to(other.global_position)
