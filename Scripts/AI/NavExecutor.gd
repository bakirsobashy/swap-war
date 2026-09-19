class_name NavExecutor
extends RefCounted

## Executes NavGraph routes edge-by-edge over real physics (plan step 4).
##
## One executor per AIController. While a goal is active it OWNS the three
## movement inputs (move_direction / wants_jump / wants_drop) and overwrites
## them every physics tick — AIController runs it AFTER the decision machine,
## so it always has the last word. When the goal ends (arrived / failed /
## canceled) it writes zeros once and stops writing, handing control back.
##
## Phase machine:
##   approach  — grounded, steering at the pending edge's launch/land point;
##               walks advance on tier-1 localization, jumps/drops commit on
##               precise windows, then flip to airborne.
##   airborne  — in flight (committed edge) or pre-launch air (spawn fall,
##               slide-off): drift toward land_x, brake overshoot, confirm
##               the landing by localization.
##   recover   — off-route: under-geometry tier-3 lies walk to the localized
##               platform's REAL cells first (covered tiles under a ramp
##               localize to a platform the actor is not actually on), then
##               replan; airborne recover drifts to the platform below.
##
## Robustness ladder, all bounded:
##   - stuck (no progress toward the phase target for 0.75 s): micro-jump;
##     second occurrence bans the edge and replans (or escapes to real cells
##     first when localization is lying, or fails on a stuck final segment).
##   - a jump/drop that lands back on its source: re-attempt twice, then
##     blacklist the edge for 3 s and replan.
##   - graph revision bump (hazard added/removed): replan.
##   - every terminal path writes status &"failed" — the owning state falls
##     back to direct steering; nothing hangs.
##
## Compile-safety: no autoloads, no preloads — pure duck-typed logic over
## (controller, actor, graph), so headless `-s` probes drive it directly.

# --- tuning (world px / seconds — layout- and tile-size-agnostic) ----------
const ARRIVE_TOL := 28.0          # final-segment arrival window
const LAUNCH_TOL := 14.0          # jump_up commit window around launch_x
const LAUNCH_BACK := 34.0         # jump_up commit reach SHORT of launch_x
const DROP_COMMIT_TOL := 12.0     # drop_through commit window around drop_x
const JUMP_SPEED_MIN := 200.0     # full-speed commit for jump_across
const RUNUP_SLACK := 12.0         # how far behind launch_x a run-up may commit
const EDGE_GUARD := 10.0          # stop-line before the edge in a run-up
const BRAKE_DECEL := 1000.0       # ground braking ≈ run accel, assumed weaker (fires the stop-line early)
const BACKOFF_DIST := 64.0        # retreat when a run-up misses its window
const STEER_GAIN := 48.0          # proportional steering distance
const AIR_MAX_TIME := 1.4         # airborne sanity bound (legit falls < 1.1 s)
const AIR_BELIEVE_TIME := 0.15    # liftoff contact tail: "grounded" this soon after a commit is not a landing
const AIR_DRIFT_GAIN := 64.0      # drift input = (target - x) / gain
const AIR_BRAKE_DIST := 32.0      # brake when about to overshoot the target
const STUCK_TIME := 0.75
const STUCK_EPS := 10.0           # target-distance improvement that resets the clock
const EDGE_MAX_ATTEMPTS := 2
const BLACKLIST_SECONDS := 3.0
const RECOVER_MAX_TIME := 3.0
const FEET_DOWN := 31.0            # capsule bottom below the body origin
const NO_CELL := Vector2i(9999, 9999)

const PHASE_IDLE := &"idle"
const PHASE_APPROACH := &"approach"
const PHASE_AIRBORNE := &"airborne"
const PHASE_RECOVER := &"recover"

const STATUS_IDLE := &"idle"
const STATUS_MOVING := &"moving"
const STATUS_ARRIVED := &"arrived"
const STATUS_FAILED := &"failed"

# --- wiring (duck-typed; setup() by AIController) ----------------------------
var _controller: Node = null
var _actor: Node = null
var _graph: RefCounted = null

# --- goal --------------------------------------------------------------------
var _route = null                 # graph Route, or null when no goal is active
var _route_index := 0             # index of the pending edge (== size: final)
var _dest_x := 0.0
var _dest_platform := -1
var _dest_pos := Vector2(INF, INF)  # clamped dest point on its platform
var _status: StringName = STATUS_IDLE
var _phase: StringName = PHASE_IDLE

