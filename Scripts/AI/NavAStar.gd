class_name NavAStar
extends RefCounted

## Stateless A* over the baked platform graph.
##
## Receives the graph duck-typed and builds results through graph.make_route(),
## so this file references no other nav class at compile time — headless probes
## can `load()` it directly and NavGraph can preload it without a cycle.
##
## Re-path triggers (team swap, destination drift, stuck timer, edge failure,
## graph revision) are executor concerns; every call here is a fresh search.
## Graphs are tiny (a handful of platforms), so the open list is a plain Array
## with a damped heuristic for guidance — never speed.
##
## `banned_edges` entries may be [from_id, to_id] pairs or the Edge object
## itself; the executor blacklists a failed edge for a few seconds.

## Cheapest route from `from_id` to `to_id`, ending at `dest_x` (clamped into
## the destination platform). Same platform -> zero-edge Route. Returns null
## when no edge chain connects the two (or either id is invalid).
static func find_route(graph, from_id: int, to_id: int, dest_x: float,
		risk_weight := 1.0, banned_edges: Array = []):
	var count: int = graph.platforms.size()
	if from_id < 0 or to_id < 0 or from_id >= count or to_id >= count:
		return null
	var target = graph.platforms[to_id]
	var target_x := clampf(dest_x, target.x_min, target.x_max)
	if from_id == to_id:
		return graph.make_route([from_id], [], target_x, to_id)

	var g: Dictionary = {}       # platform id -> best cost so far
	var f_cache: Dictionary = {} # platform id -> g + heuristic
	var parent: Dictionary = {}  # platform id -> {"id": prev id, "edge": used}
	var closed: Dictionary = {}  # platform id -> true once popped (final)
	var open: Array = [from_id]
	g[from_id] = 0.0
	f_cache[from_id] = _h(graph.platforms[from_id], target)
	while not open.is_empty():
		# Pop the lowest-f entry (stale duplicates are skipped via `closed`).
		var best_i := 0
		var best_f: float = f_cache[open[0]]
		for i in open.size():
			if f_cache[open[i]] < best_f:
				best_f = f_cache[open[i]]
				best_i = i
		var cur: int = open[best_i]
		open.remove_at(best_i)
		if closed.has(cur):
			continue
		closed[cur] = true
		if cur == to_id:
			return _build(graph, parent, from_id, to_id, target_x)
		for e in graph.edges_from(cur):
			if _is_banned(e, banned_edges):
				continue
			if closed.has(e.to_id):
				continue
			var ng: float = g[cur] + e.edge_cost(risk_weight)
			if g.has(e.to_id) and ng >= g[e.to_id]:
				continue               # not an improvement
			g[e.to_id] = ng
			parent[e.to_id] = {"id": cur, "edge": e}
			f_cache[e.to_id] = ng + _h(graph.platforms[e.to_id], target)
			open.append(e.to_id)
	return null

static func has_path(graph, from_id: int, to_id: int, risk_weight := 1.0) -> bool:
	if from_id == to_id:
		return from_id >= 0 and from_id < graph.platforms.size()
	return find_route(graph, from_id, to_id, 0.0, risk_weight) != null

## Damped interval distance: half the horizontal gap between the platforms'
## x-ranges plus a quarter of the height difference. Damped far below any real
## edge cost so it can never overestimate and mask the true cheapest route.
static func _h(a, b) -> float:
	var dx := 0.0
	if a.x_max < b.x_min:
		dx = b.x_min - a.x_max
	elif b.x_max < a.x_min:
		dx = a.x_min - b.x_max
	return dx * 0.5 + absf(a.y_top - b.y_top) * 0.25

static func _is_banned(e, banned_edges: Array) -> bool:
	for b in banned_edges:
		# Guard first: Array == Object is a runtime type error in GDScript
		# and would abort this function before the pair check below.
		if typeof(b) == TYPE_OBJECT and b == e:
			return true               # the Edge object itself
		if b is Array and b.size() >= 2 and b[0] == e.from_id and b[1] == e.to_id:
			return true               # [from_id, to_id] pair
	return false

## Walk the parent chain backwards and emit the ordered route.
static func _build(graph, parent: Dictionary, from_id: int, to_id: int,
		target_x: float):
	var ids: Array = [to_id]
	var edges: Array = []
	var cur: int = to_id
	while cur != from_id:
		var step: Dictionary = parent[cur]
		edges.push_front(step["edge"])
		cur = step["id"]
		ids.push_front(cur)
	return graph.make_route(ids, edges, target_x, to_id)