extends Node

## Fixed global stats for every weapon archetype.
## Each weapon scene reads its stats by name from this autoload.

var _data: Dictionary = {}  # String -> WeaponData


func _ready() -> void:
	_register_all()


func get_data(name: String) -> WeaponData:
	return _data.get(name, null)


func _register_all() -> void:
	# Melee: Sword
	_register({
		"weapon_name": "Sword",
		"category": "melee",
		"damage": 25.0,
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
		"category": "melee",
		"damage": 18.0,
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
		"category": "melee",
		"damage": 14.0,
		"attack_cooldown": 0.5,
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
		"category": "ranged",
		"damage": 12.0,
		"attack_cooldown": 0.35,
		"critical_chance": 0.08,
		"durability": 6,
		"knockback": 150.0,
		"attack_thrust_distance": 0.0,
		"attack_thrust_duration": 0.0,
		"projectile_speed": 550.0,
		"projectile_lifetime": 0.7,
		"follow_offset": Vector2(18.0, -4.0),
	})

	# Ranged: Rifle
	_register({
		"weapon_name": "Rifle",
		"category": "ranged",
		"damage": 22.0,
		"attack_cooldown": 0.25,
		"critical_chance": 0.12,
		"durability": 15,
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
	_data[d.weapon_name] = d