# --- per-edge / recovery state ------------------------------------------------
var _edge_attempts := 0
var _edge_committed := false      # a jump/drop was asserted for the pending edge
var _air_time := 0.0
var _air_target := 0.0           # drift target while airborne
var _backoff_x := NAN            # active run-up retry point (NAN = none)
var _stuck_clock := 0.0
var _stuck_best := INF
var _stuck_count := 0
var _recover_clock := 0.0
var _banned: Dictionary = {}      # Vector2i(from, to) -> expiry (clock seconds)
var _clock := 0.0                 # monotonic accumulated delta
var _graph_revision := -1
var _replan_asap := false
var _capsule_radius_cache := -1.0  # actor collision half-width, read once
var _risk_weight := 1.0           # jump-risk appetite for routing (AIDifficulty)

# --- per-tick outputs ----------------------------------------------------------
var _move := 0.0
var _jump := false
var _drop := false


# --- lifecycle ------------------------------------------------------------------

func setup(controller: Node, actor: Node) -> void:
	_controller = controller
	_actor = actor

func set_graph(graph: RefCounted) -> void:
	if graph == _graph:
		return
	_graph = graph
	_reset_goal()
	_graph_revision = graph.revision if graph != null else -1

func has_graph() -> bool:
	return _graph != null and not _graph.platforms.is_empty()

func status() -> StringName:
	return _status

func cancel() -> void:
	_reset_goal()

func on_respawn() -> void:
	_reset_goal()
	_banned.clear()

## The controller's hazard-escape override calls this when it takes over the
## inputs: the live route may now cross a brand-new hazard, so replan ASAP.
func notify_hazard() -> void:
	_replan_asap = true

## Re-derive the route on the next update (team swap flipped who counts as an
## enemy; the goal itself stays). The decision layer's general-purpose twin of
## notify_hazard().
func replan_soon() -> void:
	_replan_asap = true

## Jump-risk appetite for routing (AIDifficulty's jump_risk_weight): scales
## jump costs so a cautious profile takes the long safe way around.
func set_risk_weight(w: float) -> void:
	_risk_weight = maxf(w, 0.1)

## The baked graph this executor runs on (null before the first set_graph) —
## the decision layer (Sensors platform ids, Retreat refuge scoring, Patrol
## hop picking) reads platform data through the controller, via this.
func graph() -> RefCounted:
	return _graph

## Plan a fresh goal at world position `pos`. Replaces the previous goal only
## on success (&"ok"); on &"no_route" the previous goal (if any) keeps running.
## States that need direct control must call cancel() first.
func plan_to(pos: Vector2) -> StringName:
	if not has_graph():
		return &"no_route"
	var dest_id: int = _graph.platform_below(pos)
	if dest_id < 0:
		dest_id = _graph.nearest_platform(pos)
	if dest_id < 0:
		return &"no_route"
	var dest = _graph.platforms[dest_id]
	var dx: float = clampf(pos.x, dest.x_min, dest.x_max)
	# A rebuilt graph's platform ids and edges are all new objects — bans
	# from the previous layout are meaningless (a stale [from,to] pair could
	# even blacklist an innocent new edge for its remaining seconds).
	if _graph.revision != _graph_revision:
		_banned.clear()
	# A genuinely fresh destination forgets old bans; replans of the SAME
	# goal keep them — that is what makes a dead edge stay dead instead of
	# looping ban -> no-route -> clear -> re-admit -> re-fail forever.
	if dest_id != _dest_platform:
		_banned.clear()
	var r = _route_from(_localize_now(), dest_id, dx)
	if r == null:
		return &"no_route"
	# Same goal, same pending edge: a throttled refresh (the destination
	# drifted but is still reached the same way) KEEPS the per-edge
	# attempt/stuck ladders — wiping them on every refresh would reset the
	# guard/backoff cycle each time, and a dead edge could never accumulate
	# its way to a ban. A different pending edge starts its ladders fresh.
	var same_edge := false
	if dest_id == _dest_platform and _status == STATUS_MOVING:
		var old = _pending_edge()
		if old != null and not r.edges.is_empty() \
				and old.from_id == r.edges[0].from_id and old.to_id == r.edges[0].to_id:
			same_edge = true
	_dest_x = dx
	_dest_platform = dest_id
	_dest_pos = Vector2(dx, dest.y_top)
	_route = r
	_route_index = 0
	if not same_edge:
		_edge_attempts = 0
		_stuck_count = 0
		_recover_clock = 0.0
	_reset_stuck()
	_replan_asap = false
	_graph_revision = _graph.revision
	_set_status(STATUS_MOVING)
	_enter_phase_by_ground()
	return &"ok"

