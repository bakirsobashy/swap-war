extends SceneTree

## Headless probe for A* routing over the baked graph (plan step 2).
##
## Route assertions are derived from the VERIFIED step-1 bake-probe dumps of
## the placeholder arenas (re-derive when the arenas are finalized):
##   - Pit FloorWest -> StairTop: the slope-side rule removed the phantom
##     high-side walks, so the route is one 64px jump_up onto rampA plus three
##     vertex-matched slope walks — step-by-step, never a floor->top leap —
##     total cost 280 (250 + 3 walks).
##   - Pit FloorWest -> FloorEast: the only connector east is RightBlock, so
##     the route is jump_up (250), walk (10), jump_up (250), drop (52) — 562.
##   - Same-platform: zero edges, dest_x honored / clamped into the platform.
##   - Unreachable target (sky ledge, no in-edges): null + has_path false,
##     no crash.
##   - banned_edges: blacklisting FloorWest's sole east edge (the rampA
##     jump_up) kills the route; [from,to] pairs and Edge objects both work.
##   - risk_weight scales jump costs but not walk/drop costs.
##   - Hazards with the spike strip registered: FloorEast -> StairTop never
##     touches the hazardous segment, jumps the strip exactly once, and the
##     jump cost (179.6) beats walking through (212).
##
## `-s` mode discipline: runtime load() only, untyped vars, no game-class
## annotations, zero autoload references.

var _fails: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var baker = load("res://Scripts/AI/NavBaker.gd")
	await _probe_pit(baker)
	await _probe_hazards(baker)
	var verdict := "ALL PASS"
	if _fails > 0:
		verdict = "%d FAILURES" % _fails
	print("\n=== nav_astar_probe: %s ===" % verdict)
	quit(1 if _fails > 0 else 0)

