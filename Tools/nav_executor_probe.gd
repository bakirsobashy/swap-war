extends SceneTree

## Headless probe for the NavExecutor (plan step 4) — real physics, a real
## actor, the real ArenaHazards scene with the spike strip wired in.
##
## The actor runs its FULL real stack (AIController with is_ai=true AND
## nav_enabled=true — the executor overwrites the legacy machine's movement
## inputs every tick, exactly like production). current_scene is set so the
## lazy graph resolve in AIController.nav_to() bakes ArenaHazards (floor
## split at the strip) and Health's effects paths resolve.
##
## Ground truth (dumped from the arena tiles + the verified graph):
##   floor y_top=128 solid under the WHOLE arena incl. under the ramps; the
##   stair is a free-standing one-way staircase westward: ra [128,192]@64,
##   rb [64,128]@0, lip [0,64]@-64, top [-320,0]@-64 solid; strip [288,352]
##   hazardous; block [576,640]@64; mw [192,288], me [352,576].
##   Routes (A*-verified): fw->top = fw-jump_up(128)->ra->rb->lip->top (280);
##   fw->block = fw-jump_up->ra->mw-jump_across(240)->me-jump_up(576)->block
##   (689.6); top->fw = top->lip->rb-drop_through(96)->fw (97.2).
##
## Scenarios:
##   1. West floor -> stair top: arrives <= 25s, one jump_up at x<160 (the
##      ra launch), never wanders east of the strip (max_x < 288 — the
##      post-landing slide-bounce onto mw is legitimate recovery), health
##      unchanged, final position on the top platform.
##   2. West floor -> RightBlock: arrives <= 25s, a jump_across committed
##      from the strip launch window x in [216,292] (distinct from the ra
##      launch ~128 and the block launch ~576), health unchanged — THE
##      trajectory gate on the strip sizing (an over-wide strip would force
##      the actor through the spikes).
##   3. Stair top -> west floor: arrives <= 12s, one drop_through asserted
##      within rb's span x in [64,128], health unchanged — the drop ladder
##      (route top->lip->rb->fw) must beat the walk_off.
##   4. Wedge: an invisible-to-the-graph StaticBody2D wall blocks the stair
##      launch corridor. The stuck ladder must fire (micro-jump observed),
##      then ban the dead edge, replan, find no route, and report &"failed"
##      within 6s — never arriving, never hanging.
##
## `-s` mode discipline: runtime load() only, untyped vars, no game-class
## annotations, zero autoload references.

var _fails: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _probe_executor()
	var verdict := "ALL PASS"
	if _fails > 0:
		verdict = "%d FAILURES" % _fails
	print("\n=== nav_executor_probe: %s ===" % verdict)
	quit(1 if _fails > 0 else 0)

