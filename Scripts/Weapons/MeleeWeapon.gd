class_name MeleeWeapon
extends WeaponBase

## Melee damage happens ONLY during a swing (audit design flaw 6): a held
## blade resting on an enemy, or an enemy walking into it, does nothing. The
## HitBox is the single damage path — the weapon body still collides with
## actors (it shoves), but its contact hook is WeaponBase's no-op.

const CRITICAL_MULTIPLIER: float = 1.5
## can_hit: a target this close to straight above/below counts as faced.
const FACING_DEADZONE: float = 4.0
## Body radius for a target without a capsule (every actor has one).
const DEFAULT_BODY_RADIUS: float = 19.0

var _attack_cooldown_timer: float = 0.0
var _attack_timer: float = 0.0
var _is_attacking: bool = false
## Victims already struck by the current swing — one hit per victim per
## swing. Cleared when a swing starts; the swing cooldown paces repeats.
var _hit_this_swing: Dictionary = {}
## The area one swing can strike (see _swing_rect), cached on first use.
var _swing_rect_cache: Rect2 = Rect2()
var _swing_rect_ready: bool = false


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


## Would a swing launched right now hit `target`? True when the target's body
## is inside the area the swing sweeps, measured from where the blade points
## NOW (the socket turns gradually after the aim, like a gun's muzzle), and
## the holder faces the target's side. The AI and Auto Attack only swing on
## this — only swings deal damage, and a whiff burns the whole cooldown.
## Team and health checks are the caller's.
func can_hit(target: Node2D) -> bool:
	if not _holder or not _socket or is_broken():
		return false
	if not is_instance_valid(target) or target == _holder:
		return false
	var dx := target.global_position.x - _holder.global_position.x
	if absf(dx) > FACING_DEADZONE and signf(dx) != _get_holder_facing():
		return false

	# The capsule is exactly the union of circles of its radius along its
	# spine; three samples on the actor's 24 px spine leave gaps under 1 px.
	var body := _body_capsule(target)
	var radius := body.x
	var center := target.global_position
	var shape_node := target.get_node_or_null("CollisionShape2D") as Node2D
	if shape_node:
		center = shape_node.global_position
	var box := _swing_rect()
	var to_socket := _socket.global_transform.affine_inverse()
	for t: float in [-1.0, 0.0, 1.0]:
		var p: Vector2 = to_socket * (center + Vector2(0.0, t * body.y))
		var gap_x := maxf(maxf(box.position.x - p.x, p.x - box.end.x), 0.0)
		var gap_y := maxf(maxf(box.position.y - p.y, p.y - box.end.y), 0.0)
		if gap_x * gap_x + gap_y * gap_y <= radius * radius:
			return true
	return false


## Centre-to-centre distance at which a swing pointed straight at an actor
## still lands: the socket's orbit + the swing area's far edge + the body
## radius (every actor shares one capsule, so the holder's own stands in).
## The AI's reach, stand-off and Attack hand-over all derive from this.
func get_attack_range() -> float:
	if _data == null:
		return 0.0
	var orbit := _socket.position.length() if _socket else 0.0
	var radius := _body_capsule(_holder).x if _holder else DEFAULT_BODY_RADIUS
	return orbit + _swing_rect().end.x + radius


func _physics_process(delta: float) -> void:
	if not _has_live_holder():
		# Dropped mid-swing (the holder died) or its holder was freed: the
		# window gates damage now, so it must not carry over to whoever picks
		# the weapon up next.
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


## How far the blade moves forward during a swing (thrust weapons override).
func _swing_thrust() -> float:
	return 0.0


## The area one swing can strike, in the WeaponSocket's frame (+x = where the
## blade points): the HitBox's bounding box at rest, stretched forward by the
## thrust. Mirrors _update_follow_transform (weapon origin = follow offset +
## hand offset, turned by _local_weapon_rotation). A sword's slash only ever
## adds to the rest pose (it starts and ends there), so leaving it out keeps
## this conservative. Depends only on the scene and the stats: cached.
func _swing_rect() -> Rect2:
	if _swing_rect_ready:
		return _swing_rect_cache
	var hit_box := get_node_or_null("HitBox") as Area2D
	if hit_box == null or _data == null:
		return Rect2()
	var local_rot := _local_weapon_rotation()
	var hand_offset := Vector2.ZERO
	var hand_socket := get_hand_socket()
	if hand_socket:
		hand_offset = -hand_socket.position.rotated(local_rot)
	var origin := _data.follow_offset + hand_offset
	var box := Rect2()
	var first := true
	for child in hit_box.get_children():
		var shape_node := child as CollisionShape2D
		if shape_node == null or shape_node.shape == null:
			continue
		var r := shape_node.shape.get_rect()
		var xf := hit_box.transform * shape_node.transform
		for corner: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			var p: Vector2 = origin + (xf * corner).rotated(local_rot)
			if first:
				box = Rect2(p, Vector2.ZERO)
				first = false
			else:
				box = box.expand(p)
	box.size.x += _swing_thrust()
	_swing_rect_cache = box
	_swing_rect_ready = true
	return box


## (radius, spine half-length) of a body's capsule, or a plain circle when it
## has none.
func _body_capsule(body: Node) -> Vector2:
	var shape_node := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node:
		var capsule := shape_node.shape as CapsuleShape2D
		if capsule:
			return Vector2(capsule.radius, maxf(capsule.height * 0.5 - capsule.radius, 0.0))
	return Vector2(DEFAULT_BODY_RADIUS, 0.0)


func _on_hit_box_body_entered(body: Node) -> void:
	# Only a swing deals damage — a resting blade is harmless.
	if _is_attacking:
		_try_hit(body)


## Strike one body with the current swing: skip the holder, non-actors,
## allies and anyone this swing already hit.
func _try_hit(body: Node) -> void:
	# A HitBox contact can land in the tick between the holder being freed
	# mid-swing and _physics_process noticing; is_same_team would error on it.
	if not _has_live_holder() or body == _holder:
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
	var dir := _knockback_dir(body)
	if not health.take_damage(final_damage, _holder, dir, is_critical):
		return
	_apply_knockback(body, dir)
	if AudioManager:
		AudioManager.play_hit()
	_lose_durability(1)


## The blade's own velocity, else away from the blade, else the facing.
## Computed before the hit so Health (HitFeel's spray/stain) gets it too.
func _knockback_dir(body: Node) -> Vector2:
	var dir := linear_velocity.normalized()
	if dir.is_zero_approx():
		dir = (body.global_position - global_position).normalized()
	if dir.is_zero_approx():
		dir = Vector2(_target_facing, 0.0)
	return dir


func _apply_knockback(body: Node, dir: Vector2) -> void:
	var other_body := body as RigidBody2D
	if not other_body:
		return

	if other_body.has_method("apply_knockback"):
		other_body.apply_knockback(dir * _data.knockback)
	else:
		other_body.apply_central_impulse(dir * _data.knockback)
