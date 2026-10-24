class_name Projectile
extends Area2D

var _data: WeaponData = null
var _source: Node = null
var _velocity: Vector2 = Vector2.ZERO
var _life_timer: float = 0.0

@onready var _sprite: Sprite2D = $Sprite2D


func start(pos: Vector2, dir: Vector2, data: WeaponData, source: Node) -> void:
	global_position = pos
	_data = data
	_source = source
	_velocity = dir.normalized() * data.projectile_speed
	_life_timer = data.projectile_lifetime
	rotation = dir.angle()


func _ready() -> void:
	add_to_group("projectiles")   # ArenaManager clears these on Play Again
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	position += _velocity * delta
	_life_timer -= delta
	if _life_timer <= 0.0:
		queue_free()


func _on_body_entered(body: Node) -> void:
	# The shooter can be freed mid-flight (Play Again despawns actors); a
	# freed source can't be team-checked or credited, so the shot just ends.
	if not is_instance_valid(_source):
		queue_free()
		return
	if body == _source:
		return

	# Collide with teammates but do not damage them.
	if TeamMember.is_same_team(_source, body):
		return

	# Any non-teammate impact (actor or wall) gets impact feedback.
	if AudioManager:
		AudioManager.play_hit()

	var health := body.get_node_or_null("Components/Health") as Health
	if health:
		var final_damage := _data.damage
		var is_critical := randf() < _data.critical_chance
		if is_critical:
			final_damage *= 1.5
		if health.take_damage(final_damage, _source):
			_apply_knockback(body)

	queue_free()


func _apply_knockback(body: Node) -> void:
	var other_body := body as RigidBody2D
	if not other_body:
		return
	var dir := _velocity.normalized()
	if other_body.has_method("apply_knockback"):
		other_body.apply_knockback(dir * _data.knockback)
	else:
		other_body.apply_central_impulse(dir * _data.knockback)
