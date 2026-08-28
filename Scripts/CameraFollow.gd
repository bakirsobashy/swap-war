extends Camera2D

@export var target_path: NodePath = "../Actors/Actor"
@export var follow_speed: float = 8.0

@onready var _target: Node2D = get_node_or_null(target_path)

func _process(delta: float) -> void:
	if not _target:
		return
	position = position.lerp(_target.position, follow_speed * delta)
