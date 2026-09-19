extends SceneTree

## One-off ground-truth probe: which way the one-way slope triangles point
## (tile-local polygon points) + where the legacy stair waypoints sit.
## Used to derive the executor's ramp-transition behavior (plan step 4).

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var inst = load("res://Scenes/Arenas/ArenaHazards.tscn").instantiate()
	root.add_child(inst)
	await physics_frame
	var layer = inst.get_node_or_null("World/TileMapLayer")
	for cell in [Vector2i(2, 1), Vector2i(1, 0), Vector2i(0, -1)]:
		var td = layer.get_cell_tile_data(cell)
		print("cell %s atlas=%s one_way_polys=%d" % [cell,
				layer.get_cell_atlas_coords(cell), td.get_collision_polygons_count(1)])
		print("  orderA(layer,poly) pts=%s" % td.get_collision_polygon_points(1, 0))
		print("  orderB(poly,layer) pts=%s" % td.get_collision_polygon_points(0, 1))
		print("  orderA one_way=%s" % td.is_collision_polygon_one_way(1, 0))
		print("  orderB one_way=%s" % td.is_collision_polygon_one_way(0, 1))
	for cell in [Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)]:
		var tds = layer.get_cell_tile_data(cell)
		print("cell %s solid_polys=%d" % [cell, tds.get_collision_polygons_count(0)])
	var wp = inst.get_node_or_null("World/StairWaypoints")
	if wp != null:
		for c in wp.get_children():
			print("waypoint %s pos=%s" % [c.name, c.global_position])
	else:
		print("no StairWaypoints node")
	inst.queue_free()
	await physics_frame
	quit(0)