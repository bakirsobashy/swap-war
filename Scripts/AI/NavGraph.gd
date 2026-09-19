class_name NavGraph
extends RefCounted

## Baked platform-graph for one arena instance.
##
## Built by NavBaker from the instantiated TileMapLayer; one graph per arena,
## shared by every AI (cached on the scene node's meta). Holds the classified
## tile cells, the extracted platforms, the movement edges, hazard rects, and
## every navigation query (localization, hazard lookups, route factory).
##
## All geometry is in world pixels; `tile_size` is read from the arena's
## TileSet so 62px and 64px arenas both bake correctly. Physics-derived
## constants carry 75-80% safety margins on the verified jump envelope
## (apex 103px, flat reach 275px at 60 tps, gravity 980).
##
## Compile-safety: this script must stay autoload-free and self-contained so
## headless probes can `load()` it in `-s` mode. Other nav scripts reach it
## through `preload("res://Scripts/AI/NavGraph.gd")` and duck-typed calls,
## never through this class_name at compile time.

const WALK_Y_TOL := 4.0
const JUMP_LEVEL_TOL := 16.0
const JUMP_UP_MAX_RISE := 80.0        # verified apex 103px * ~77%
const JUMP_UP_MAX_H := 160.0          # reach at 64px rise, ~75% margin
const JUMP_ACROSS_MAX_GAP := 208.0    # verified flat reach 275px * ~76%
const JUMP_ACROSS_LAUNCH_PULLBACK := 48.0
const JUMP_ACROSS_LAND_INSET := 28.0
const JUMP_APEX_BAND := 110.0         # apex 103px + capsule leeway
const DROP_MAX_HEIGHT := 600.0        # pacing bound only; the kill filter
                                      # already guarantees safe landings
                                      # (real ledge drops are 512px)
const DROP_DRIFT_X := 96.0
const MIN_PLATFORM_W := 24.0
const HAZARD_SURFACE_BAND := 96.0
const EDGE_MARGIN := 12.0
const HAZARD_CORRIDOR_SURCHARGE := 60.0

## Routing delegate (A* lives in NavAStar). NavAStar is a leaf with no
## preloads of its own, so this cannot cycle.
const NavAStarScript := preload("res://Scripts/AI/NavAStar.gd")

## A contiguous walkable top surface (maximal run of same-kind surface cells).
class Platform:
	var id: int = -1
	var x_min: float = 0.0
	var x_max: float = 0.0
	var y_top: float = 0.0
	var kind: StringName = &"solid"      # &"solid" | &"one_way"
	## One-way slope orientation: -1 = surface climbs westward (high vertex
	## west, low end east), +1 = climbs eastward, 0 = solid or flat one-way.
	var ascend: int = 0
	var hazardous: bool = false
	var hazard_multiplier: float = 1.0
	var cells: Array = []                # surface Vector2i cells, left to right

	func width() -> float:
		return x_max - x_min

	func center() -> float:
		return (x_min + x_max) * 0.5

	func contains_x(x: float) -> bool:
		return x >= x_min and x <= x_max

## One traversable movement between two platforms. Per-query cost:
##   cost_fixed + hazard_cost + cost_scale * cost_dist * (risk if risk_scaled)
class Edge:
	var from_id: int = -1
	var to_id: int = -1
	var type: StringName = &"walk"       # walk | jump_up | jump_across | drop_down
	var method: StringName = &""         # walk: ""|slope; drop: drop_through|walk_off
	var launch_x: float = 0.0
	var land_x: float = 0.0
	var dy: float = 0.0                  # B.y_top - A.y_top (positive = B lower)
	var cost_dist: float = 0.0
	var cost_scale: float = 1.0
	var risk_scaled: bool = false
	var cost_fixed: float = 10.0
	var hazard_cost: float = 0.0
	var blocked: bool = false

	func edge_cost(risk_weight: float) -> float:
		var c := cost_fixed + hazard_cost
		c += cost_scale * cost_dist * (risk_weight if risk_scaled else 1.0)
		return c

## A planned path produced by NavAStar (built via NavGraph.make_route).
class Route:
	var platform_ids: Array = []
	var edges: Array = []
	var dest_x: float = 0.0
	var dest_platform: int = -1

	## Sum of edge costs at this risk weight (RetreatState scores candidates
	## with it; probes assert exact route costs).
	func total_cost(risk_weight := 1.0) -> float:
		var sum := 0.0
		for e: Edge in edges:
			sum += e.edge_cost(risk_weight)
		return sum

