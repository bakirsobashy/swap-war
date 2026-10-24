extends SceneTree

## Headless probe for the navigation bake (plan step 1).
##
## For each arena (Flat / Pit / Hazards + legacy arena.tscn):
##   - prints the full platform/edge dump
##   - asserts layout-independent sanity (margins, kill filter, localization
##     round-trips) that stays valid when the placeholder arenas are repainted
##   - asserts a small set of placeholder snapshot values (stair chain, floor
##     split, 62px tile honoring) that get re-derived when arenas finalize
## Plus: override-marker contract, hazard split/cost math, graph caching,
## empty-scene guard.
##
## `-s` mode discipline: runtime load() only, untyped vars, no game-class
## annotations, zero autoload references.

var _fails: int = 0
var _arena_index: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var baker = load("res://Scripts/AI/NavBaker.gd")

	# --- per-arena sanity + snapshots -----------------------------------
	await _probe_scene(baker, "res://Scenes/arena.tscn", false)
	await _probe_scene(baker, "res://Scenes/Arenas/ArenaFlat.tscn", true)
	await _probe_scene(baker, "res://Scenes/Arenas/ArenaPit.tscn", true)
	await _probe_scene(baker, "res://Scenes/Arenas/ArenaHazards.tscn", true)

	# --- override / hazard / cache contract (all on ArenaHazards) -------
	await _probe_overrides(baker)
	await _probe_hazards(baker)
	await _probe_caching(baker)

	var verdict := "ALL PASS"
	if _fails > 0:
		verdict = "%d FAILURES" % _fails
	print("\n=== nav_bake_probe: %s ===" % verdict)
	quit(1 if _fails > 0 else 0)

func _check(ok: bool, what: String) -> void:
	var verdict := "FAIL"
	if ok:
		verdict = "PASS"
	print("  %s: %s" % [verdict, what])
	if not ok:
		_fails += 1

func _instantiate(path: String) -> Node:
	var scene = load(path)
	var inst = scene.instantiate()
	root.add_child(inst)
	await physics_frame
	await physics_frame
	return inst

# --- sanity (layout-independent) ----------------------------------------------

func _sanity(graph, label: String) -> void:
	var count: int = graph.platforms.size()
	if count == 0:
		_check(false, "%s: expected platforms, baked none" % label)
		return
	for p in graph.platforms:
		if p.x_max - p.x_min < graph.MIN_PLATFORM_W:
			_check(false, "%s: platform P%d thinner than MIN_PLATFORM_W" % [label, p.id])
		if p.y_top >= graph.kill_rect.position.y:
			_check(false, "%s: platform P%d inside the kill zone" % [label, p.id])
		if p.cells.is_empty():
			_check(false, "%s: platform P%d has no cells" % [label, p.id])
	# Localization round-trip: grounded on a known cell -> that platform.
	# The tier-1 check is separate because tier-2 alone can mask a hole in the
	# cell->platform map (the grounded case would silently fall through).
	for p in graph.platforms:
		var feet = Vector2(p.center(), p.y_top)
		if graph.localize(feet, true, p.cells[0]) != p.id:
			_check(false, "%s: localize(feet on P%d, grounded) != P%d" % [label, p.id, p.id])
		if graph.platform_from_cell(p.cells[0]) != p.id:
			_check(false, "%s: tier-1 cell map: P%d.cells[0] resolves wrong" % [label, p.id])
	# Every platform localizes airborne to something valid.
	for p in graph.platforms:
		if graph.localize(Vector2(p.center(), p.y_top - 200.0), false, Vector2i(9999, 9999)) < 0:
			_check(false, "%s: airborne localize over P%d found nothing" % [label, p.id])
	# Edge margins: every auto edge respects the verified physics envelope.
	var edge_count := 0
	for a in graph.edges_by_from.keys():
		for e in graph.edges_by_from[a]:
			edge_count += 1
			var A = graph.platforms[e.from_id]
			var B = graph.platforms[e.to_id]
			if e.launch_x < A.x_min or e.launch_x > A.x_max:
				_check(false, "%s: edge P%d->P%d launch outside A" % [label, e.from_id, e.to_id])
			if e.land_x < B.x_min or e.land_x > B.x_max:
				_check(false, "%s: edge P%d->P%d land outside B" % [label, e.from_id, e.to_id])
			if e.type == &"jump_up":
				if -e.dy > graph.JUMP_UP_MAX_RISE:
					_check(false, "%s: jump_up P%d->P%d rise %.0f over cap" % [label, e.from_id, e.to_id, -e.dy])
				if absf(e.land_x - e.launch_x) > graph.JUMP_UP_MAX_H:
					_check(false, "%s: jump_up P%d->P%d over horizontal cap" % [label, e.from_id, e.to_id])
			elif e.type == &"jump_across":
				if absf(e.dy) > graph.JUMP_LEVEL_TOL:
					_check(false, "%s: jump_across P%d->P%d not level" % [label, e.from_id, e.to_id])
			elif e.type == &"drop_down":
				if e.dy > graph.DROP_MAX_HEIGHT:
					_check(false, "%s: drop P%d->P%d over height cap" % [label, e.from_id, e.to_id])
	print("  [%s] sanity ok: %d platforms, %d edges" % [label, count, edge_count])

