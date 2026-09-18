class_name WeaponSpawner
extends Node

## Number of weapons dropped in each sky wave.
@export var wave_size: int = 3

## Seconds between spawn waves.
@export var wave_interval: float = 10.0

## Total weapon instances allowed at once (held + ground + dropped).
const MAX_ACTIVE_WEAPONS: int = 10

## How many guns (held + ground) are allowed at once. Melee is unlimited.
@export var max_active_guns: int = 2

## Relative chance to spawn a melee weapon vs a gun when there is room for guns.
@export var melee_weight: float = 3.0
@export var gun_weight: float = 1.0

const MELEE_SCENES: Array[PackedScene] = [
	preload("res://Scenes/Weapons/Sword.tscn"),
	preload("res://Scenes/Weapons/Spear.tscn"),
	preload("res://Scenes/Weapons/Fork.tscn"),
]

const GUN_SCENES: Array[PackedScene] = [
	preload("res://Scenes/Weapons/Pistol.tscn"),
	preload("res://Scenes/Weapons/Rifle.tscn"),
]

static var _active_weapon_count: int = 0

var _wave_timer: float = 0.0


func _ready() -> void:
	_wave_timer = wave_interval


func _process(delta: float) -> void:
	_wave_timer -= delta
	if _wave_timer <= 0.0:
		_wave_timer = wave_interval
		_spawn_wave()


static func can_spawn_weapon() -> bool:
	return _active_weapon_count < MAX_ACTIVE_WEAPONS


static func register_weapon() -> void:
	_active_weapon_count += 1


static func unregister_weapon() -> void:
	_active_weapon_count = maxi(_active_weapon_count - 1, 0)


func spawn_weapon(at_global_position: Vector2) -> WeaponBase:
	if not can_spawn_weapon():
		return null

	var scene := _pick_weapon_scene()
	if scene == null:
		return null

	var weapon := scene.instantiate() as WeaponBase
	if weapon == null:
		return null

	weapon.global_position = at_global_position
	weapon.rotation = randf_range(-0.2, 0.2)
	weapon.collision_mask = WeaponBase.GROUND_MASK

	var root := get_tree().current_scene
	if root:
		root.call_deferred("add_child", weapon)

	return weapon


func _spawn_wave() -> void:
	if not can_spawn_weapon():
		return

	var points := get_tree().get_nodes_in_group("weapon_spawn_points")
	if points.is_empty():
		return

	for i in wave_size:
		if not can_spawn_weapon():
			break
		var point := points.pick_random() as Node2D
		if point == null:
			continue
		spawn_weapon(point.global_position + Vector2(randf_range(-10.0, 10.0), 0.0))


func _pick_weapon_scene() -> PackedScene:
	var allow_guns := _count_active_guns() < max_active_guns
	var gun_scenes := GUN_SCENES.duplicate()
	var melee_scenes := MELEE_SCENES.duplicate()

	if allow_guns and not gun_scenes.is_empty() and not melee_scenes.is_empty():
		var total := melee_weight + gun_weight
		var roll := randf() * total
		if roll < melee_weight:
			return melee_scenes.pick_random()
		else:
			return gun_scenes.pick_random()
	elif not melee_scenes.is_empty():
		return melee_scenes.pick_random()
	elif allow_guns and not gun_scenes.is_empty():
		return gun_scenes.pick_random()
	return null


func _count_active_guns() -> int:
	var count := 0
	for weapon in get_tree().get_nodes_in_group("weapons"):
		var w := weapon as WeaponBase
		if w and w.is_ranged() and not w.is_queued_for_deletion():
			count += 1
	return count
