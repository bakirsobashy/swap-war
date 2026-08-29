class_name Chest
extends Node2D

## Seconds between chest weapon spawns.
@export var spawn_interval: float = 12.0

## Vertical offset from the chest where the weapon appears.
@export var spawn_offset: Vector2 = Vector2(0, -40)

@onready var _spawner: Node = null
@onready var _timer: float = spawn_interval


func _ready() -> void:
	_spawner = get_node_or_null("/root/WeaponSpawner")
	if _spawner == null:
		# Fall back to finding a spawner sibling in the current scene.
		var root := get_tree().current_scene
		if root:
			_spawner = root.get_node_or_null("WeaponSpawner")


func _process(delta: float) -> void:
	if _spawner == null or not _spawner.has_method("spawn_weapon"):
		return

	_timer -= delta
	if _timer <= 0.0:
		_timer = spawn_interval
		_spawn_weapon()


func _spawn_weapon() -> void:
	if _spawner == null or not _spawner.has_method("spawn_weapon"):
		return
	_spawner.spawn_weapon(global_position + spawn_offset)
