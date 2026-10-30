class_name Fork
extends MeleeWeapon


func _init() -> void:
	weapon_name = "Fork"


func _current_follow_offset() -> Vector2:
	var base := _data.follow_offset if _data != null else Vector2(24.0, -4.0)
	if _is_attacking and _data != null:
		base += Vector2(_data.attack_thrust_distance, 0.0)
	return base
