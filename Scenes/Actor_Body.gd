extends Node2D

@export var position_lag: float = 10.0
@export var max_visual_offset: float = 12.0
@export var rotation_lag: float = 8.0
@export var max_lean_degrees: float = 20.0
@export var lean_responsiveness: float = 0.08

@onready var _parent: RigidBody2D = get_parent() as RigidBody2D

func _physics_process(delta: float) -> void:
	_update_position_lag(delta)
	_update_rotation_lag(delta)


func _update_position_lag(delta: float) -> void:
	var parent_velocity := _parent.linear_velocity
	var target_offset := -parent_velocity * 0.03
	target_offset.x = clamp(target_offset.x, -max_visual_offset, max_visual_offset)
	target_offset.y = clamp(target_offset.y, -max_visual_offset * 0.5, max_visual_offset * 0.5)

	position = position.lerp(target_offset, position_lag * delta)


func _update_rotation_lag(delta: float) -> void:
	var parent_velocity_x := _parent.linear_velocity.x
	var target_lean := -parent_velocity_x * lean_responsiveness
	target_lean = clamp(target_lean, -max_lean_degrees, max_lean_degrees)

	var target_rotation := deg_to_rad(target_lean) 
	rotation = lerp_angle(rotation, target_rotation, rotation_lag * delta)
