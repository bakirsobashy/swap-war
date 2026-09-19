extends SceneTree

## Headless probe for the hazard system (plan step 3).
##
## Scenarios (ArenaHazards with the real SpikeStrip wired in the scene):
##   - Scene wiring: World/Hazards/SpikeStrip exists with nav rect
##     [288,352]x[96,128] and the designed exports (15 dmg / 0.5s / x4).
##   - Nav group scan: baking AFTER the strip is in the tree splits the floor
##     and marks the segment hazardous; point_in_hazard + escape dir work.
##   - Damage pacing: actor standing in the strip with knockback temporarily
##     zeroed (a frozen body is NOT picked up by area monitoring — verified
##     empirically — so pacing is measured on a live, stationary actor) takes
##     EXACTLY 3 hits in 1.2s (immediate + one every 0.5s cooldown), 15 each
##     -> hp 55. (The plan sketch said "2 hits in 1.2s"; with an immediate
##     first hit the arithmetic is 0 + 0.5 + 1.0 -> 3. The invariant under
##     test is per-interval pacing, not per-frame spam.)
##   - Knockback: unfrozen actor pops upward on hit (vy <= -200).
##   - Outside the strip: zero hits over 1.0s.
##   - instant_kill: overlapping actor dies, then respawns full-HP.
##   - Runtime self-registration: a HazardArea constructed AFTER the graph is
##     cached adds its rect to the live graph (revision bump, floor split),
##     and removes it when freed (floor rejoined).
##
## `-s` mode discipline: runtime load() only, untyped vars, no game-class
## annotations, zero autoload references. current_scene is set so Health's
## floating-number/particle paths resolve into the arena's Effects node.

var _fails: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var baker = load("res://Scripts/AI/NavBaker.gd")
	await _probe_all(baker)
	var verdict := "ALL PASS"
	if _fails > 0:
		verdict = "%d FAILURES" % _fails
	print("\n=== hazard_damage_probe: %s ===" % verdict)
	quit(1 if _fails > 0 else 0)

