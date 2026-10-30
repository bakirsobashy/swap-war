extends SceneTree

## Headless probe for swing-only melee damage (audit design flaw 6; plan:
## docs/godot-prompter/plans/melee-swing-only-damage.md). A held blade must
## damage ONLY during its swing window, at most once per victim per swing.
##
##   1. Resting blade is harmless: an enemy teleported onto the blade (a fresh
##      overlap) and left there 2 s takes no damage; durability is untouched.
##   2. Walking into the blade is harmless: a LIVE enemy driven through the
##      blade (HitBox entries + weapon-body contacts) takes no damage.
##   3. One swing, one hit: an enemy on the blade for the whole window loses
##      exactly one hit (damage or crit), durability -1.
##   4. Held swings all land: attack() every tick (the AI / Auto Attack
##      pattern, paced by the weapon's cooldown) — every swing hits. The old
##      wall-clock per-victim gate could refuse a swing by a millisecond.
##   5. Teams: an ally on the blade is never hit; once the team changes, the
##      next swing hits.
##   6. Multi-target: two enemies on the blade — one swing hits both.
##   7. Mid-window entry: a Spear thrust reaches an enemy that is out of reach
##      at rest — hit through HitBox.body_entered during the window.
##   8. Dropped mid-swing: the window closes (it gates damage, so it must not
##      carry over to the next holder).
##
## Rig: ArenaHazards instanced manually (ArenaManager's scene_changed hook stays
## out of the way), swap timer stopped, AI brains off, holder and dummies
## frozen (a frozen body skips _integrate_forces, so nothing swings unless the
## probe calls attack()), dummies' pickup disabled, huge dummy health.
##
## `-s` discipline: runtime load() only, untyped vars, no game-class
## annotations, autoloads via /root paths.

const CRIT_MULT := 1.5   # MeleeWeapon.CRITICAL_MULTIPLIER
const PARK := Vector2(-600.0, 78.0)   # spare dummies wait here (west of the holder, behind its blade)

var _fails: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var inst: Node = (load("res://Scenes/Arenas/ArenaHazards.tscn") as PackedScene).instantiate()
	root.add_child(inst)
	current_scene = inst
	await _physics(2)

	var team_manager = root.get_node_or_null("/root/TeamManager")
	if team_manager:
		for ch in team_manager.get_children():
			if ch is Timer:
				ch.stop()

	await _probe(inst)

	var verdict := "ALL PASS"
	if _fails > 0:
		verdict = "%d FAILURES" % _fails
	print("\n=== melee_swing_probe: %s ===" % verdict)
	quit(1 if _fails > 0 else 0)

