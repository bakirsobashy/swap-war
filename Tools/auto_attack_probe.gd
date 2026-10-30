extends SceneTree

## Headless probe for the Auto Attack setting (melee + ranged halves).
##
##   A. Melee auto-swing: with Auto Attack on, the player AIMED at a hostile
##      60 px away (aim stick held toward it — Auto Attack never aims for
##      you) swings on the sword's own cooldown (rising edges of
##      is_attacking). The gate is MeleeWeapon.can_hit: in reach, facing it,
##      the blade on it.
##   B. Negatives — no swing while aiming AWAY from the hostile (and the aim
##      stays where the player put it: no snap onto the target), when the
##      enemy is beyond the sword's reach, when the setting is off, when the
##      nearby actor is an ALLY, or when it is dead.
##   C. Ranged is touch-only — a pistol never auto-fires without the aim
##      stick (PC = mouse + click), fires while the stick is deflected
##      (durability = magazine), and stops shortly after release.
##   D. Aim channel — a held stick steers aim_direction; after release on
##      this touchless headless run the hold-last guard (_is_touch_input_recent)
##      is false, so aim must return to the mouse fallback instead of
##      sticking to the old stick direction. (Hold-last on real touch
##      hardware is manual-checklist item 4.)
##
## The player is NEVER frozen (frozen bodies skip _integrate_forces — that is
## where attack input is consumed); only the dummies are frozen (they ignore
## knockback). Dummy max_health is raised so the pacing window cannot kill it.
##
## HEADLESS CAVEAT: parsed InputEventScreenTouch events do NOT dispatch to
## Node._input under the headless display server (verified empirically), so
## the aim-stick touch events are fed directly to both sticks' handlers —
## the engine's broadcast is reproduced, and everything downstream (capture,
## deadzone, aim value, Actor-Movement consumption) is the real code.
##
## `-s` discipline: runtime load() only, untyped vars, no game-class
## annotations, no direct autoload references (guarded node-path access is
## fine). Settings are written via DIRECT property assignment — the setters
## persist to user://swap_war_settings.cfg and a probe must never clobber the
## developer's config. Manual add_child + current_scene assignment keeps
## ArenaManager's scene_changed hook out of the way (probes are invisible to
## the match flow).

var _fails: int = 0
var _sticks: Array = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# ArenaHazards, NOT ArenaFlat: live actors provably rest on this floor
	# (hazard_damage_probe/decision_probe spawn live actors here), while a
	# live actor spawned on ArenaFlat's current floor sinks straight
	# through it into the KillZone — a pre-existing Flat issue this probe
	# surfaced; auto-attack is the subject here, not that.
	var inst: Node = (load("res://Scenes/Arenas/ArenaHazards.tscn") as PackedScene).instantiate()
	root.add_child(inst)
	current_scene = inst
	await physics_frame
	await physics_frame

	# Probe discipline: stop the team-swap timer (teams must stay put) and
	# purge the weapons group between scenarios.
	var team_manager = root.get_node_or_null("/root/TeamManager")
	if team_manager:
		for ch in team_manager.get_children():
			if ch is Timer:
				ch.stop()
	var settings = root.get_node_or_null("/root/SettingsManager")
	_check(settings != null, "setup: SettingsManager autoload present")
	if settings:
		settings.touch_controls_mode = 1      # ALWAYS — direct set, no save
		settings.auto_attack_enabled = true
	var tc: Node = inst.get_node("HUD/TouchControls")
	tc._visibility_changed()
	_sticks = [tc.get_node("%MoveStick"), tc.get_node("%AimStick")]

	await _probe(inst, settings, tc)

	var verdict := "ALL PASS"
	if _fails > 0:
		verdict = "%d FAILURES" % _fails
	print("\n=== auto_attack_probe: %s ===" % verdict)
	quit(1 if _fails > 0 else 0)