# --- world data (set once by NavBaker) --------------------------------------
var tile_size: float = 64.0
var solid_cells: Dictionary = {}        # Vector2i -> true
var one_way_cells: Dictionary = {}      # Vector2i -> int ascend (-1 west, +1 east, 0 flat)
var bounds_min_x: float = -1000000.0
var bounds_max_x: float = 1000000.0
var kill_rect: Rect2 = Rect2(0.0, 1000000.0, 0.0, 0.0)  # position.y = kill top

# --- runtime-mutable content -------------------------------------------------
var hazard_rects: Array = []            # {rect: Rect2, mult: float}
var block_markers: Array = []           # {x: float, radius: float, type: StringName}
var force_link_markers: Array = []      # {from_pos, to_pos, type, cost}

# --- derived -----------------------------------------------------------------
var platforms: Array = []              # Array[Platform], ids = index
var edges_by_from: Dictionary = {}     # from_id -> Array[Edge]
var cell_to_platform: Dictionary = {}  # Vector2i -> platform id
var revision: int = 0
var _dirty := false

## Called by NavBaker once the world data is collected. Marks a rebuild; the
## baker flushes after hazards and overrides are registered too.
func set_world_data(ts: Vector2i, solids: Dictionary, one_ways: Dictionary,
		min_x: float, max_x: float, kill: Rect2) -> void:
	tile_size = maxf(8.0, float(ts.x))
	solid_cells = solids
	one_way_cells = one_ways
	bounds_min_x = min_x
	bounds_max_x = max_x
	kill_rect = kill
	_dirty = true

## Register a hazard (spike strip, future timed hazards). Splits intersecting
## platforms and regenerates edges. Works pre- and post-bake with the same API:
## NavBaker collects hazards found at bake time; HazardArea calls this directly
## when it appears after the graph exists.
func add_hazard_rect(rect: Rect2, mult: float, immediate := true) -> void:
	hazard_rects.append({"rect": rect.abs(), "mult": maxf(1.0, mult)})
	_dirty = true
	if immediate:
		flush()

func remove_hazard_rect(rect: Rect2, immediate := true) -> void:
	var target := rect.abs()
	for i in hazard_rects.size():
		if (hazard_rects[i]["rect"] as Rect2).is_equal_approx(target):
			hazard_rects.remove_at(i)
			_dirty = true
			if immediate:
				flush()
			return

## Override marker: remove auto edges whose launch/land point falls within
## `radius` of world x, optionally only of one type (&"" = any).
func add_block_marker(x: float, radius: float, type: StringName, immediate := true) -> void:
	block_markers.append({"x": x, "radius": radius, "type": type})
	_dirty = true
	if immediate:
		flush()

## Override marker: one-directional manual edge between the platforms that the
## two marker positions localize to. `type` &"" infers from the height diff.
func add_force_link(from_pos: Vector2, to_pos: Vector2, type: StringName,
		cost: float, immediate := true) -> void:
	force_link_markers.append({
		"from_pos": from_pos, "to_pos": to_pos, "type": type, "cost": cost,
	})
	_dirty = true
	if immediate:
		flush()

## Rebuild platforms and edges if anything changed. Bumps `revision` so the
## executor knows to replan.
func flush() -> void:
	if not _dirty:
		return
	_dirty = false
	_build_platforms()
	_build_edges()
	revision += 1

# --- platform extraction -----------------------------------------------------

func _is_one_way(cell: Vector2i) -> bool:
	return one_way_cells.has(cell)

func _is_support(cell: Vector2i) -> bool:
	return solid_cells.has(cell) or one_way_cells.has(cell)

## A cell is a walkable surface iff something supports it and nothing covers
## it from above (solid OR one-way both count as cover — a ramp tile sitting on
## the floor removes the floor cells beneath it from the walkable set).
func _is_surface(cell: Vector2i) -> bool:
	return _is_support(cell) and not _is_support(cell + Vector2i(0, -1))

