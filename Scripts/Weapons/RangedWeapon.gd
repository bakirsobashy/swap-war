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
	if not _holder:
		return

	if _fire_cooldown_timer > 0.0:
		_fire_cooldown_timer -= delta

	_update_follow_transform()


func _local_weapon_rotation() -> float:
	# Gun sprites already point to the right; do not rotate them like melee weapons.
	return 0.0


func _fire_projectile() -> void:
	var projectile_scene := preload("res://Scenes/Weapons/Projectile.tscn")
	var projectile := projectile_scene.instantiate() as Projectile

	var muzzle := get_node_or_null("Visuals/Muzzle") as Marker2D
	var spawn_pos := global_position
	var dir := _get_aim_direction()

	if muzzle:
		spawn_pos = muzzle.global_position
		var muzzle_dir := Vector2.RIGHT.rotated(muzzle.global_rotation)
		if not muzzle_dir.is_zero_approx():
			dir = muzzle_dir

	get_tree().current_scene.add_child(projectile)
	projectile.start(spawn_pos, dir, _data, _holder)

	if AudioManager:
		AudioManager.play_attack()
