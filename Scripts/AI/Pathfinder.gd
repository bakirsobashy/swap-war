class_name Pathfinder
extends RefCounted

## The AIController that owns this pathfinder.
var owner = null

## Extra vertical margin required before a committed stair direction flips.
## Prevents oscillation when the actor or target jitters near a layer boundary.
const DIRECTION_SWITCH_BUFFER: float = 40.0

## Distance at which the current waypoint is considered reached. When a
## waypoint is reached and the target is on the same layer, the stair plan ends
## and the AI navigates directly to the target.
const WAYPOINT_REACHED_DIST: float = 50.0

## Vertical buffer a waypoint must be cleared by before the next one is chosen.
## Keeps the actor from flip-flopping between waypoints at the same height.
const WAYPOINT_PASS_BUFFER: float = 20.0

## How close the actor must be to the stair polyline to be considered "on" it.
## When off the path, the AI heads for the stair entry waypoint instead.
const PATH_PROXIMITY: float = 80.0

var _sequence: Array = []
var _last_target: Vector2 = Vector2.ZERO
var _committed_direction: String = ""


func _init(ai_controller) -> void:
	owner = ai_controller


## Returns the immediate point the AI should walk/jump to.
##
## For same-layer targets this is the final target. For layer transitions it
## routes through the stair entry/exit waypoint pair so the AI walks the ramp
## instead of jumping over or dropping through it.
func get_move_target(final_target: Vector2) -> Vector2:
	if not owner.actor:
		return final_target

	var pos: Vector2 = owner.actor.global_position
	var dy: float = final_target.y - pos.y

	# Large target change: drop any stale stair plan.
	if final_target.distance_to(_last_target) > 100.0:
		_release_sequence()
		_committed_direction = ""
	_last_target = final_target

	# Update the committed stair direction using hysteresis so tiny vertical
	# oscillations near a layer boundary don't flip the sequence.
	_update_committed_direction(dy)

	if _committed_direction == "":
		_release_sequence()
		return final_target

	var sequence := _build_sequence(_committed_direction)
	if sequence.is_empty():
		_release_sequence()
		return final_target

	_sequence = sequence

	var target := _select_target_waypoint(pos, sequence)
	if not target:
		_release_sequence()
		return final_target

	# If we have reached the current waypoint, finish the stair plan when the
	# target is on the same layer or when this is the last waypoint (the stairs
	# cannot take us any farther in the committed direction).
	var dist_to_waypoint: float = pos.distance_to(target.global_position)
	if dist_to_waypoint <= WAYPOINT_REACHED_DIST:
		var reached_last: bool = (target == sequence[sequence.size() - 1])
		var same_layer: bool = abs(dy) <= owner.layer_height_threshold
		if same_layer or reached_last:
			_release_sequence()
			return final_target

	return target.global_position


## Hysteresis for the committed stair direction. Two thresholds prevent rapid
## flipping, and the actor's position relative to the stair exits stops it from
## committing to a direction that the stairs can no longer help with.
func _update_committed_direction(dy: float) -> void:
	var threshold: float = owner.layer_height_threshold
	var switch_margin: float = threshold + DIRECTION_SWITCH_BUFFER

	var pos: Vector2 = owner.actor.global_position if owner.actor else Vector2.ZERO
	var bottom := _find_waypoint("bottom")
	var top := _find_waypoint("top")

	var can_go_up: bool = true
	var can_go_down: bool = true
	if bottom and top:
		can_go_up = pos.y > top.global_position.y + WAYPOINT_PASS_BUFFER
		can_go_down = pos.y < bottom.global_position.y - WAYPOINT_PASS_BUFFER

	match _committed_direction:
		"":
			if dy < -switch_margin and can_go_up:
				_committed_direction = "up"
			elif dy > switch_margin and can_go_down:
				_committed_direction = "down"
		"up":
			if dy >= -threshold or not can_go_up:
				_committed_direction = ""
		"down":
			if dy <= threshold or not can_go_down:
				_committed_direction = ""


## Build the ordered list of waypoints for a full climb or descent.
## Assumes markers are named/ordered by height: Bottom < Mid < Top.
func _build_sequence(direction: String) -> Array:
	var bottom := _find_waypoint("bottom")
	var mid := _find_waypoint("mid")
	var top := _find_waypoint("top")

	# If we only have top/bottom (no mid), fall back to direct movement.
	if not bottom or not top:
		return []
	if not mid:
		if direction == "up":
			return [bottom, top]
		else:
			return [top, bottom]

	if direction == "up":
		return [bottom, mid, top]
	return [top, mid, bottom]


func _find_waypoint(level: String) -> Marker2D:
	for wp in owner.actor.get_tree().get_nodes_in_group("stair_waypoints"):
		var marker := wp as Marker2D
		if not marker:
			continue
		if marker.get_meta("target_level", "") == level:
			return marker
	return null


## Pick the waypoint the actor should head for right now.
##
## When the actor is close to the stair polyline, it targets the forward
## waypoint of the segment it is on. When far from the polyline, it heads for
## the stair entry (first waypoint) if it has not yet exited the stairs, or
## the exit (last waypoint) if it has passed it.
func _select_target_waypoint(pos: Vector2, sequence: Array) -> Marker2D:
	if sequence.is_empty():
		return null
	if sequence.size() == 1:
		return sequence[0]

	var best_seg_idx: int = -1
	var best_t: float = 0.0
	var best_dist: float = INF

	for i in range(sequence.size() - 1):
		var a: Marker2D = sequence[i]
		var b: Marker2D = sequence[i + 1]
		if not a or not b:
			continue
		var seg: Vector2 = b.global_position - a.global_position
		var to_pos: Vector2 = pos - a.global_position
		var t: float = seg.dot(to_pos) / seg.length_squared()
		var clamped_t: float = clamp(t, 0.0, 1.0)
		var closest: Vector2 = a.global_position + seg * clamped_t
		var d: float = pos.distance_to(closest)
		if d < best_dist:
			best_dist = d
			best_seg_idx = i
			best_t = t

	if best_seg_idx >= 0 and best_dist <= PATH_PROXIMITY and best_t >= 0.0 and best_t <= 1.0:
		return sequence[best_seg_idx + 1]

	# Off the stair path: head for the entry, or finish if already past the exit.
	if _is_past_last_waypoint(pos, sequence):
		return sequence[sequence.size() - 1]
	return sequence[0]


func _is_past_last_waypoint(pos: Vector2, sequence: Array) -> bool:
	if sequence.size() < 2:
		return false

	var last: Marker2D = sequence[sequence.size() - 1]
	var first: Marker2D = sequence[0]
	if not last or not first:
		return false

	var ascending: bool = first.global_position.y > last.global_position.y
	if ascending:
		return pos.y <= last.global_position.y - WAYPOINT_PASS_BUFFER
	return pos.y >= last.global_position.y + WAYPOINT_PASS_BUFFER


func _release_sequence() -> void:
	_sequence.clear()


func update(_delta: float) -> void:
	pass