func _build_platforms() -> void:
	platforms.clear()
	cell_to_platform.clear()
	var by_row: Dictionary = {}   # cell.y -> Array[Vector2i] surface cells
	for cell: Vector2i in solid_cells.keys():
		if _is_surface(cell):
			by_row.get_or_add(cell.y, []).append(cell)
	for cell: Vector2i in one_way_cells.keys():
		if _is_surface(cell):
			by_row.get_or_add(cell.y, []).append(cell)
	for y: int in by_row.keys():
		var cells: Array = by_row[y]
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
		var i := 0
		while i < cells.size():
			var one_way := _is_one_way(cells[i])
			var j := i
			while j + 1 < cells.size() \
					and cells[j + 1].x == cells[j].x + 1 \
					and _is_one_way(cells[j + 1]) == one_way:
				j += 1
			_push_run(cells.slice(i, j + 1), y, one_way)  # slice end is exclusive
			i = j + 1
	# Stable ids: top-to-bottom, left-to-right.
	platforms.sort_custom(func(a, b) -> bool:
		if a.y_top != b.y_top:
			return a.y_top < b.y_top
		return a.x_min < b.x_min)
	for idx: int in platforms.size():
		platforms[idx].id = idx
		# Tier-1 localization map: every surviving surface cell resolves to its
		# platform (segments own disjoint cells, so no cell is written twice).
		for c: Vector2i in platforms[idx].cells:
			cell_to_platform[c] = idx

func _push_run(cells: Array, y: int, one_way: bool) -> void:
	if cells.is_empty():
		return
	var ts := tile_size
	# Bounds clipping: keep cells with any horizontal overlap with the playable
	# interval, then clip the run's x-range to it.
	var x_lo := maxf(float(cells[0].x) * ts, bounds_min_x)
	var x_hi := minf(float(cells[cells.size() - 1].x + 1) * ts, bounds_max_x)
	if x_hi - x_lo < MIN_PLATFORM_W:
		return                          # sliver past a wall — not standable
	if float(y) * ts >= kill_rect.position.y:
		return                          # standing here means death — not in the graph
	var segs := _split_by_hazard(x_lo, x_hi, float(y) * ts)
	# Assign run cells to segments by center. Leftover cells (a run half-cut
	# by a boundary wall) go to the nearest segment they still overlap, so
	# tier-1 localization resolves them; cells fully outside the playable
	# interval are dropped — nothing can stand there.
	var seg_cells: Array = []
	for i in segs.size():
		seg_cells.append([])
	for c: Vector2i in cells:
		var cx := (float(c.x) + 0.5) * ts
		var hit := -1
		for i in segs.size():
			if cx >= segs[i]["x_min"] and cx <= segs[i]["x_max"]:
				hit = i
				break
		if hit < 0:
			var c_lo := float(c.x) * ts
			if c_lo >= x_hi or c_lo + ts <= x_lo:
				continue                   # outside the clipped interval
			hit = 0 if cx < x_lo else segs.size() - 1
		seg_cells[hit].append(c)
	for i in segs.size():
		if segs[i]["x_max"] - segs[i]["x_min"] < MIN_PLATFORM_W or seg_cells[i].is_empty():
			continue                   # sliver or cell-less slice — not standable
		var p := Platform.new()
		p.x_min = segs[i]["x_min"]
		p.x_max = segs[i]["x_max"]
		p.y_top = float(y) * ts
		p.kind = &"one_way" if one_way else &"solid"
		p.ascend = _run_ascend(seg_cells[i]) if one_way else 0
		p.hazardous = segs[i]["hazardous"]
		p.hazard_multiplier = segs[i]["multiplier"]
		p.cells = seg_cells[i]
		platforms.append(p)

## Platform-level slope orientation from its cells' stored ascend values. All
## cells agreeing on a direction gives that direction; any flat or mixed cell
## gives 0 (no side rule — both ends connect).
func _run_ascend(cells: Array) -> int:
	var asc := 0
	for c: Vector2i in cells:
		var d := int(one_way_cells.get(c, 0))
		if d == 0 or (asc != 0 and asc != d):
			return 0
		asc = d
	return asc

## Split a run's x-interval against hazard rects that reach its surface band.
## Returns ordered segments with hazard flags; the run itself is kept intact
## when nothing intersects it.
func _split_by_hazard(x_lo: float, x_hi: float, y_top: float) -> Array:
	var cuts: Array = [x_lo, x_hi]
	var active: Array = []   # overlapping {lo, hi, mult}
	for h in hazard_rects:
		var r: Rect2 = h["rect"]
		if r.position.y >= y_top or r.position.y + r.size.y <= y_top - HAZARD_SURFACE_BAND:
			continue                    # rect does not reach the surface band
		var lo := maxf(r.position.x, x_lo)
		var hi := minf(r.position.x + r.size.x, x_hi)
		if hi <= lo:
			continue
		cuts.append(lo)
		cuts.append(hi)
		active.append({"lo": lo, "hi": hi, "mult": h["mult"]})
	cuts.sort()
	var segs: Array = []
	for k in cuts.size() - 1:
		var s_lo: float = cuts[k]
		var s_hi: float = cuts[k + 1]
		if s_hi - s_lo < 0.5:
			continue
		var mult := 1.0
		for a in active:
			if s_lo >= a.lo - 0.5 and s_hi <= a.hi + 0.5:
				mult = maxf(mult, a.mult)
		segs.append({
			"x_min": s_lo, "x_max": s_hi,
			"hazardous": mult > 1.0, "multiplier": mult,
		})
	if segs.is_empty():
		segs.append({"x_min": x_lo, "x_max": x_hi, "hazardous": false, "multiplier": 1.0})
	return segs

