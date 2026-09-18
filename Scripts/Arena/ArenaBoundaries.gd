class_name ArenaBoundaries
extends StaticBody2D

## Positions invisible WorldBoundaryShape2D walls around the painted TileMapLayer.
## Add this as a child of the World node, next to the TileMapLayer.

@export var tilemap_path: NodePath = ^"../TileMapLayer"
@export var margin: float = 32.0

@onready var _left: CollisionShape2D = $LeftWall
@onready var _right: CollisionShape2D = $RightWall
@onready var _top: CollisionShape2D = $TopWall

func _ready() -> void:
	_update_walls()

func _update_walls() -> void:
	var tilemap := get_node_or_null(tilemap_path) as TileMapLayer
	if not tilemap:
		push_warning("ArenaBoundaries: TileMapLayer not found at path '%s'" % tilemap_path)
		return

	var used := tilemap.get_used_rect()
	var cell_size := tilemap.tile_set.tile_size
	var half := cell_size * 0.5

	var top_left_world := tilemap.map_to_local(used.position) - half
	var bottom_right_world := tilemap.map_to_local(used.position + used.size - Vector2i(1, 1)) + half

	_left.global_position = Vector2(top_left_world.x - margin, 0.0)
	_right.global_position = Vector2(bottom_right_world.x + margin, 0.0)
	_top.global_position = Vector2(0.0, top_left_world.y - margin)
