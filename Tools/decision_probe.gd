extends SceneTree

## Headless probe for the rewritten decision layer (plan step 5) — the full
## stack LIVE: sensors 2.0 + six states + AIDifficulty + facing_intent + the
## NavExecutor, on the real ArenaHazards scene with real actors.
##
## Complements nav_executor_probe (which parks the machine and drives the
## executor directly); this one lets the machine make every decision.
##
## Scenarios:
##   1. Armed AI engages an enemy across the map (full-map awareness — no
##      sight radius): arms from a co-placed sword, transitions
##      ApproachEnemy, faces east, routes over the spike strip without
##      taking damage, and reaches Attack. Live checklist items 1, 5, 7.
##   2. Unarmed AI beelines the map-scored weapon (item 4): SeekWeapon,
##      picks up, leaves the state.
##   3. Unarmed AI with a close threat retreats via scored refuge (distance
##      grows) WITHOUT running past the threat — neither the refuge pick nor
##      the patrol after it — then exits Retreat once the threat is far.
##   4. Team swap: no ally-attack, no forced state teardown — the enemy is
##      dropped immediately (became an ally), the Attack state is held but
##      silent through the swap_reaction_time window, a NEW hostile is not
##      targeted during it, then is (retarget ~0.5s). 4b: a swap that keeps
##      the same enemy never breaks off the fight (no Idle/Patrol hop).
##   5. Facing holds through knockback (item 6): facing_intent and the
##      actor's facing_direction stay on the enemy while velocity flies the
##      opposite way.
##   6. Hazard escape override (item 2): an armed AI pinned IN the spike strip
##      with an enemy inside attack reach does not fight — the override owns
##      the inputs (attack silenced, escape dir drives the body), it is out
##      in ~0.5s, takes at most 2 hits, and resumes the fight after.
##   7. Hazard-aware weapon choice (item 3): an unarmed AI skips a nearer
##      sword lying ON the spikes and fetches the farther safe one (+300
##      score), crossing airborne and untouched.
##   8. Patrol never targets hazard segments: 8s of idle patrolling with no
##      enemies and no weapons never sets a foot in the strip.
##
## AI review regressions (2026-10-25 — each reproduced live before its fix):
##   9. Unarmed low-HP AI leaves Retreat once the threat is far and fetches a
##      weapon (the health exit pinned it in hiding: nothing heals).
##  10. Ranged AI after a swap flips its target behind it: every shot waits
##      for the gun (muzzle) to come round — none fly off-target.
##  11. Ranged AI in range but with no lane (enemy atop the raised block)
##      moves to find one and lands a hit instead of parking in Attack.
##  12. Melee AI vs an enemy at a ledge lip: routes onto the ledge and lands
##      a hit instead of parking on the floor right under it.
##  13. Armed retreat faces the enemy (facing intent outranks move input).
##  14. ArenaFlat: a ranged AI kiting toward an island's edge stops at the
##      lip instead of backing into the KillZone.
##
## `-s` mode discipline: runtime load() only, untyped vars, no game-class
## annotations, zero direct autoload references (the team-swap handler is
## invoked on the controller directly).

var _fails: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _probe_decisions()
	await _probe_flat_kite()
	var verdict := "ALL PASS"
	if _fails > 0:
		verdict = "%d FAILURES" % _fails
	print("\n=== decision_probe: %s ===" % verdict)
	quit(1 if _fails > 0 else 0)

