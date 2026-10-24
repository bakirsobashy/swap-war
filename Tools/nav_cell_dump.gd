extends SceneTree

## One-off ground-truth dump: every used TileMapLayer cell with its atlas
## coords and collision-polygon counts per physics layer, per arena.
## Settles exactly what the placeholder arenas paint (solid vs one-way ramps).

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for path in [
		"res://Scenes/Arenas/ArenaFlat.tscn",
		"res://Scenes/Arenas/ArenaPit.tscn",
		"res://Scenes/Arenas/ArenaHazards.tscn",
	]:
		var inst = load(path).instantiate()
		root.add_child(inst)
		await physics_frame
		var layer: TileMapLayer = inst.get_node_or_null("World/TileMapLayer")
		print("\n=== %s (ts=%s) ===" % [path.get_file(),
				layer.tile_set.tile_size if layer and layer.tile_set else "?"])
		if layer == null or layer.tile_set == null:
			print("  no tilemap")
			inst.queue_free()
			continue
		var cells = layer.get_used_cells()
		cells.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
		var kinds := {"solid": [], "one_way": [], "none": []}
		for c in cells:
			var td = layer.get_cell_tile_data(c)
			var k := "none"
			if td.get_collision_polygons_count(0) > 0:
				k = "solid"
			elif td.get_collision_polygons_count(1) > 0:
				k = "one_way"
			var atlas = layer.get_cell_atlas_coords(c)
			kinds[k].append("%s@(%d,%d)" % [c, atlas.x, atlas.y])
		for k in ["solid", "one_way", "none"]:
			if kinds[k].size() > 0:
				print("  %s (%d):" % [k, kinds[k].size()])
				print("    " + ", ".join(kinds[k]))
		# Boundary structure, to fix the bounds reader.
		var bounds = inst.get_node_or_null("World/Boundaries")
		if bounds:
			print("  Boundaries: %s" % bounds.get_class())
			for ch in bounds.get_children():
				print("    child %s (%s) pos=%s" % [ch.name, ch.get_class(), ch.global_position])
				for gc in ch.get_children():
					print("      grandchild %s (%s) pos=%s" % [gc.name, gc.get_class(), gc.global_position])
		inst.queue_free()
		await physics_frame
	quit(0)