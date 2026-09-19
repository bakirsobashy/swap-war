class_name Sensors
extends RefCounted

## 2.0 — full-map perception on the baked graph. Locked decisions:
##   - NO sight/seek radii: every actor and weapon on the map is known at all
##     times; distance appears only inside scores (weapon preference), never
##     as a knowledge filter (decision #11).
##   - LOS survives ONLY as a ranged-firing gate — one ray against the solid
##     world, never a knowledge gate.
##
## Environment (platform id, hazard state) comes from the baked NavGraph via
## the controller, localizing with the same tiered contract the executor
## uses, so the decision layer and the executor always agree on "which
## platform am I on". Everything degrades gracefully with no graph (probe
## mode): ids stay -1, hazard flags stay false.

const FEET_DOWN := 31.0        # capsule bottom below the body origin (executor's convention)
const NO_CELL := Vector2i(9999, 9999)

var owner = null

# --- targets (full-map scans, no radii) ----------------------------------------
var nearest_enemy: Node2D = null
## Best weapon to fetch by score (NOT nearest): distance − ranged preference
## bonus + a hazard penalty. Duck-typed WeaponBase — it may be freed between
## ticks, so consumers must is_instance_valid() before use.
var best_weapon = null
var aim_direction: Vector2 = Vector2.RIGHT

# --- environment (from the baked graph) ----------------------------------------
var current_platform_id: int = -1
var enemy_platform_id: int = -1
var weapon_platform_id: int = -1
## Body is inside a hazard rect right now (standing on the spikes). Gates the
## controller's top-priority escape override.
var in_hazard: bool = false
## ±1 toward the nearer edge of the containing hazard rect; 0 when safe.
var hazard_escape_dir: float = 0.0
## Solid-world-only ray to the enemy reaches it — a FIRE gate for ranged
## weapons ("don't shoot the wall"), never a knowledge gate.
var has_los_to_enemy: bool = false

var _reaction_timer: float = 0.0
var _target_switch_timer: float = 0.0
var _aim_error_deg: float = 0.0          # re-rolled on every target refresh


func _init(ai_controller) -> void:
	owner = ai_controller


## Full reset: respawn, fresh spawn.
func invalidate_targets() -> void:
	nearest_enemy = null
	best_weapon = null
	_reaction_timer = 0.0
	_target_switch_timer = 0.0


## Team-swap reaction window, step 1: forget the enemy NOW (it may be an
## ally); step 2 is force_refresh_after() — re-acquisition happens after the
## window, with no forced state transition anywhere.
func invalidate_enemy() -> void:
	nearest_enemy = null
	_target_switch_timer = 0.0


## Team-swap reaction window, step 2: schedule the next target refresh `sec`
## seconds out. The reaction timer IS the delay mechanism — one clock, no
## second timer to keep in sync.
func force_refresh_after(sec: float) -> void:
	_reaction_timer = maxf(sec, owner.reaction_time)


## Main update: perception + environment sensing.
func update(delta: float) -> void:
	# Cached targets can be freed between refresh cycles (weapon broke, fell
	# off the map, etc.). Clear stale references immediately so states never
	# see them.
	if best_weapon and not is_instance_valid(best_weapon):
		best_weapon = null
	if nearest_enemy and not is_instance_valid(nearest_enemy):
		nearest_enemy = null

	_reaction_timer -= delta
	_target_switch_timer -= delta

	if _reaction_timer <= 0.0:
		refresh_targets()
		_reaction_timer = owner.reaction_time

	_update_environment()
	_update_los()
	_update_aim()


## Target scans. The enemy is sticky (the switch cooldown paces churn); the
## weapon is pure score — nearest, with a ranged bonus and a hazard penalty,
## so a sword 50px away still beats a bow sitting in the spikes 40px away.
func refresh_targets() -> void:
	best_weapon = _find_best_weapon()

	if not _is_valid_target(nearest_enemy) or _target_switch_timer <= 0.0:
		var candidate := _find_nearest_enemy()
		if candidate != nearest_enemy:
			nearest_enemy = candidate
			_target_switch_timer = owner.target_switch_cooldown

	# Ranged aim scatter re-rolls per refresh — a bad roll holds fire for one
	# reaction window (the attack state gates on the aim dot), then re-rolls.
	_aim_error_deg = randf_range(-owner.aim_error_deg, owner.aim_error_deg)

	var graph = owner.nav_graph()
	if graph != null:
		if nearest_enemy != null:
			enemy_platform_id = graph.platform_below(nearest_enemy.global_position)
		if best_weapon != null:
			weapon_platform_id = graph.platform_below(best_weapon.global_position)


## Unbiased nearest enemy, map-wide (locked decisions: no player bias, no
## sight range — an enemy across the arena is as visible as one at 50px).
func _find_nearest_enemy() -> Node2D:
	var best: Node2D = null
	var best_dist: float = INF

	for a in owner.actor.get_tree().get_nodes_in_group("actors"):
		# The "actors" group also holds Health nodes (plain Node, not Node2D) —
		# the cast filter neutralizes that double-add.
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


