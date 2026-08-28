extends Node2D

@export var wobble_amount: float = 0.08
@export var wobble_speed: float = 12.0
@export var attack_wobble_multiplier: float = 2.0
@export var return_speed: float = 8.0

var _phase: float = 0.0
var _sprite: Sprite2D = null
var _weapon: RigidBody2D = null
var _base_rotation: float = 0.0

func _ready() -> void:
	_sprite = get_node_or_null("Sprite2D") as Sprite2D
	_weapon = get_parent() as RigidBody2D
	if _sprite:
		_base_rotation = _sprite.rotation

func _process(delta: float) -> void:
	if not _weapon or not _sprite:
		return

	var is_attacking := false
	var is_moving_fast := false
	if _weapon.has_method("is_attacking"):
		is_attacking = _weapon.is_attacking()
	is_moving_fast = abs(_weapon.linear_velocity.x) > 50.0 or is_attacking

	var target_wobble := 0.0
	if is_moving_fast:
		_phase += delta * wobble_speed
		target_wobble = sin(_phase) * wobble_amount
		if is_attacking:
			target_wobble *= attack_wobble_multiplier
	else:
		_phase = 0.0

	_sprite.rotation = lerp(_sprite.rotation, _base_rotation + target_wobble, clamp(return_speed * delta, 0.0, 1.0))