func update(delta: float) -> void:
	_clock += delta
	_move = 0.0
	_jump = false
	_drop = false
	if _status != STATUS_MOVING:
		return
	if _graph == null or _route == null:
		_finish(STATUS_FAILED)
		_write_inputs()
		return
	if _graph.revision != _graph_revision or _replan_asap:
		_replan_asap = false
		_replan()
		if _status != STATUS_MOVING:
			_write_inputs()
			return
	var grounded := _is_grounded_now()
	match _phase:
		PHASE_APPROACH:
			_update_approach(delta, grounded)
		PHASE_AIRBORNE:
			_update_airborne(delta, grounded)
		PHASE_RECOVER:
			_update_recover(delta, grounded)
	_write_inputs()


# --- approach -------------------------------------------------------------------

func _update_approach(delta: float, grounded: bool) -> void:
	if not grounded:
		# Slid off / knocked off mid-approach: treat the flight as airborne
		# for the pending edge (walks confirm on the far side, jumps re-arm).
		_edge_committed = false
		_air_time = 0.0
		_air_target = _air_aim_x()
		_phase = PHASE_AIRBORNE
		return

	# Unified localization watch: crossing onto any LATER route platform
	# advances (this is how walks finish); dropping back off-route recovers.
	var loc := _localize_now()
	var j: int = _route.platform_ids.find(loc)
	var e = _pending_edge()
	if j > _route_index:
		_advance_to(j)
		e = _pending_edge()
	elif j == -1 or j < _route_index:
		_off_route(loc)
		return

	if e == null:
		_update_final(delta)
		return
	var stuck_target := _target_x_for(e)
	if not is_nan(_backoff_x):
		stuck_target = _backoff_x
	if _run_stuck(delta, stuck_target):
		return

	match String(e.type):
		"walk":
			_approach_walk(e)
		"jump_up":
			_approach_jump_up(e)
		"jump_across":
			_approach_jump_across(e, grounded)
		"drop_down":
			_approach_drop(e)
		_:
			# force_link may inject exotic types; treat as a level walk.
			_approach_walk(e)

func _approach_walk(e) -> void:
	_move = _steer(e.land_x, _slope_mode(e))

func _approach_jump_up(e) -> void:
	var dir: float = signf(e.land_x - e.launch_x)
	if dir == 0.0:
		dir = 1.0
	_move = _steer(e.launch_x, false)
	# Asymmetric commit window: the actor may be up to LAUNCH_BACK short of
	# launch_x but only LAUNCH_TOL past it. A launch point clamped onto a seam
	# the actor cannot physically reach (capsule radius pressed against the
	# destination's face, e.g. RightBlock's west side) must still commit — the
	# airborne drift toward land_x covers the shortfall.
	var dx_rel: float = (_actor_x() - e.launch_x) * dir
	if dx_rel <= LAUNCH_TOL and dx_rel >= -LAUNCH_BACK:
		_jump = true
		_commit_air(e.land_x)

func _approach_jump_across(e, grounded: bool) -> void:
	var dir: float = signf(e.land_x - e.launch_x)
	if dir == 0.0:
		dir = 1.0
	var A = _graph.platforms[e.from_id]
	var edge_x: float = A.x_max if dir > 0.0 else A.x_min
	var guard_x := edge_x - dir * EDGE_GUARD
	# A hazardous surface inside the gap (the spike strip this jump clears)
	# reaches the capsule before the ledge does: keep the run-up short of the
	# hazard edge by capsule radius plus stopping slop, or a slow pass clips
	# the tips (the stop-line coast still lands ~4px past guard_x).
	var B = _graph.platforms[e.to_id]
	var cap := _capsule_radius()
	for P in _graph.platforms:
		if not bool(P.hazardous) or P.y_top < A.y_top - 8.0:
			continue
		if dir > 0.0 and A.x_max - 1.0 <= P.x_min and P.x_min <= B.x_min + 1.0:
			guard_x = minf(guard_x, P.x_min - cap - 10.0)
		elif dir < 0.0 and A.x_min + 1.0 >= P.x_max and P.x_max >= B.x_max - 1.0:
			guard_x = maxf(guard_x, P.x_max + cap + 10.0)
	var x := _actor_x()
	var vx := _actor_vx()
	if not is_nan(_backoff_x):
		# Re-run: retreat behind the launch point, then attack the window again.
		_move = _steer(_backoff_x, false)
		if absf(x - _backoff_x) <= 8.0 and absf(vx) < 50.0:
			_backoff_x = NAN
		return
	var in_window: bool = (x - e.launch_x) * dir >= -RUNUP_SLACK \
			and (guard_x - x) * dir >= 0.0
	if grounded and in_window and absf(vx) >= JUMP_SPEED_MIN and signf(vx) == dir:
		_jump = true
		_commit_air(e.land_x)
		return
	# Stop-line guard: fire early enough that the coast — braking distance at
	# the current speed — still stops the center short of guard_x. A raw
	# center-crossing test lets momentum carry the capsule past the line and
	# into whatever the guard protects (spike tips at a hazardous gap).
	if grounded and (x - guard_x) * dir + (vx * absf(vx)) / (2.0 * BRAKE_DECEL) > 0.0:
		# Reached the guard uncommitted — too slow to clear the gap. Back off
		# and build a proper run-up; repeated misses blacklist the edge.
		_edge_attempts += 1
		if _edge_attempts > EDGE_MAX_ATTEMPTS:
			_ban_edge(e)
			_replan()
		else:
			_backoff_x = e.launch_x - dir * BACKOFF_DIST
		return
	_move = dir  # full run at the edge — speed builds through the window