## Best pickup by score, map-wide: distance − ranged preference bonus + a
## hazard penalty when the weapon sits inside a hazard rect (spike-diving for
## a sword is a last resort, not a tiebreak). Lowest score wins.
func _find_best_weapon() -> WeaponBase:
	var graph = owner.nav_graph()
	var best: WeaponBase = null
	var best_score: float = INF

	for w in owner.actor.get_tree().get_nodes_in_group("weapons"):
		var weapon := w as WeaponBase
		if not weapon or not is_instance_valid(weapon):
			continue
		if weapon.is_held():
			continue

		var score: float = owner.actor.global_position.distance_to(weapon.global_position)
		if weapon.is_ranged():
			score -= owner.ranged_preference_bonus
		if graph != null and graph.point_in_hazard(weapon.global_position):
			score += 300.0
		if score < best_score:
			best_score = score
			best = weapon

	return best


func _is_valid_target(other: Node) -> bool:
	if not is_instance_valid(other):
		return false

	var health := other.get_node_or_null("Components/Health") as Health
	if health and health.is_dead():
		return false

	return not TeamMember.is_same_team(owner.actor, other)


## Public wrapper so states can validate a target without knowing internals.
func is_valid_target(other: Node) -> bool:
	return _is_valid_target(other)


## Per-tick environment: which platform are we on, are we in a hazard. Same
## localization the executor uses, so the layers never disagree.
func _update_environment() -> void:
	current_platform_id = -1
	in_hazard = false
	hazard_escape_dir = 0.0

	var graph = owner.nav_graph()
	if graph == null:
		return

	# Probe with the body origin AND just above the feet: the origin (31px
	# above the surface) lands inside shallow hazard bands like the spike
	# strip's [y_top−32, y_top); the feet point catches tall rects whose band
	# starts below the origin. Either hit means "body in hazard".
	var origin: Vector2 = owner.actor.global_position
	var feet: Vector2 = origin + Vector2(0.0, FEET_DOWN - 4.0)
	current_platform_id = graph.localize(origin + Vector2(0.0, FEET_DOWN),
			bool(owner.actor.is_grounded()), _ground_cell())
	if graph.point_in_hazard(origin) or graph.point_in_hazard(feet):
		in_hazard = true
		# Escape direction from whichever point tripped: the origin sits above
		# shallow bands while the feet dip in (landing, mid-hop), so origin-only
		# would return 0 here and leave the escape override dormant while the
		# feet take spike damage.
		hazard_escape_dir = graph.hazard_escape_dir(origin)
		if hazard_escape_dir == 0.0:
			hazard_escape_dir = graph.hazard_escape_dir(feet)


## One ray, mask 1 (solid world only): weapons, actors and hazards never
## block fire, so this is purely "is there terrain in the way".
func _update_los() -> void:
	has_los_to_enemy = false
	if nearest_enemy == null or not is_instance_valid(nearest_enemy):
		return

	var from: Vector2 = owner.actor.global_position
	var to: Vector2 = nearest_enemy.global_position
	if from.distance_to(to) < 4.0:
		has_los_to_enemy = true
		return

	var params := PhysicsRayQueryParameters2D.create(from, to, 1)
	params.exclude = [owner.actor.get_rid()]
	var hit: Dictionary = owner.actor.get_world_2d().direct_space_state.intersect_ray(params)
	has_los_to_enemy = hit.is_empty()


## Aim at the enemy with the per-refresh scatter roll, else forward.
## Actor-Movement slerps the actual weapon aim onto this.
func _update_aim() -> void:
	var facing := _get_actor_facing()
	if nearest_enemy and is_instance_valid(nearest_enemy):
		var to_target: Vector2 = nearest_enemy.global_position - owner.actor.global_position
		if to_target.length_squared() > 1.0:
			aim_direction = to_target.normalized().rotated(deg_to_rad(_aim_error_deg))
			return
	aim_direction = Vector2(facing, 0.0)


func _get_actor_facing() -> float:
	var a: Node = owner.actor
	if "facing_direction" in a:
		return sign(a.facing_direction)
	if abs(a.linear_velocity.x) > 10.0:
		return sign(a.linear_velocity.x)
	return 1.0


## Ground cell from the actor's existing GroundCheck ray — the same sampling
## Actor-Movement and the NavExecutor use, zero extra physics queries.
func _ground_cell() -> Vector2i:
	var ray = owner.actor.get_node_or_null("GroundCheck")
	if ray == null or not ray.is_colliding():
		return NO_CELL
	var col = ray.get_collider()
	if col == null or not col.has_method("local_to_map"):
		return NO_CELL
	var hit: Vector2 = ray.get_collision_point()
	return col.local_to_map(col.to_local(hit))