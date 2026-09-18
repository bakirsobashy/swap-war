class_name ArenaDatabase
extends RefCounted

## Static registry of playable arenas. Display names are shown in the MainMenu
## selector; scene paths are loaded when the match starts.

const DEFAULT_PATH := "res://Scenes/Arenas/ArenaFlat.tscn"

const ARENAS: Array[Dictionary] = [
	{
		"id": "flat",
		"name": "Flat Arena",
		"path": "res://Scenes/Arenas/ArenaFlat.tscn",
	},
	{
		"id": "pit",
		"name": "Pit Arena",
		"path": "res://Scenes/Arenas/ArenaPit.tscn",
	},
	{
		"id": "hazards",
		"name": "Hazard Arena",
		"path": "res://Scenes/Arenas/ArenaHazards.tscn",
	},
]


static func get_arena_names() -> Array[String]:
	var names: Array[String] = []
	for entry in ARENAS:
		names.append(entry["name"])
	return names


static func get_arena_path(name: String) -> String:
	for entry in ARENAS:
		if entry["name"] == name:
			return entry["path"]
	return DEFAULT_PATH


static func get_arena_path_by_index(index: int) -> String:
	if index < 0 or index >= ARENAS.size():
		return DEFAULT_PATH
	return ARENAS[index]["path"]


static func get_default_index() -> int:
	return 0