func _check(ok: bool, what: String) -> void:
	print("  %s: %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1

func _physics(n: int) -> void:
	for i in n:
		await physics_frame

## An actor with its AI off, a fixed team and (for dummies) pickup disabled —
## a dummy must never steal a weapon. Health is set before add_child so
## Health._ready seeds current_health from it.
func _spawn(inst: Node, x: float, y: float, team: int, frozen: bool):
	var actor = load("res://Scenes/actor.tscn").instantiate()
	actor.get_node("AIController").is_ai = false
	actor.get_node("Components/Health").max_health = 10000.0
	actor.position = Vector2(x, y)
	inst.get_node("Actors").add_child(actor)
	# team_id after add_child: the team-change flash needs the tree.
	actor.get_node("Components/TeamMember").team_id = team
	actor.freeze = frozen
	return actor

func _disarm_pickup(actor) -> void:
	actor.get_node("PickupArea").set_deferred("monitoring", false)
	actor.get_node("WeaponHolder").set_physics_process(false)

func _equip(inst: Node, actor, path: String):
	var w = load(path).instantiate()
	inst.add_child(w)
	w.global_position = actor.global_position + Vector2(0, -300)
	await _physics(2)
	actor.get_node("WeaponHolder")._equip_weapon(w)
	await _physics(3)
	w.current_durability = 99   # durability is asserted as a delta
	return w

func _hp(actor) -> float:
	return float(actor.get_node("Components/Health").current_health)

func _on_blade(weapon, actor) -> bool:
	return weapon.get_node("HitBox").get_overlapping_bodies().has(actor)

## One swing (cooldown cleared so scenarios don't wait on each other), then
## let the whole window play out.
func _swing(weapon) -> void:
	weapon._attack_cooldown_timer = 0.0
	weapon.attack()
	await _physics(30)

## Exactly one hit's worth: normal or critical damage.
func _one_hit(drop: float, weapon) -> bool:
	var dmg: float = weapon._data.damage
	return absf(drop - dmg) < 0.01 or absf(drop - dmg * CRIT_MULT) < 0.01

func _probe(inst: Node) -> void:
	# ArenaHazards floor: live actors rest at ~y 78. Everything stays WEST of
	# the spike strip ([288, 352]). The holder faces +x (default facing; AI
	# off, so the aim stays Vector2.RIGHT) — the blade points east.
	var holder = _spawn(inst, -400.0, 78.0, 0, true)
	var sword = await _equip(inst, holder, "res://Scenes/Weapons/Sword.tscn")
	await _physics(20)   # let the socket settle on its aim
	_check(holder.get_node("WeaponHolder").current_weapon == sword, "setup: holder holds the sword")
	var dir: Vector2 = (sword.global_position - holder.global_position).normalized()
	var on_blade: Vector2 = holder.global_position + dir * 70.0

	# --- 1. resting blade ---------------------------------------------------
	print("\n--- 1: a resting blade is harmless ---")
	var e1 = _spawn(inst, PARK.x, PARK.y, 1, true)
	_disarm_pickup(e1)
	await _physics(2)
	var dur0: int = sword.current_durability
	e1.global_position = on_blade
	await _physics(120)
	_check(_on_blade(sword, e1), "1: setup — the enemy is on the blade (dir=%s)" % dir)
	_check(_hp(e1) == 10000.0, "1: no damage after 2 s on the blade (hp=%.0f)" % _hp(e1))
	_check(sword.current_durability == dur0,
			"1: durability untouched (%d -> %d)" % [dur0, sword.current_durability])

	# --- 2. a live enemy walks through the blade -----------------------------
	print("\n--- 2: walking into the blade is harmless ---")
	# Live (unfrozen), 160 px east of the holder — beyond the blade's reach.
	var e2 = _spawn(inst, holder.global_position.x + 160.0, 78.0, 1, false)
	_disarm_pickup(e2)
	await _physics(2)
	var touches := [0]   # HitBox entries + weapon-body contacts (lambdas capture arrays by reference)
	var count_touch = func(body):
		if body == e2:
			touches[0] += 1
	sword.get_node("HitBox").body_entered.connect(count_touch)
	sword.body_entered.connect(count_touch)
	var toward: float = -signf(dir.x)
	for i in 90:
		if absf(e2.global_position.x - holder.global_position.x) < 30.0:
			break
		e2.linear_velocity.x = toward * 180.0
		await physics_frame
	await _physics(30)
	sword.get_node("HitBox").body_entered.disconnect(count_touch)
	sword.body_entered.disconnect(count_touch)
	_check(touches[0] > 0, "2: setup — the enemy touched the blade (%d touches)" % touches[0])
	_check(_hp(e2) == 10000.0, "2: no damage walking through the blade (hp=%.0f)" % _hp(e2))
	_check(sword.current_durability == dur0,
			"2: durability untouched (%d -> %d)" % [dur0, sword.current_durability])
	e2.queue_free()
	await _physics(2)

	# --- 3. one swing, one hit ------------------------------------------------
	print("\n--- 3: one swing, one hit ---")
	var hp3 := _hp(e1)
	var dur3: int = sword.current_durability
	await _swing(sword)
	_check(_one_hit(hp3 - _hp(e1), sword), "3: exactly one hit (hp %.0f -> %.0f)" % [hp3, _hp(e1)])
	_check(sword.current_durability == dur3 - 1,
			"3: durability -1 (%d -> %d)" % [dur3, sword.current_durability])

	# --- 4. held swings all land ----------------------------------------------
	print("\n--- 4: held swings, paced by the cooldown, all land ---")
	var swings := 0
	var hits := 0
	var was_attacking: bool = sword.is_attacking()
	var hp_prev := _hp(e1)
	for i in 200:   # ~3.3 s
		sword.attack()
		var now_attacking: bool = sword.is_attacking()
		if now_attacking and not was_attacking:
			swings += 1
		was_attacking = now_attacking
		await physics_frame
		if _hp(e1) < hp_prev - 0.01:
			hits += 1
		hp_prev = _hp(e1)
	await _physics(30)
	_check(swings >= 5, "4: setup — the held input swung repeatedly (%d swings)" % swings)
	_check(hits == swings, "4: every swing landed (%d hits / %d swings)" % [hits, swings])

	# --- 5. teams --------------------------------------------------------------
	print("\n--- 5: allies are never hit ---")
	var team1 = e1.get_node("Components/TeamMember")
	team1.team_id = 0
	await _physics(2)
	var hp5 := _hp(e1)
	await _swing(sword)
	_check(_hp(e1) == hp5, "5: an ally on the blade takes no damage (hp %.0f -> %.0f)" % [hp5, _hp(e1)])
	team1.team_id = 1
	await _physics(2)
	await _swing(sword)
	_check(_one_hit(hp5 - _hp(e1), sword),
			"5: an enemy again -> the next swing hits (hp %.0f -> %.0f)" % [hp5, _hp(e1)])

	# --- 6. multi-target ----------------------------------------------------------
	print("\n--- 6: one swing hits every enemy on the blade ---")
	var e3 = _spawn(inst, PARK.x - 40.0, PARK.y, 1, true)
	_disarm_pickup(e3)
	await _physics(2)
	e3.global_position = holder.global_position + dir * 55.0
	await _physics(10)
	_check(_on_blade(sword, e1) and _on_blade(sword, e3), "6: setup — both enemies on the blade")
	var hp6a := _hp(e1)
	var hp6b := _hp(e3)
	await _swing(sword)
	_check(_one_hit(hp6a - _hp(e1), sword) and _one_hit(hp6b - _hp(e3), sword),
			"6: both hit once (%.0f -> %.0f, %.0f -> %.0f)" % [hp6a, _hp(e1), hp6b, _hp(e3)])

	# --- 7. spear thrust reaches mid-window --------------------------------------
	print("\n--- 7: a thrust hits a body only in reach while extended ---")
	holder.get_node("WeaponHolder").drop_weapon(false)
	await _physics(2)
	sword.queue_free()
	e3.global_position = PARK
	e1.global_position = PARK
	var spear = await _equip(inst, holder, "res://Scenes/Weapons/Spear.tscn")
	await _physics(20)
	var sdir: Vector2 = (spear.global_position - holder.global_position).normalized()
	# Resting tip = the HitBox polygon's farthest point along the spear.
	var shape_node = spear.get_node("HitBox/HitBoxShape")
	var xf: Transform2D = shape_node.global_transform
	var tip := 0.0
	for p in shape_node.shape.points:
		tip = maxf(tip, (xf * p - holder.global_position).dot(sdir))
	# Capsule radius 19 + a 20 px gap at rest; the 48 px thrust closes it.
	e1.global_position = holder.global_position + sdir * (tip + 19.0 + 20.0)
	await _physics(10)
	_check(not _on_blade(spear, e1), "7: setup — out of reach at rest (tip %.0f px)" % tip)
	var hp7 := _hp(e1)
	await _swing(spear)
	_check(_one_hit(hp7 - _hp(e1), spear), "7: the thrust hit (hp %.0f -> %.0f)" % [hp7, _hp(e1)])

	# --- 8. dropped mid-swing ---------------------------------------------------
	print("\n--- 8: dropping mid-swing closes the window ---")
	spear._attack_cooldown_timer = 0.0
	spear.attack()
	await _physics(2)
	_check(spear.is_attacking(), "8: setup — mid-swing")
	holder.get_node("WeaponHolder").drop_weapon(false)
	await _physics(3)
	_check(not spear.is_attacking(), "8: the dropped weapon is no longer attacking")
