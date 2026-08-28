class_name Health
extends Node

@export var max_health: float = 100.0

signal health_changed(current: float, max_health: float)
signal died()

var current_health: float = max_health
var _is_dead: bool = false

@onready var _actor: RigidBody2D = get_parent().get_parent()

func _ready() -> void:
	add_to_group("actors")
	current_health = max_health
	health_changed.emit(current_health, max_health)

func take_damage(amount: float, attacker: Node = null) -> void:
	if _is_dead:
		return
	current_health -= amount
	current_health = clamp(current_health, 0.0, max_health)
	health_changed.emit(current_health, max_health)
	_flash_hit()

	if attacker:
		_record_attacker(attacker)

	if current_health <= 0.0:
		die()

func _flash_hit() -> void:
	var body := _actor.get_node_or_null("VisualBody/Sprite2D") as Sprite2D
	if not body:
		return
	var original_mod := body.modulate
	body.modulate = Color.WHITE
	_actor.get_tree().create_timer(0.08).timeout.connect(func() -> void:
		if is_instance_valid(body):
			body.modulate = original_mod
	)

func _record_attacker(attacker: Node) -> void:
	var holder := _actor.get_node_or_null("WeaponHolder") as WeaponHolder
	if holder:
		holder.last_attacker = attacker

func die() -> void:
	if _is_dead:
		return
	_is_dead = true
	died.emit()

	if AudioManager:
		AudioManager.play_death()
	_spawn_death_particles()

	_actor.process_mode = Node.PROCESS_MODE_DISABLED
	_actor.visible = false
	_actor.set_deferred("collision_layer", 0)
	_actor.set_deferred("collision_mask", 0)

	var holder = _actor.get_node_or_null("WeaponHolder")
	if holder and holder.current_weapon:
		holder.drop_weapon()

	await _actor.get_tree().create_timer(1.5).timeout
	_respawn()

func _spawn_death_particles() -> void:
	var effects := _actor.get_tree().current_scene.get_node_or_null("Effects")
	if not effects:
		return
	var particles := CPUParticles2D.new()
	particles.global_position = _actor.global_position
	particles.amount = 24
	particles.lifetime = 0.5
	particles.explosiveness = 0.8
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 20.0
	particles.direction = Vector2(0, -1)
	particles.spread = 90.0
	particles.initial_velocity_min = 80.0
	particles.initial_velocity_max = 160.0
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 6.0
	particles.color = _team_color()
	effects.add_child(particles)
	particles.emitting = true
	_actor.get_tree().create_timer(particles.lifetime).timeout.connect(func() -> void:
		if is_instance_valid(particles):
			particles.queue_free()
	)

func _team_color() -> Color:
	var team_member := _actor.get_node_or_null("Components/TeamMember") as TeamMember
	if not team_member:
		return Color.WHITE
	match team_member.team_id:
		0: return Color.GREEN
		1: return Color.RED
		2: return Color.PURPLE
		3: return Color.YELLOW
		_: return Color.WHITE

func _respawn() -> void:
	var spawn_points_node = _actor.get_tree().current_scene.get_node_or_null("World/SpawnPoints")
	var spawn_points: Array[Node] = []
	if spawn_points_node:
		spawn_points = spawn_points_node.get_children().filter(func(n): return n is Marker2D)

	var chosen := Vector2.ZERO
	if spawn_points.size() > 0:
		chosen = (spawn_points.pick_random() as Marker2D).global_position

	_actor.global_position = chosen
	current_health = max_health
	_is_dead = false
	_actor.set_deferred("collision_layer", 2)
	_actor.set_deferred("collision_mask", 15)
	_actor.visible = true
	_actor.process_mode = Node.PROCESS_MODE_INHERIT
	health_changed.emit(current_health, max_health)