func _find_platform(graph, x_min: float, x_max: float, y_top: float, kind: String):
	for p in graph.platforms:
		if absf(p.x_min - x_min) < 0.5 and absf(p.x_max - x_max) < 0.5 \
				and absf(p.y_top - y_top) < 0.5 and String(p.kind) == kind:
			return p
	return null

func _find_edge(graph, from_id: int, to_id: int, type: String):
	for e in graph.edges_from(from_id):
		if e.to_id == to_id and (type == "" or String(e.type) == type):
			return e
	return null

# --- per-arena probe ------------------------------------------------------------

func _probe_scene(baker, path: String, with_snapshots: bool) -> void:
	_arena_index += 1
	var label := path.get_file()
	var inst = await _instantiate(path)
	var graph = baker.bake(inst)
	print("\n=== bake %d: %s ===" % [_arena_index, label])
	print(graph.dump())
	_sanity(graph, label)

	if label == "ArenaFlat.tscn":
		# 62px tile size honored: every platform edge lands on a 62px cell
		# boundary (a 64px bake would read e.g. [-960, -448]). The repainted
		# floor has two pits, so it bakes as three floor segments joined by
		# jump_across edges over the gaps (snapshot re-derived after the
		# "Refresh UI and arena presentation" arena repaint).
		var seg_w = _find_platform(graph, -930.0, -434.0, 0.0, "solid")
		var seg_m = _find_platform(graph, -248.0, 186.0, 0.0, "solid")
		var seg_e = _find_platform(graph, 372.0, 930.0, 0.0, "solid")
		_check(seg_w != null, "Flat: west floor segment [-930,-434]@0 (62px honored)")
		_check(seg_m != null, "Flat: mid floor segment [-248,186]@0")
		_check(seg_e != null, "Flat: east floor segment [372,930]@0 (62px honored)")
		_check(int(graph.tile_size) == 62, "Flat: tile size read from TileSet (62)")
		if seg_w != null and seg_m != null and seg_e != null:
			_check(_find_edge(graph, seg_w.id, seg_m.id, "jump_across") != null,
					"Flat: pits are crossable (west->mid jump_across)")
			_check(_find_edge(graph, seg_m.id, seg_e.id, "jump_across") != null,
					"Flat: pits are crossable (mid->east jump_across)")
		# Sub-floor pillars are covered by the floor cells above them: nothing
		# below floor level may appear as a platform.
		var below_floor := 0
		for p in graph.platforms:
			if p.y_top > 0.5:
				below_floor += 1
		_check(below_floor == 0, "Flat: sub-floor pillars filtered out (%d leaked)" % below_floor)
		# The two floating props are exit-only: nothing reaches them (rise 434
		# is far past any jump), but each drops to whichever floor segment sits
		# under it (fall 434).
		for p in graph.platforms:
			if absf(p.y_top - (-434.0)) >= 0.5:
				continue
			var has_in := false
			for a in graph.edges_by_from.keys():
				for e in graph.edges_by_from[a]:
					if e.to_id == p.id:
						has_in = true
			_check(not has_in, "Flat: floating prop P%d has no in-edges" % p.id)
			var drops_to_floor := false
			for e in graph.edges_by_from.get(p.id, []):
				if String(e.type) == "drop_down" and absf(e.dy - 434.0) < 1.0:
					drops_to_floor = true
			_check(drops_to_floor, "Flat: prop P%d walk_off drop to a floor segment" % p.id)
		_check(absf(graph.kill_rect.position.y - 247.0) < 1.0,
				"Flat: scaled KillZone shape -> kill top ~247 (global transform)")
		_check(absf(graph.bounds_min_x - (-1052.0)) < 0.5 and absf(graph.bounds_max_x - 1052.0) < 0.5,
				"Flat: bounds clipped to inner wall faces +/-1052")

	if label == "ArenaPit.tscn" or label == "ArenaHazards.tscn":
		# Stair chain (same painted tiles in both arenas).
		var top = _find_platform(graph, -320.0, 0.0, -64.0, "solid")
		var lip = _find_platform(graph, 0.0, 64.0, -64.0, "one_way")
		var ramp_b = _find_platform(graph, 64.0, 128.0, 0.0, "one_way")
		var ramp_a = _find_platform(graph, 128.0, 192.0, 64.0, "one_way")
		var floor_w = _find_platform(graph, -668.0, 128.0, 128.0, "solid")
		var block = _find_platform(graph, 576.0, 640.0, 64.0, "solid")
		var floor_e = _find_platform(graph, 640.0, 668.0, 128.0, "solid")
		# Pit's mid floor is one platform; Hazards' is split at BAKE time by
		# the scene-wired spike strip (NavBaker's hazards group scan) into
		# mid_west / strip (hazardous) / mid_east. The chain asserts below use
		# whichever platform borders the ramps / RightBlock in each arena.
		var floor_mid = _find_platform(graph, 192.0, 576.0, 128.0, "solid")
		var mid_west = _find_platform(graph, 192.0, 288.0, 128.0, "solid")
		var strip = _find_platform(graph, 288.0, 352.0, 128.0, "solid")
		var mid_east = _find_platform(graph, 352.0, 576.0, 128.0, "solid")
		var is_haz := label == "ArenaHazards.tscn"
		var east_of_ramps = mid_west if is_haz else floor_mid
		var east_of_block = mid_east if is_haz else floor_mid
		_check(top != null, "%s: StairTop [-320,0]@-64 solid" % label)
		_check(lip != null, "%s: one-way lip [0,64]@-64" % label)
		_check(ramp_b != null, "%s: rampB [64,128]@0 one_way" % label)
		_check(ramp_a != null, "%s: rampA [128,192]@64 one_way" % label)
		_check(floor_w != null, "%s: FloorWest [-668,128]@128 (floor breaks at stairs)" % label)
		_check(east_of_ramps != null, "%s: mid floor borders the ramps (%s)" % [label,
				"split [192,288]" if is_haz else "FloorMid [192,576]"])
		_check(east_of_block != null, "%s: mid floor borders RightBlock (%s)" % [label,
				"split [352,576]" if is_haz else "FloorMid [192,576]"])
		_check(block != null, "%s: RightBlock [576,640]@64" % label)
		_check(floor_e != null, "%s: FloorEast [640,668]@128" % label)
		if is_haz:
			_check(mid_west != null and mid_east != null,
					"Hazards: FloorMid split at bake ([192,288] + [352,576])")
			_check(strip != null and bool(strip.hazardous),
					"Hazards: scene strip segment hazardous at bake (group scan)")
		else:
			_check(floor_mid != null, "Pit: FloorMid [192,576]@128 (block splits east floor)")
		if top != null and lip != null and ramp_b != null and ramp_a != null \
				and floor_w != null and east_of_block != null:
			# Stair chain under the slope-side rule: a ramp connects ONLY on
			# its low (east) end — the covered floor tiles let actors walk
			# UNDER its high end, so high-side "walks" would be phantom edges.
			# FloorWest therefore reaches rampA by a real 64px jump_up onto the
			# first step (step-by-step, never a floor->top leap), the ramp
			# chain itself stays pure vertex-matched walks, and leaving the
			# stairs westward is an honest drop.
			var up1 = _find_edge(graph, floor_w.id, ramp_a.id, "jump_up")
			var up2 = _find_edge(graph, ramp_a.id, ramp_b.id, "walk")
			var up3 = _find_edge(graph, ramp_b.id, lip.id, "walk")
			var up4 = _find_edge(graph, lip.id, top.id, "walk")
			_check(up1 != null and absf(up1.launch_x - 128.0) < 0.5 \
					and absf(up1.land_x - 140.0) < 0.5 and absf(up1.dy + 64.0) < 0.5,
					"%s: jump_up FloorWest->rampA (launch 128, land 140, rise 64)" % label)
			_check(_find_edge(graph, floor_w.id, ramp_a.id, "walk") == null,
					"%s: no walk FloorWest->rampA (high side is under-ramp cover)" % label)
			_check(_find_edge(graph, ramp_a.id, floor_w.id, "walk") == null,
					"%s: no walk rampA->FloorWest (high-side exit is a drop, not a walk)" % label)
			_check(up2 != null and up3 != null and String(up2.method) == "slope" \
					and String(up3.method) == "slope",
					"%s: walk up rampA->rampB->lip (vertex-matched slope chain)" % label)
			_check(up4 != null and String(up4.method) == "", "%s: flat walk lip->StairTop" % label)
			var down4 = _find_edge(graph, top.id, lip.id, "walk")
			var down3 = _find_edge(graph, lip.id, ramp_b.id, "walk")
			var down2 = _find_edge(graph, ramp_b.id, ramp_a.id, "walk")
			_check(down4 != null and down3 != null, "%s: walk back down StairTop->lip->rampB" % label)
			_check(down2 != null and String(down2.method) == "slope",
					"%s: walk back down rampB->rampA" % label)
			var drop_b = _find_edge(graph, ramp_b.id, floor_w.id, "drop_down")
			_check(drop_b != null and String(drop_b.method) == "drop_through" \
					and absf(drop_b.launch_x - 96.0) < 0.5,
					"%s: drop rampB->FloorWest (drop_through at the cell center)" % label)
			_check(_find_edge(graph, ramp_a.id, floor_w.id, "drop_down") == null,
					"%s: no rampA->FloorWest drop (covered column blocks the shaft)" % label)
			# Drop off the stair top down to the west floor (walk_off).
			var drop_e = _find_edge(graph, top.id, floor_w.id, "drop_down")
			_check(drop_e != null and String(drop_e.method) == "walk_off",
					"%s: drop StairTop->FloorWest (walk_off)" % label)
			# Localization: boundary x between the mid floor and RightBlock is
			# deterministic, and airborne above the stairs finds StairTop.
			_check(graph.localize(Vector2(576.0, 128.0), false, Vector2i(9999, 9999)) == east_of_block.id,
					"%s: boundary x=576 localizes the mid-floor side" % label)
			_check(graph.localize(Vector2(-160.0, -264.0), false, Vector2i(9999, 9999)) == top.id,
					"%s: airborne above stairs -> StairTop (highest below)" % label)
		# The bottom ramp connects the mid floor to the stair chain on its
		# LOW (east) end (whole mid floor in Pit, west split segment in
		# Hazards); the west side is reached by the jump_up asserted above.
		if ramp_a != null:
			_check(graph.platform_from_cell(Vector2i(2, 2)) == -1,
					"%s: covered floor cell (2,2) maps to no platform" % label)
		if ramp_a != null and east_of_ramps != null:
			_check(_find_edge(graph, ramp_a.id, east_of_ramps.id, "walk") != null,
					"%s: rampA walks down to the mid floor (east slope)" % label)
			_check(_find_edge(graph, east_of_ramps.id, ramp_a.id, "walk") != null,
					"%s: mid floor walks up rampA (east slope)" % label)
		# The jump across the stair gap is blocked: the ramp column pokes into
		# the flight band west, RightBlock east. The graph must route over the
		# ramps / block instead of leaping.
		if floor_w != null and east_of_ramps != null:
			_check(_find_edge(graph, floor_w.id, east_of_ramps.id, "jump_across") == null,
					"%s: no jump_across FloorWest->mid floor (ramp column blocks it)" % label)
		if east_of_block != null and floor_e != null:
			_check(_find_edge(graph, east_of_block.id, floor_e.id, "jump_across") == null,
					"%s: no jump_across mid floor->FloorEast (RightBlock blocks it)" % label)
		if top != null and ramp_b != null:
			_check(_find_edge(graph, top.id, ramp_b.id, "drop_down") == null,
					"%s: no StairTop->rampB drop (landing needs 392px drift in a 64px fall)" % label)
		if east_of_block != null and block != null:
			var j = _find_edge(graph, east_of_block.id, block.id, "jump_up")
			_check(j != null, "%s: jump_up mid floor->RightBlock (rise 64)" % label)
		# Sky ledges: exit-only perches 512px above the floor — no jump reaches
		# them, and dropping off is the only way down. EastLedge->FloorEast is
		# directly over it but physically blocked: the east column is the wall,
		# the west column is RightBlock — the route goes via the block.
		var ledge_w = _find_platform(graph, -668.0, -640.0, -384.0, "solid")
		var ledge_e = _find_platform(graph, 640.0, 668.0, -384.0, "solid")
		_check(ledge_w != null, "%s: WestLedge [-668,-640]@-384" % label)
		_check(ledge_e != null, "%s: EastLedge [640,668]@-384" % label)
		if ledge_w != null:
			var w_in := false
			for a in graph.edges_by_from.keys():
				for e in graph.edges_by_from[a]:
					if e.to_id == ledge_w.id:
						w_in = true
			_check(not w_in, "%s: WestLedge unreachable (no in-edges)" % label)
			if floor_w != null:
				var dw = _find_edge(graph, ledge_w.id, floor_w.id, "drop_down")
				_check(dw != null and String(dw.method) == "walk_off",
						"%s: WestLedge walk_off drop to FloorWest (fall 512)" % label)
		if ledge_e != null:
			var ledge_e_in := false
			for a in graph.edges_by_from.keys():
				for e in graph.edges_by_from[a]:
					if e.to_id == ledge_e.id:
						ledge_e_in = true
			_check(not ledge_e_in, "%s: EastLedge unreachable (no in-edges)" % label)
			if block != null:
				_check(_find_edge(graph, ledge_e.id, block.id, "drop_down") != null,
						"%s: EastLedge drop to RightBlock" % label)
			if floor_e != null:
				_check(_find_edge(graph, ledge_e.id, floor_e.id, "drop_down") == null,
						"%s: no direct EastLedge->FloorEast drop (wall column)" % label)
		if label == "ArenaHazards.tscn":
			_check(absf(graph.kill_rect.position.y - 260.0) < 0.5,
					"Hazards: kill top 260")
		if label == "ArenaPit.tscn":
			_check(absf(graph.kill_rect.position.y - 280.0) < 0.5,
					"Pit: kill top 280")

	inst.queue_free()
	await physics_frame

