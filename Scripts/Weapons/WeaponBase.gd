class_name WeaponBase
extends RigidBody2D

## The fixed stats for this weapon archetype.
var _data: WeaponData = null

## Current remaining uses. For melee this is successful hits; for ranged it is magazine shots.
var current_durability: int = 0

## Archetype name used as the key into WeaponDatabase. Subclasses must set this.
var weapon_name: String = ""

var _holder: RigidBody2D = null
var _socket: Node2D = null
var _target_facing: float = 1.0

## Earliest time (msec) the weapon may be picked up again. Stamped on drop so a
## freshly dropped weapon is not instantly re-grabbed while it is still inside
## the dropper's PickupArea.
var _pickup_allowed_at_msec: int = 0

const PICKUP_DELAY_SEC := 0.5

const GROUND_MASK: int = CollisionConfig.MASK_GROUND_WEAPON  # World + Weapons: ground weapons collide with level and each other.
const HELD_MASK: int = CollisionConfig.LAYER_WORLD | CollisionConfig.LAYER_ACTORS  # World + other actors: held weapons physically shove actors (no damage — melee hits come from the HitBox during a swing). The holder is excluded via collision exception; other weapons are never touched.
const GROUND_LAYER: int = CollisionConfig.LAYER_WEAPONS  # Layer 4 (Weapons), same as the weapon scenes.
const HELD_LAYER: int = CollisionConfig.LAYER_HELD_WEAPONS  # Layer 6 (HeldWeapons)


func _ready() -> void:
	add_to_group("weapons")
	if Engine.is_editor_hint():
		return
	_data = WeaponDatabase.get_data(weapon_name)
	if _data:
		current_durability = _data.durability
	else:
		push_error("WeaponBase: no WeaponData for '%s'" % weapon_name)

	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)

	# Weapons that are not held should not physically block actors.
	if not is_held():
		collision_mask = GROUND_MASK

	WeaponSpawner.register_weapon()
	tree_exiting.connect(_on_tree_exiting)


func _on_tree_exiting() -> void:
	WeaponSpawner.unregister_weapon()


## Override in subclass.
func attack() -> void:
	push_warning("WeaponBase.attack() called on abstract weapon")


## Override in subclass.
func is_attacking() -> bool:
	return false


## Would an attack launched now hit `target`? MeleeWeapon answers it; guns
## have their own gate (AIController.ranged_shot_ready).
func can_hit(_target: Node2D) -> bool:
	return false


func is_held() -> bool:
	return _holder != null


## Drop the weapon if currently held, then remove it from the world.
## Used by the death plane / kill zone when a weapon falls off the map.
func remove_from_world() -> void:
	if _holder:
		var holder_weapon := _holder.get_node_or_null("WeaponHolder") as WeaponHolder
		if holder_weapon and holder_weapon.current_weapon == self:
			holder_weapon.drop_weapon()
	queue_free()


func is_broken() -> bool:
	return current_durability <= 0


func is_ranged() -> bool:
	return _data != null and _data.category == "ranged"


## The range at which the AI should consider itself able to attack.
## MeleeWeapon overrides it with the swing's real reach.
func get_attack_range() -> float:
	if _data == null:
		return 0.0
	if is_ranged():
		return _data.projectile_speed * _data.projectile_lifetime * 0.8
	return _data.attack_thrust_distance


func can_be_picked_up() -> bool:
	return _holder == null and Time.get_ticks_msec() >= _pickup_allowed_at_msec


func pick_up(holder: RigidBody2D, socket: Node2D) -> void:
	if _holder != null or Time.get_ticks_msec() < _pickup_allowed_at_msec:
		return

	_holder = holder
	_socket = socket
	_target_facing = _get_holder_facing()

	add_collision_exception_with(holder)
	collision_layer = HELD_LAYER
	collision_mask = HELD_MASK

	gravity_scale = 0.0
	set_deferred("freeze_mode", RigidBody2D.FREEZE_MODE_KINEMATIC)
	set_deferred("freeze", true)
	set_deferred("lock_rotation", false)

	_update_follow_transform()


func drop() -> void:
	var throw_velocity := Vector2.ZERO
	var cached_holder := _holder
	if cached_holder:
		throw_velocity = cached_holder.linear_velocity * 0.5
		throw_velocity += Vector2(_target_facing * 100.0, -80.0)

	_holder = null
	_socket = null
	# Nobody (including the dropper) may re-pick this weapon until the delay
	# passes — it is still inside the dropper's PickupArea at this moment.
	_pickup_allowed_at_msec = Time.get_ticks_msec() + int(PICKUP_DELAY_SEC * 1000.0)

	# Reset to a neutral dropped appearance so it doesn't keep the held orientation/scale.
	scale = Vector2.ONE
	rotation = randf_range(-0.2, 0.2)
	gravity_scale = 1.0

	# Return to ground layer/mask immediately so the weapon doesn't keep
	# interacting with actors or other held weapons for even one frame.
	collision_layer = GROUND_LAYER
	collision_mask = GROUND_MASK

	# Apply all physics-affecting changes together in one deferred call to avoid
	# one-frame state mixes (kinematic + gravity, frozen + velocity, etc.).
	call_deferred("_do_drop", cached_holder, throw_velocity)