func _check(ok: bool, what: String) -> void:
	print("  %s: %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1

## Spawn an actor with AI off (never a second brain in a probe), optional
## player flag, inflated health, and a fixed team. Set BEFORE add_child so
## _ready reads the intended values (AIController self-disables on players,
## Health seeds current_health from max_health).
func _spawn(inst: Node, x: float, y: float, team: int, is_player: bool) -> Node:
	var actor: Node = (load("res://Scenes/actor.tscn") as PackedScene).instantiate()
	actor.get_node("AIController").is_ai = false
	if is_player:
		actor.is_player = true
	actor.get_node("Components/Health").max_health = 1000.0
	actor.position = Vector2(x, y)
	inst.get_node("Actors").add_child(actor)
	# team_id AFTER add_child: the team-change flash needs get_tree(), which
	# errors on out-of-tree nodes. The deferred TeamManager registration
	# still picks the right team (it reads team_id when it runs).
	actor.get_node("Components/TeamMember").team_id = team
	return actor

func _equip(inst: Node, holder: Node, scene_path: String) -> Node:
	var weapon: Node = (load(scene_path) as PackedScene).instantiate()
	inst.get_node("Actors").add_child(weapon)
	await physics_frame
	await physics_frame
	holder._on_pickup_body_entered(weapon)
	return weapon

func _touch(index: int, pressed: bool, pos: Vector2) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = pressed
	ev.position = pos
	for stick in _sticks:
		stick._input(ev)
	await process_frame

func _drag(index: int, pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	for stick in _sticks:
		stick._input(ev)
	await process_frame

func _settle() -> void:
	# Let any in-flight swing window (attack_thrust_duration 0.2 s) expire
	# after a state change so the calm checks measure only NEW swings.
	for i in 24:                      # 0.4 s
		await physics_frame

func _probe(inst: Node, settings, tc: Node) -> void:
	# ArenaHazards: floor top at y = 128 (hazard probe's live actors rest at
	# ~y 78); spawn WEST of the spike strip ([288,352]) so nothing takes
	# hazard damage during the scenarios.
	var player: Node = _spawn(inst, -400.0, 78.0, 0, true)
	var dummy: Node = _spawn(inst, -460.0, 78.0, 1, false)
	dummy.freeze = true
	await physics_frame
	var holder: Node = player.get_node("WeaponHolder")
	var sword: Node = await _equip(inst, holder, "res://Scenes/Weapons/Sword.tscn")
	_check(holder.current_weapon == sword, "A: player armed with the sword")

	print("\n=== A: melee auto-swing at the hostile you aim at ===")
	# Aim with the stick: the headless mouse sits top-left of the screen, so
	# the mouse fallback would point the blade up-left, off the dummy.
	var aim_stick = tc.get_node("%AimStick")
	var stick_span: float = aim_stick.MAX_DEFLECTION * aim_stick.scale.x
	await _touch(1, true, aim_stick.position)
	await _drag(1, aim_stick.position + Vector2(-1.0, 0.0) * stick_span)   # west, at the dummy
	var swung := false
	for i in 60:                      # 1 s: the blade turns onto the dummy first
		await physics_frame
		if sword.is_attacking():
			swung = true
			break
	_check(swung, "A: auto-swings when the blade is on a hostile at 60 px")
	var edges := 0
	var last := false
	var freed_tick := -1
	for i in 96:                      # 1.6 s
		await physics_frame
		if not is_instance_valid(sword):
			freed_tick = i
			break
		var now_attacking: bool = sword.is_attacking()
		if now_attacking and not last:
			edges += 1
		last = now_attacking
	_check(freed_tick == -1, "A: sword survives the pacing window")
	_check(edges >= 2 and edges <= 4,
			"A: swing pacing 2-4 rising edges in 1.6 s (cooldown 0.5, got %d)" % edges)

	print("\n=== B: negatives ===")
	# Aim AWAY (east) with the dummy 60 px west: facing flips with the aim at
	# once, so no swing even while the blade turns — and no snap back.
	await _drag(1, aim_stick.position + Vector2(1.0, 0.0) * stick_span)
	await _settle()                   # let any in-flight swing window expire
	var calm := true
	for i in 48:                      # 0.8 s > cooldown
		await physics_frame
		if sword.is_attacking():
			calm = false
	_check(calm, "B: no swing while aiming away from the hostile")
	_check(player.aim_direction.x > 0.9,
			"B: Auto Attack leaves the aim alone (no snap onto the dummy, got %s)"
			% player.aim_direction)
	await _drag(1, aim_stick.position + Vector2(-1.0, 0.0) * stick_span)   # back at the dummy

	dummy.global_position = player.global_position + Vector2(-200.0, 0.0)
	await _settle()
	calm = true
	for i in 48:
		await physics_frame
		if sword.is_attacking():
			calm = false
	_check(calm, "B: no swing beyond the sword's reach (dummy at 200 px)")

	dummy.global_position = player.global_position + Vector2(-60.0, 0.0)
	if settings:
		settings.auto_attack_enabled = false
	await _settle()
	calm = true
	for i in 48:
		await physics_frame
		if sword.is_attacking():
			calm = false
	_check(calm, "B: no swing with Auto Attack OFF")
	if settings:
		settings.auto_attack_enabled = true

	dummy.get_node("Components/TeamMember").team_id = 0
	await _settle()
	calm = true
	for i in 48:
		await physics_frame
		if sword.is_attacking():
			calm = false
	_check(calm, "B: no swing at an ALLY (teams re-shuffle mid-match)")
	dummy.get_node("Components/TeamMember").team_id = 1
	await _settle()                   # a swing may legitimately fire here

	dummy.get_node("Components/Health").die()
	await _settle()
	calm = true
	for i in 48:
		await physics_frame
		if sword.is_attacking():
			calm = false
	_check(calm, "B: no swing at a dead actor")
	dummy.queue_free()
	await _touch(1, false, aim_stick.position)
	await physics_frame

	print("\n=== C: ranged auto-fire is touch-only ===")
	holder.drop_weapon(false)          # death path: no auto-pick of the sword
	var pistol: Node = await _equip(inst, holder, "res://Scenes/Weapons/Pistol.tscn")
	_check(holder.current_weapon == pistol, "C: player armed with the pistol")
	var d0: int = pistol.current_durability
	var stable := true
	for i in 48:                      # 0.8 s
		await physics_frame
		if pistol.current_durability != d0:
			stable = false
	_check(stable, "C: no auto-fire without the aim stick (PC = mouse + click)")

	await _touch(1, true, aim_stick.position)
	# Drag off-center — a bare press at the center is inside the deadzone.
	await _drag(1, aim_stick.position + Vector2(0.7, -0.7) * (aim_stick.MAX_DEFLECTION * aim_stick.scale.x))
	var aim_val: Vector2 = tc.get_aim_stick_value()
	_check(aim_val.length_squared() > 0.0,
			"C: aim stick value flows to the consumer surface")
	var before: int = pistol.current_durability
	for i in 90:                      # 1.5 s held (cooldown 0.35 -> ~4 shots)
		await physics_frame
	var fired: int = before - pistol.current_durability
	_check(fired >= 2 and fired <= 6,
			"C: auto-fires while the aim stick is held (durability %d -> %d)"
			% [before, pistol.current_durability])

	await _touch(1, false, aim_stick.position)
	var after_release: int = pistol.current_durability
	stable = true
	for i in 42:                      # 0.7 s > cooldown 0.35
		await physics_frame
		if pistol.current_durability != after_release:
			stable = false
	_check(stable, "C: firing stops shortly after the stick is released")

	print("\n=== D: aim channel + hold-last guard ===")
	# The stick is driven DOWN-RIGHT deliberately: with the arena camera, the
	# headless mouse sits at the screen's top-left corner, so the mouse
	# fallback aims up-left — driving the stick up-left too would make the
	# two indistinguishable (dot ~0.96). Down-right separates them (~-0.96).
	await _touch(1, true, aim_stick.position)
	await _drag(1, aim_stick.position + Vector2(0.7, 0.7) * (aim_stick.MAX_DEFLECTION * aim_stick.scale.x))
	await process_frame
	var stick_aim: Vector2 = player.aim_direction
	_check(stick_aim.dot(Vector2(1.0, 1.0).normalized()) > 0.9,
			"D: held stick steers aim down-right (got %s)" % stick_aim)
	await _touch(1, false, aim_stick.position)
	await process_frame
	var after_aim: Vector2 = player.aim_direction
	_check(after_aim.dot(stick_aim) < 0.5,
			"D: on a touchless run aim hands back to the mouse fallback after release (got %s)" % after_aim)

	inst.queue_free()
	await physics_frame