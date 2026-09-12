extends RigidBody2D

const WeaponBase = preload("res://Scripts/Weapons/WeaponBase.gd")

@export var run_force: float = 1200.0
@export var max_run_speed: float = 300.0
@export var jump_impulse: float = 450.0
@export var air_force_multiplier: float = 0.4
@export var ground_friction: float = 0.88
@export var air_friction: float = 0.98
@export var is_player: bool = false

@export var socket_rotate_speed: float = 4.0
@export var socket_radius: float = 6.0

var _is_grounded: bool = false
var facing_direction: float = 1.0
var aim_direction: Vector2 = Vector2.RIGHT

@onready var ground_check: RayCast2D = $GroundCheck
@onready var visual_body: Node2D = $VisualBody
@onready var weapon_socket: Node2D = $WeaponSocket
@onready var _ai_controller: Node = get_node_or_null("AIController")
@onready var _weapon_holder: Node = get_node_or_null("WeaponHolder")

const ONE_WAY_LAYER: int = 3
const DROP_DURATION: float = 0.3

var _drop_timer: float = 0.0

func _ready() -> void:
	add_to_group("actors")

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	_update_ground_state(state)
	_apply_run_force(state)
	_apply_jump(state)
	_apply_friction(state)
	_cap_speeds(state)
	_update_facing(state)
	_update_attack()

func _process(delta: float) -> void:
	_update_aim(delta)
	_update_socket(delta)
	_update_visuals()
	_update_drop_timer(delta)

func _update_ground_state(state: PhysicsDirectBodyState2D) -> void:
	_is_grounded = _check_grounded_by_contacts(state)

func _check_grounded_by_contacts(state: PhysicsDirectBodyState2D) -> bool:
	# Use the passed physics body state so this is safe inside _integrate_forces.
	var up := Vector2.UP
	for i in range(state.get_contact_count()):
		var local_normal := state.get_contact_local_normal(i)
		# If a collision normal points upward relative to the actor, we are standing on something.
		if local_normal.dot(up) > 0.3:
			return true
	return false


## Public read-only accessor so other systems (like the AI) can check grounded state.
func is_grounded() -> bool:
	return _is_grounded

func _get_move_input() -> float:
	if is_player:
		return Input.get_axis("Move_Left", "Move_Right")
	if _ai_controller and "move_direction" in _ai_controller:
		return _ai_controller.move_direction
	return 0.0

func _get_jump_input() -> bool:
	if is_player:
		return Input.is_action_just_pressed("Jump")
	if _ai_controller and "wants_jump" in _ai_controller:
		return _ai_controller.wants_jump
	return false

func _wants_drop_through() -> bool:
	if is_player:
		return Input.is_action_pressed("Move_Down")
	if _ai_controller and "wants_drop" in _ai_controller:
		return _ai_controller.wants_drop
	return false

func _is_on_one_way_slope() -> bool:
	# Detect if we're standing on anything via contacts; one-way slopes use layer 3.
	return _is_grounded

func _start_drop_through() -> void:
	_drop_timer = DROP_DURATION
	set_collision_mask_value(ONE_WAY_LAYER, false)

func _update_drop_timer(delta: float) -> void:
	if _drop_timer > 0.0:
		_drop_timer -= delta
		if _drop_timer <= 0.0:
			_drop_timer = 0.0
			set_collision_mask_value(ONE_WAY_LAYER, true)

func _get_attack_input() -> bool:
	if is_player:
		return Input.is_action_just_pressed("Attack")
	if _ai_controller and "wants_attack" in _ai_controller:
		return _ai_controller.wants_attack
	return false

func _apply_run_force(state: PhysicsDirectBodyState2D) -> void:
	var input_x := _get_move_input()
	if input_x == 0.0:
		return

	var force := input_x * run_force
	if not _is_grounded:
		force *= air_force_multiplier

	state.apply_force(Vector2(force, 0.0))

func _update_facing(state: PhysicsDirectBodyState2D) -> void:
	if is_player:
		return

	var input_x := _get_move_input()
	if input_x != 0.0:
		facing_direction = input_x
	elif abs(state.linear_velocity.x) > 10.0:
		facing_direction = sign(state.linear_velocity.x)

func _update_aim(delta: float) -> void:
	var target_aim := _get_target_aim()
	if target_aim.is_zero_approx():
		target_aim = Vector2(facing_direction, 0.0)

	# For player, flip facing based on mouse x position.
	if is_player:
		facing_direction = sign(target_aim.x)
		if facing_direction == 0.0:
			facing_direction = 1.0

	# Smooth AI gun aim so the weapon turns toward the target gradually.
	if not is_player and _is_holding_ranged_weapon():
		aim_direction = aim_direction.slerp(target_aim.normalized(), 5.0 * delta)
	else:
		aim_direction = target_aim.normalized()


func _is_holding_ranged_weapon() -> bool:
	if not _weapon_holder:
		return false
	var weapon: WeaponBase = _weapon_holder.current_weapon
	if not weapon:
		return false
	return weapon.is_ranged()

func _get_target_aim() -> Vector2:
	if is_player:
		var mouse_pos := get_global_mouse_position()
		return mouse_pos - global_position

	if _ai_controller and "aim_direction" in _ai_controller:
		return _ai_controller.aim_direction

	return Vector2(facing_direction, 0.0)

func _update_socket(delta: float) -> void:
	if not weapon_socket:
		return

	var target_angle := atan2(aim_direction.y, aim_direction.x)
	var current_angle := atan2(weapon_socket.position.y, weapon_socket.position.x)
	var next_angle := lerp_angle(current_angle, target_angle, socket_rotate_speed * delta)

	weapon_socket.position = Vector2(cos(next_angle), sin(next_angle)) * socket_radius
	weapon_socket.rotation = next_angle

func _update_visuals() -> void:
	$VisualBody/Sprite2D.flip_h = facing_direction < 0.0

func _apply_jump(state: PhysicsDirectBodyState2D) -> void:
	var was_grounded := _is_grounded

	if _wants_drop_through() and _is_grounded and _is_on_one_way_slope():
		_start_drop_through()
		return

	if _get_jump_input() and _is_grounded:
		state.apply_central_impulse(Vector2(0.0, -jump_impulse))
		_is_grounded = false
		if AudioManager:
			AudioManager.play_jump()
	elif not was_grounded and _is_grounded:
		if AudioManager:
			AudioManager.play_land()

func _update_attack() -> void:
	if not _weapon_holder:
		return
	if not _weapon_holder.is_holding_weapon():
		return
	if not _get_attack_input():
		return
	var weapon := _weapon_holder.current_weapon as WeaponBase
	if weapon:
		weapon.attack()
		if AudioManager:
			AudioManager.play_attack()

func _apply_friction(state: PhysicsDirectBodyState2D) -> void:
	var input_x := _get_move_input()
	if input_x != 0.0:
		return

	var vel := state.linear_velocity
	var friction := ground_friction if _is_grounded else air_friction
	vel.x *= friction
	state.linear_velocity = vel

func _cap_speeds(state: PhysicsDirectBodyState2D) -> void:
	var vel := state.linear_velocity
	if abs(vel.x) > max_run_speed:
		vel.x = sign(vel.x) * max_run_speed
		state.linear_velocity = vel
