class_name AIController
extends Node

## 2.0 — decision layer on baked-graph navigation (plan step 5).
##
## Per-tick flow: respawn detect -> reset virtual inputs -> sensors ->
## state machine (states set nav goals / direct inputs) -> NavExecutor
## (overwrites move/jump/drop while a goal is active) -> hazard-escape
## override (top priority) -> publish aim + facing intent.
##
## The virtual-input surface consumed by Actor-Movement is unchanged plus one
## optional member: `facing_intent` (Actor-Movement reads it with an `in`
## guard, so the player path and probe bodies without it are unaffected).

const Sensors = preload("res://Scripts/AI/Sensors.gd")
const StateMachine = preload("res://Scripts/AI/StateMachine.gd")
const IdleState = preload("res://Scripts/AI/States/IdleState.gd")
const PatrolState = preload("res://Scripts/AI/States/PatrolState.gd")
const SeekWeaponState = preload("res://Scripts/AI/States/SeekWeaponState.gd")
const ApproachEnemyState = preload("res://Scripts/AI/States/ApproachEnemyState.gd")
const AttackState = preload("res://Scripts/AI/States/AttackState.gd")
const RetreatState = preload("res://Scripts/AI/States/RetreatState.gd")
const AIDifficultyScript = preload("res://Scripts/AI/AIDifficulty.gd")
const NavBakerScript := preload("res://Scripts/AI/NavBaker.gd")
const NavExecutorScript := preload("res://Scripts/AI/NavExecutor.gd")

## While the executor is moving toward a destination fresher than this, a
## nav_to call is a no-op — per-tick replanning would reset the executor's
## stuck/backoff ladders every tick (they need seconds of continuity to
## ever fire). 96px is the plan's "destination moved materially" threshold.
const NAV_REPLAN_DIST := 96.0

# Virtual inputs read by Actor-Movement.gd
var move_direction: float = 0.0
var wants_jump: bool = false
var wants_attack: bool = false
var wants_drop: bool = false
var aim_direction: Vector2 = Vector2.RIGHT
## Body facing the decision layer wants (Actor-Movement reads it between its
## move-input branch and the velocity fallback). 0 = no intent: the velocity
## fallback governs.
var facing_intent: float = 0.0

@export var is_ai: bool = true
## Tuning profile applied in _ready (AIDifficulty holds the table; the table
## wins over editor-set values — one source of tuning truth).
@export var difficulty: StringName = &"normal"

@export_group("Sensing")
@export var reaction_time: float = 0.25
@export var target_switch_cooldown: float = 0.5
@export var swap_reaction_time: float = 0.35
@export var aim_error_deg: float = 10.0

@export_group("Combat")
@export var attack_range: float = 80.0
@export var retreat_health_ratio: float = 0.3
@export var retreat_range: float = 120.0
@export var retreat_safe_distance: float = 250.0
@export var ai_attack_enabled: bool = true
@export var ranged_preference_bonus: float = 150.0

@export_group("Navigation")
## Baked-graph navigation kill-switch (the plan's one-window emergency
## rollback: set false and the states fall back to direct steering).
@export var nav_enabled: bool = true
@export var jump_risk_weight: float = 1.0
@export var patrol_hop_interval: float = 2.5

var actor: RigidBody2D = null
var weapon_holder: WeaponHolder = null
var health: Health = null
var team_member: TeamMember = null

var sensors: Sensors = null
var machine: StateMachine = null
var nav_executor: NavExecutorScript = null

var _nav_scene: Node = null
var _was_dead: bool = false
var _nav_plan_pos := Vector2(INF, INF)
## Seconds an armed AI must fight before it may retreat again. Set when a
## Retreat times out: nothing heals, so a low-HP AI used to flee forever.
var retreat_lockout: float = 0.0


func _ready() -> void:
	actor = get_parent() as RigidBody2D

	# Players are controlled by human input, not this controller.
	if actor and "is_player" in actor and actor.is_player:
		is_ai = false

	AIDifficultyScript.apply(self, difficulty)
	_cache_components()
	sensors = Sensors.new(self)
	machine = StateMachine.new(self)
	nav_executor = NavExecutorScript.new()
	nav_executor.setup(self, actor)
	nav_executor.set_risk_weight(jump_risk_weight)
	_register_states()
	_connect_events()

	machine.transition_to("Idle")


func _physics_process(delta: float) -> void:
	if not is_ai or not actor:
		return

	# Detect respawn: Health disables process_mode on death and restores it later.
	if _was_dead and actor.process_mode != Node.PROCESS_MODE_DISABLED:
		_was_dead = false
		sensors.invalidate_targets()
		machine.transition_to("Idle")
		_nav_plan_pos = Vector2(INF, INF)
		if nav_executor != null:
			nav_executor.on_respawn()

	if retreat_lockout > 0.0:
		retreat_lockout -= delta

	# Reset one-shot inputs each tick; states will set them.
	move_direction = 0.0
	wants_jump = false
	wants_attack = false
	wants_drop = false

	sensors.update(delta)
	machine.physics_update(delta)
	# The executor runs AFTER the decision machine and overwrites the movement
	# inputs while a nav goal is active — clean attribution, one owner.
	if nav_enabled and nav_executor != null:
		nav_executor.update(delta)

	# Hazard escape outranks every decision: standing in spikes means the
	# current plan already failed — run the graph's escape direction, keep
	# every other input silent, and make the executor re-plan from wherever
	# we end up.
	if sensors.in_hazard and sensors.hazard_escape_dir != 0.0:
		if nav_executor != null:
			nav_executor.notify_hazard()
		move_direction = sensors.hazard_escape_dir
		wants_jump = false
		wants_drop = false
		wants_attack = false

	_publish_facing()
	_publish_aim()


