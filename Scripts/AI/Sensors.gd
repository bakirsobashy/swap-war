class_name Sensors
extends RefCounted

const UNREACHABLE_TIMEOUT: float = 1.5

var owner = null

var nearest_enemy: Node2D = null
var nearest_weapon: WeaponBase = null
var aim_direction: Vector2 = Vector2.RIGHT
var is_grounded: bool = false
var wall_ahead: bool = false
var gap_ahead: bool = false
var platform_above: bool = false
var platform_below: bool = false

var _reaction_timer: float = 0.0
var _target_switch_timer: float = 0.0
var _unreachable_timer: float = 0.0


func _init(ai_controller) -> void:
	owner = ai_controller


## Reset all timers and targets. Called on team change, respawn, etc.
func invalidate_targets() -> void:
	nearest_enemy = null
	nearest_weapon = null
	_reaction_timer = 0.0
	_target_switch_timer = 0.0
	_unreachable_timer = 0.0


## Main update: perception + environment sensing.
func update(delta: float) -> void:
	_reaction_timer -= delta
	_target_switch_timer -= delta

	if _reaction_timer <= 0.0:
		refresh_targets()
		_reaction_timer = owner.reaction_time

	_update_aim()
	_update_ground_state()
	_update_navigation_rays()
	_track_unreachable(delta)


## Refresh weapon and enemy targets. Weapons are always nearest straight-line.
## Enemies are sticky: only switch when allowed by the cooldown or current target invalid.
func refresh_targets() -> void:
	nearest_weapon = _find_nearest_weapon()

	if not _is_valid_target(nearest_enemy) or _target_switch_timer <= 0.0:
		var candidate := _find_nearest_enemy()
		if candidate != nearest_enemy:
			nearest_enemy = candidate
			_target_switch_timer = owner.target_switch_cooldown
			_unreachable_timer = 0.0


func _find_nearest_enemy() -> Node2D:
	var best: Node2D = null
	var best_dist: float = owner.detection_radius

	for a in owner.actor.get_tree().get_nodes_in_group("actors"):
		var other := a as Node2D
		if not other or other == owner.actor:
			continue
		if not _is_valid_target(other):
			continue

		var d: float = owner.actor.global_position.distance_to(other.global_position)
		if d < best_dist:
			best_dist = d
			best = other

	return best


func _find_nearest_weapon() -> WeaponBase:
	var best: WeaponBase = null
	var best_dist: float = owner.weapon_seek_radius

	for w in owner.actor.get_tree().get_nodes_in_group("weapons"):
		var weapon := w as WeaponBase
		if not weapon:
			continue
		if not is_instance_valid(weapon):
			continue
		if weapon.is_held():
			continue

		var d: float = owner.actor.global_position.distance_to(weapon.global_position)

		# Prefer ranged weapons at equal distance.
		if weapon.is_ranged() and is_equal_approx(d, best_dist):
			best = weapon
		elif d < best_dist:
			best_dist = d
			best = weapon

	return best


func _is_valid_target(other: Node) -> bool:
	if not is_instance_valid(other):
		return false

	var health := other.get_node_or_null("Components/Health") as Health
	if health and health._is_dead:
		return false

	return not TeamMember.is_same_team(owner.actor, other)


## Public wrapper so states can validate a target without knowing internals.
func is_valid_target(other: Node) -> bool:
	return _is_valid_target(other)


func _track_unreachable(delta: float) -> void:
	if not nearest_enemy:
		_unreachable_timer = 0.0
		return

	var dy: float = nearest_enemy.global_position.y - owner.actor.global_position.y
	if abs(dy) > owner.layer_height_threshold:
		_unreachable_timer += delta
	else:
		_unreachable_timer = 0.0


func is_target_unreachable() -> bool:
	return _unreachable_timer > UNREACHABLE_TIMEOUT


func reset_unreachable() -> void:
	_unreachable_timer = 0.0


## Aim toward the nearest enemy if present, otherwise forward.
func _update_aim() -> void:
	var facing: float = _get_actor_facing()
	if nearest_enemy and is_instance_valid(nearest_enemy):
		var to_target: Vector2 = nearest_enemy.global_position - owner.actor.global_position
		if to_target.length_squared() > 1.0:
			aim_direction = to_target.normalized()
		else:
			aim_direction = Vector2(facing, 0.0)
	else:
		aim_direction = Vector2(facing, 0.0)


func _get_actor_facing() -> float:
	var a: Node = owner.actor
	if "facing_direction" in a:
		return sign(a.facing_direction)
	if abs(a.linear_velocity.x) > 10.0:
		return sign(a.linear_velocity.x)
	return 1.0


## Mirror the actor's contact-normal ground check.
func _update_ground_state() -> void:
	var state := PhysicsServer2D.body_get_direct_state(owner.actor.get_rid())
	if not state:
		is_grounded = false
		return

	var up := Vector2.UP
	is_grounded = false
	for i in range(state.get_contact_count()):
		if state.get_contact_local_normal(i).dot(up) > 0.3:
			is_grounded = true
			return


## Cast short rays in front and below the actor to detect walls, gaps, and platforms.
func _update_navigation_rays() -> void:
	var space: PhysicsDirectSpaceState2D = owner.actor.get_world_2d().direct_space_state
	var pos: Vector2 = owner.actor.global_position
	var dir: float = _get_actor_facing()
	var radius: float = 19.0
	var collision_mask: int = 1 | 4  # world (layer 1) + one-way platforms (layer 3)

	# Wall ahead.
	var wall_origin: Vector2 = pos + Vector2(dir * radius, 0)
	var wall_params := PhysicsRayQueryParameters2D.create(
		wall_origin,
		wall_origin + Vector2(dir * owner.wall_check_distance, 0),
		collision_mask
	)
	wall_ahead = not space.intersect_ray(wall_params).is_empty()

	# Gap ahead.
	var gap_origin: Vector2 = pos + Vector2(dir * (radius + 8.0), 0)
	var gap_params := PhysicsRayQueryParameters2D.create(
		gap_origin,
		gap_origin + Vector2(0, owner.edge_check_depth),
		collision_mask
	)
	gap_ahead = space.intersect_ray(gap_params).is_empty()

	# Platform above.
	var up_origin: Vector2 = pos + Vector2(dir * 8.0, -radius)
	var up_params := PhysicsRayQueryParameters2D.create(
		up_origin,
		up_origin + Vector2(dir * 40.0, -120.0),
		collision_mask
	)
	platform_above = not space.intersect_ray(up_params).is_empty()

	# Platform below.
	var down_params := PhysicsRayQueryParameters2D.create(
		pos,
		pos + Vector2(0, 200),
		collision_mask
	)
	platform_below = not space.intersect_ray(down_params).is_empty()