# --- edge generation ---------------------------------------------------------

func _build_edges() -> void:
	edges_by_from.clear()
	for a in platforms.size():
		edges_by_from[a] = []
		var A: Platform = platforms[a]
		for b in platforms.size():
			if a == b:
				continue
			var e := _make_edge(A, platforms[b])
			if e != null and not _edge_blocked(e):
				edges_by_from[a].append(e)
	_apply_force_links()

## At most one auto edge per ordered pair: the type bands are disjoint in dy
## (walk |dy|<=4, slope up one tile, jump_up rise 16..80, jump_across |dy|<=16
## with a real gap, drop fall 16..500).
func _make_edge(A: Platform, B: Platform) -> Edge:
	var dy := B.y_top - A.y_top
	var gap := maxf(B.x_min - A.x_max, A.x_min - B.x_max)  # <=0 = overlap
	if absf(dy) <= WALK_Y_TOL and gap <= 2.0:
		return _walk_edge(A, B, &"")
	# Walk up a one-way slope (the stair ramps): small rise, abutting, and the
	# higher run must be one-way. SIDE RULE: a slope only accepts walkers on
	# its LOW end — the covered floor tiles under a ramp let actors pass
	# beneath its HIGH end, so a "walk" edge onto the high side would be a
	# phantom the executor can never follow (it would stroll under the slope
	# and localize on covered cells). Vertex-matched slope chains (the stair
	# steps) sit on each other's low end by construction, so they still
	# connect; a flat one-way tile (ascend 0) has no low end and connects on
	# both sides.
	if dy <= -WALK_Y_TOL and dy >= -tile_size - 2.0 and B.kind == &"one_way" and gap <= 2.0 \
			and _on_low_side(A, B):
		return _walk_edge(A, B, &"slope")
	# Walk back DOWN off a one-way slope to the ground it sits on — same low-end
	# rule, mirrored: the lower platform must be under the slope's low end.
	# Stepping off the high end is a real drop (the executor falls onto the
	# floor), which the drop_down edges model honestly instead.
	if dy >= WALK_Y_TOL and dy <= tile_size + 2.0 and A.kind == &"one_way" and gap <= 2.0 \
			and _on_low_side(B, A):
		return _walk_edge(A, B, &"slope")
	if absf(dy) <= JUMP_LEVEL_TOL and gap > 2.0 and gap <= JUMP_ACROSS_MAX_GAP:
		return _jump_across_edge(A, B, gap)
	if dy <= -JUMP_LEVEL_TOL and dy >= -JUMP_UP_MAX_RISE:
		return _jump_up_edge(A, B)
	if dy >= JUMP_LEVEL_TOL and dy <= DROP_MAX_HEIGHT:
		return _drop_edge(A, B)
	return null

func _hazard_entry_cost(P: Platform) -> float:
	if P.hazardous:
		return (P.hazard_multiplier - 1.0) * P.width()
	return 0.0

## Interval-nearest x of A toward B's x-range, clamped inside A.
func _nearest_x_toward(A: Platform, B: Platform) -> float:
	if B.x_max < A.x_min:
		return A.x_min
	if B.x_min > A.x_max:
		return A.x_max
	return clampf(B.center(), A.x_min, A.x_max)

## True when `lower` sits on `slope`'s LOW end — the side where the slope
## surface meets the lower walking level. An ascending-west ramp (ascend -1)
## has its low end east, so the walker must be entirely east of the slope;
## ascend +1 mirrors it. Ascend 0 (flat one-way tile / solid) connects both
## ways. Boundary-sharing counts (x_min == slope.x_max is "east").
func _on_low_side(lower: Platform, slope: Platform) -> bool:
	if slope.ascend == 0:
		return true
	if slope.ascend < 0:
		return lower.x_min >= slope.x_max
	return lower.x_max <= slope.x_min