func _check(ok: bool, what: String) -> void:
	print("  %s: %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1

func _ticks(n: int) -> void:
	for i in n:
		await physics_frame

func _state_name(ctl) -> String:
	var s = ctl.machine.current_state
	return String(s.get_name()) if s != null else "<none>"

## Tick sampler: runs at most `budget` physics frames, returning the first
## frame at which `pred()` holds (or -1).
func _wait_until(pred: Callable, budget: int) -> int:
	for i in budget:
		await physics_frame
		if pred.call():
			return i
	return -1

func _spawn_ai(inst: Node, x: float, y: float, team: int):
	var actor = load("res://Scenes/actor.tscn").instantiate()
	var ctl = actor.get_node("AIController")
	ctl.is_ai = true
	ctl.nav_enabled = true
	actor.position = Vector2(x, y)
	inst.get_node("Actors").add_child(actor)
	# Post-add_child so TeamMember's flash finds a live tree (a pre-tree set
	# spams native get_tree() errors — the team lands either way).
	actor.get_node("Components/TeamMember").team_id = team
	return actor

## A passive, very tough body — never dies to the test sword, never acts,
## never steals weapons.
func _spawn_dummy(inst: Node, x: float, y: float, team: int):
	var actor = load("res://Scenes/actor.tscn").instantiate()
	var ctl = actor.get_node("AIController")
	ctl.is_ai = false
	actor.position = Vector2(x, y)
	inst.get_node("Actors").add_child(actor)
	actor.get_node("Components/TeamMember").team_id = team
	# Pin the dummy in place: a free body drifts east under every swing's
	# knockback — the AI's approach chases a receding foe and can lose that
	# race (never closing into attack range). Frozen = static: fights
	# converge deterministically.
	actor.freeze = true
	# WeaponHolder auto-pickup is live on EVERY actor (players rely on it) —
	# a dummy standing near a scenario drop steals the sword, and the AI ends
	# up chasing a held, ungrabbable weapon forever. Disarm the dummy's pickup
	# paths (area signal + periodic scan).
	actor.get_node("PickupArea").set_deferred("monitoring", false)
	var wh = actor.get_node("WeaponHolder")
	wh.set_physics_process(false)
	# Jack health AFTER _ready so nothing resets it: a dying dummy would
	# teleport to a spawn marker mid-scenario and scramble every assert.
	var h = actor.get_node("Components/Health")
	h.max_health = 100000.0
	h.current_health = 100000.0
	return actor

## A fresh sword at `pos` (instantly pickable: fresh weapons carry no drop
## delay) with huge durability so no scenario is interrupted by a break.
func _drop_sword(inst: Node, pos: Vector2):
	return _drop_weapon(inst, "res://Scenes/Weapons/Sword.tscn", pos)

func _drop_weapon(inst: Node, scene_path: String, pos: Vector2):
	var weapon = load(scene_path).instantiate()
	weapon.position = pos
	inst.add_child(weapon)
	weapon.current_durability = 1000000
	return weapon

## Projectiles spawned since `seen` was filled (ids are recorded into it).
func _new_projectiles(seen: Dictionary) -> Array:
	var out: Array = []
	for p in get_nodes_in_group("projectiles"):
		if is_instance_valid(p) and not seen.has(p.get_instance_id()):
			seen[p.get_instance_id()] = true
			out.append(p)
	return out

func _damage_taken(dummy) -> float:
	return 100000.0 - float(dummy.get_node("Components/Health").current_health)

## Free every weapon, held or lying, so each scenario starts on a clean
## board. Critical detail: a weapon held by a queue_free'd actor stays
## "held" forever (freed instances compare non-null in GDScript), making it
## ungrabbable — SeekWeapon bait that can never be picked up.
func _purge_weapons() -> void:
	for w in get_nodes_in_group("weapons"):
		if is_instance_valid(w):
			w.queue_free()

func _probe_decisions() -> void:
	print("\n=== decisions: ArenaHazards, full stack live ===")
	var inst = load("res://Scenes/Arenas/ArenaHazards.tscn").instantiate()
	root.add_child(inst)
	current_scene = inst
	await physics_frame
	await physics_frame
	# No random weapon waves: pull the spawn markers so WeaponSpawner no-ops.
	for n in inst.get_tree().get_nodes_in_group("weapon_spawn_points"):
		if inst.is_ancestor_of(n):
			n.remove_from_group("weapon_spawn_points")
	# Swap-War's core mechanic lives in TeamManager: an auto-swap Timer that
	# RANDOMIZES every registered actor's team every 5s and broadcasts
	# team_changed. Left running mid-probe it scrambled the scenario teams
	# (an S4 "ally" flipping back to an enemy mid-fight, S5's foe turning
	# ally so the AI never engaged). Stop its Timer via node path — guarded,
	# no class refs (probe discipline). S4 drives the same handler directly.
	var tm = root.get_node_or_null("/root/TeamManager")
	if tm:
		for c in tm.get_children():
			if c is Timer:
				c.stop()
	# Clean board: any pre-placed weapons go.
	_purge_weapons()
	await physics_frame

	# --- S1: armed AI engages an enemy across the map -------------------------
	print("\n--- S1: full-map awareness -> ApproachEnemy -> Attack ---")
	var ai1 = _spawn_ai(inst, -400.0, 78.0, 0)
	var ctl1 = ai1.get_node("AIController")
	var hp1 = ai1.get_node("Components/Health")
	var foe1 = _spawn_dummy(inst, 500.0, 78.0, 1)
	# +30px: co-placed exactly, the actor capsule physically shoves the sword
	# body out before the PickupArea tick can grab it. Offset lands it outside
	# the capsule, still inside pickup reach — the unarmed AI walks one step
	# and grabs it (also exercises the Idle->SeekWeapon hop).
	_drop_sword(inst, ai1.position + Vector2(30.0, 0.0))
	var t_arm := await _wait_until(func(): return ctl1.weapon_holder.is_holding_weapon(), 180)
	_check(t_arm >= 0, "S1: picks up the co-placed sword (t=%d)" % t_arm)
	_check(ctl1.sensors.current_platform_id >= 0,
			"S1: sensors localize onto a platform (graph live)")
	var t_appr := await _wait_until(func(): return _state_name(ctl1) == "ApproachEnemy", 150)
	_check(t_appr >= 0, "S1: ApproachEnemy entered right after arming (t=%d)" % t_appr)
	_check(absf(ctl1.facing_intent - 1.0) < 0.01,
			"S1: faces the enemy east while approaching (intent=%.0f)" % ctl1.facing_intent)
	var min_hp := float(hp1.current_health)
	var t_atk := -1
	for i in 1500:
		await physics_frame
		min_hp = minf(min_hp, float(hp1.current_health))
		if _state_name(ctl1) == "Attack":
			t_atk = i
			break
	_check(t_atk >= 0, "S1: reaches Attack across the map (t=%d, state=%s)"
			% [t_atk, _state_name(ctl1)])
	_check(absf(min_hp - 100.0) < 0.01,
			"S1: spike strip crossed undamaged (hp=%.0f)" % min_hp)
	# One tick so Attack's OWN physics_update runs (the transition tick's
	# inputs were still ApproachEnemy's) before sampling the attack intent.
	await physics_frame
	_check(bool(ctl1.wants_attack), "S1: holds the attack intent in range")
	ai1.queue_free()
	foe1.queue_free()
	await physics_frame
	_purge_weapons()
	await physics_frame

	# --- S2: unarmed AI beelines the map-scored weapon --------------------------
	print("\n--- S2: unarmed -> SeekWeapon -> armed ---")
	var ai2 = _spawn_ai(inst, -400.0, 78.0, 0)
	var ctl2 = ai2.get_node("AIController")
	_drop_sword(inst, Vector2(-200.0, 90.0))
	var t_seek := await _wait_until(func(): return _state_name(ctl2) == "SeekWeapon", 90)
	_check(t_seek >= 0, "S2: SeekWeapon entered from idle (t=%d)" % t_seek)
	_check(ctl2.sensors.best_weapon != null,
			"S2: weapon known map-wide (score scan, no seek radius)")
	var t_armed := await _wait_until(func(): return ctl2.weapon_holder.is_holding_weapon(), 900)
	_check(t_armed >= 0, "S2: reaches and grabs the weapon (t=%d, x=%.0f)"
			% [t_armed, ai2.position.x])
	var t_left := await _wait_until(func(): return _state_name(ctl2) != "SeekWeapon", 150)
	_check(t_left >= 0, "S2: leaves SeekWeapon once armed (state=%s)" % _state_name(ctl2))
	ai2.queue_free()
	await physics_frame
	_purge_weapons()
	await physics_frame

	# --- S3: unarmed retreat — scored refuge, then clean exit -------------------
	print("\n--- S3: close threat -> Retreat -> exit ---")
	var ai3 = _spawn_ai(inst, -400.0, 78.0, 0)
	var ctl3 = ai3.get_node("AIController")
	var foe3 = _spawn_dummy(inst, -310.0, 78.0, 1)
	var t_ret := await _wait_until(func(): return _state_name(ctl3) == "Retreat", 90)
	_check(t_ret >= 0, "S3: unarmed AI retreats from a close threat (t=%d)" % t_ret)
	var dist0: float = ai3.position.distance_to(foe3.position)
	# The AI starts WEST of the threat with more floor east of it: the old
	# far-end refuge pick ran straight through the threat to the east end,
	# and once safe, Patrol walked the unarmed AI back through it. Sample
	# the whole retreat AND the patrol after it.
	var crossed3 := false
	for i in 300:
		await physics_frame
		if ai3.position.x > foe3.position.x:
			crossed3 = true
	var dist1: float = ai3.position.distance_to(foe3.position)
	_check(dist1 > dist0 + 40.0,
			"S3: puts real distance on the threat (%.0f -> %.0f)" % [dist0, dist1])
	_check(not crossed3, "S3: never runs past the threat (retreat or patrol; x=%.0f, threat x=%.0f)"
			% [ai3.position.x, foe3.position.x])
	# Throw the threat to the far side of the map from wherever the AI ended
	# up — the retreat exit needs dist > retreat_safe_distance (250px), so the
	# teleport must land far from the AI whichever way it fled.
	var far_x := -600.0 if ai3.position.x > 0.0 else 600.0
	foe3.global_position = Vector2(far_x, 78.0)
	var t_exit := await _wait_until(func(): return _state_name(ctl3) != "Retreat", 200)
	_check(t_exit >= 0, "S3: exits Retreat once the threat is far (t=%d, state=%s)"
			% [t_exit, _state_name(ctl3)])
	ai3.queue_free()
	foe3.queue_free()
	await physics_frame
	_purge_weapons()
	await physics_frame

	# --- S4: team swap — window, no ally-attack, retarget ----------------------
	print("\n--- S4: team swap reaction window ---")
	var ai4 = _spawn_ai(inst, -300.0, 78.0, 0)
	var ctl4 = ai4.get_node("AIController")
	var ally4 = _spawn_dummy(inst, -240.0, 78.0, 1)
	# West of the AI: the dummy sits east — even with the dummy's pickup
	# disarmed, keep scenario drops out of every other actor's reach.
	_drop_sword(inst, ai4.position + Vector2(-30.0, 0.0))
	var t_fight := await _wait_until(func(): return _state_name(ctl4) == "Attack", 300)
	_check(t_fight >= 0, "S4: fighting before the swap (t=%d)" % t_fight)
	# The swap: the enemy becomes a teammate; the controller's handler is the
	# same one TeamManager.team_changed drives in production.
	ally4.get_node("Components/TeamMember").team_id = 0
	var foe4 = _spawn_dummy(inst, 400.0, 78.0, 1)
	ctl4._on_team_changed({})
	var held4 := true
	var swung4 := false
	for i in 12:
		await physics_frame
		if _state_name(ctl4) != "Attack":
			held4 = false
		if bool(ctl4.wants_attack):
			swung4 = true
	var s = ctl4.sensors.nearest_enemy
	_check(s == null, "S4: no target during the swap window (got %s)"
			% ("<none>" if s == null else "one"))
	_check(not swung4, "S4: stops attacking the new ally during the window")
	_check(held4, "S4: Attack state held through the window — no teardown (state=%s)"
			% _state_name(ctl4))
	var t_retgt := await _wait_until(func(): return ctl4.sensors.nearest_enemy == foe4, 90)
	_check(t_retgt >= 0, "S4: retargets the new hostile after the window (t=%d)" % t_retgt)
	var t_appr4 := await _wait_until(func(): return _state_name(ctl4) == "ApproachEnemy", 150)
	_check(t_appr4 >= 0, "S4: re-engages (state=%s)" % _state_name(ctl4))
	ai4.queue_free()
	ally4.queue_free()
	foe4.queue_free()
	await physics_frame
	_purge_weapons()
	await physics_frame

	# --- S4b: a swap that keeps the same enemy never breaks off the fight ------
	print("\n--- S4b: same-enemy swap holds the fight ---")
	var ai4b = _spawn_ai(inst, -300.0, 78.0, 0)
	var ctl4b = ai4b.get_node("AIController")
	var foe4b = _spawn_dummy(inst, -240.0, 78.0, 1)
	_drop_sword(inst, ai4b.position + Vector2(-30.0, 0.0))
	var t_fight4b := await _wait_until(func(): return _state_name(ctl4b) == "Attack", 300)
	_check(t_fight4b >= 0, "S4b: fighting before the swap (t=%d)" % t_fight4b)
	await _ticks(30)
	var x4b: float = ai4b.position.x
	# The old window tore the state down (no enemy -> Idle -> Patrol, whose
	# enter() planned a random hop: ~95px of wandering off mid-fight).
	ctl4b._on_team_changed({})
	var seq4b: Array = [_state_name(ctl4b)]
	var drift4b := 0.0
	for i in 60:
		await physics_frame
		if seq4b.back() != _state_name(ctl4b):
			seq4b.append(_state_name(ctl4b))
		drift4b = maxf(drift4b, absf(ai4b.position.x - x4b))
	_check(seq4b == ["Attack"], "S4b: no teardown through the window (states %s)"
			% " > ".join(seq4b))
	_check(drift4b < 32.0, "S4b: stays at the fight (drift %.0fpx)" % drift4b)
	_check(bool(ctl4b.wants_attack), "S4b: swinging again after the window")
	ai4b.queue_free()
	foe4b.queue_free()
	await physics_frame
	_purge_weapons()
	await physics_frame

	# --- S5: facing holds through knockback --------------------------------------
	print("\n--- S5: facing intent survives knockback ---")
	var ai5 = _spawn_ai(inst, -300.0, 78.0, 0)
	var ctl5 = ai5.get_node("AIController")
	var foe5 = _spawn_dummy(inst, -250.0, 78.0, 1)
	# West of the AI, away from the east-side dummy (see S4).
	_drop_sword(inst, ai5.position + Vector2(-30.0, 0.0))
	var t_fight5 := await _wait_until(func(): return _state_name(ctl5) == "Attack", 300)
	_check(t_fight5 >= 0, "S5: fighting (t=%d)" % t_fight5)
	# Let the melee micro-spacing settle first: entering Attack from point
	# blank trips the back-off (move input away), and move input outranks
	# facing intent for the BODY facing while it lasts.
	await _ticks(30)
	_check(ctl5.facing_intent == 1.0 and ai5.facing_direction > 0.0,
			"S5: faces the enemy before the hit (intent=%.0f body=%.2f)"
			% [ctl5.facing_intent, ai5.facing_direction])
	ai5.apply_central_impulse(Vector2(-800.0, 0.0))
	var intent_held := true
	var body_held := true
	# NOTE: Actor-Movement's input branch stores the RAW move input as
	# facing_direction (proportional nav writes 0.7 etc.), so "facing east" is
	# a SIGN check (facing > 0), not an exact ±1.0 comparison.
	for i in 12:
		await physics_frame
		if ctl5.facing_intent != 1.0:
			intent_held = false
		if ai5.linear_velocity.x < -50.0 and ai5.facing_direction <= 0.0:
			if body_held:
				print("    S5 flip trace: t=%d state=%s move=%.1f intent=%.0f face=%.2f vx=%.0f x=%.0f foe=%.0f dist=%.0f"
						% [i, _state_name(ctl5), ctl5.move_direction, ctl5.facing_intent,
						ai5.facing_direction, ai5.linear_velocity.x, ai5.position.x,
						foe5.position.x, ai5.position.distance_to(foe5.position)])
			body_held = false
	_check(intent_held, "S5: facing_intent stays on the enemy through the knockback")
	_check(body_held, "S5: actor facing holds while velocity flies backwards")
	ai5.queue_free()
	foe5.queue_free()
	await physics_frame
	_purge_weapons()
	await physics_frame

	# --- S6: spike-pinned escape override outranks the fight ---------------------
	print("\n--- S6: escape override while armed with an enemy in reach ---")
	# Arm at the SAFE edge west of the strip first: the override escapes in
	# under 10 ticks — faster than a falling sword lands in pickup reach — so
	# arming in-place would leave the AI unarmed mid-pin, and an unarmed AI
	# correctly retreats instead of fighting (locked decision: unarmed =
	# evade + seek). Arm, THEN pin the fight-ready actor in the strip center.
	var ai6 = _spawn_ai(inst, 240.0, 90.0, 0)
	var ctl6 = ai6.get_node("AIController")
	var hp6 = ai6.get_node("Components/Health")
	var foe6 = _spawn_dummy(inst, 370.0, 78.0, 1)
	_drop_sword(inst, ai6.position + Vector2(30.0, 0.0))
	var t_arm6 := await _wait_until(func(): return ctl6.weapon_holder.is_holding_weapon(), 90)
	_check(t_arm6 >= 0, "S6: arms at the safe edge first (t=%d)" % t_arm6)
	# Teleport the ARMED actor into the strip center: 50px from the foe —
	# inside melee reach — where the override must outrank both the machine
	# (Attack) and the executor (its approach route).
	ai6.global_position = Vector2(320.0, 90.0)
	var t_pin := await _wait_until(func(): return ctl6.sensors.in_hazard, 90)
	_check(t_pin >= 0, "S6: pinned in the spike strip after the teleport (t=%d)" % t_pin)
	var attack_silenced := true
	var traced := false
	var t_escape6 := -1
	for i in 45:
		await physics_frame
		if ctl6.sensors.in_hazard and bool(ctl6.wants_attack):
			attack_silenced = false
			if not traced:
				traced = true
				print("    S6 attack trace: i=%d esc=%.0f state=%s x=%.0f y=%.0f move=%.1f armed=%s foe_dx=%.0f"
						% [i, ctl6.sensors.hazard_escape_dir, _state_name(ctl6),
						ai6.position.x, ai6.position.y, ctl6.move_direction,
						ctl6.weapon_holder.is_holding_weapon(),
						foe6.position.x - ai6.position.x])
		if not ctl6.sensors.in_hazard:
			t_escape6 = i
			break
	_check(t_escape6 >= 0,
			"S6: escape override frees the AI in ~0.5s (t=%d)" % t_escape6)
	_check(attack_silenced,
			"S6: attack input silenced while pinned (armed, enemy in reach)")
	_check(float(hp6.current_health) >= 70.0,
			"S6: at most 2 spike hits during the pin (hp=%.0f)"
			% float(hp6.current_health))
	var t_fight6 := await _wait_until(func(): return _state_name(ctl6) == "Attack", 300)
	_check(t_fight6 >= 0, "S6: resumes the fight after escaping (t=%d, state=%s)"
			% [t_fight6, _state_name(ctl6)])
	ai6.queue_free()
	foe6.queue_free()
	await physics_frame
	_purge_weapons()
	await physics_frame

	# --- S7: map-scored weapon choice skips the in-hazard drop --------------------
	print("\n--- S7: weapon choice avoids the strip (+300 hazard score) ---")
	var sword_near = _drop_sword(inst, Vector2(320.0, 90.0))   # ON the spike strip
	var sword_far = _drop_sword(inst, Vector2(480.0, 90.0))    # safe mid-east floor
	# Settle BOTH onto the floor before the AI exists: a falling sword's origin
	# sits briefly above the hazard rect, so an early scan would score the near
	# one as safe and only flip on a later refresh. Settled first, the very
	# first scan makes the exact choice.
	await _ticks(20)
	var ai7 = _spawn_ai(inst, 240.0, 90.0, 0)
	var ctl7 = ai7.get_node("AIController")
	var hp7 = ai7.get_node("Components/Health")
	var t_seek7 := await _wait_until(func(): return _state_name(ctl7) == "SeekWeapon", 90)
	_check(t_seek7 >= 0, "S7: SeekWeapon entered (t=%d)" % t_seek7)
	var t_choice := await _wait_until(func(): return ctl7.sensors.best_weapon == sword_far, 90)
	_check(t_choice >= 0,
			"S7: near in-strip sword loses to the safe one (80+300 > 240, t=%d)" % t_choice)
	var t_armed7 := await _wait_until(func(): return ctl7.weapon_holder.is_holding_weapon(), 900)
	_check(t_armed7 >= 0, "S7: fetches the safe weapon across the strip (t=%d)" % t_armed7)
	_check(ctl7.weapon_holder.current_weapon == sword_far,
			"S7: holds the SAFE sword")
	_check(not sword_near.is_held(), "S7: the in-strip sword is never touched")
	_check(absf(float(hp7.current_health) - 100.0) < 0.01,
			"S7: strip crossed airborne, hp untouched (%.0f)"
			% float(hp7.current_health))
	ai7.queue_free()
	await physics_frame
	_purge_weapons()
	await physics_frame

	# --- S8: patrol never sets foot in a hazard segment ----------------------------
	print("\n--- S8: 8s of idle patrolling, strip untouched ---")
	var ai8 = _spawn_ai(inst, -300.0, 78.0, 0)
	var ctl8 = ai8.get_node("AIController")
	var hp8 = ai8.get_node("Components/Health")
	var t_patrol := await _wait_until(func(): return _state_name(ctl8) == "Patrol", 90)
	_check(t_patrol >= 0, "S8: Patrol entered with nothing to do (t=%d)" % t_patrol)
	var ever_hazard := false
	for i in 480:
		await physics_frame
		if ctl8.sensors.in_hazard:
			ever_hazard = true
	_check(not ever_hazard, "S8: never sets a foot in the strip while patrolling")
	_check(absf(float(hp8.current_health) - 100.0) < 0.01,
			"S8: patrol is damage-free (hp=%.0f)" % float(hp8.current_health))
	ai8.queue_free()
	await physics_frame
	_purge_weapons()
	await physics_frame

	# --- S9: hurt + unarmed: leaves Retreat once safe, goes and re-arms --------
	print("\n--- S9: unarmed low-HP retreat ends on distance ---")
	var ai9 = _spawn_ai(inst, -100.0, 78.0, 0)
	var ctl9 = ai9.get_node("AIController")
	var foe9 = _spawn_dummy(inst, -30.0, 78.0, 1)
	# On top of the raised block: never on the flight path, so only a real
	# fetch picks it up.
	_drop_sword(inst, Vector2(-160.0, -100.0))
	await physics_frame
	ai9.get_node("Components/Health").current_health = 25.0   # below the 40% health exit
	var t_ret9 := await _wait_until(func(): return _state_name(ctl9) == "Retreat", 120)
	_check(t_ret9 >= 0, "S9: retreats from the close threat (t=%d)" % t_ret9)
	await _ticks(30)
	foe9.global_position = Vector2(500.0, 78.0)
	var t_left9 := await _wait_until(func(): return _state_name(ctl9) != "Retreat", 120)
	_check(t_left9 >= 0, "S9: leaves Retreat once the threat is far, health still low (t=%d)"
			% t_left9)
	var t_armed9 := await _wait_until(func(): return ctl9.is_armed(), 600)
	_check(t_armed9 >= 0, "S9: goes and fetches the sword (t=%d, state=%s)"
			% [t_armed9, _state_name(ctl9)])
	ai9.queue_free()
	foe9.queue_free()
	await physics_frame
	_purge_weapons()
	await physics_frame

	# --- S10: ranged fire waits for the gun to come round ----------------------
	print("\n--- S10: shots after a target flip all fly on target ---")
	var ai10 = _spawn_ai(inst, -420.0, 78.0, 0)
	var ctl10 = ai10.get_node("AIController")
	var east10 = _spawn_dummy(inst, -150.0, 78.0, 1)
	var west10 = _spawn_dummy(inst, -640.0, 78.0, 0)
	_drop_weapon(inst, "res://Scenes/Weapons/Rifle.tscn", ai10.position + Vector2(-30.0, 0.0))
	var t_fight10 := await _wait_until(func(): return _state_name(ctl10) == "Attack" and ctl10.is_armed(), 400)
	_check(t_fight10 >= 0, "S10: shooting east first (t=%d)" % t_fight10)
	await _ticks(60)
	# The swap puts the new enemy BEHIND the gun. Aim-intent gating fired the
	# first shots mid-swing — one flew straight backwards.
	east10.get_node("Components/TeamMember").team_id = 0
	west10.get_node("Components/TeamMember").team_id = 1
	var seen10 := {}
	_new_projectiles(seen10)
	ctl10._on_team_changed({})
	var shots10 := 0
	var worst10 := 1.0
	for i in 150:
		await physics_frame
		for p in _new_projectiles(seen10):
			var v: Vector2 = p._velocity
			if v.length() <= 0.0:
				continue
			shots10 += 1
			var to_foe: Vector2 = (west10.global_position - ai10.global_position).normalized()
			worst10 = minf(worst10, v.normalized().dot(to_foe))
	_check(shots10 > 0, "S10: fires at the new enemy within 2.5s (%d shots)" % shots10)
	_check(worst10 > 0.9, "S10: every shot within ~25 degrees of the enemy (worst dot %.2f)"
			% worst10)
	ai10.queue_free()
	east10.queue_free()
	west10.queue_free()
	await physics_frame
	_purge_weapons()
	await physics_frame

	# --- S11: ranged in range but no lane: goes and finds one ------------------
	print("\n--- S11: blocked lane -> reposition -> hit ---")
	var ai11 = _spawn_ai(inst, -520.0, 78.0, 0)
	var ctl11 = ai11.get_node("AIController")
	_drop_weapon(inst, "res://Scenes/Weapons/Rifle.tscn", ai11.position + Vector2(-30.0, 0.0))
	var t_arm11 := await _wait_until(func(): return ctl11.is_armed(), 200)
	_check(t_arm11 >= 0, "S11: armed with the rifle (t=%d)" % t_arm11)
	# Atop the raised block: ~450px away (rifle reach 720) with the block's
	# body between them. The old Attack waited there forever, shot-less.
	var foe11 = _spawn_dummy(inst, -100.0, -110.0, 1)
	var t_hit11 := await _wait_until(func(): return _damage_taken(foe11) > 0.0, 600)
	_check(t_hit11 >= 0, "S11: finds a lane and lands a hit (t=%d, state=%s, x=%.0f)"
			% [t_hit11, _state_name(ctl11), ai11.position.x])
	# The route passes the spike strip: a goal flipping mid-hop as the lane
	# flickered carried the body into it (the dummy is unarmed — any damage
	# here is spikes).
	var hp11: float = float(ai11.get_node("Components/Health").current_health)
	_check(absf(hp11 - 100.0) < 0.01, "S11: no spike damage on the way (hp=%.0f)" % hp11)
	ai11.queue_free()
	foe11.queue_free()
	await physics_frame
	_purge_weapons()
	await physics_frame

	# --- S12: melee vs an enemy at a ledge lip ---------------------------------
	print("\n--- S12: ledge-lip enemy -> climb -> hit ---")
	var ai12 = _spawn_ai(inst, -520.0, 78.0, 0)
	var ctl12 = ai12.get_node("AIController")
	_drop_sword(inst, ai12.position + Vector2(-30.0, 0.0))
	var t_arm12 := await _wait_until(func(): return ctl12.is_armed(), 200)
	_check(t_arm12 >= 0, "S12: armed with the sword (t=%d)" % t_arm12)
	# The raised block's west lip (block = [-320, 0]). The old 2D stand-off
	# point fell off the lip onto the floor: the route "arrived" right under
	# the enemy and the AI parked there, 200px out of reach.
	var foe12 = _spawn_dummy(inst, -300.0, -110.0, 1)
	var t_hit12 := await _wait_until(func(): return _damage_taken(foe12) > 0.0, 720)
	_check(t_hit12 >= 0, "S12: climbs onto the ledge and lands a hit (t=%d, state=%s, ai=(%.0f, %.0f))"
			% [t_hit12, _state_name(ctl12), ai12.position.x, ai12.position.y])
	ai12.queue_free()
	foe12.queue_free()
	await physics_frame
	_purge_weapons()
	await physics_frame

	# --- S13: an armed retreat keeps facing the enemy ---------------------------
	print("\n--- S13: facing intent outranks move input ---")
	var ai13 = _spawn_ai(inst, -200.0, 78.0, 0)
	var ctl13 = ai13.get_node("AIController")
	_drop_weapon(inst, "res://Scenes/Weapons/Pistol.tscn", ai13.position + Vector2(-30.0, 0.0))
	var t_arm13 := await _wait_until(func(): return ctl13.is_armed(), 200)
	_check(t_arm13 >= 0, "S13: armed with the pistol (t=%d)" % t_arm13)
	ai13.get_node("Components/Health").current_health = 20.0
	var foe13 = _spawn_dummy(inst, -120.0, 78.0, 1)
	var t_ret13 := await _wait_until(func(): return _state_name(ctl13) == "Retreat", 120)
	_check(t_ret13 >= 0, "S13: low-HP armed AI retreats (t=%d)" % t_ret13)
	var away13 := 0
	var moving13 := 0
	for i in 120:
		await physics_frame
		if _state_name(ctl13) != "Retreat" or ctl13.facing_intent == 0.0:
			continue
		if ctl13.move_direction != 0.0:
			moving13 += 1
		if signf(ai13.facing_direction) != signf(ctl13.facing_intent):
			away13 += 1
	_check(moving13 > 30, "S13: actually moving while retreating (%d ticks)" % moving13)
	_check(away13 == 0, "S13: never turns its back on the enemy (%d ticks facing away)" % away13)
	ai13.queue_free()
	foe13.queue_free()
	await physics_frame
	_purge_weapons()
	await physics_frame

	inst.queue_free()
	await physics_frame


## S14 needs a lethal edge: ArenaFlat's floor islands sit over the KillZone.
func _probe_flat_kite() -> void:
	print("\n=== ArenaFlat: ledge-safe kiting ===")
	var inst = load("res://Scenes/Arenas/ArenaFlat.tscn").instantiate()
	root.add_child(inst)
	current_scene = inst
	await physics_frame
	await physics_frame
	for n in inst.get_tree().get_nodes_in_group("weapon_spawn_points"):
		if inst.is_ancestor_of(n):
			n.remove_from_group("weapon_spawn_points")
	_purge_weapons()
	await physics_frame

	# --- S14: kiting stops at the lip -------------------------------------------
	print("\n--- S14: ranged kite toward an island edge stops short ---")
	# Middle island = [-248, 186] at y_top 0; open pit east of 186.
	var ai14 = _spawn_ai(inst, 130.0, -50.0, 0)
	var ctl14 = ai14.get_node("AIController")
	var hp14 = ai14.get_node("Components/Health")
	_drop_weapon(inst, "res://Scenes/Weapons/Pistol.tscn", ai14.position + Vector2(-30.0, 0.0))
	var t_arm14 := await _wait_until(func(): return ctl14.is_armed(), 200)
	_check(t_arm14 >= 0, "S14: armed with the pistol (t=%d)" % t_arm14)
	# Crowding from the west, inside half the pistol stand-off: kite east.
	var foe14 = _spawn_dummy(inst, ai14.position.x - 90.0, -50.0, 1)
	var died14 := [false]
	hp14.died.connect(func(): died14[0] = true)
	var kited14 := 0
	var max_x14 := -INF
	for i in 180:
		await physics_frame
		if died14[0]:
			break
		max_x14 = maxf(max_x14, ai14.position.x)
		if _state_name(ctl14) == "Attack" and ctl14.move_direction > 0.5:
			kited14 += 1
	_check(kited14 > 0, "S14: kites away from the crowding enemy (%d ticks)" % kited14)
	_check(not died14[0] and max_x14 < 186.0,
			"S14: stops at the lip instead of backing into the pit (max x=%.0f, died=%s)"
			% [max_x14, died14[0]])
	ai14.queue_free()
	foe14.queue_free()
	await physics_frame
	_purge_weapons()
	await physics_frame
	inst.queue_free()
	await physics_frame