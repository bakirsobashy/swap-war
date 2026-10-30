class_name Spear
extends MeleeWeapon


func _init() -> void:
	weapon_name = "Spear"


func _current_follow_offset() -> Vector2:
	var base := _data.follow_offset if _data != null else Vector2(24.0, -4.0)
	if _is_attacking:
		base += Vector2(_swing_thrust(), 0.0)
	return base


func _swing_thrust() -> float:
	return _data.attack_thrust_distance if _data != null else 0.0