func _walk_edge(A: Platform, B: Platform, method: StringName) -> Edge:
	var e := Edge.new()
	e.from_id = A.id
	e.to_id = B.id
	e.type = &"walk"
	e.method = method
	e.dy = B.y_top - A.y_top
	e.launch_x = _nearest_x_toward(A, B)
	e.land_x = B.center()
	e.cost_fixed = 10.0
	e.cost_scale = 0.0
	e.hazard_cost = _hazard_entry_cost(B)
	return e

func _jump_up_edge(A: Platform, B: Platform) -> Edge:
	var rise := A.y_top - B.y_top
	var dir := -1.0 if B.x_max <= A.x_min else 1.0
	var launch_x := _nearest_x_toward(A, B)
	# Land inset from B's near edge so the capsule clears the ledge side.
	var inset := minf(EDGE_MARGIN, B.width() * 0.25)
	var land_x := clampf(_nearest_x_toward(B, A) + dir * inset, B.x_min, B.x_max)
	if absf(land_x - launch_x) > JUMP_UP_MAX_H:
		return null
	if not _jump_up_corridor_clear(A, B, launch_x, land_x):
		return null
	var e := Edge.new()
	e.from_id = A.id
	e.to_id = B.id
	e.type = &"jump_up"
	e.dy = B.y_top - A.y_top
	e.launch_x = launch_x
	e.land_x = land_x
	e.cost_dist = absf(land_x - launch_x) + 2.0 * rise
	e.cost_scale = 1.5
	e.risk_scaled = true
	e.cost_fixed = 40.0
	e.hazard_cost = _hazard_entry_cost(B) + _hazard_corridor_surcharge(A, B, launch_x, land_x)
	return e

func _jump_across_edge(A: Platform, B: Platform, gap: float) -> Edge:
	var dir := -1.0 if B.x_max < A.x_min else 1.0
	var launch_x := clampf((A.x_max if dir > 0.0 else A.x_min) - dir * JUMP_ACROSS_LAUNCH_PULLBACK,
			A.x_min, A.x_max)
	var land_x := clampf((B.x_min if dir > 0.0 else B.x_max) + dir * JUMP_ACROSS_LAND_INSET,
			B.x_min, B.x_max)
	if not _jump_across_corridor_clear(A, B, launch_x, land_x):
		return null
	var e := Edge.new()
	e.from_id = A.id
	e.to_id = B.id
	e.type = &"jump_across"
	e.dy = B.y_top - A.y_top
	e.launch_x = launch_x
	e.land_x = land_x
	e.cost_dist = gap
	e.cost_scale = 1.4
	e.risk_scaled = true
	e.cost_fixed = 30.0
	e.hazard_cost = _hazard_entry_cost(B) + _hazard_corridor_surcharge(A, B, launch_x, land_x)
	return e

func _drop_edge(A: Platform, B: Platform) -> Edge:
	# Landing window: where B sits under a fall drifting <= DROP_DRIFT_X off A.
	var dy := B.y_top - A.y_top
	var lo := maxf(B.x_min, A.x_min - DROP_DRIFT_X)
	var hi := minf(B.x_max, A.x_max + DROP_DRIFT_X)
	if hi < lo:
		return null
	var drop_x := 0.0
	var land_x := 0.0
	if A.kind == &"one_way":
		# drop_through: fall straight down anywhere on A. Candidate columns
		# are A's own cell centers with a clear shaft to B and a landing the
		# fall can actually drift to.
		var best_d := INF
		for c: Vector2i in A.cells:
			var cx := (float(c.x) + 0.5) * tile_size
			if cx < B.x_min - DROP_DRIFT_X or cx > B.x_max + DROP_DRIFT_X:
				continue
			if not _drop_column_clear(A, B, cx):
				continue
			if absf(clampf(cx, B.x_min, B.x_max) - cx) > _max_fall_drift(dy):
				continue               # cannot cover that drift before landing
			var d := absf(cx - B.center())
			if d < best_d:
				best_d = d
				drop_x = cx
		if best_d == INF:
			return null
		land_x = clampf(drop_x, B.x_min, B.x_max)
	else:
		# walk_off: step off A's edge facing B — the fall happens just OUTSIDE
		# the edge, on the neighboring column (dropping off a block lands on
		# the floor cell beside it, not under it). Try the edge facing B first;
		# if that side is the boundary wall or its column is blocked, the far
		# edge works too — the executor drifts toward land_x while falling.
		var want_left := B.center() < A.center()
		var found := false
		for i in 2:
			var left_side := want_left if i == 0 else not want_left
			var edge_x := A.x_min if left_side else A.x_max
			var col_x := edge_x - 8.0 if left_side else edge_x + 8.0
			if col_x < bounds_min_x or col_x > bounds_max_x:
				continue               # the boundary wall blocks stepping off
			if not _drop_column_clear(A, B, col_x):
				continue
			var l := clampf(col_x, B.x_min, B.x_max)
			if absf(l - col_x) > _max_fall_drift(dy):
				continue               # cannot cover that drift before landing
			drop_x = edge_x
			land_x = l
			found = true
			break
		if not found:
			return null
	var e := Edge.new()
	e.from_id = A.id
	e.to_id = B.id
	e.type = &"drop_down"
	e.method = &"drop_through" if A.kind == &"one_way" else &"walk_off"
	e.dy = dy
	e.launch_x = drop_x
	e.land_x = land_x
	e.cost_dist = absf(land_x - drop_x) + e.dy * 0.5
	e.cost_scale = 1.05
	e.cost_fixed = 10.0
	e.hazard_cost = _hazard_entry_cost(B)
	return e