func _do_drop(holder: RigidBody2D, throw_velocity: Vector2) -> void:
	if is_instance_valid(holder):
		remove_collision_exception_with(holder)

	# Pop the weapon a little away from the actor so it doesn't start overlapping.
	global_position += Vector2(_target_facing * 8.0, -4.0)

	collision_layer = GROUND_LAYER
	collision_mask = GROUND_MASK
	freeze = false
	lock_rotation = false
	linear_velocity = throw_velocity
	angular_velocity = _target_facing * -2.0


func set_facing(facing: float) -> void:
	_target_facing = sign(facing)
	if _target_facing == 0.0:
		_target_facing = 1.0


## Marker used to place the actor's held hand on the weapon.
func get_hand_socket() -> Node2D:
	return get_node_or_null("Visuals/HandSocket")


## Rest rotation of the weapon relative to the actor's weapon socket.
func _local_weapon_rotation() -> float:
	return deg_to_rad(90.0)


## Where an attack launched right now would go (the AI's fire gate reads it).
## RangedWeapon overrides it with the muzzle, which lags the holder's aim.
func get_fire_direction() -> Vector2:
	return _get_aim_direction()


## Where the weapon is currently aiming.
func _get_aim_direction() -> Vector2:
	if _holder and "aim_direction" in _holder:
		return _holder.aim_direction
	return Vector2(_target_facing, 0.0)


## Called when the weapon body physically contacts another body. No weapon
## damages through it today (melee uses its HitBox, only while swinging);
## it is the hook for thrown-weapon damage.
func _on_body_entered(_body: Node) -> void:
	pass


func _physics_process(_delta: float) -> void:
	if not _holder:
		return
	if not is_instance_valid(_holder):
		# Freed instances compare non-null in GDScript, so the check above
		# passed: the holder left the tree without dropping (match restart
		# frees armed actors mid-hold). Release before touching the freed
		# socket — otherwise this errors every tick and the weapon stays
		# "held" forever, an unpickable frozen phantom left on the field.
		call_deferred("_release_from_lost_holder")
		return
	_update_follow_transform()


## Release to normal ground state when the holder was freed without dropping.
## Health.die drops properly; this is the abrupt-free path (restart, teardown).
## Deferred from _physics_process so the physics-affecting state changes apply
## outside any physics callback — same discipline as drop()'s _do_drop.
func _release_from_lost_holder() -> void:
	_holder = null
	_socket = null
	scale = Vector2.ONE
	rotation = 0.0
	gravity_scale = 1.0
	collision_layer = GROUND_LAYER
	collision_mask = GROUND_MASK
	freeze = false
	lock_rotation = false


func _update_follow_transform() -> void:
	if not _holder or not _socket:
		return

	var socket_pos := _socket.global_position
	var socket_rot := _socket.global_rotation

	var hand_socket := get_hand_socket()
	var hand_offset := Vector2.ZERO
	if hand_socket:
		hand_offset = -hand_socket.position.rotated(_local_weapon_rotation())

	var offset := _current_follow_offset().rotated(socket_rot)
	var target_pos := socket_pos + offset + hand_offset.rotated(socket_rot)

	global_position = target_pos
	global_rotation = socket_rot + _local_weapon_rotation()

	# Only ranged weapons flip scale when facing left; melee stays unchanged.
	if self is RangedWeapon:
		scale = Vector2(1.0,_target_facing)


## Override in subclasses to add attack offsets (thrust, slash, etc.).
func _current_follow_offset() -> Vector2:
	return _data.follow_offset if _data != null else Vector2(24.0, -4.0)


func _get_holder_facing() -> float:
	if "facing_direction" in _holder:
		return sign(_holder.facing_direction)
	return sign(_holder.linear_velocity.x) if abs(_holder.linear_velocity.x) > 10.0 else 1.0


func _lose_durability(amount: int) -> void:
	current_durability -= amount
	if current_durability <= 0:
		_break_weapon()


func _break_weapon() -> void:
	# Placeholder break feedback.
	if _holder:
		var holder_weapon := _holder.get_node_or_null("WeaponHolder")
		if holder_weapon:
			holder_weapon.drop_weapon()
	queue_free()
