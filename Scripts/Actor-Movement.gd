extends RigidBody2D

const WeaponBase = preload("res://Scripts/Weapons/WeaponBase.gd")

@export var run_force: float = 1200.0
@export var max_run_speed: float = 300.0
@export var jump_impulse: float = 450.0
@export var air_force_multiplier: float = 0.4
@export var ground_friction: float = 0.88
@export var air_friction: float = 0.92
@export var is_player: bool = false

@export var socket_rotate_speed: float = 4.0
@export var socket_radius: float = 6.0

var _is_grounded: bool = false
var _was_grounded: bool = false
var facing_direction: float = 1.0
var aim_direction: Vector2 = Vector2.RIGHT

@onready var ground_check: RayCast2D = $GroundCheck
@onready var weapon_socket: Node2D = $WeaponSocket
@onready var _ai_controller: Node = get_node_or_null("AIController")
@onready var _weapon_holder: Node = get_node_or_null("WeaponHolder")

const ONE_WAY_LAYER: int = 3
const DROP_DURATION: float = 0.3

## Hold the last aim-stick direction after the stick is released — a ranged
## weapon keeps its firing lane while the thumb returns to jump. Flip this
## single line to make aim fall back to facing on release instead.
const TOUCH_AIM_HOLD_ON_RELEASE: bool = true

## Auto-attack melee: swing at the nearest hostile within this center-to-
## center reach. Contact reach = socket orbit 6 + follow_offset 24 + thrust
## 32 ≈ 62 px in front, + enemy capsule r19 ≈ 81; the AI's own attack_range
## precedent is 80 (AIDifficulty). 90 adds a tick of margin — and a miss
## costs nothing (melee loses durability only on damaging hits).
const AUTO_MELEE_REACH: float = 90.0

var _drop_timer: float = 0.0

## The arena's touch controls layer, resolved lazily. Kept untyped so the
## duck-typed get_aim_stick_value() call needs no class_name dependency.
var _touch_controls = null
## Last aim direction the right stick produced (held on release when
## TOUCH_AIM_HOLD_ON_RELEASE is on). Zero until the stick is first used.
var _last_stick_aim: Vector2 = Vector2.ZERO

## Timestamps of the most recent REAL mouse and touch input. Emulated
## mouse-from-touch events are excluded (they carry the emulation device id),
## so taps on menus never register as mouse activity.
var _last_mouse_msec: int = -1
var _last_touch_msec: int = 0

func _ready() -> void:
	add_to_group("actors")

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_last_touch_msec = Time.get_ticks_msec()
	elif event is InputEventMouse and event.device != InputEvent.DEVICE_ID_EMULATION:
		_last_mouse_msec = Time.get_ticks_msec()

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	# Capture previous grounded state before this frame's ground check,
	# so landing detection can compare air -> ground across physics steps.
	_was_grounded = _is_grounded
	_update_ground_state(state)
	_apply_run_force(state)
	_apply_jump(state)
	_apply_friction(state)
	_cap_speeds(state)
	_update_facing(state)
	_update_attack()

func _physics_process(delta: float) -> void:
	_update_drop_timer(delta)

func _process(delta: float) -> void:
	_update_aim(delta)
	_update_socket(delta)
	_update_visuals()

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

func _is_on_one_way_slope(_state: PhysicsDirectBodyState2D) -> bool:
	# Use the downward ground ray to detect what the actor is standing on.
	# This is more reliable than contact colliders for TileMapLayer one-way tiles,
	# because the TileMapLayer node's own collision_layer is 0; the layer comes from
	# the TileSet physics layer assigned to the tile.
	if not ground_check or not ground_check.is_colliding():
		return false

	var collider := ground_check.get_collider()
	if collider is TileMapLayer:
		var tilemap := collider as TileMapLayer
		var hit_point := ground_check.get_collision_point()
		var local_point := tilemap.to_local(hit_point)
		var cell := tilemap.local_to_map(local_point)
		var tile_data := tilemap.get_cell_tile_data(cell)
		if tile_data:
			# Physics layer 1 in the TileSet is mapped to collision layer 4 (layer 3).
			var tile_physics_count := tile_data.get_collision_polygons_count(1)
			if tile_physics_count > 0:
				return true
	elif collider is CollisionObject2D:
		var obj := collider as CollisionObject2D
		if (obj.collision_layer & (1 << (ONE_WAY_LAYER - 1))) != 0:
			return true

	return false

func _start_drop_through(state: PhysicsDirectBodyState2D) -> void:
	_drop_timer = DROP_DURATION
	set_collision_mask_value(ONE_WAY_LAYER, false)
	# Give the body an immediate downward nudge so it separates from the
	# one-way platform within the same physics step the mask bit flips off.
	state.apply_central_impulse(Vector2(0.0, 80.0))

func _update_drop_timer(delta: float) -> void:
	if _drop_timer > 0.0:
		_drop_timer -= delta
		if _drop_timer <= 0.0:
			_drop_timer = 0.0
			set_collision_mask_value(ONE_WAY_LAYER, true)

