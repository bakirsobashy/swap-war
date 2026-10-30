extends SceneTree

## Renders an arena with its baked navigation graph drawn on top and saves a
## PNG. Needs a real display (not --headless):
##
##   godot --path . -s Tools/nav_graph_snapshot.gd -- res://Scenes/Arenas/ArenaHazards.tscn out.png
##
## Platforms: green = solid, blue = one-way slope/ledge, red = hazard segment.
## Edges: grey = walk, yellow = jump up / across, pink dashed = drop down.

const OVERLAY_SRC := """
extends Node2D

var graph

const C_SOLID := Color(0.216, 0.851, 0.549)
const C_ONE_WAY := Color(0.569, 0.475, 1.0)
const C_HAZARD := Color(0.988, 0.361, 0.396)
const C_WALK := Color(0.85, 0.85, 0.85, 0.9)
const C_JUMP := Color(1.0, 0.714, 0.0)
const C_DROP := Color(0.988, 0.361, 0.596)

func _arc(a: Vector2, b: Vector2, lift: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var mid := (a + b) * 0.5 + Vector2(0.0, -lift)
	for i in 21:
		var t := i / 20.0
		pts.append(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
	return pts

func _arrow(tip: Vector2, from: Vector2, col: Color) -> void:
	var d := (tip - from).normalized()
	var n := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([tip, tip - d * 14.0 + n * 7.0, tip - d * 14.0 - n * 7.0]), col)

func _draw() -> void:
	if graph == null:
		return
	for P in graph.platforms:
		var col: Color = C_HAZARD if P.hazardous else (C_ONE_WAY if P.kind == &"one_way" else C_SOLID)
		var y: float = P.y_top - 4.0
		draw_line(Vector2(P.x_min, y), Vector2(P.x_max, y), col, 8.0, true)
		draw_circle(Vector2(P.x_min, y), 6.0, col)
		draw_circle(Vector2(P.x_max, y), 6.0, col)
	for from_id in graph.edges_by_from:
		for e in graph.edges_by_from[from_id]:
			if e.type == &"walk":
				continue
			var A = graph.platforms[e.from_id]
			var B = graph.platforms[e.to_id]
			var a: Vector2 = Vector2(e.launch_x, A.y_top - 10.0)
			var b: Vector2 = Vector2(e.land_x, B.y_top - 10.0)
			if e.type == &"drop_down":
				var pts := _arc(a, b, 20.0)
				for i in range(0, pts.size() - 1, 2):
					draw_line(pts[i], pts[i + 1], C_DROP, 4.0, true)
				_arrow(pts[pts.size() - 1], pts[pts.size() - 3], C_DROP)
			else:
				var lift: float = 70.0 + absf(b.x - a.x) * 0.15
				var pts := _arc(a, b, lift)
				draw_polyline(pts, C_JUMP, 4.0, true)
				_arrow(pts[pts.size() - 1], pts[pts.size() - 3], C_JUMP)
"""

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path: String = args[0] if args.size() > 0 else "res://Scenes/Arenas/ArenaHazards.tscn"
	var out_path: String = args[1] if args.size() > 1 else "nav_graph.png"

	var inst = load(scene_path).instantiate()
	root.add_child(inst)
	for i in 10:
		await physics_frame

	var baker = load("res://Scripts/AI/NavBaker.gd")
	var graph = baker.get_cached(inst)

	var script := GDScript.new()
	script.source_code = OVERLAY_SRC
	script.reload()
	var overlay := Node2D.new()
	overlay.set_script(script)
	overlay.set("graph", graph)
	overlay.z_index = 100
	inst.add_child(overlay)

	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var err := img.save_png(out_path)
	print("nav_graph_snapshot: %d platforms -> %s (err=%d)" % [graph.platforms.size(), out_path, err])
	quit(0 if err == OK else 1)