# --- override-marker contract ----------------------------------------------------

func _probe_overrides(baker) -> void:
	print("\n=== override markers (ArenaHazards) ===")
	var inst = await _instantiate("res://Scenes/Arenas/ArenaHazards.tscn")
	var world = inst.get_node("World")

	var g = baker.bake(inst)
	var fw = _find_platform(g, -668.0, 128.0, 128.0, "solid")
	var ra = _find_platform(g, 128.0, 192.0, 64.0, "one_way")
	if fw == null or ra == null:
		_check(false, "override: baseline platforms missing (FloorWest/rampA)")
		inst.queue_free()
		await physics_frame
		return
	_check(_find_edge(g, fw.id, ra.id, "jump_up") != null,
			"override: baseline jump_up FloorWest->rampA exists")

	# block: removes auto edges whose launch/land falls within the radius.
	# Marker at x=144 r=8 catches the jump_up via its land_x (140) while every
	# edge launching at the shared x=128 boundary (rampA->rampB, rampB->rampA)
	# stays outside the radius — precise positional filtering.
	var m1 = Marker2D.new()
	m1.name = "NavBlock"
	m1.position = Vector2(144.0, 40.0)
	m1.add_to_group("nav_overrides")
	m1.set_meta("block", 8.0)
	world.add_child(m1)
	var g2 = baker.bake(inst)
	var fw2 = _find_platform(g2, -668.0, 128.0, 128.0, "solid")
	var ra2 = _find_platform(g2, 128.0, 192.0, 64.0, "one_way")
	var rb2 = _find_platform(g2, 64.0, 128.0, 0.0, "one_way")
	var lip2 = _find_platform(g2, 0.0, 64.0, -64.0, "one_way")
	if fw2 == null or ra2 == null or rb2 == null or lip2 == null:
		_check(false, "override: platforms missing after block marker")
	else:
		_check(_find_edge(g2, fw2.id, ra2.id, "jump_up") == null,
				"override: block removes FloorWest->rampA jump_up (land_x within radius)")
		_check(_find_edge(g2, ra2.id, rb2.id, "walk") != null,
				"override: block leaves the launch-adjacent ramp walk alone")
		_check(_find_edge(g2, rb2.id, lip2.id, "walk") != null,
				"override: block leaves far edges alone")

	# typed block: only edges of that type are removed.
	m1.set_meta("block_type", "jump_across")
	var g3 = baker.bake(inst)
	var fw3 = _find_platform(g3, -668.0, 128.0, 128.0, "solid")
	var ra3 = _find_platform(g3, 128.0, 192.0, 64.0, "one_way")
	if fw3 == null or ra3 == null:
		_check(false, "override: platforms missing after typed block")
	else:
		_check(_find_edge(g3, fw3.id, ra3.id, "jump_up") != null,
				"override: typed block spares other types")
	m1.free()

	# force_link: manual one-directional edge between the platforms the two
	# markers localize to. The to-marker at (384,128) sits on the mid floor —
	# the east split segment [352,576] now that the scene strip is baked in.
	var from_m = Marker2D.new()
	from_m.name = "NavForceFrom"
	from_m.position = Vector2(-270.0, 128.0)
	from_m.add_to_group("nav_overrides")
	from_m.set_meta("force_link", "../NavForceTo")
	var to_m = Marker2D.new()
	to_m.name = "NavForceTo"
	to_m.position = Vector2(384.0, 128.0)
	world.add_child(from_m)
	world.add_child(to_m)
	var g4 = baker.bake(inst)
	var fw4 = _find_platform(g4, -668.0, 128.0, 128.0, "solid")
	var fm4 = _find_platform(g4, 352.0, 576.0, 128.0, "solid")
	if fw4 == null or fm4 == null:
		_check(false, "override: platforms missing after force_link markers")
	else:
		_check(_find_edge(g4, fw4.id, fm4.id, "jump_across") != null,
				"override: force_link adds FloorWest->mid-floor jump_across")
		_check(_find_edge(g4, fm4.id, fw4.id, "jump_across") == null,
				"override: force_link is one-directional")
	from_m.free()
	to_m.free()

	inst.queue_free()
	await physics_frame

