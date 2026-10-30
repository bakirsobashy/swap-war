class_name RangedWeapon
extends WeaponBase

var _fire_cooldown_timer: float = 0.0


func attack() -> void:
	if not _holder:
		return
	if is_broken():
		return
	if _fire_cooldown_timer > 0.0:
		return

	_fire_cooldown_timer = _data.attack_cooldown
	_fire_projectile()
	_lose_durability(1)


func _physics_process(delta: float) -> void:
	if not _has_live_holder():
		return

	if _fire_cooldown_timer > 0.0:
		_fire_cooldown_timer -= delta

	_update_follow_transform()


func _local_weapon_rotation() -> float:
	# Gun sprites already point to the right; do not rotate them like melee weapons.
	return 0.0


## The muzzle's world direction: the gun turns gradually after the aim, so
## this — not the aim — is where a shot fired now travels.
func get_fire_direction() -> Vector2:
	var muzzle := get_node_or_null("Visuals/Muzzle") as Marker2D
	if muzzle:
		var muzzle_dir := Vector2.RIGHT.rotated(muzzle.global_rotation)
		if not muzzle_dir.is_zero_approx():
			return muzzle_dir
	return _get_aim_direction()


func _fire_projectile() -> void:
	var projectile_scene := preload("res://Scenes/Weapons/Projectile.tscn")
	var projectile := projectile_scene.instantiate() as Projectile

	var muzzle := get_node_or_null("Visuals/Muzzle") as Marker2D
	var spawn_pos := muzzle.global_position if muzzle else global_position
	var dir := get_fire_direction()

	# Defer spawn to avoid adding an Area2D during _integrate_forces.
	call_deferred("_spawn_projectile_deferred", projectile, spawn_pos, dir, _data, _holder)


func _spawn_projectile_deferred(projectile: Projectile, spawn_pos: Vector2, dir: Vector2, data: WeaponData, source: Node) -> void:
	if not is_instance_valid(projectile):
		return
	var root := get_tree().current_scene
	if not root:
		return
	root.add_child(projectile)
	projectile.start(spawn_pos, dir, data, source)
	if AudioManager:
		AudioManager.play_ranged_fire()