# --- corridor checks ---------------------------------------------------------

## Horizontal distance an actor can cover while falling `dy` px — 75% of the
## 300px/s run speed over the fall time sqrt(2*dy/g). Bounds the drift between
## a drop column and the clamped landing point so the graph never promises
## mid-air travel the physics cannot deliver.
func _max_fall_drift(dy: float) -> float:
	return 225.0 * sqrt(2.0 * maxf(dy, 1.0) / 980.0)

func _cell_belongs_to(cell: Vector2i, P: Platform) -> bool:
	return P.cells.has(cell)

func _cells_in_rect(x_lo: float, x_hi: float, y_lo: float, y_hi: float) -> Array:
	var out: Array = []
	var cx0 := floori(x_lo / tile_size)
	var cx1 := floori(x_hi / tile_size)
	var cy0 := floori(y_lo / tile_size)
	var cy1 := floori(y_hi / tile_size)
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			out.append(Vector2i(cx, cy))
	return out

## Upward jump corridor: no SOLID cell may occupy the open band between the
## two surfaces over the launch->land span. One-way cells never obstruct
## upward flight (passable from below, land-on-able from above). Cells of the
## source/destination platforms are excluded — the destination's own body is
## inside the band by construction, and without the exclusion every jump onto
## a block would test infeasible.
func _jump_up_corridor_clear(A: Platform, B: Platform, launch_x: float, land_x: float) -> bool:
	var x_lo := minf(launch_x, land_x) - EDGE_MARGIN
	var x_hi := maxf(launch_x, land_x) + EDGE_MARGIN
	for cell: Vector2i in _cells_in_rect(x_lo, x_hi, B.y_top, A.y_top):
		if not solid_cells.has(cell):
			continue
		if _cell_belongs_to(cell, A) or _cell_belongs_to(cell, B):
			continue
		# Overlaps the open band (B.y_top, A.y_top)?
		if float(cell.y) * tile_size < A.y_top and float(cell.y + 1) * tile_size > B.y_top:
			return false
	return true

## Level/step jump corridor: anything poking above the higher platform level
## over the span blocks the flight — but cells AT platform level (e.g. the
## floor continuing under a spike strip) do not, which is exactly what makes
## jumping over a ground hazard strip feasible. One-way cells count too here:
## sideways flight cannot pass a ramp triangle that rises into the band.
func _jump_across_corridor_clear(A: Platform, B: Platform, launch_x: float, land_x: float) -> bool:
	var ref_y := minf(A.y_top, B.y_top)
	var x_lo := minf(launch_x, land_x) - EDGE_MARGIN
	var x_hi := maxf(launch_x, land_x) + EDGE_MARGIN
	for cell: Vector2i in _cells_in_rect(x_lo, x_hi, ref_y - JUMP_APEX_BAND, ref_y):
		if not solid_cells.has(cell) and not one_way_cells.has(cell):
			continue
		if _cell_belongs_to(cell, A) or _cell_belongs_to(cell, B):
			continue
		if float(cell.y) * tile_size < ref_y - 4.0 \
				and float(cell.y + 1) * tile_size > ref_y - JUMP_APEX_BAND:
			return false
	return true