func _approach_drop(e) -> void:
	var dir := _drop_dir(e)
	var is_walk_off := String(e.method) == "walk_off"
	if is_walk_off:
		# Walk past the edge; losing the ground flips us to airborne.
		_move = _steer(e.launch_x + dir * 14.0, false)
		return
	_move = _steer(e.launch_x, _slope_mode(e))
	if absf(_actor_x() - e.launch_x) <= DROP_COMMIT_TOL:
		_drop = true
		_commit_air(e.land_x)

func _update_final(delta: float) -> void:
	if absf(_dest_x - _actor_x()) <= ARRIVE_TOL:
		_finish(STATUS_ARRIVED)
		return
	if _run_stuck(delta, _dest_x):
		return
	_move = _steer(_dest_x, _slope_mode(null))


# --- airborne --------------------------------------------------------------------

func _update_airborne(delta: float, grounded: bool) -> void:
	_air_time += delta
	if grounded:
		if _edge_committed and _air_time < AIR_BELIEVE_TIME:
			# Liftoff tail: the contact list still reports the floor for a step
			# or two after a jump/drop impulse. Believing it cancels a healthy
			# arc as "landed back on source". Keep the commit; steer ballistically
			# for the moment (no re-assert — the actor IS airborne, and a second
			# impulse while the actor-side ground state lags would double-jump).
			return
		_on_landed()
		return
	if _air_time > AIR_MAX_TIME:
		if _graph.platform_below(_feet_pos()) < 0:
			# Nothing below — KillZone-bound. Nothing to steer toward.
			_finish(STATUS_FAILED)
			return
	var d := _air_target - _actor_x()
	_move = clampf(d / AIR_DRIFT_GAIN, -1.0, 1.0)
	var vx := _actor_vx()
	# About to overshoot the drift target — brake against the momentum.
	if absf(d) < AIR_BRAKE_DIST and signf(vx) != 0.0 and signf(vx) != signf(d):
		_move = -signf(vx) * 0.5

func _on_landed() -> void:
	_air_time = 0.0
	var loc := _localize_now()
	var j: int = _route.platform_ids.find(loc)
	if j > _route_index:
		_advance_to(j)
		_phase = PHASE_APPROACH
	elif j == _route_index:
		# Back on (or never left) the source platform.
		if _edge_committed:
			_edge_attempts += 1
			if _edge_attempts > EDGE_MAX_ATTEMPTS:
				var e = _pending_edge()
				if e != null:
					_ban_edge(e)
				_replan()
			else:
				_edge_committed = false
				_phase = PHASE_APPROACH
		else:
			_phase = PHASE_APPROACH
	else:
		# Behind the route or off it entirely.
		_off_route(loc)


# --- recover --------------------------------------------------------------------

