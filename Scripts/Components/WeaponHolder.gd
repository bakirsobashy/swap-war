class_name WeaponHolder
extends Node

var current_weapon: WeaponBase = null
var last_attacker: Node = null
var last_attacker_time: float = 0.0

const ATTRIBUTION_WINDOW: float = 5.0

@onready var _actor: RigidBody2D = get_parent()
@onready var _pickup_area: Area2D = _actor.get_node_or_null("PickupArea")
@onready var _socket: Node2D = _actor.get_node_or_null("WeaponSocket")
@onready var _held_hand: Sprite2D = _actor.get_node_or_null("HeldHand")

func _ready() -> void:
	if _pickup_area:
		_pickup_area.body_entered.connect(_on_pickup_body_entered)
	if _held_hand:
		_held_hand.visible = true
		_update_unarmed_hand_position(_get_actor_facing())

func _physics_process(delta: float) -> void:
	if current_weapon != null:
		current_weapon.set_facing(_get_actor_facing())

func _process(delta: float) -> void:
	if _held_hand == null:
		return

	if current_weapon == null:
		_update_unarmed_hand_position(_get_actor_facing())
		return

	var hand_socket := current_weapon.get_hand_socket()
	if not hand_socket:
		return

	_held_hand.z_index = 11
	_held_hand.global_position = hand_socket.global_position
	_held_hand.global_rotation = hand_socket.global_rotation

func _update_unarmed_hand_position(facing: float) -> void:
	if _socket == null:
		return
	# The socket already mirrors with the actor in Actor-Movement.gd.
	# Add a small outward/downward offset so the hand rests naturally at the side.
	var side_offset := Vector2(facing * 8.0, 6.0)
	_held_hand.position = _socket.position + side_offset
	_held_hand.rotation = deg_to_rad(20.0 * facing)
	_held_hand.flip_h = facing < 0.0
	_held_hand.z_index = 1

func _get_actor_facing() -> float:
	if "facing_direction" in _actor:
		return sign(_actor.facing_direction)
	return sign(_actor.linear_velocity.x) if abs(_actor.linear_velocity.x) > 10.0 else 1.0

func _on_pickup_body_entered(body: Node) -> void:
	if current_weapon != null:
		return
	if not body is WeaponBase:
		return

	var weapon := body as WeaponBase
	if weapon.is_held():
		return
	# A freshly dropped weapon is briefly unpickable so it doesn't snap right
	# back into the dropper's hands while still inside their PickupArea.
	if not weapon.can_be_picked_up():
		return

	_equip_weapon(weapon)


func _equip_weapon(weapon: WeaponBase) -> void:
	current_weapon = weapon
	weapon.pick_up(_actor, _socket)
	if AudioManager:
		AudioManager.play_pickup()


## Pick up the closest pickable weapon already overlapping the PickupArea.
## Used right after a drop: a weapon that entered the area while the actor was
## armed never re-fires body_entered, so an active scan is the only way to
## grab it. The just-dropped weapon is excluded by its fresh-drop cooldown.
func _try_pickup_nearby() -> void:
	if current_weapon != null or _pickup_area == null:
		return

	var best: WeaponBase = null
	var best_dist_sq := 0.0
	for body in _pickup_area.get_overlapping_bodies():
		if not body is WeaponBase:
			continue
		var weapon := body as WeaponBase
		if weapon.is_held() or not weapon.can_be_picked_up():
			continue
		var dist_sq := _actor.global_position.distance_squared_to(weapon.global_position)
		if best == null or dist_sq < best_dist_sq:
			best = weapon
			best_dist_sq = dist_sq

	if best:
		_equip_weapon(best)


func drop_weapon(auto_pickup := true) -> void:
	if current_weapon == null:
		return
	current_weapon.drop()
	current_weapon = null
	if AudioManager:
		AudioManager.play_drop()
	_update_unarmed_hand_position(_get_actor_facing())
	# If a different weapon is already lying at the actor's feet, grab it
	# right away instead of waiting for a body_entered that already fired.
	# Death drops pass false: a dead actor must not re-equip.
	if auto_pickup:
		_try_pickup_nearby()

func record_attacker(attacker: Node) -> void:
	if not attacker:
		return
	last_attacker = attacker
	last_attacker_time = Time.get_ticks_msec() / 1000.0

func get_last_attacker() -> Node:
	if not last_attacker:
		return null
	var now := Time.get_ticks_msec() / 1000.0
	if now - last_attacker_time > ATTRIBUTION_WINDOW:
		return null
	return last_attacker

func clear_attacker() -> void:
	last_attacker = null
	last_attacker_time = 0.0

func is_holding_weapon() -> bool:
	return current_weapon != null