## Drop column: between the two surfaces (their own cells excluded) nothing
## may stand — solid OR one-way — or the fall lands early. An intervening
## one-way platform is its own graph node and must not be tunneled past.
## A's row is included so walls rising beside the edge we step off block the
## fall; B's row is included so covered cells at landing level that belong to
## NO platform (the ramp column) block it too.
func _drop_column_clear(A: Platform, B: Platform, x: float) -> bool:
	var cx := floori(x / tile_size)
	var row_a := floori(A.y_top / tile_size)
	var row_b := floori(B.y_top / tile_size)
	for cy in range(row_a, row_b + 1):
		var cell := Vector2i(cx, cy)
		if _cell_belongs_to(cell, A) or _cell_belongs_to(cell, B):
			continue
		if solid_cells.has(cell) or one_way_cells.has(cell):
			return false
	return true

## Flat surcharge when a jump's flight path passes over a hazard rect — the
## jump is safe but a botched one lands in the spikes, so A* sees some risk.
func _hazard_corridor_surcharge(A: Platform, B: Platform, launch_x: float, land_x: float) -> float:
	var x_lo := minf(launch_x, land_x)
	var x_hi := maxf(launch_x, land_x)
	var ref_y := minf(A.y_top, B.y_top)
	for h in hazard_rects:
		var r: Rect2 = h["rect"]
		if r.position.x >= x_hi or r.position.x + r.size.x <= x_lo:
			continue                    # no x overlap
		if r.position.y >= ref_y or r.position.y + r.size.y <= ref_y - JUMP_APEX_BAND:
			continue                    # not inside the flight band
		return HAZARD_CORRIDOR_SURCHARGE
	return 0.0

# --- overrides ----------------------------------------------------------------

func _edge_blocked(e: Edge) -> bool:
	for m in block_markers:
		var t: StringName = m["type"]
		if t != &"" and t != e.type:
			continue
		if absf(e.launch_x - m["x"]) <= m["radius"] or absf(e.land_x - m["x"]) <= m["radius"]:
			return true
	return false

func _apply_force_links() -> void:
	for fl in force_link_markers:
		var from_id := platform_below(fl["from_pos"])
		var to_id := platform_below(fl["to_pos"])
		if from_id < 0 or to_id < 0 or from_id == to_id:
			continue
		var A: Platform = platforms[from_id]
		var B: Platform = platforms[to_id]
		var e := Edge.new()
		e.from_id = from_id
		e.to_id = to_id
		e.dy = B.y_top - A.y_top
		e.launch_x = clampf(fl["from_pos"].x, A.x_min, A.x_max)
		e.land_x = clampf(fl["to_pos"].x, B.x_min, B.x_max)
		var t: StringName = fl["type"]
		if t == &"":
			if e.dy <= -JUMP_LEVEL_TOL:
				t = &"jump_up"
			elif e.dy >= JUMP_LEVEL_TOL:
				t = &"drop_down"
			else:
				t = &"jump_across"
		e.type = t
		match t:
			&"jump_up":
				e.cost_dist = absf(e.land_x - e.launch_x) + 2.0 * absf(e.dy)
				e.cost_scale = 1.5
				e.risk_scaled = true
				e.cost_fixed = 40.0
			&"jump_across":
				e.cost_dist = maxf(absf(e.land_x - e.launch_x) - 32.0, 0.0)
				e.cost_scale = 1.4
				e.risk_scaled = true
				e.cost_fixed = 30.0
			&"drop_down":
				e.cost_dist = absf(e.land_x - e.launch_x) + absf(e.dy) * 0.5
				e.cost_scale = 1.05
				e.cost_fixed = 10.0
			_:
				e.cost_scale = 0.0
				e.cost_fixed = 10.0
		var cost: float = fl["cost"]
		if cost >= 0.0:
			e.cost_fixed = cost
			e.cost_scale = 0.0
			e.cost_dist = 0.0
			e.risk_scaled = false
			e.hazard_cost = 0.0
		edges_by_from[from_id].append(e)

# --- localization & queries ----------------------------------------------------

## Tier 1: grounded on a known surface cell.
func platform_from_cell(cell: Vector2i) -> int:
	return cell_to_platform.get(cell, -1)

## The platform whose surface is (nearly) exactly under this feet position.
func platform_at(feet_pos: Vector2) -> int:
	for p: Platform in platforms:
		if p.contains_x(feet_pos.x) and absf(p.y_top - feet_pos.y) <= 8.0:
			return p.id
	return -1

## Tier 2: x-containment, highest surface at/below the feet (y_top >= pos.y - 4;
## ties broken toward the nearer platform center).
func platform_below(feet_pos: Vector2) -> int:
	var best := -1
	var best_y := 0.0
	for p: Platform in platforms:
		if not p.contains_x(feet_pos.x):
			continue
		if p.y_top < feet_pos.y - 4.0:
			continue                    # surface above the feet — not below
		if best == -1 or p.y_top < best_y \
				or (p.y_top == best_y and absf(p.center() - feet_pos.x) < absf(platforms[best].center() - feet_pos.x)):
			best = p.id
			best_y = p.y_top
	return best