func _update_recover(delta: float, grounded: bool) -> void:
	_recover_clock += delta
	if _recover_clock > RECOVER_MAX_TIME:
		_finish(STATUS_FAILED)
		return
	if not grounded:
		var below: int = _graph.platform_below(_feet_pos())
		if below >= 0:
			var P = _graph.platforms[below]
			if bool(P.hazardous):
				# Falling over spikes — aim for the nearer edge, not the middle.
				_air_target = P.x_min + 8.0 if _actor_x() > P.center() else P.x_max - 8.0
			else:
				_air_target = P.center()
		var d := _air_target - _actor_x()
		_move = clampf(d / AIR_DRIFT_GAIN, -1.0, 1.0)
		return
	var loc := _localize_now()
	if loc < 0 or loc >= _graph.platforms.size():
		_finish(STATUS_FAILED)
		return
	var P = _graph.platforms[loc]
	if P.contains_x(_actor_x()):
		_replan()
	else:
		# Under-geometry tier-3 lie (covered tiles under a ramp): walk to the
		# localized platform's REAL cells first — replanning from a platform
		# the actor is not on would loop forever.
		_move = _steer(P.center(), false)


# --- shared mechanics -------------------------------------------------------------

func _advance_to(j: int) -> void:
	_route_index = j
	_edge_attempts = 0
	_edge_committed = false
	_backoff_x = NAN
	_stuck_count = 0
	_reset_stuck()

func _commit_air(target: float) -> void:
	_edge_committed = true
	_air_time = 0.0
	_air_target = target
	_phase = PHASE_AIRBORNE
	_stuck_count = 0
	_reset_stuck()

func _enter_phase_by_ground() -> void:
	_edge_committed = false
	_air_time = 0.0
	_backoff_x = NAN
	if _is_grounded_now():
		_phase = PHASE_APPROACH
	else:
		_air_target = _air_aim_x()
		_phase = PHASE_AIRBORNE

func _off_route(loc: int) -> void:
	if loc >= 0 and loc < _graph.platforms.size():
		var P = _graph.platforms[loc]
		if P.contains_x(_actor_x()):
			_replan()
			return
		_recover_clock = 0.0
		_phase = PHASE_RECOVER
		return
	_finish(STATUS_FAILED)

## Re-derive the route from wherever the actor is now. Escapes to real cells
## first when localization is lying (under-geometry); fails when no route
## exists (possibly after one ban-clearing retry).
func _replan() -> void:
	if not has_graph() or _dest_platform < 0:
		_finish(STATUS_FAILED)
		return
	var here := _localize_now()
	# The platform array is rebuilt and re-sorted whenever the graph changes
	# (a hazard split shifts every id after it), so the stored dest id may
	# name a DIFFERENT platform by now. Re-derive it from the stored
	# destination POINT — position survives a rebuild; ids do not.
	var dest_id: int = _graph.platform_below(_dest_pos)
	if dest_id < 0:
		dest_id = _graph.nearest_platform(_dest_pos)
	if dest_id < 0:
		_finish(STATUS_FAILED)
		return
	_dest_platform = dest_id
	if here >= 0 and here < _graph.platforms.size() \
			and not _graph.platforms[here].contains_x(_actor_x()):
		_recover_clock = 0.0
		_phase = PHASE_RECOVER
		return
	var r = _route_from(here, dest_id, _dest_x)
	if r == null:
		_finish(STATUS_FAILED)
		return
	_route = r
	_route_index = 0
	_edge_attempts = 0
	_stuck_count = 0
	_reset_stuck()
	_recover_clock = 0.0
	_graph_revision = _graph.revision
	_set_status(STATUS_MOVING)
	_enter_phase_by_ground()

func _route_from(here: int, dest_id: int, dx: float):
	if here < 0 or here >= _graph.platforms.size():
		return null
	_prune_bans()
	return _graph.route(here, dest_id, dx, _risk_weight, _active_bans())

## No progress toward the phase target for STUCK_TIME. Occurrence 1 pops a
## micro-jump (lips, small debris); occurrence 2 escalates: under-geometry
## lies escape to real cells, real ground bans the pending edge and replans,
## a stuck final segment fails (the destination itself is unreachable).
## Returns true when the tick must stop after the occurrence.
func _run_stuck(delta: float, target: float) -> bool:
	var d := absf(target - _actor_x())
	if d < _stuck_best - STUCK_EPS:
		_stuck_best = d
		_stuck_clock = 0.0
		return false
	_stuck_clock += delta
	if _stuck_clock < STUCK_TIME:
		return false
	_stuck_clock = 0.0
	_stuck_count += 1
	if _stuck_count == 1:
		_jump = true
		return false
	_stuck_count = 0
	var loc := _localize_now()
	if loc >= 0 and loc < _graph.platforms.size() \
			and not _graph.platforms[loc].contains_x(_actor_x()):
		_recover_clock = 0.0
		_phase = PHASE_RECOVER
		return true
	var e = _pending_edge()
	if e != null:
		_ban_edge(e)
	_replan()
	if _status == STATUS_MOVING and _route != null and _route.edges.is_empty():
		# Replanned onto the destination platform but still stuck — the
		# destination point itself is unreachable.
		_finish(STATUS_FAILED)
	return true

