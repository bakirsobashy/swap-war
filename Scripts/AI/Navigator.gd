class_name Navigator
extends RefCounted

var owner = null
var _jump_timer: float = 0.0


func _init(ai_controller) -> void:
	owner = ai_controller


## Decrement internal timers.
func update(delta: float) -> void:
	if _jump_timer > 0.0:
		_jump_timer -= delta


## Returns a Dictionary with move_direction (-1..1), wants_jump (bool), wants_drop (bool).
func navigate_to(target: Vector2) -> Dictionary:
	var result := {"move_direction": 0.0, "wants_jump": false, "wants_drop": false}

	if not owner.actor:
		return result

	var pos: Vector2 = owner.actor.global_position
	var dir: float = sign(target.x - pos.x)
	var dy: float = target.y - pos.y
	var same_layer: bool = abs(dy) <= owner.layer_height_threshold

	if dir == 0.0:
		return result

	# Horizontal movement.
	result.move_direction = dir

	# Match facing to movement while navigating.
	if "facing_direction" in owner.actor:
		owner.actor.facing_direction = dir

	var can_jump: bool = _jump_timer <= 0.0 and owner.sensors.is_grounded

	# Wall in front while target is above: jump up/over.
	if can_jump and owner.sensors.wall_ahead and dy < -owner.jump_height_threshold:
		result.wants_jump = true

	# Gap in front while target is on the other side: jump across.
	if can_jump and owner.sensors.gap_ahead and same_layer:
		result.wants_jump = true

	# Target is above and a platform is reachable: jump toward it.
	if can_jump and dy < -owner.jump_height_threshold and owner.sensors.platform_above:
		result.wants_jump = true

	# Target is significantly below and there is ground below: drop through.
	if dy > owner.drop_height_threshold and owner.sensors.platform_below and owner.sensors.is_grounded:
		result.wants_drop = true

	if result.wants_jump:
		_jump_timer = owner.jump_cooldown

	return result
