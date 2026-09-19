class_name NavBaker
extends RefCounted

## Extracts a NavGraph from an instantiated arena scene.
##
## One graph per arena instance, cached on the scene node's meta by
## `get_cached` (the meta holds a strong reference, so the graph lives exactly
## as long as the arena node — freed arena, freed graph, next arena rebakes).
##
## Everything is derived from the painted tiles at runtime: cell
## classification, bounds from the boundary walls, the kill rect via world
## transforms, hazards from the "hazards" group, and nav override markers from
## the "nav_overrides" group. Repaint the arena and the graph follows — no
## waypoint re-authoring.
##
## Compile-safety: references NavGraph through a preload path, never through
## its class_name, so headless `-s` probes can load this file directly.

const NavGraphScript := preload("res://Scripts/AI/NavGraph.gd")

const HAZARD_GROUP := "hazards"
const OVERRIDE_GROUP := "nav_overrides"
const NO_BOUNDS := 1000000.0

## Minimum fraction of walkable surface cells that must lie on a tall shape's
## inner side for it to count as a boundary wall (see the side-wall guard).
const SIDE_WALL_SURFACE_FRAC := 0.75

## Graph for this scene instance — bakes on first call, then cached.
static func get_cached(scene: Node) -> RefCounted:
	if scene == null:
		return null
	if scene.has_meta("nav_graph"):
		var cached = scene.get_meta("nav_graph")
		if cached != null:
			return cached
	var graph := bake(scene)
	scene.set_meta("nav_graph", graph)
	return graph

## Fresh graph from the scene's current state. Cheap enough to call per probe.
static func bake(scene: Node) -> RefCounted:
	var graph: RefCounted = NavGraphScript.new()
	var layer: TileMapLayer = scene.get_node_or_null("World/TileMapLayer")
	if layer == null or layer.tile_set == null:
		return graph                    # empty graph — states fall back to steering

	# 1. Cells: solid = polygons on physics layer 0, one-way = layer 1.
	#    Walkable surface cells (nothing solid directly above) feed the
	#    boundary-wall guard in step 2.
	var solids: Dictionary = {}
	var one_ways: Dictionary = {}
	for cell: Vector2i in layer.get_used_cells():
		var td: TileData = layer.get_cell_tile_data(cell)
		if td == null:
			continue
		if td.get_collision_polygons_count(0) > 0:
			solids[cell] = true
		elif td.get_collision_polygons_count(1) > 0:
			one_ways[cell] = _one_way_ascend(td)

	var ts_x := float(layer.tile_set.tile_size.x)
	var surface_lefts: PackedFloat32Array = []
	for cell: Vector2i in solids.keys():
		if not solids.has(cell + Vector2i(0, -1)):
			surface_lefts.append(float(cell.x) * ts_x)
	for cell: Vector2i in one_ways.keys():
		if not solids.has(cell + Vector2i(0, -1)):
			surface_lefts.append(float(cell.x) * ts_x)

	# 2. Bounds: tall boundary shapes are walls; clip to their inner faces.
	#    The wall CollisionShape2Ds are DIRECT children of the StaticBody2D in
	#    every current arena, but nested bodies are also collected so a
	#    repainted arena works either way.
	var min_x := -NO_BOUNDS
	var max_x := NO_BOUNDS
	var bounds := scene.get_node_or_null("World/Boundaries")
	if bounds != null:
		var wall_shapes: Array = []
		for ch in bounds.get_children():
			if ch is CollisionShape2D:
				wall_shapes.append(ch)
			else:
				for gc in ch.get_children():
					if gc is CollisionShape2D:
						wall_shapes.append(gc)
		for cs in wall_shapes:
			if not (cs.shape is RectangleShape2D):
				continue
			var r := shape_world_rect(cs)
			if r.size.y <= r.size.x:
				continue        # wide = ceiling/floor, not a wall
			# Side-wall guard: a tall shape only clips the playable interval
			# when nearly all the walkable surface lies on its inner side.
			# Real boundary walls qualify despite decorative tiles painted
			# behind them (Pit/Hazards' high ledges); an interior tall shape
			# under World/Boundaries (a future divider) sits in the middle,
			# is refused, and must NOT silently delete every platform beyond
			# it — its physics still blocks actors, the graph keeps both
			# sides, and routes degrade honestly through it.
			var keep_east := r.get_center().x < 0.0
			var face := r.position.x + r.size.x if keep_east else r.position.x
			var kept: int = 0
			for lx in surface_lefts:
				if (lx >= face) == keep_east:
					kept += 1
			if surface_lefts.size() > 0 \
					and float(kept) / float(surface_lefts.size()) < SIDE_WALL_SURFACE_FRAC:
				continue
			if keep_east:
				min_x = maxf(min_x, face)
			else:
				max_x = minf(max_x, face)

	# 3. KillZone: world rect (shapes may be scaled — Flat's is).
	var kill := Rect2(0.0, NO_BOUNDS, 0.0, 0.0)
	var kill_node := scene.get_node_or_null("KillZone")
	if kill_node != null:
		for cs in kill_node.get_children():
			if cs is CollisionShape2D and cs.shape is RectangleShape2D:
				var r := shape_world_rect(cs)
				kill = r if kill.position.y == NO_BOUNDS else kill.merge(r)

	graph.set_world_data(layer.tile_set.tile_size, solids, one_ways,
			min_x, max_x, kill)

	# 4. Hazards on scene descendants (late arrivals self-register through
	#    graph.add_hazard_rect with the same API).
	for h in scene.get_tree().get_nodes_in_group(HAZARD_GROUP):
		if h == scene or not scene.is_ancestor_of(h):
			continue
		if not h.has_method("get_nav_rect"):
			continue
		var hrect: Rect2 = h.get_nav_rect()
		if not hrect.has_area():
			continue                # no rectangle shape -> nav-invisible
		var mult := 4.0
		if "nav_cost_multiplier" in h:
			mult = float(h.nav_cost_multiplier)
		graph.add_hazard_rect(hrect, mult, false)

	# 5. Override markers under this scene.
	for m in scene.get_tree().get_nodes_in_group(OVERRIDE_GROUP):
		if m == scene or not scene.is_ancestor_of(m):
			continue
		_apply_override(graph, m)

	graph.flush()
	return graph