func _reset_stuck() -> void:
	_stuck_best = INF
	_stuck_clock = 0.0

func _ban_edge(e) -> void:
	_banned[Vector2i(e.from_id, e.to_id)] = _clock + BLACKLIST_SECONDS

func _prune_bans() -> void:
	for k in _banned.keys():
		if float(_banned[k]) <= _clock:
			_banned.erase(k)

func _active_bans() -> Array:
	_prune_bans()
	var out: Array = []
	for k: Vector2i in _banned.keys():
		out.append([k.x, k.y])
	return out

func _pending_edge():
	if _route == null or _route_index >= _route.edges.size():
		return null
	return _route.edges[_route_index]

## Drift aim while airborne without a live commit (knockback pop, spawn fall,
## slide-off): the pending edge's LAND point. Over a gap or hazard that means
## "carry toward the far side" — never brake back over the edge just left.
func _air_aim_x() -> float:
	var e = _pending_edge()
	if e == null:
		return _dest_x
	return e.land_x

func _target_x_for(e) -> float:
	if e == null:
		return _dest_x
	match String(e.type):
		"walk":
			return e.land_x
		"jump_up", "jump_across":
			return e.launch_x
		"drop_down":
			if String(e.method) == "walk_off":
				return e.launch_x + _drop_dir(e) * 14.0
			return e.launch_x
	return e.land_x

func _drop_dir(e) -> float:
	var d: float = signf(e.land_x - e.launch_x)
	if d == 0.0:
		d = signf(_graph.platforms[e.to_id].center() \
				- _graph.platforms[e.from_id].center())
	return 1.0 if d == 0.0 else d

## Full ±1 steering on one-way slope nodes: gravity pulls actors down the
## 45° faces (~693 px/s² along-slope) and a tapered input loses to it.
func _slope_mode(e) -> bool:
	var here: int = _route.platform_ids[_route_index]
	if _graph.platforms[here].kind == &"one_way":
		return true
	if e != null and _graph.platforms[e.to_id].kind == &"one_way":
		return true
	return false

func _steer(target: float, slope: bool) -> float:
	var d := target - _actor_x()
	if slope:
		if absf(d) < 1.0:
			return 0.0
		return signf(d)
	return clampf(d / STEER_GAIN, -1.0, 1.0)

func _finish(s: StringName) -> void:
	_set_status(s)
	_phase = PHASE_IDLE
	_route = null
	_route_index = 0

func _reset_goal() -> void:
	_finish(STATUS_IDLE)

func _set_status(s: StringName) -> void:
	_status = s

func _write_inputs() -> void:
	if _controller == null:
		return
	_controller.move_direction = _move
	_controller.wants_jump = _jump
	_controller.wants_drop = _drop


# --- actor sensing (duck-typed) ---------------------------------------------------

func _localize_now() -> int:
	return _graph.localize(_feet_pos(), _is_grounded_now(), _ground_cell_now())

func _feet_pos() -> Vector2:
	return _actor.position + Vector2(0.0, FEET_DOWN)

func _is_grounded_now() -> bool:
	return bool(_actor.is_grounded())

func _actor_x() -> float:
	return _actor.position.x

func _actor_vx() -> float:
	return _actor.linear_velocity.x

## Capsule half-width from the actor's collision shape, cached — the hazard
## guard needs it to keep the body (not just the center) clear of spike tips.
func _capsule_radius() -> float:
	if _capsule_radius_cache < 0.0:
		var cs = _actor.get_node_or_null("CollisionShape2D")
		if cs != null and cs.shape != null and "radius" in cs.shape:
			_capsule_radius_cache = float(cs.shape.radius)
		else:
			_capsule_radius_cache = 16.0
	return _capsule_radius_cache

## Ground cell from the actor's existing GroundCheck ray — the same sampling
## Actor-Movement uses for one-way detection, zero extra physics queries.
func _ground_cell_now() -> Vector2i:
	var ray = _actor.get_node_or_null("GroundCheck")
	if ray == null or not ray.is_colliding():
		return NO_CELL
	var col = ray.get_collider()
	if col == null or not col.has_method("local_to_map"):
		return NO_CELL
	var hit: Vector2 = ray.get_collision_point()
	return col.local_to_map(col.to_local(hit))