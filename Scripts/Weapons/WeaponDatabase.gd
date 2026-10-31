extends Node

## The weapon registry: every archetype's stats, scene and card art, in one
## place. Weapon scenes read their stats by name; WeaponSpawner spawns from
## get_scene(); the CHOOSE WEAPONS panel lists get_names(). Adding a weapon =
## one _register() entry (plus its scene).

## Stats shown on the weapon cards, in card order (keys for get_stat()).
const CARD_STATS: Array[StringName] = [
	&"damage", &"attack_speed", &"critical_chance", &"durability", &"knockback", &"range",
]

var _data: Dictionary = {}       # String -> WeaponData
var _order: Array[String] = []   # registration order (card + spawn order)
var _scene_paths: Dictionary = {} # String -> scene path
var _scenes: Dictionary = {}     # String -> PackedScene (loaded on first use)


func _ready() -> void:
	_register_all()


func get_data(name: String) -> WeaponData:
	return _data.get(name, null)


## Every registered weapon name, in registration order.
func get_names() -> Array[String]:
	return _order.duplicate()


func get_scene(name: String) -> PackedScene:
	if not _scenes.has(name) and _scene_paths.has(name):
		_scenes[name] = load(_scene_paths[name]) as PackedScene
	return _scenes.get(name, null)


## Card art (the weapon's own sprite texture).
func get_icon(name: String) -> Texture2D:
	var d := get_data(name)
	return d.texture if d else null


## Reach in px: melee = thrust distance, ranged = projectile travel.
func get_range(name: String) -> float:
	var d := get_data(name)
	if d == null:
		return 0.0
	if d.category == "ranged":
		return d.projectile_speed * d.projectile_lifetime
	return d.attack_thrust_distance


## One CARD_STATS value: damage, attack_speed (attacks/s), critical_chance
## (0..1), durability (hits), knockback, range (px).
func get_stat(name: String, stat: StringName) -> float:
	var d := get_data(name)
	if d == null:
		return 0.0
	match stat:
		&"damage": return d.damage
		&"attack_speed": return 1.0 / d.attack_cooldown if d.attack_cooldown > 0.0 else 0.0
		&"critical_chance": return d.critical_chance
		&"durability": return float(d.durability)
		&"knockback": return d.knockback
		&"range": return get_range(name)
	return 0.0


## Best value of a stat (the cards' bars scale to it) — across all weapons,
## or only one category ("melee" / "ranged") when given.
func get_stat_max(stat: StringName, category: String = "") -> float:
	var best := 0.0
	for name in _order:
		if not category.is_empty() and get_data(name).category != category:
			continue
		best = maxf(best, get_stat(name, stat))
	return best


func _register_all() -> void:
	# Melee: Sword
	_register({
		"weapon_name": "Sword",
		"scene": "res://Scenes/Weapons/Sword.tscn",
		"icon": "res://Assets/PNG/Default/item_sword.png",
		"category": "melee",
		"damage": 22.0,
		"attack_cooldown": 0.5,
		"critical_chance": 0.10,
		"durability": 20,
		"knockback": 400.0,
		"attack_thrust_distance": 32.0,
		"attack_thrust_duration": 0.20,
		"slash_arc_degrees": 45.0,
		"follow_offset": Vector2(24.0, -4.0),
	})

	# Melee: Spear
	_register({
		"weapon_name": "Spear",
		"scene": "res://Scenes/Weapons/Spear.tscn",
		"icon": "res://Assets/PNG/Default/item_spear.png",
		"category": "melee",
		"damage": 20.0,
		"attack_cooldown": 0.6,
		"critical_chance": 0.15,
		"durability": 15,
		"knockback": 350.0,
		"attack_thrust_distance": 48.0,
		"attack_thrust_duration": 0.18,
		"follow_offset": Vector2(30.0, -4.0),
	})

	# Melee: Fork
	_register({
		"weapon_name": "Fork",
		"scene": "res://Scenes/Weapons/Fork.tscn",
		"icon": "res://Assets/PNG/Default/item_rod.png",
		"category": "melee",
		"damage": 17.0,
		"attack_cooldown": 0.4,
		"critical_chance": 0.12,
		"durability": 12,
		"knockback": 320.0,
		"attack_thrust_distance": 40.0,
		"attack_thrust_duration": 0.16,
		"follow_offset": Vector2(28.0, -4.0),
	})

	# Ranged: Pistol
	_register({
		"weapon_name": "Pistol",
		"scene": "res://Scenes/Weapons/Pistol.tscn",
		"icon": "res://Assets/PNG/Default/item_gun.png",
		"category": "ranged",
		"damage": 15.0,
		"attack_cooldown": 0.35,
		"critical_chance": 0.08,
		"durability": 10,
		"knockback": 150.0,
		"attack_thrust_distance": 0.0,
		"attack_thrust_duration": 0.0,
		"projectile_speed": 550.0,
		"projectile_lifetime": 1.0,
		"follow_offset": Vector2(18.0, -4.0),
	})

	# Ranged: Rifle
	_register({
		"weapon_name": "Rifle",
		"scene": "res://Scenes/Weapons/Rifle.tscn",
		"icon": "res://Assets/PNG/Default/item_blaster.png",
		"category": "ranged",
		"damage": 22.0,
		"attack_cooldown": 0.25,
		"critical_chance": 0.12,
		"durability": 18,
		"knockback": 200.0,
		"attack_thrust_distance": 0.0,
		"attack_thrust_duration": 0.0,
		"projectile_speed": 900.0,
		"projectile_lifetime": 1.0,
		"follow_offset": Vector2(22.0, -4.0),
	})


func _register(values: Dictionary) -> void:
	var d := WeaponData.new()
	d.weapon_name = values["weapon_name"]
	d.category = values["category"]
	d.damage = values["damage"]
	d.attack_cooldown = values["attack_cooldown"]
	d.critical_chance = values["critical_chance"]
	d.durability = values["durability"]
	d.knockback = values["knockback"]
	d.attack_thrust_distance = values["attack_thrust_distance"]
	d.attack_thrust_duration = values["attack_thrust_duration"]
	if values.has("slash_arc_degrees"):
		d.slash_arc_degrees = values["slash_arc_degrees"]
	if values.has("projectile_speed"):
		d.projectile_speed = values["projectile_speed"]
		d.projectile_lifetime = values["projectile_lifetime"]
	if values.has("follow_offset"):
		d.follow_offset = values["follow_offset"]
	d.texture = load(values["icon"]) as Texture2D
	_data[d.weapon_name] = d
	_order.append(d.weapon_name)
	_scene_paths[d.weapon_name] = values["scene"]
