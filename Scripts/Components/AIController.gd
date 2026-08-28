class_name AIController
extends Node

const State = preload("res://Scripts/AI/State.gd")
const Sensors = preload("res://Scripts/AI/Sensors.gd")
const Pathfinder = preload("res://Scripts/AI/Pathfinder.gd")
const Navigator = preload("res://Scripts/AI/Navigator.gd")
const StateMachine = preload("res://Scripts/AI/StateMachine.gd")
const IdleState = preload("res://Scripts/AI/States/IdleState.gd")
const SeekWeaponState = preload("res://Scripts/AI/States/SeekWeaponState.gd")
const ApproachEnemyState = preload("res://Scripts/AI/States/ApproachEnemyState.gd")
const AttackState = preload("res://Scripts/AI/States/AttackState.gd")
const RetreatState = preload("res://Scripts/AI/States/RetreatState.gd")

# Virtual inputs read by Actor-Movement.gd
var move_direction: float = 0.0
var wants_jump: bool = false
var wants_attack: bool = false
var wants_drop: bool = false
var aim_direction: Vector2 = Vector2.RIGHT

@export var is_ai: bool = true

@export_group("Sensing")
@export var detection_radius: float = 600.0
@export var weapon_seek_radius: float = 800.0
@export var reaction_time: float = 0.2
@export var target_switch_cooldown: float = 0.5

@export_group("Combat")
@export var attack_range: float = 80.0
@export var low_health_ratio: float = 0.3
@export var retreat_range: float = 120.0
@export var retreat_safe_distance: float = 250.0
@export var ai_attack_enabled: bool = true

@export_group("Navigation")
@export var layer_height_threshold: float = 50.0
@export var jump_height_threshold: float = 40.0
@export var drop_height_threshold: float = 60.0
@export var wall_check_distance: float = 24.0
@export var edge_check_depth: float = 60.0
@export var jump_cooldown: float = 0.4

var actor: RigidBody2D = null
var weapon_holder: WeaponHolder = null
var health: Health = null
var team_member: TeamMember = null

var sensors: Sensors = null
var pathfinder: Pathfinder = null
var navigator: Navigator = null
var machine: StateMachine = null

var _was_dead: bool = false


func _ready() -> void:
	actor = get_parent() as RigidBody2D

	# Players are controlled by human input, not this controller.
	if actor and "is_player" in actor and actor.is_player:
		is_ai = false

	_cache_components()
	sensors = Sensors.new(self)
	pathfinder = Pathfinder.new(self)
	navigator = Navigator.new(self)
	machine = StateMachine.new(self)
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

	# Reset one-shot inputs each tick; states will set them.
	move_direction = 0.0
	wants_jump = false
	wants_attack = false
	wants_drop = false

	sensors.update(delta)
	pathfinder.update(delta)
	navigator.update(delta)
	machine.physics_update(delta)
	_publish_aim()


func _process(delta: float) -> void:
	if not is_ai or not actor:
		return
	machine.update(delta)


func _cache_components() -> void:
	weapon_holder = actor.get_node_or_null("WeaponHolder") as WeaponHolder
	health = actor.get_node_or_null("Components/Health") as Health
	team_member = actor.get_node_or_null("Components/TeamMember") as TeamMember

	if health:
		health.died.connect(_on_actor_died)


func _register_states() -> void:
	machine.register("Idle", IdleState.new())
	machine.register("SeekWeapon", SeekWeaponState.new())
	machine.register("ApproachEnemy", ApproachEnemyState.new())
	machine.register("Attack", AttackState.new())
	machine.register("Retreat", RetreatState.new())


func _connect_events() -> void:
	if TeamManager:
		TeamManager.team_changed.connect(_on_team_changed)


func _publish_aim() -> void:
	aim_direction = sensors.aim_direction


func _on_team_changed(_teams: Dictionary) -> void:
	sensors.invalidate_targets()
	machine.transition_to("Idle")


func _on_actor_died() -> void:
	_was_dead = true