## Tier 3: recovery anchor for off-graph positions (knockback over a wall etc.).
func nearest_platform(feet_pos: Vector2) -> int:
	var best := -1
	var best_d := INF
	for p: Platform in platforms:
		var dx := 0.0
		if feet_pos.x < p.x_min:
			dx = p.x_min - feet_pos.x
		elif feet_pos.x > p.x_max:
			dx = feet_pos.x - p.x_max
		var d := dx + 2.0 * absf(p.y_top - feet_pos.y)
		if d < best_d:
			best_d = d
			best = p.id
	return best

## The localization contract: grounded on a known cell -> that platform;
## otherwise the surface below; otherwise the nearest platform.
## `feet_pos` is the actor's FEET point (body origin plus the down offset).
func localize(feet_pos: Vector2, grounded: bool, ground_cell: Vector2i) -> int:
	if grounded:
		var pid := platform_from_cell(ground_cell)
		if pid >= 0:
			return pid
	var below := platform_below(feet_pos)
	if below >= 0:
		return below
	return nearest_platform(feet_pos)

func platform_center(id: int) -> Vector2:
	if id < 0 or id >= platforms.size():
		return Vector2.ZERO
	var p: Platform = platforms[id]
	return Vector2(p.center(), p.y_top)

func point_in_hazard(pos: Vector2) -> bool:
	for h in hazard_rects:
		if (h["rect"] as Rect2).has_point(pos):
			return true
	return false

## Direction (±1) out of the hazard containing `pos`, toward its nearer
## horizontal edge. 0 when not inside anything.
func hazard_escape_dir(pos: Vector2) -> float:
	for h in hazard_rects:
		var r: Rect2 = h["rect"]
		if r.grow(8.0).has_point(pos):
			return -1.0 if pos.x < r.get_center().x else 1.0
	return 0.0

## Route factory — NavAStar builds paths through this so it never has to
## reference the inner Route class across files.
func make_route(platform_ids: Array, edges: Array, dest_x: float, dest_platform: int) -> Route:
	var r := Route.new()
	r.platform_ids = platform_ids
	r.edges = edges
	r.dest_x = dest_x
	r.dest_platform = dest_platform
	return r

func edges_from(platform_id: int) -> Array:
	return edges_by_from.get(platform_id, [])

## Cheapest route between two platforms, ending at `dest_x` (clamped into the
## destination platform). `banned_edges` holds [from_id, to_id] pairs (or Edge
## objects) the executor wants blacklisted for this query — e.g. an edge that
## just failed mid-air.
func route(from_id: int, to_id: int, dest_x: float, risk_weight := 1.0,
		banned_edges: Array = []) -> Route:
	return NavAStarScript.find_route(self, from_id, to_id, dest_x,
			risk_weight, banned_edges)

func has_path(from_id: int, to_id: int, risk_weight := 1.0) -> bool:
	return NavAStarScript.has_path(self, from_id, to_id, risk_weight)

## Human-readable dump for probes and editor debugging.
func dump() -> String:
	var lines: Array = []
	lines.append("graph ts=%d bounds=[%d,%d] kill_top=%d hazards=%d rev=%d platforms=%d" % [
		int(tile_size), int(bounds_min_x), int(bounds_max_x),
		int(kill_rect.position.y), hazard_rects.size(), revision, platforms.size(),
	])
	for p: Platform in platforms:
		var tag := ""
		if p.hazardous:
			tag = " HAZARD x%.1f" % p.hazard_multiplier
		lines.append("  P%d [%d, %d] y_top=%d %s%s" % [
			p.id, int(p.x_min), int(p.x_max), int(p.y_top), String(p.kind), tag,
		])
	var edge_count := 0
	for a: int in edges_by_from.keys():
		for e: Edge in edges_by_from[a]:
			edge_count += 1
			lines.append("  E P%d -> P%d %s%s launch=%d land=%d dy=%d cost=%.1f%s" % [
				e.from_id, e.to_id, String(e.type),
				(":" + String(e.method)) if e.method != &"" else "",
				int(e.launch_x), int(e.land_x), int(e.dy),
				e.edge_cost(1.0), " BLOCKED" if e.blocked else "",
			])
	lines.append("  edges total: %d" % edge_count)
	return "\n".join(lines)