func _check(ok: bool, what: String) -> void:
	print("  %s: %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1

func _spawn_ai(inst: Node, x: float, y: float):
	var actor = load("res://Scenes/actor.tscn").instantiate()
	var ctl = actor.get_node("AIController")
	ctl.is_ai = true
	ctl.nav_enabled = true
	actor.position = Vector2(x, y)
	inst.get_node("Actors").add_child(actor)
	# Park the decision machine: with the step-5 rewrite the states set nav
	# goals THEMSELVES, so a live machine (Patrol hops toward random
	# platforms) would fight this probe's explicit nav_to goals inside the
	# controller's 96px replan throttle. current_state = null turns the
	# machine's physics_update into a no-op; the executor keeps sole
	# ownership of the inputs, exactly what these scenarios assert.
	ctl.machine.current_state = null
	return actor

func _settle(ticks: int) -> void:
	for i in ticks:
		await physics_frame

## Physics-tick drive loop: captures every asserted jump/drop with the actor's
## x at assert time, the extremes, and the status the moment the executor
## reports a terminal state (arrival position captured BEFORE the legacy
## machine gets the inputs back and wanders off).
func _drive(controller, actor, health, budget: int, trace_from := -1, trace_to := -1) -> Dictionary:
	var out := {"jumps": [], "drops": [], "hits": [], "trace": [], "max_x": -99999.0,
			"min_hp": float(health.current_health),
			"end": "timeout", "x": 0.0, "y": 0.0, "ticks": 0}
	var last_hp: float = out.min_hp
	for i in budget:
		await physics_frame
		out.ticks = i
		if bool(controller.wants_jump):
			out.jumps.append(Vector2(actor.position.x, actor.position.y))
		if bool(controller.wants_drop):
			out.drops.append(actor.position.x)
		var hp := float(health.current_health)
		if hp < last_hp:
			out.hits.append("t=%d (%.0f,%.0f) hp %.0f->%.0f"
					% [i, actor.position.x, actor.position.y, last_hp, hp])
			last_hp = hp
		if i >= trace_from and i <= trace_to:
			var ex = controller.nav_executor
			out.trace.append("t=%4d x=%6.0f y=%6.0f vx=%5.0f g=%d mv=%4.1f ph=%-8s ri=%d att=%d bo=%s sc=%d cm=%d tgt=%3.0f"
					% [i, actor.position.x, actor.position.y, actor.linear_velocity.x,
					1 if actor.is_grounded() else 0, controller.move_direction,
					String(ex._phase), ex._route_index, ex._edge_attempts,
					("%.0f" % ex._backoff_x) if not is_nan(ex._backoff_x) else "-",
					ex._stuck_count, 1 if ex._edge_committed else 0, ex._air_target])
		out.max_x = maxf(out.max_x, actor.position.x)
		out.min_hp = minf(out.min_hp, hp)
		if controller.nav_arrived():
			out.end = "arrived"
		elif controller.nav_failed():
			out.end = "failed"
		if out.end != "timeout":
			out.x = actor.position.x
			out.y = actor.position.y
			break
	if out.end == "timeout":
		out.x = actor.position.x
		out.y = actor.position.y
	return out

func _print_result(tag: String, r: Dictionary) -> void:
	print("  %s: end=%s ticks=%d x=%.0f y=%.0f max_x=%.0f hp=%.0f jumps=%s drops=%s" \
			% [tag, r.end, r.ticks, r.x, r.y, r.max_x, r.min_hp,
			str(r.jumps), str(r.drops)])
	for hit in r.hits:
		print("    HIT %s" % hit)
	for line in r.trace:
		print("    %s" % line)

func _probe_executor() -> void:
	print("\n=== executor: ArenaHazards, real physics ===")
	var inst = load("res://Scenes/Arenas/ArenaHazards.tscn").instantiate()
	root.add_child(inst)
	current_scene = inst
	await physics_frame
	await physics_frame
	# Sky-dropped weapons are SOLID bodies the actor physically collides
	# with, and a fresh drop cannot be picked up immediately (pickup
	# cooldown) — a random wave landing mid-run blocks the run-up and makes
	# the scenarios nondeterministic. Pull the spawn markers from their group
	# so WeaponSpawner's waves no-op for this probe run.
	for n in inst.get_tree().get_nodes_in_group("weapon_spawn_points"):
		if inst.is_ancestor_of(n):
			n.remove_from_group("weapon_spawn_points")

	# --- Scenario 1: west floor -> stair top (jump_up + slope chain) ------
	print("\n--- S1: FloorWest -> StairTop ---")
	var a1 = _spawn_ai(inst, -400.0, 78.0)
	var c1 = a1.get_node("AIController")
	var h1 = a1.get_node("Components/Health")
	await _settle(30)
	var rc1: StringName = c1.nav_to(Vector2(-160.0, -64.0))
	_check(rc1 == &"ok", "S1: nav_to stair top -> ok")
	var r1 = await _drive(c1, a1, h1, 1500)
	_print_result("S1", r1)
	_check(r1.end == "arrived", "S1: arrives within 25s (end=%s)" % r1.end)
	var jump_west := false
	for jx in r1.jumps:
		if float(jx.x) < 160.0:
			jump_west = true
	_check(jump_west, "S1: jump_up asserted west of x=160 (the ra launch)")
	_check(r1.max_x < 288.0,
			"S1: never east of the strip (max_x=%.0f < 288)" % r1.max_x)
	_check(absf(r1.min_hp - 100.0) < 0.01, "S1: health unchanged")
	_check(r1.end == "arrived" and absf(r1.x + 160.0) <= 30.0,
			"S1: final x within 30px of -160 (got %.0f)" % r1.x)
	_check(r1.end == "arrived" and absf(r1.y + 95.0) <= 12.0,
			"S1: final y on the top platform (~-95, got %.0f)" % r1.y)
	a1.queue_free()
	await physics_frame

	# --- Scenario 2: west floor -> RightBlock over the strip --------------
	print("\n--- S2: FloorWest -> RightBlock (strip jump-over) ---")
	var a2 = _spawn_ai(inst, -400.0, 78.0)
	var c2 = a2.get_node("AIController")
	var h2 = a2.get_node("Components/Health")
	await _settle(30)
	var rc2: StringName = c2.nav_to(Vector2(608.0, 64.0))
	_check(rc2 == &"ok", "S2: nav_to RightBlock -> ok")
	var r2 = await _drive(c2, a2, h2, 1500)
	_print_result("S2", r2)
	_check(r2.end == "arrived", "S2: arrives within 25s (end=%s)" % r2.end)
	var strip_jump := false
	for jx in r2.jumps:
		if float(jx.x) >= 216.0 and float(jx.x) <= 292.0:
			strip_jump = true
	_check(strip_jump,
			"S2: jump_across committed from the strip window [216,292] (jumps=%s)" % str(r2.jumps))
	_check(absf(r2.min_hp - 100.0) < 0.01,
			"S2: health unchanged — clears the spikes undamaged (hp=%.0f)" % r2.min_hp)
	_check(r2.end == "arrived" and absf(r2.x - 608.0) <= 30.0,
			"S2: final x within 30px of 608 (got %.0f)" % r2.x)
	_check(r2.end == "arrived" and absf(r2.y - 33.0) <= 12.0,
			"S2: final y on the block platform (~33, got %.0f)" % r2.y)
	a2.queue_free()
	await physics_frame

	# --- Scenario 3: stair top -> west floor (slope chain + drop_through) --
	print("\n--- S3: StairTop -> FloorWest (drop ladder) ---")
	var a3 = _spawn_ai(inst, -16.0, -95.0)
	var c3 = a3.get_node("AIController")
	var h3 = a3.get_node("Components/Health")
	await _settle(12)
	var rc3: StringName = c3.nav_to(Vector2(-400.0, 128.0))
	_check(rc3 == &"ok", "S3: nav_to FloorWest -> ok")
	var r3 = await _drive(c3, a3, h3, 720)
	_print_result("S3", r3)
	_check(r3.end == "arrived", "S3: arrives within 12s (end=%s)" % r3.end)
	var rb_drop := false
	for dx in r3.drops:
		if float(dx) >= 64.0 and float(dx) <= 128.0:
			rb_drop = true
	_check(rb_drop,
			"S3: drop_through asserted on rb [64,128] (drops=%s)" % str(r3.drops))
	_check(absf(r3.min_hp - 100.0) < 0.01, "S3: health unchanged")
	_check(r3.end == "arrived" and absf(r3.x + 400.0) <= 30.0,
			"S3: final x within 30px of -400 (got %.0f)" % r3.x)
	_check(r3.end == "arrived" and absf(r3.y - 97.0) <= 12.0,
			"S3: final y on the floor (~97, got %.0f)" % r3.y)
	a3.queue_free()
	await physics_frame

	# --- Scenario 4: wedge -> stuck ladder -> honest failure ----------------
	print("\n--- S4: wedge wall -> stuck ladder -> failed ---")
	var a4 = _spawn_ai(inst, -400.0, 78.0)
	var c4 = a4.get_node("AIController")
	var h4 = a4.get_node("Components/Health")
	await _settle(40)
	# Invisible to the graph (a StaticBody2D, not tiles/hazards/overrides):
	# the route still exists, the corridor does not.
	var wall = StaticBody2D.new()
	wall.name = "WedgeWall"
	wall.collision_layer = 1
	wall.collision_mask = 0
	var wcs = CollisionShape2D.new()
	wcs.name = "WallShape"
	var wsh = RectangleShape2D.new()
	wsh.size = Vector2(12.0, 130.0)
	wcs.shape = wsh
	wall.position = Vector2(-350.0, 63.0)
	wall.add_child(wcs)
	inst.add_child(wall)
	await physics_frame
	await physics_frame
	var rc4: StringName = c4.nav_to(Vector2(-160.0, -64.0))
	_check(rc4 == &"ok", "S4: nav_to still plans (wall invisible to the graph)")
	var r4 = await _drive(c4, a4, h4, 360)
	_print_result("S4", r4)
	_check(r4.end == "failed",
			"S4: reports failed within 6s (end=%s)" % r4.end)
	_check(r4.jumps.size() >= 1,
			"S4: micro-jump fired before giving up (jumps=%s)" % str(r4.jumps))
	_check(r4.end == "failed" and r4.max_x <= -300.0,
			"S4: never crossed the wall (max_x=%.0f <= -300)" % r4.max_x)
	_check(absf(r4.min_hp - 100.0) < 0.01, "S4: health unchanged")
	_check(not c4.nav_arrived(), "S4: never reports arrived")
	wall.queue_free()
	a4.queue_free()

	inst.queue_free()
	await physics_frame