# --- hazard split & cost math (scene-wired strip + graph-level add/remove) ---------

func _probe_hazards(baker) -> void:
	print("\n=== hazard split & costs (ArenaHazards) ===")
	var inst = await _instantiate("res://Scenes/Arenas/ArenaHazards.tscn")
	var g = baker.bake(inst)

	# The scene-wired SpikeStrip is picked up by NavBaker's hazards group scan
	# at bake time: the mid floor arrives already split, no runtime add needed.
	var west = _find_platform(g, 192.0, 288.0, 128.0, "solid")
	var strip = _find_platform(g, 288.0, 352.0, 128.0, "solid")
	var east = _find_platform(g, 352.0, 576.0, 128.0, "solid")
	_check(west != null and east != null,
			"hazard: floor splits around the strip at bake (group scan)")
	_check(strip != null and strip.hazardous and absf(strip.hazard_multiplier - 4.0) < 0.01,
			"hazard: strip segment hazardous x4 (scene group scan)")

	# Route math from the plan: walk-through = 10 + (4-1)*64 + 10 = 212,
	# jump-over = 30 + 64*1.4 + 60 (corridor surcharge) = 179.6.
	if west == null or strip == null or east == null:
		_check(false, "hazard: split platforms missing (west/strip/east)")
	else:
		var entry = _find_edge(g, west.id, strip.id, "walk")
		var exit = _find_edge(g, strip.id, east.id, "walk")
		var over = _find_edge(g, west.id, east.id, "jump_across")
		_check(entry != null and absf(entry.edge_cost(1.0) - 202.0) < 0.6,
				"hazard: walk entry into strip costs 10+192")
		_check(exit != null and absf(exit.edge_cost(1.0) - 10.0) < 0.01,
				"hazard: walk exit of strip costs 10")
		_check(over != null, "hazard: jump_across over the strip exists")
		if over != null and entry != null and exit != null:
			_check(absf(over.edge_cost(1.0) - 179.6) < 0.6,
					"hazard: jump-over costs 179.6 (30 + 89.6 + 60)")
			_check(over.edge_cost(1.0) < entry.edge_cost(1.0) + exit.edge_cost(1.0),
					"hazard: A* prefers jumping the strip (179.6 < 212)")
	if strip != null:
		_check(g.point_in_hazard(Vector2(320.0, 120.0)),
				"hazard: point_in_hazard inside the strip")
		_check(g.localize(Vector2(320.0, 128.0), false, Vector2i(9999, 9999)) == strip.id,
				"hazard: x=320 localizes the hazardous platform")
		_check(absf(g.hazard_escape_dir(Vector2(320.0, 120.0))) == 1.0,
				"hazard: escape dir is nonzero inside the strip")

	# Runtime add/remove still works on a graph that already carries the
	# scene strip: a second rect over FloorWest splits it, and removing that
	# rect restores ONLY FloorWest — the strip survives (rect-keyed removal).
	var rev0: int = g.revision
	g.add_hazard_rect(Rect2(64.0, 96.0, 64.0, 32.0), 4.0)
	_check(g.revision > rev0, "hazard: revision bumps on add")
	var west_a = _find_platform(g, -668.0, 64.0, 128.0, "solid")
	var west_b = _find_platform(g, 64.0, 128.0, 128.0, "solid")
	_check(west_a != null and west_b != null and bool(west_b.hazardous),
			"hazard: second rect splits FloorWest ([64,128] hazardous)")
	var rev1: int = g.revision
	g.remove_hazard_rect(Rect2(64.0, 96.0, 64.0, 32.0))
	_check(g.revision > rev1, "hazard: revision bumps on remove")
	_check(_find_platform(g, -668.0, 128.0, 128.0, "solid") != null,
			"hazard: FloorWest rejoined after remove")
	_check(g.point_in_hazard(Vector2(320.0, 120.0)),
			"hazard: scene strip survives the other rect's removal")

	inst.queue_free()
	await physics_frame

# --- caching ----------------------------------------------------------------------

func _probe_caching(baker) -> void:
	print("\n=== caching & empty scenes ===")
	var inst = await _instantiate("res://Scenes/Arenas/ArenaPit.tscn")
	var g1 = baker.get_cached(inst)
	var g2 = baker.get_cached(inst)
	_check(g1 == g2, "caching: get_cached returns the same instance")
	_check(inst.has_meta("nav_graph"), "caching: graph stored on scene meta")
	var g3 = baker.bake(inst)
	_check(g3 != g1 and g3.platforms.size() == g1.platforms.size(),
			"caching: bake() makes a fresh graph with the same platforms")
	inst.queue_free()
	await physics_frame

	var empty = Node2D.new()
	root.add_child(empty)
	var ge = baker.get_cached(empty)
	_check(ge != null and ge.platforms.size() == 0,
			"caching: scene without TileMapLayer -> empty graph")
	_check(baker.get_cached(empty) == ge, "caching: empty graph cached too")
	_check(baker.get_cached(null) == null, "caching: null scene -> null")
	empty.queue_free()
	await physics_frame