## World-space rect of a rectangle CollisionShape2D, honoring the global
## transform (Flat scales its KillZone shape).
static func shape_world_rect(cs: CollisionShape2D) -> Rect2:
	var shape: RectangleShape2D = cs.shape
	var rect := shape.get_rect()
	var xf := cs.global_transform
	var a: Vector2 = xf * rect.position
	var b: Vector2 = xf * (rect.position + rect.size)
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)),
			Vector2(absf(b.x - a.x), absf(b.y - a.y)))

## Ascend direction of a one-way tile's first physics-layer-1 polygon:
## -1 = the high vertex sits on the tile's west half (the surface climbs
## westward, low end east), +1 = east half (climbs eastward), 0 = the top
## edge spans both halves (a flat one-way platform tile — no low side).
## Derived from the topmost polygon vertices' x signs. NOTE the argument
## order get_collision_polygon_points(layer_id, polygon_id) — the editor docs
## reverse these; verified empirically against the stair tiles.
static func _one_way_ascend(td: TileData) -> int:
	var pts: PackedVector2Array = td.get_collision_polygon_points(1, 0)
	if pts.is_empty():
		return 0
	var top_y := pts[0].y
	for p: Vector2 in pts:
		top_y = minf(top_y, p.y)
	var west := false
	var east := false
	for p: Vector2 in pts:
		if absf(p.y - top_y) < 0.01:
			if p.x < 0.0:
				west = true
			elif p.x > 0.0:
				east = true
	if west and not east:
		return -1
	if east and not west:
		return 1
	return 0

static func _apply_override(graph: RefCounted, m: Node2D) -> void:
	if m.has_meta("block"):
		var radius := float(m.get_meta("block"))
		var type := &""
		if m.has_meta("block_type"):
			type = StringName(String(m.get_meta("block_type")))
		graph.add_block_marker(m.global_position.x, radius, type, false)
	elif m.has_meta("force_link"):
		var target: Node2D = m.get_node_or_null(NodePath(String(m.get_meta("force_link"))))
		if target == null:
			return
		var type := &""
		if m.has_meta("link_type"):
			type = StringName(String(m.get_meta("link_type")))
		var cost := -1.0
		if m.has_meta("link_cost"):
			cost = float(m.get_meta("link_cost"))
		graph.add_force_link(m.global_position, target.global_position, type, cost, false)
	elif m.has_meta("hazard_region"):
		var radius := float(m.get_meta("hazard_region"))
		var mult := 4.0
		if m.has_meta("cost_multiplier"):
			mult = float(m.get_meta("cost_multiplier"))
		var r := Rect2(m.global_position.x - radius, m.global_position.y - radius,
				radius * 2.0, radius * 2.0)
		graph.add_hazard_rect(r, mult, false)