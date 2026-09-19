extends "res://Scripts/AI/State.gd"

## NEW (decision-layer rewrite): idle wandering with a purpose. The other
## states all need something (enemy, weapon); Patrol is what an armed AI with
## no enemies left does, and what an unarmed one does while waiting for a
## drop. Picks a random reachable platform within ~2 hops and walks there.

const HOP_REACH := 520.0        # ~2 platform hops — wander radius for the next target
const JITTER := 48.0            # random offset from the picked platform's center
const EDGE_PAD := 8.0           # keep hop targets off the very lip of a platform


var _hop_clock := 0.0


func get_name() -> String:
	return "Patrol"


func enter() -> void:
	_hop_clock = 0.0
	_plan_hop()


func exit() -> void:
	owner.nav_cancel()


func physics_update(delta: float) -> String:
	# The hub conditions outrank patrolling — bounce back the instant one
	# fires (armed with an enemy to fight, unarmed with a weapon to fetch).
	var enemy: Node2D = owner.sensors.nearest_enemy
	if owner.is_armed() and owner.sensors.is_valid_target(enemy):
		return "Idle"
	if not owner.is_armed() and owner.sensors.best_weapon != null:
		return "Idle"

	_hop_clock -= delta
	if owner.nav_arrived() or owner.nav_failed() or _hop_clock <= 0.0:
		_plan_hop()
	return ""


func _plan_hop() -> void:
	_hop_clock = owner.patrol_hop_interval
	var target := _pick_hop_target()
	if target.x != INF:
		owner.nav_to(target)


## A random non-hazardous platform reachable from here and within ~2 hops,
## jittered off its center. Unreachable picks are filtered out; if nothing
## qualifies (isolated platform — Flat's floor has no outgoing routes) the
## hop degrades to wandering in place on the current platform, which is the
## designed Flat behavior ("patrol-hops, nothing to jump to").
func _pick_hop_target() -> Vector2:
	var graph = owner.nav_graph()
	if graph == null or graph.platforms.is_empty():
		return Vector2(INF, INF)
	var actor_x: float = owner.actor.global_position.x
	var here: int = owner.sensors.current_platform_id

	var candidates: Array = []
	for P in graph.platforms:
		if bool(P.hazardous) or P.id == here:
			continue
		if here >= 0 and not graph.has_path(here, P.id, owner.jump_risk_weight):
			continue
		if absf(P.center() - actor_x) > HOP_REACH:
			continue
		candidates.append(P)

	if candidates.is_empty():
		if here < 0:
			return Vector2(INF, INF)
		var cur = graph.platforms[here]
		var x: float = clampf(actor_x + randf_range(-HOP_REACH, HOP_REACH),
				cur.x_min + EDGE_PAD, cur.x_max - EDGE_PAD)
		return Vector2(x, cur.y_top)

	var P = candidates[randi() % candidates.size()]
	var x: float = clampf(P.center() + randf_range(-JITTER, JITTER),
			P.x_min + EDGE_PAD, P.x_max - EDGE_PAD)
	return Vector2(x, P.y_top)