func _get_attack_input() -> bool:
	if is_player:
		# Manual input always works, in both modes.
		if Input.is_action_just_pressed("Attack"):
			return true
		if _auto_attack_enabled() and _weapon_holder \
				and _weapon_holder.is_holding_weapon():
			var weapon := _weapon_holder.current_weapon as WeaponBase
			if weapon == null:
				return false
			if weapon.is_ranged():
				# Ranged auto-fire is touch-only (scope): fires while the aim
				# stick is deflected past its deadzone. PC ranged stays
				# mouse + click. Held-true every tick is safe — weapons
				# self-throttle their own cooldowns (the AI's held
				# wants_attack is the same pattern).
				var tc = _get_touch_controls()
				return tc != null \
					and tc.get_aim_stick_value().length_squared() > 0.0
			# Melee: auto-swing while a hostile is in reach (PC and touch).
			# Returning held-true is paced by MeleeWeapon's cooldown.
			return _find_auto_attack_target() != null
		return false
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
	elif _ai_controller and "facing_intent" in _ai_controller \
			and _ai_controller.facing_intent != 0.0:
		# The decision layer's intent outranks physics: an armed AI keeps its
		# eyes on the enemy even while knockback velocity shoves it the other
		# way (the old velocity-first fallback flipped facing on every hit).
		facing_direction = sign(_ai_controller.facing_intent)
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

func _auto_attack_enabled() -> bool:
	return SettingsManager != null and SettingsManager.auto_attack_enabled

func _is_holding_melee_weapon() -> bool:
	if not _weapon_holder:
		return false
	var weapon: WeaponBase = _weapon_holder.current_weapon
	return weapon != null and not weapon.is_ranged()

## Nearest hostile within AUTO_MELEE_REACH, for the auto-attack melee half.
## Same "actors"-group discipline as the AI's sensors: the group is
## double-added (the actor RigidBody2D AND its Health node), so the Node2D
## cast filter neutralizes the Health nodes. No LOS check — matches AI melee,
## which also swings within reach without a sight test.
func _find_auto_attack_target() -> Node2D:
	var best: Node2D = null
	var best_dist: float = AUTO_MELEE_REACH
	for a in get_tree().get_nodes_in_group("actors"):
		var other := a as Node2D
		if other == null or other == self:
			continue
		var health = other.get_node_or_null("Components/Health")
		if health == null or health.is_dead():
			continue
		if TeamMember.is_same_team(self, other):
			continue
		var d := global_position.distance_to(other.global_position)
		if d < best_dist:
			best_dist = d
			best = other
	return best

## True when the most recent pointing input was a REAL touch (emulated mouse
## carries the emulation device id and never updates _last_mouse_msec).
func _is_touch_input_recent() -> bool:
	return DisplayServer.is_touchscreen_available() \
		and _last_touch_msec >= _last_mouse_msec

## "HUD/TouchControls" resolves in every playable arena (all inherit ArenaBase
## which instances HUD; the legacy arena.tscn too). Null-safe for headless
## probes where current_scene may be null — callers guard.
func _get_touch_controls() -> Node:
	if _touch_controls != null and is_instance_valid(_touch_controls) \
			and _touch_controls.is_inside_tree():
		return _touch_controls
	_touch_controls = null
	var scene := get_tree().current_scene
	if scene != null:
		_touch_controls = scene.get_node_or_null("HUD/TouchControls")
	return _touch_controls

func _get_target_aim() -> Vector2:
	if is_player:
		# 1. Auto-attack melee lock: aim (and therefore face) at the target
		#    so the swing connects — this outranks the stick, else auto-swings
		#    would fire the wrong way while the stick is deflected.
		if _auto_attack_enabled() and _is_holding_melee_weapon():
			var auto_target := _find_auto_attack_target()
			if auto_target:
				var to_target: Vector2 = auto_target.global_position - global_position
				if to_target.length() > 0.01:
					return to_target.normalized()
		# 2. Right aim stick: deflection steers aim AND facing (facing is
		#    derived from aim in _update_aim — twin-stick play wants both).
		var tc = _get_touch_controls()
		if tc:
			var stick_value: Vector2 = tc.get_aim_stick_value()
			if stick_value.length_squared() > 0.0:
				_last_stick_aim = stick_value.normalized()
				return _last_stick_aim
			if TOUCH_AIM_HOLD_ON_RELEASE and _last_stick_aim != Vector2.ZERO \
					and _is_touch_input_recent():
				return _last_stick_aim
		# 3. Touch fallback: with no aim-stick input on a touchscreen the
		#    player aims along facing — like a classic button-driven mobile
		#    platformer (mouse-from-touch emulation is disabled during play
		#    so taps never fire the mouse-bound Attack action).
		if _is_touch_input_recent():
			return Vector2(facing_direction, 0.0)
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
	if _wants_drop_through() and _is_grounded and _is_on_one_way_slope(state):
		_start_drop_through(state)
		return

	if _get_jump_input() and _is_grounded:
		state.apply_central_impulse(Vector2(0.0, -jump_impulse))
		_is_grounded = false
		if AudioManager:
			AudioManager.play_jump()
	elif not _was_grounded and _is_grounded:
		# Landed this physics step (was in air last step, on ground now).
		if AudioManager:
			AudioManager.play_land()

func _update_attack() -> void:
	if not _weapon_holder:
		return
	if not _weapon_holder.is_holding_weapon():
		return
	if _get_drop_weapon_input():
		_weapon_holder.drop_weapon()
		return
	if not _get_attack_input():
		return
	var weapon := _weapon_holder.current_weapon as WeaponBase
	if weapon:
		# Let the weapon class play its own attack sound so melee/ranged can
		# handle cooldown checks and avoid doubling up with projectile spawn.
		weapon.attack()

func _get_drop_weapon_input() -> bool:
	if is_player:
		return Input.is_action_just_pressed("Drop_Weapon")
	return false

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