func _check(ok: bool, what: String) -> void:
	print("  %s: %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1

func _instantiate(path: String) -> Node:
	var scene = load(path)
	var inst = scene.instantiate()
	root.add_child(inst)
	await physics_frame
	await physics_frame
	return inst

func _find_platform(graph, x_min: float, x_max: float, y_top: float, kind: String):
	for p in graph.platforms:
		if absf(p.x_min - x_min) < 0.5 and absf(p.x_max - x_max) < 0.5 \
				and absf(p.y_top - y_top) < 0.5 and String(p.kind) == kind:
			return p
	return null

func _print_route(tag: String, route) -> void:
	if route == null:
		print("  %s: NO ROUTE" % tag)
		return
	var parts: Array = []
	for i in route.edges.size():
		var e = route.edges[i]
		parts.append("P%d-%s->P%d(%.1f)" % [e.from_id, String(e.type),
				e.to_id, e.edge_cost(1.0)])
	print("  %s: [%s] cost=%.1f dest_x=%.0f" % [tag, ", ".join(parts),
			route.total_cost(1.0), route.dest_x])

## Structural invariants every non-null route must satisfy.
func _check_shape(graph, route, from_id: int, to_id: int, what: String) -> void:
	if route == null:
		_check(false, what + " (route is null)")
		return
	var ok: bool = route.platform_ids[0] == from_id \
			and route.platform_ids[route.platform_ids.size() - 1] == to_id \
			and route.edges.size() == route.platform_ids.size() - 1
	for i in route.edges.size():
		var e = route.edges[i]
		if e.from_id != route.platform_ids[i] or e.to_id != route.platform_ids[i + 1]:
			ok = false
	_check(ok, what)

func _probe_pit(baker) -> void:
	print("\n=== A* routes: ArenaPit ===")
	var inst = await _instantiate("res://Scenes/Arenas/ArenaPit.tscn")
	var graph = baker.bake(inst)
	var fw = _find_platform(graph, -668.0, 128.0, 128.0, "solid")
	var ra = _find_platform(graph, 128.0, 192.0, 64.0, "one_way")
	var rb = _find_platform(graph, 64.0, 128.0, 0.0, "one_way")
	var lip = _find_platform(graph, 0.0, 64.0, -64.0, "one_way")
	var top = _find_platform(graph, -320.0, 0.0, -64.0, "solid")
	var fm = _find_platform(graph, 192.0, 576.0, 128.0, "solid")
	var block = _find_platform(graph, 576.0, 640.0, 64.0, "solid")
	var fe = _find_platform(graph, 640.0, 668.0, 128.0, "solid")
	var ledge_w = _find_platform(graph, -668.0, -640.0, -384.0, "solid")
	if fw == null or ra == null or rb == null or lip == null or top == null \
			or fm == null or block == null or fe == null or ledge_w == null:
		_check(false, "Pit: key platforms missing (arena layout changed?)")
		inst.queue_free()
		await physics_frame
		return

	# Localization feeds routing: grounded on the floor, airborne above stair.
	var loc_ground: int = graph.localize(Vector2(-270.0, 127.0), true, fw.cells[0])
	_check(loc_ground == fw.id, "Pit: grounded localize -> FloorWest")
	var loc_air: int = graph.localize(Vector2(-160.0, -200.0), false, Vector2i(9999, 9999))
	_check(loc_air == top.id, "Pit: airborne localize -> StairTop")

	# Stair climb: one 64px jump_up onto the first ramp (the slope-side rule
	# removed the phantom high-side walks), then three vertex-matched slope
	# walks — step-by-step, never a floor->top leap (250 + 3*10 = 280).
	var up = graph.route(fw.id, top.id, -160.0)
	_print_route("FloorWest->StairTop", up)
	_check_shape(graph, up, fw.id, top.id, "Pit: route shape FloorWest->StairTop")
	var jump_steps := 0
	var step_up_ok := false
	if up != null:
		for e in up.edges:
			if String(e.type) != "walk":
				jump_steps += 1
		step_up_ok = up.edges.size() > 0 and String(up.edges[0].type) == "jump_up" \
				and absf(up.edges[0].dy + 64.0) < 0.5
	_check(up != null and up.platform_ids == [fw.id, ra.id, rb.id, lip.id, top.id],
			"Pit: stair route is fw-(jump_up)->rampA->rampB->lip->top")
	_check(jump_steps == 1 and step_up_ok,
			"Pit: stair climb = one 64px jump_up onto rampA + 3 walks")
	_check(up != null and absf(up.total_cost(1.0) - 280.0) < 0.01,
			"Pit: stair route cost 280 (250 jump_up + 3 walks)")

	# Cross-arena: the only connector east is RightBlock (250 + 10 + 250 + 52).
	var east = graph.route(fw.id, fe.id, 654.0)
	_print_route("FloorWest->FloorEast", east)
	_check_shape(graph, east, fw.id, fe.id, "Pit: route shape FloorWest->FloorEast")
	_check(east != null and east.platform_ids == [fw.id, ra.id, fm.id, block.id, fe.id],
			"Pit: east route crosses via rampA->FloorMid->RightBlock")
	_check(east != null and absf(east.total_cost(1.0) - 562.0) < 0.5,
			"Pit: east route cost 562")
	_check(east != null and absf(east.dest_x - 654.0) < 0.01,
			"Pit: dest_x honored inside target platform")

	# Same-platform: zero edges, dest_x kept / clamped.
	var same = graph.route(fw.id, fw.id, -270.0)
	_check(same != null and same.edges.is_empty() and same.platform_ids == [fw.id] \
			and absf(same.dest_x - (-270.0)) < 0.01,
			"Pit: same-platform route has no edges and keeps dest_x")
	var clamped = graph.route(fw.id, fw.id, 5000.0)
	_check(clamped != null and absf(clamped.dest_x - 128.0) < 0.01,
			"Pit: out-of-range dest_x clamped into the platform")

	# Unreachable: sky ledges have no in-edges.
	_check(graph.route(fw.id, ledge_w.id, -654.0) == null,
			"Pit: route to unreachable WestLedge is null")
	_check(not graph.has_path(fw.id, ledge_w.id),
			"Pit: has_path false to WestLedge")
	_check(graph.has_path(fw.id, fe.id), "Pit: has_path true across the arena")
	_check(graph.route(-5, fw.id, 0.0) == null and graph.route(0, 999, 0.0) == null,
			"Pit: invalid ids return null without crash")

	# Blacklist: FloorWest's ONLY east edge is the rampA jump_up.
	var banned: Array = [[fw.id, ra.id]]
	_check(graph.route(fw.id, fm.id, 384.0, 1.0, banned) == null,
			"Pit: banning the sole east edge kills the route")
	_check(graph.route(fw.id, fm.id, 384.0) != null,
			"Pit: unbanned query still routes")

	# Edge-object form: ban the FloorMid->RightBlock jump_up (the only way
	# east onto RightBlock), same Edge instance the graph holds. The route now
	# holds TWO jump_ups (FloorWest->rampA is one too); the loop picks the
	# last, which is the block step.
	var jump = null
	if east != null:
		for e in east.edges:
			if String(e.type) == "jump_up":
				jump = e
	_check(jump != null, "Pit: east route contains the jump_up to ban")
	_check(jump != null and graph.route(fw.id, fe.id, 654.0, 1.0, [jump]) == null,
			"Pit: banning the Edge object kills the route (object form)")

	# risk_weight doubles each jump_up's distance term only:
	# (12+128)*1.5*2 + 40 = 460 per jump -> 460 + 10 + 460 + 52 = 982.
	var risky = graph.route(fw.id, fe.id, 654.0, 2.0)
	_print_route("FloorWest->FloorEast (risk 2)", risky)
	_check(risky != null and absf(risky.total_cost(2.0) - 982.0) < 0.5,
			"Pit: risk weight 2 scales jump costs (460+10+460+52)")

	inst.queue_free()
	await physics_frame

func _probe_hazards(baker) -> void:
	print("\n=== A* routes: ArenaHazards (scene-wired spike strip) ===")
	var inst = await _instantiate("res://Scenes/Arenas/ArenaHazards.tscn")
	var graph = baker.bake(inst)
	# The strip is baked in by NavBaker's group scan — no graph-level add here.
	var fe = _find_platform(graph, 640.0, 668.0, 128.0, "solid")
	var block = _find_platform(graph, 576.0, 640.0, 64.0, "solid")
	var mid_east = _find_platform(graph, 352.0, 576.0, 128.0, "solid")
	var strip = _find_platform(graph, 288.0, 352.0, 128.0, "solid")
	var mid_west = _find_platform(graph, 192.0, 288.0, 128.0, "solid")
	var ra = _find_platform(graph, 128.0, 192.0, 64.0, "one_way")
	var rb = _find_platform(graph, 64.0, 128.0, 0.0, "one_way")
	var lip = _find_platform(graph, 0.0, 64.0, -64.0, "one_way")
	var top = _find_platform(graph, -320.0, 0.0, -64.0, "solid")
	if fe == null or block == null or mid_east == null or strip == null \
			or mid_west == null or ra == null or rb == null or lip == null or top == null:
		_check(false, "Hazards: key platforms missing after strip split")
		inst.queue_free()
		await physics_frame
		return
	_check(bool(strip.hazardous), "Hazards: strip segment flagged hazardous")
	_check(not bool(mid_east.hazardous) and not bool(mid_west.hazardous),
			"Hazards: only the strip segment is hazardous")

	# Walking THROUGH the strip costs 202 (entry, hazard mult 4) + 10 (exit).
	var walk_entry = null
	var walk_exit = null
	for e in graph.edges_from(mid_east.id):
		if e.to_id == strip.id and String(e.type) == "walk":
			walk_entry = e
	for e in graph.edges_from(strip.id):
		if e.to_id == mid_west.id and String(e.type) == "walk":
			walk_exit = e
	var through := -1.0
	if walk_entry != null and walk_exit != null:
		through = walk_entry.edge_cost(1.0) + walk_exit.edge_cost(1.0)
	print("  walk-through cost: %.1f (entry %.1f + exit %.1f)" % [through,
			walk_entry.edge_cost(1.0) if walk_entry != null else -1.0,
			walk_exit.edge_cost(1.0) if walk_exit != null else -1.0])
	_check(absf(through - 212.0) < 0.6, "Hazards: walk-through cost 212")

	# FloorEast -> StairTop must jump over the strip, never route through it.
	var west = graph.route(fe.id, top.id, -160.0)
	_print_route("FloorEast->StairTop", west)
	_check_shape(graph, west, fe.id, top.id, "Hazards: route shape FloorEast->StairTop")
	var strip_in_route := false
	var jump_count := 0
	if west != null:
		for pid in west.platform_ids:
			if pid == strip.id:
				strip_in_route = true
		for e in west.edges:
			if String(e.type) == "jump_across":
				jump_count += 1
	_check(west != null and not strip_in_route,
			"Hazards: route never touches the spike segment")
	_check(jump_count == 1, "Hazards: exactly one jump_across over the strip")
	_check(west != null and absf(west.total_cost(1.0) - 521.6) < 0.5,
			"Hazards: route cost 521.6 (250+52+179.6+40)")
	_check(west != null and west.total_cost(1.0) < 250.0 + 52.0 + through + 40.0,
			"Hazards: jump-over (179.6) beats walk-through (%.0f)" % through)
	_check(west != null and west.platform_ids == [fe.id, block.id, mid_east.id,
			mid_west.id, ra.id, rb.id, lip.id, top.id],
			"Hazards: full chain fe->block->midEast-(jump)->midWest->ramps->top")

	# Localizing over the strip x still reports the hazardous segment (the
	# executor's escape override keys off this), while routing avoids it.
	var loc_strip: int = graph.localize(Vector2(320.0, 127.0), true, strip.cells[0])
	_check(loc_strip == strip.id, "Hazards: on-strip localize -> hazardous segment")

	inst.queue_free()
	await physics_frame