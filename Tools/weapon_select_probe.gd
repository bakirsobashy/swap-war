extends SceneTree

## Headless probe for CHOOSE WEAPONS: the WeaponDatabase registry, the
## spawner's enabled-weapon filter and the WeaponsPanel selection rules.
## Verifies:
##   1. every registry entry has a loadable scene (whose weapon_name matches)
##      and card art
##   2. a weapon in SettingsManager.disabled_weapons never spawns (300 picks);
##      with every melee weapon off only guns spawn
##   3. a name missing from the disabled list counts as enabled (new weapons
##      start ON for old settings files)
##   4. WeaponsPanel: the last enabled weapon is locked, an "all off" list is
##      refused, a switch flip updates the selection + emits, INCLUDE ALL
##      re-enables everything
##
## Probe discipline: runtime load(), untyped vars, autoloads by node path.
## disabled_weapons is set as a property only (the setter persists).

var _fails: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var registry = root.get_node_or_null("/root/WeaponDatabase")
	var settings = root.get_node_or_null("/root/SettingsManager")
	if registry == null or settings == null:
		_check(false, "WeaponDatabase + SettingsManager autoloads present")
		quit(1)
		return
	var saved_disabled = settings.disabled_weapons.duplicate()

	# 1. registry
	var names: Array = registry.get_names()
	_check(names.size() >= 5, "registry lists %d weapons" % names.size())
	for weapon_name in names:
		var scene = registry.get_scene(weapon_name)
		var weapon = scene.instantiate() if scene else null
		_check(weapon != null and weapon.weapon_name == weapon_name and registry.get_icon(weapon_name) != null,
				"%s: scene + art load, scene is the %s" % [weapon_name, weapon_name])
		if weapon:
			weapon.free()

	# 2. spawner filter
	var spawner = load("res://Scenes/Weapons/WeaponSpawner.tscn").instantiate()
	spawner.set_process(false)
	root.add_child(spawner)
	settings.disabled_weapons = PackedStringArray(["Sword", "Pistol"])
	var seen := _pick_names(spawner, registry, 300)
	_check(not seen.has("Sword") and not seen.has("Pistol") and seen.has("Spear") and seen.has("Rifle"),
			"disabled Sword + Pistol never spawn (seen %s)" % [seen.keys()])
	var melee := []
	for weapon_name in names:
		if registry.get_data(weapon_name).category == "melee":
			melee.append(weapon_name)
	settings.disabled_weapons = PackedStringArray(melee)
	seen = _pick_names(spawner, registry, 100)
	var only_guns := not seen.is_empty()
	for weapon_name in seen:
		if registry.get_data(weapon_name).category != "ranged":
			only_guns = false
	_check(only_guns, "every melee weapon off -> only guns spawn (seen %s)" % [seen.keys()])

	# 3. unknown names / new weapons default ON
	settings.disabled_weapons = PackedStringArray(["SomeOldWeapon"])
	var all_on := true
	for weapon_name in names:
		all_on = all_on and settings.is_weapon_enabled(weapon_name)
	_check(all_on, "names missing from the disabled list are enabled")
	settings.disabled_weapons = saved_disabled
	spawner.queue_free()

	# 4. panel rules
	var panel = load("res://Scenes/UI/WeaponsPanel.tscn").instantiate()
	root.add_child(panel)
	await process_frame
	var keep_on: String = names[names.size() - 1]
	var others := PackedStringArray()
	for weapon_name in names:
		if weapon_name != keep_on:
			others.append(weapon_name)
	panel.set_disabled(others)
	var last_card = panel.get_card(keep_on)
	_check(panel.get_enabled_count() == 1 and last_card.get_switch().disabled,
			"the last enabled weapon (%s) is locked" % keep_on)
	panel.set_disabled(PackedStringArray(names))
	_check(panel.get_enabled_count() == names.size(), "an all-off list is refused (everything back on)")
	var emitted := [0]
	panel.selection_changed.connect(func(): emitted[0] += 1)
	panel.get_card(names[0]).get_switch().button_pressed = false
	_check(panel.get_disabled().has(names[0]) and emitted[0] == 1,
			"switching %s off updates the selection and emits" % names[0])
	panel.include_all()
	_check(panel.get_disabled().is_empty() and panel.get_node("%IncludeAllBtn").disabled,
			"INCLUDE ALL re-enables everything (button greys out)")
	panel.queue_free()

	var verdict := "ALL PASS"
	if _fails > 0:
		verdict = "%d FAILURES" % _fails
	print(verdict)
	quit(1 if _fails > 0 else 0)

## Weapon names produced by `count` spawner picks.
func _pick_names(spawner, registry, count: int) -> Dictionary:
	var by_path := {}
	for weapon_name in registry.get_names():
		by_path[registry.get_scene(weapon_name).resource_path] = weapon_name
	var seen := {}
	for i in count:
		var scene = spawner._pick_weapon_scene()
		if scene:
			seen[by_path.get(scene.resource_path, "?")] = true
	return seen

func _check(ok: bool, what: String) -> void:
	var verdict := "FAIL"
	if ok:
		verdict = "PASS"
	print("%s: %s" % [verdict, what])
	if not ok:
		_fails += 1
