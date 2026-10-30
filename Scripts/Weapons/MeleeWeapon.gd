class_name MeleeWeapon
extends WeaponBase

## Melee damage happens ONLY during a swing (audit design flaw 6): a held
## blade resting on an enemy, or an enemy walking into it, does nothing. The
## HitBox is the single damage path — the weapon body still collides with
## actors (it shoves), but its contact hook is WeaponBase's no-op.

const CRITICAL_MULTIPLIER: float = 1.5

var _attack_cooldown_timer: float = 0.0
var _attack_timer: float = 0.0
var _is_attacking: bool = false
## Victims already struck by the current swing — one hit per victim per
## swing. Cleared when a swing starts; the swing cooldown paces repeats.
var _hit_this_swing: Dictionary = {}


func _ready() -> void:
	super._ready()
	var hit_box := get_node_or_null("HitBox") as Area2D
	if hit_box:
		hit_box.body_entered.connect(_on_hit_box_body_entered)


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
	_hit_this_swing.clear()

	if AudioManager:
		AudioManager.play_melee_attack()

	# body_entered only fires on overlap BEGIN, so an enemy already touching
	# the blade would never be hit. Strike what the hitbox overlaps now;
	# bodies the swing reaches later arrive through _on_hit_box_body_entered.
	var hit_box := get_node_or_null("HitBox") as Area2D
	if hit_box:
		for body in hit_box.get_overlapping_bodies():
			_try_hit(body)


func is_attacking() -> bool:
	return _is_attacking


func _physics_process(delta: float) -> void:
	if not _holder:
		# Dropped mid-swing (the holder died): the window gates damage now,
		# so it must not carry over to whoever picks the weapon up next.
		_is_attacking = false
		_attack_timer = 0.0
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


func _on_hit_box_body_entered(body: Node) -> void:
	# Only a swing deals damage — a resting blade is harmless.
	if _is_attacking:
		_try_hit(body)


## Strike one body with the current swing: skip the holder, non-actors,
## allies and anyone this swing already hit.
func _try_hit(body: Node) -> void:
	if not _holder or body == _holder:
		return
	if _hit_this_swing.has(body):
		return

	var health := body.get_node_or_null("Components/Health") as Health
	if not health:
		return
	if TeamMember.is_same_team(_holder, body):
		return
	# Marked before take_damage: a blocked hit still spends this victim's
	# one chance this swing.
	_hit_this_swing[body] = true

	var final_damage := _data.damage
	var is_critical := randf() < _data.critical_chance
	if is_critical:
		final_damage *= CRITICAL_MULTIPLIER

	# A blocked hit (dead / respawn-invulnerable target) costs nothing and
	# pushes nobody — durability and knockback used to apply regardless.
	if not health.take_damage(final_damage, _holder):
		return
	_apply_knockback(body)
	if AudioManager:
		AudioManager.play_hit()
	_lose_durability(1)


func _apply_knockback(body: Node) -> void:
	var other_body := body as RigidBody2D
	if not other_body:
		return

	var dir := linear_velocity.normalized()
	if dir.is_zero_approx():
		dir = (body.global_position - global_position).normalized()
	if dir.is_zero_approx():
		dir = Vector2(_target_facing, 0.0)

	if other_body.has_method("apply_knockback"):
		other_body.apply_knockback(dir * _data.knockback)
	else:
		other_body.apply_central_impulse(dir * _data.knockback)
