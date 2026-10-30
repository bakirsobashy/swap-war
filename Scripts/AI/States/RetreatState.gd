extends "res://Scripts/AI/State.gd"

## Panic state: put distance and terrain between us and the threat. The
## refuge is SCORED, not steered at: route cost (don't sprint across the map)
## + a hazard penalty − weighted distance from the threat; the nav route then
## provides the movement — which fixes the old sign(dx)==0 deadlock (a threat
## directly overhead used to freeze retreat, because "away" evaluated to 0).
## An armed retreat still covers fire while running.

const RESCORE_INTERVAL := 0.25   # refuge re-scoring cadence (A* per platform)
const HAZARD_PENALTY := 100.0    # score penalty for hazardous refuge platforms
const THREAT_DISTANCE_WEIGHT := 0.5
## A refuge spot past a threat at our level (owner.is_past_threat) means
## running through its weapon to get there.
const CROSS_PENALTY := 400.0
const SAFE_HOLD_TIME := 0.6      # the exit condition must hold this long
const GRAB_RANGE := 80.0         # a weapon this close gets picked up mid-flight
## Nothing heals, so the health exit can never fire for a low-HP AI: give up
## fleeing after this long and fight for RETREAT_LOCKOUT before fleeing again.
const MAX_RETREAT_TIME := 5.0
const RETREAT_LOCKOUT := 6.0


var _rescore_clock := 0.0
var _safe_clock := 0.0
var _have_refuge := false
var _retreat_clock := 0.0


func get_name() -> String:
	return "Retreat"


func enter() -> void:
	_rescore_clock = 0.0
	_safe_clock = 0.0
	_have_refuge = false
	_retreat_clock = 0.0


func physics_update(delta: float) -> String:
	var threat: Node2D = owner.sensors.nearest_enemy
	if not threat or not owner.sensors.is_valid_target(threat):
		return "Idle"

	var dist: float = owner.actor.global_position.distance_to(threat.global_position)

	# Armed and out of road: turn and fight (the unarmed AI keeps evading —
	# it has no attack at all).
	_retreat_clock += delta
	if owner.is_armed() and _retreat_clock >= MAX_RETREAT_TIME:
		owner.retreat_lockout = RETREAT_LOCKOUT
		owner.nav_cancel()
		return "Idle"

	_cover_fire(threat, dist)

	# Re-pick the refuge on a slow cadence — a full A* per platform per tick
	# buys nothing (the threat barely moves in 0.25 s).
	_rescore_clock -= delta
	if _rescore_clock <= 0.0:
		_rescore_clock = RESCORE_INTERVAL
		_have_refuge = _plan_refuge(threat)

	if not _have_refuge:
		# Nothing routable (no graph, or nothing reachable): direct-steer
		# away, direction from geometry — never sign(dx) alone.
		owner.nav_cancel()
		var dx: float = threat.global_position.x - owner.actor.global_position.x
		var away: float = -signf(dx)
		owner.move_direction = owner.safe_move(away if away != 0.0 \
				else -signf(owner.actor.facing_direction))

	# Exit when the pressure is genuinely off, held: the threat kept beyond
	# safe distance — and for an ARMED retreat (a low-health trigger) health
	# back above the trigger too. The unarmed retreat is a proximity trigger,
	# so distance alone ends it: nothing heals, and the health clause pinned a
	# hurt unarmed AI in hiding until the next swap with weapons on the map.
	var safe: bool = dist > owner.retreat_safe_distance
	if owner.is_armed():
		safe = safe and owner.health_ratio() > owner.retreat_health_ratio + 0.1
	if safe:
		_safe_clock += delta
		if _safe_clock >= SAFE_HOLD_TIME:
			return "Idle"
	else:
		_safe_clock = 0.0

	# Unarmed and a weapon is practically underfoot: grabbing it IS the escape
	# (locked decision: the unarmed AI never fights — armed changes everything).
	if not owner.is_armed() and owner.sensors.best_weapon != null:
		var w = owner.sensors.best_weapon
		if is_instance_valid(w) \
				and owner.actor.global_position.distance_to(w.global_position) <= GRAB_RANGE:
			return "SeekWeapon"

	return ""


## Cover-fire while retreating: an armed retreat still shoots when the threat
## is in reach with clear LOS — the sensors' aim follows the enemy, so this
## is just the trigger (a gun also waits for its muzzle to come round).
func _cover_fire(threat: Node2D, dist: float) -> void:
	if not owner.ai_attack_enabled or not owner.is_armed():
		return
	if dist > owner.attack_reach() or not owner.sensors.has_los_to_enemy:
		return
	if owner.is_ranged_armed() and not owner.ranged_shot_ready(threat):
		return
	owner.wants_attack = true


## Pick the best refuge spot and route to it. Lowest score wins: route cost
## (cheaper = closer) + hazard penalty − weighted distance from the threat
## (farther = better) + a crossing penalty for spots past a level threat.
## Returns false when nothing is routable.
func _plan_refuge(threat: Node2D) -> bool:
	var graph = owner.nav_graph()
	if graph == null:
		return false
	var here: int = owner.sensors.current_platform_id
	if here < 0:
		return false

	var threat_x: float = threat.global_position.x
	var best_pos := Vector2(INF, INF)
	var best_score := INF
	for P in graph.platforms:
		var route = graph.route(here, P.id, P.center(), owner.jump_risk_weight)
		if route == null:
			continue
		var base: float = route.total_cost(owner.jump_risk_weight) \
				+ (HAZARD_PENALTY if bool(P.hazardous) else 0.0)
		# Score BOTH ends, not the center: the wide floor alone spans ~860px
		# and its center can sit closer to the threat than we already stand.
		# Nor just the end farthest from the threat: with the threat between
		# us and that end, the panic walk ran straight through its weapon.
		var pad: float = minf(16.0, P.width() * 0.25)
		for stand_x: float in [P.x_min + pad, P.x_max - pad]:
			var score: float = base - THREAT_DISTANCE_WEIGHT * absf(stand_x - threat_x)
			if owner.is_past_threat(threat, stand_x):
				score += CROSS_PENALTY
			if score < best_score:
				best_score = score
				best_pos = Vector2(stand_x, P.y_top)

	if best_pos.x == INF:
		return false
	owner.nav_to(best_pos)
	return true