func _cache_components() -> void:
	weapon_holder = actor.get_node_or_null("WeaponHolder") as WeaponHolder
	health = actor.get_node_or_null("Components/Health") as Health
	team_member = actor.get_node_or_null("Components/TeamMember") as TeamMember

	if health:
		health.died.connect(_on_actor_died)


func _register_states() -> void:
	machine.register("Idle", IdleState.new())
	machine.register("Patrol", PatrolState.new())
	machine.register("SeekWeapon", SeekWeaponState.new())
	machine.register("ApproachEnemy", ApproachEnemyState.new())
	machine.register("Attack", AttackState.new())
	machine.register("Retreat", RetreatState.new())


func _connect_events() -> void:
	if TeamManager:
		TeamManager.team_changed.connect(_on_team_changed)


# --- shared blackboard helpers (states + this controller) -----------------------

func is_armed() -> bool:
	return weapon_holder != null and weapon_holder.is_holding_weapon()


## Armed low-HP retreat trigger, respecting the post-retreat lockout.
func should_retreat(dist: float) -> bool:
	return retreat_lockout <= 0.0 and health_ratio() <= retreat_health_ratio \
			and dist <= retreat_range


func health_ratio() -> float:
	if health == null or health.max_health <= 0.0:
		return 1.0
	return health.current_health / health.max_health


## Effective attack reach with the current weapon (bare attack_range while
## unarmed between picks).
func attack_reach() -> float:
	var reach := attack_range
	if weapon_holder and weapon_holder.is_holding_weapon() and weapon_holder.current_weapon:
		reach = maxf(reach, weapon_holder.current_weapon.get_attack_range())
	return reach


## Where this AI wants to STAND in a fight: melee edges in at 75% of reach,
## ranged holds 65% of the weapon's effective range (clamped — kiting room).
func combat_standoff() -> float:
	if weapon_holder and weapon_holder.is_holding_weapon() and weapon_holder.current_weapon \
			and weapon_holder.current_weapon.is_ranged():
		return clampf(weapon_holder.current_weapon.get_attack_range() * 0.65, 120.0, 400.0)
	return attack_reach() * 0.75


# --- publishing ------------------------------------------------------------------

## Facing intent: an armed AI with a live enemy always faces it — approach,
## exchange, or retreat with cover-fire (the ranged weapon render flips on
## facing, and melee keeps its eyes on the target through knockback: the old
## velocity fallback flipped facing on every hit). Unarmed states leave the
## intent 0 and the velocity fallback governs.
func _publish_facing() -> void:
	facing_intent = 0.0
	if not is_armed():
		return
	var enemy: Node2D = sensors.nearest_enemy
	if enemy == null or not sensors.is_valid_target(enemy):
		return
	var dx: float = enemy.global_position.x - actor.global_position.x
	if dx != 0.0:
		facing_intent = signf(dx)
	elif "facing_direction" in actor:
		facing_intent = signf(actor.facing_direction)


func _publish_aim() -> void:
	aim_direction = sensors.aim_direction


# --- events ----------------------------------------------------------------------

## Team swap: NO state is torn down (no flinch). The sensors forget the
## enemy NOW (it may be an ally), re-acquire after the reaction window, and
## the executor re-plans so a route toward the old enemy is re-considered.
func _on_team_changed(_teams: Dictionary) -> void:
	sensors.invalidate_enemy()
	sensors.force_refresh_after(swap_reaction_time)
	if nav_executor != null:
		nav_executor.replan_soon()


func _on_actor_died() -> void:
	_was_dead = true


# --- baked-graph navigation API (states call these) -------------------------------

## Plan a nav goal at world position `pos`. Returns &"ok" or &"no_route".
## Active-goal throttle: while the executor is already moving toward a
## fresh-enough destination this is a no-op returning &"ok". The goal
## refreshes when the destination moved >96px or the previous goal ended
## (arrived / failed / cancelled) — see NAV_REPLAN_DIST.
func nav_to(pos: Vector2) -> StringName:
	if not nav_enabled or nav_executor == null:
		return &"no_route"
	if not _ensure_nav_graph():
		return &"no_route"
	if nav_executor.status() == &"moving" \
			and pos.distance_to(_nav_plan_pos) <= NAV_REPLAN_DIST:
		return &"ok"
	var rc := nav_executor.plan_to(pos)
	if rc == &"ok":
		_nav_plan_pos = pos
	return rc


func nav_cancel() -> void:
	_nav_plan_pos = Vector2(INF, INF)
	if nav_executor != null:
		nav_executor.cancel()


func nav_arrived() -> bool:
	return nav_executor != null and nav_executor.status() == &"arrived"


func nav_failed() -> bool:
	return nav_executor != null and nav_executor.status() == &"failed"


func has_nav_graph() -> bool:
	return nav_executor != null and nav_executor.has_graph()


## The baked graph (shared per arena), for state-side platform data — Retreat
## refuge scoring, Patrol hop picking, Sensors localization. Null when no
## scene graph is available (probe mode).
func nav_graph() -> RefCounted:
	if nav_executor == null:
		return null
	if not _ensure_nav_graph():
		return null
	return nav_executor.graph()


## Graph for the current scene, baked once and cached on the scene node —
## one graph per arena, shared by every AI in it. A null current_scene (probe
## mode before wiring) just yields no graph rather than crashing.
func _ensure_nav_graph() -> bool:
	if get_tree() == null or get_tree().current_scene == null:
		return false
	var scene: Node = get_tree().current_scene
	if scene != _nav_scene or not nav_executor.has_graph():
		_nav_scene = scene
		nav_executor.set_graph(NavBakerScript.get_cached(scene))
	return nav_executor.has_graph()
