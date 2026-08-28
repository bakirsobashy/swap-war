class_name Weapon
extends RigidBody2D

@export var damage: float = 25.0
@export var knockback: float = 400.0
@export var cooldown_per_actor: float = 0.5
@export var follow_offset: Vector2 = Vector2(24.0, -4.0)
@export var throw_velocity_multiplier: float = 0.5
@export var attack_cooldown: float = 0.5
@export var attack_thrust_distance: float = 32.0
@export var attack_thrust_duration: float = 0.15

var _holder: RigidBody2D = null
var _socket: Node2D = null
var _recent_hits: Dictionary = {}
var _target_facing: float = 1.0
var _attack_timer: float = 0.0
var _attack_cooldown_timer: float = 0.0
var _is_attacking: bool = false

func _ready() -> void:
	add_to_group("weapons")
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)

	var hit_box := get_node_or_null("HitBox") as Area2D
	if hit_box:
		hit_box.body_entered.connect(_on_body_entered)

func pick_up(holder: RigidBody2D, socket: Node2D) -> void:
	if _holder != null:
		return

	_holder = holder
	_socket = socket
	_target_facing = _get_holder_facing()

	add_collision_exception_with(holder)

	gravity_scale = 0.0
	set_deferred("freeze_mode", RigidBody2D.FREEZE_MODE_KINEMATIC)
	set_deferred("freeze", true)
	set_deferred("lock_rotation", false)

	_update_follow_transform()

func drop() -> void:
	if _holder:
		remove_collision_exception_with(_holder)

	var throw_velocity := Vector2.ZERO
	if _holder:
		throw_velocity = _holder.linear_velocity * throw_velocity_multiplier
		throw_velocity += Vector2(_target_facing * 100.0, -80.0)

	_holder = null
	_socket = null
	gravity_scale = 1.0
	set_deferred("freeze", false)
	set_deferred("lock_rotation", true)

	set_deferred("linear_velocity", throw_velocity)
	set_deferred("angular_velocity", _target_facing * -2.0)

func attack() -> void:
	if not _holder:
		return
	if _attack_cooldown_timer > 0.0:
		return
	_attack_cooldown_timer = attack_cooldown
	_attack_timer = attack_thrust_duration
	_is_attacking = true

func is_attacking() -> bool:
	return _is_attacking

func is_held() -> bool:
	return _holder != null

func get_hand_socket() -> Node2D:
	return get_node_or_null("SwordVisuals/HandSocket")

func set_facing(facing: float) -> void:
	_target_facing = sign(facing)
	if _target_facing == 0.0:
		_target_facing = 1.0

func _physics_process(delta: float) -> void:
	if not _holder:
		return
	if _attack_cooldown_timer > 0.0:
		_attack_cooldown_timer -= delta
	if _attack_timer > 0.0:
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			_is_attacking = false
	_update_follow_transform()

func _current_follow_offset() -> Vector2:
	var base := follow_offset
	if _is_attacking:
		base += Vector2(attack_thrust_distance, 0.0)
	return base

func _update_follow_transform() -> void:
	if not _holder or not _socket:
		return

	var socket_pos := _socket.global_position
	var socket_rot := _socket.global_rotation

	# Anchor the sword so its hand socket sits on the actor's weapon socket.
	var hand_socket := get_hand_socket()
	var hand_offset := Vector2.ZERO
	if hand_socket:
		hand_offset = -hand_socket.position.rotated(_local_weapon_rotation())

	var offset := _current_follow_offset().rotated(socket_rot)
	var target_pos := socket_pos + offset + hand_offset.rotated(socket_rot)

	global_position = target_pos
	global_rotation = socket_rot + _local_weapon_rotation()

func _local_weapon_rotation() -> float:
	# The sword sprite points up in its texture; rotate it to point along the socket forward.
	return deg_to_rad(90.0)

func _get_holder_facing() -> float:
	if "facing_direction" in _holder:
		return sign(_holder.facing_direction)
	return sign(_holder.linear_velocity.x) if abs(_holder.linear_velocity.x) > 10.0 else 1.0

func _get_holder_aim() -> Vector2:
	if _holder and "aim_direction" in _holder:
		return _holder.aim_direction
	return Vector2(_target_facing, 0.0)

func _on_body_entered(body: Node) -> void:
	if not _holder:
		return
	if body == _holder:
		return

	var health = body.get_node_or_null("Components/Health")
	if not health:
		return

	if _is_on_same_team(body):
		return

	var now := Time.get_ticks_msec() / 1000.0
	var last_hit: float = _recent_hits.get(body, -cooldown_per_actor - 1.0)
	if now - last_hit < cooldown_per_actor:
		return
	_recent_hits[body] = now

	health.take_damage(damage, _holder)
	_apply_knockback(body)
	if AudioManager:
		AudioManager.play_hit()

func _is_on_same_team(body: Node) -> bool:
	return TeamMember.is_same_team(_holder, body)

func _apply_knockback(body: Node) -> void:
	var other_body := body as RigidBody2D
	if not other_body:
		return

	var dir := linear_velocity.normalized()
	if dir.is_zero_approx():
		dir = (body.global_position - global_position).normalized()

	other_body.apply_central_impulse(dir * knockback)
