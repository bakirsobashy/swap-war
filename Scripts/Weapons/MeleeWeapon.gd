class_name MeleeWeapon
extends WeaponBase

const CRITICAL_MULTIPLIER: float = 1.5

var _attack_cooldown_timer: float = 0.0
var _attack_timer: float = 0.0
var _is_attacking: bool = false
var _recent_hits: Dictionary = {}


func attack() -> void:
	if not _holder:
		return
	if is_broken():
		return
	if _attack_cooldown_timer > 0.0:
		return

	_attack_cooldown_timer = _data.attack_cooldown
	_attack_timer = _data.attack_thrust_duration
	_is_attacking = true

	if AudioManager:
		AudioManager.play_melee_attack()


func is_attacking() -> bool:
	return _is_attacking


func _physics_process(delta: float) -> void:
	if not _holder:
		return

	if _attack_cooldown_timer > 0.0:
		_attack_cooldown_timer -= delta
	if _attack_timer > 0.0:
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			_is_attacking = false
			_attack_ended()

	_update_follow_transform()


## Override in subclasses for one-shot cleanup when the attack window closes.
func _attack_ended() -> void:
	pass


func _on_body_entered(body: Node) -> void:
	if not _holder or body == _holder:
		return

	var health := body.get_node_or_null("Components/Health") as Health
	if not health:
		return
	if TeamMember.is_same_team(_holder, body):
		return

	var now := Time.get_ticks_msec() / 1000.0
	var last_hit: float = _recent_hits.get(body, -_data.attack_cooldown - 1.0)
	if now - last_hit < _data.attack_cooldown:
		return
	_recent_hits[body] = now

	var final_damage := _data.damage
	var is_critical := randf() < _data.critical_chance
	if is_critical:
		final_damage *= CRITICAL_MULTIPLIER

	health.take_damage(final_damage, _holder)
	_apply_knockback(body)
	_lose_durability(1)

	if AudioManager:
		AudioManager.play_hit()


func _apply_knockback(body: Node) -> void:
	var other_body := body as RigidBody2D
	if not other_body:
		return

	var dir := linear_velocity.normalized()
	if dir.is_zero_approx():
		dir = (body.global_position - global_position).normalized()
	if dir.is_zero_approx():
		dir = Vector2(_target_facing, 0.0)

	other_body.apply_central_impulse(dir * _data.knockback)