func _check(ok: bool, what: String) -> void:
	print("  %s: %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1

func _find_platform(graph, x_min: float, x_max: float, y_top: float, kind: String):
	for p in graph.platforms:
		if absf(p.x_min - x_min) < 0.5 and absf(p.x_max - x_max) < 0.5 \
				and absf(p.y_top - y_top) < 0.5 and String(p.kind) == kind:
			return p
	return null

func _spawn_actor(inst: Node, x: float):
	var actor = load("res://Scenes/actor.tscn").instantiate()
	actor.get_node("AIController").is_ai = false
	actor.position = Vector2(x, 78.0)
	inst.get_node("Actors").add_child(actor)
	return actor

func _probe_all(baker) -> void:
	print("\n=== hazards: wiring + nav ===")
	var inst = load("res://Scenes/Arenas/ArenaHazards.tscn").instantiate()
	root.add_child(inst)
	current_scene = inst
	await physics_frame
	await physics_frame

	var strip = inst.get_node_or_null("World/Hazards/SpikeStrip")
	_check(strip != null, "scene: World/Hazards/SpikeStrip exists")
	if strip == null:
		inst.queue_free()
		await physics_frame
		return
	var nav_rect: Rect2 = strip.get_nav_rect()
	_check(nav_rect.is_equal_approx(Rect2(288.0, 96.0, 64.0, 32.0)),
			"scene: strip nav rect [288,352]x[96,128]")
	_check(absf(float(strip.damage) - 15.0) < 0.01
			and absf(float(strip.damage_interval) - 0.5) < 0.01
			and absf(float(strip.nav_cost_multiplier) - 4.0) < 0.01,
			"scene: exports 15 dmg / 0.5s interval / x4 nav cost")

	var graph = baker.get_cached(inst)
	_check(graph != null, "nav: graph cached on the arena scene")
	var seg = _find_platform(graph, 288.0, 352.0, 128.0, "solid")
	_check(seg != null and bool(seg.hazardous), "nav: strip segment hazardous (group scan)")
	_check(graph.point_in_hazard(Vector2(320.0, 120.0)), "nav: point_in_hazard inside strip")
	_check(absf(graph.hazard_escape_dir(Vector2(320.0, 120.0))) == 1.0,
			"nav: escape dir nonzero inside strip")

	print("\n=== hazards: damage pacing (knockback zeroed, live actor) ===")
	var saved_knockback: Vector2 = strip.knockback_impulse
	strip.knockback_impulse = Vector2.ZERO
	var actor1 = _spawn_actor(inst, 320.0)
	var health1 = actor1.get_node("Components/Health")
	var hit_ticks: Array = []
	var last_hp = float(health1.current_health)
	for tick in 72:                    # 1.2s at 60 tps
		await physics_frame
		var now_hp = float(health1.current_health)
		if now_hp < last_hp:
			hit_ticks.append(tick)
			last_hp = now_hp
	_check(hit_ticks.size() == 3,
			"damage: exactly 3 hits in 1.2s (got %d -> %s)" % [hit_ticks.size(), str(hit_ticks)])
	var spaced := hit_ticks.size() >= 2
	for i in hit_ticks.size() - 1:
		if hit_ticks[i + 1] - hit_ticks[i] < 27:   # < 0.45s = per-frame spam
			spaced = false
	_check(spaced, "damage: hits spaced >= 0.45s (cooldown pacing)")
	_check(absf(float(health1.current_health) - 55.0) < 0.01,
			"damage: 3 x 15 -> hp 55 (got %.1f)" % float(health1.current_health))
	strip.knockback_impulse = saved_knockback
	actor1.queue_free()
	await physics_frame

	print("\n=== hazards: knockback + outside ===")
	var actor2 = _spawn_actor(inst, 320.0)
	var health2 = actor2.get_node("Components/Health")
	var min_vy := 0.0
	var kb_hits := 0
	var hp2 = float(health2.current_health)
	for i in 36:                       # 0.6s
		await physics_frame
		min_vy = minf(min_vy, actor2.linear_velocity.y)
		if float(health2.current_health) < hp2:
			hp2 = float(health2.current_health)
			kb_hits += 1
	_check(kb_hits >= 1, "knockback: unfrozen actor is hit")
	_check(min_vy <= -200.0, "knockback: upward impulse (min vy %.0f <= -200)" % min_vy)

	actor2.global_position = Vector2(-400.0, 78.0)
	var outside_hp = float(health2.current_health)
	var outside_hits := 0
	for i in 60:                       # 1.0s
		await physics_frame
		if float(health2.current_health) < outside_hp:
			outside_hits += 1
			outside_hp = float(health2.current_health)
	_check(outside_hits == 0, "outside: 0 hits over 1.0s west of the strip")
	actor2.queue_free()
	await physics_frame

	print("\n=== hazards: instant_kill + respawn ===")
	strip.instant_kill = true
	var actor3 = _spawn_actor(inst, 320.0)
	var health3 = actor3.get_node("Components/Health")
	# Lambdas capture locals BY VALUE in GDScript — use an array cell so the
	# signal handler can flip shared state.
	var died_state: Array = [false]
	health3.died.connect(func() -> void: died_state[0] = true)
	for i in 20:                      # 0.33s
		await physics_frame
		if died_state[0]:
			break
	_check(bool(died_state[0]) and float(health3.current_health) <= 0.0,
			"instant_kill: overlapping actor dies")
	# Health's 1.5s respawn timer must still work through the hazard death
	# (full heal + invulnerability, so the strip cannot chain-kill).
	for i in 130:                     # ~2.2s
		await physics_frame
		if absf(float(health3.current_health) - 100.0) < 0.01:
			break
	_check(absf(float(health3.current_health) - 100.0) < 0.01,
			"respawn: full hp after the 1.5s respawn (got %.1f)" % float(health3.current_health))
	actor3.queue_free()
	strip.instant_kill = false
	await physics_frame

	print("\n=== hazards: runtime self-registration ===")
	var rev_before: int = graph.revision
	var ha = Area2D.new()
	ha.set_script(load("res://Scripts/Components/HazardArea.gd"))
	ha.position = Vector2(-400.0, 112.0)
	ha.collision_layer = 0
	ha.collision_mask = 2
	var cs = CollisionShape2D.new()
	cs.name = "CollisionShape2D"
	var sh = RectangleShape2D.new()
	sh.size = Vector2(64.0, 32.0)
	cs.shape = sh
	ha.add_child(cs)
	inst.add_child(ha)
	await physics_frame
	await physics_frame
	_check(graph.revision > rev_before, "runtime: revision bumps on self-registration")
	_check(graph.point_in_hazard(Vector2(-400.0, 120.0)),
			"runtime: registered rect hazardous in the cached graph")
	var seg2 = _find_platform(graph, -432.0, -368.0, 128.0, "solid")
	_check(seg2 != null and bool(seg2.hazardous), "runtime: FloorWest splits at the new rect")
	ha.queue_free()
	await physics_frame
	await physics_frame
	_check(not graph.point_in_hazard(Vector2(-400.0, 120.0)),
			"runtime: rect removed from the graph on free")
	_check(_find_platform(graph, -668.0, 128.0, 128.0, "solid") != null,
			"runtime: FloorWest rejoined after removal")

	inst.queue_free()
	await physics_frame