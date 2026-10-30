class_name Sword
extends MeleeWeapon

## Whether the last slash finished above the rest angle. The next slash goes the opposite way.
var _slash_went_up_last: bool = false


func _init() -> void:
	weapon_name = "Sword"


## Override follow transform to add a 45° slash rotation during attacks.
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

	var slash_rotation := 0.0
	if _is_attacking and _data != null:
		var half_arc := deg_to_rad(_data.slash_arc_degrees) * 0.5
		var t := 1.0 - (_attack_timer / _data.attack_thrust_duration)
		t = clamp(t, 0.0, 1.0)

		# Swing one way during first half, return during second half.
		if t < 0.5:
			slash_rotation = lerp_angle(0.0, half_arc if _slash_went_up_last else -half_arc, t * 2.0)
		else:
			slash_rotation = lerp_angle(half_arc if _slash_went_up_last else -half_arc, 0.0, (t - 0.5) * 2.0)

	global_rotation = socket_rot + _local_weapon_rotation() + slash_rotation


func _attack_ended() -> void:
	_slash_went_up_last = not _slash_went_up_last
