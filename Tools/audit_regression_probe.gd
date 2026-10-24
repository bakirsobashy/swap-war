extends SceneTree

## Regression probe for the 2026-10-23 audit (docs/godot-prompter/plans/AUDIT_REPORT_2026-10.md).
## Boots real matches the way the menu does (change_scene_to_file ->
## ArenaManager.scene_changed) and replays each reproduced bug.
##   FIXED checks fail the probe (exit 1) if the bug comes back.
##   KNOWN checks report bugs that are still open and never fail the probe;
##   when one prints "now fixed", promote it to a _check.
## Probe discipline: runtime access only, untyped vars, no game-class
## annotations, autoloads via /root paths. Wall-clock waits use timers
## (headless process frames are uncapped).

var am = null
var tm = null
var sm = null
var settings = null
var audio = null
var _fails := 0
var _known_open := 0

func _init() -> void:
	call_deferred("_run")

func _check(name: String, ok: bool, detail: String) -> void:
	print("  %s: %s (%s)" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		_fails += 1

func _known(name: String, still_broken: bool, detail: String) -> void:
	if still_broken:
		_known_open += 1
		print("  KNOWN (open): %s (%s)" % [name, detail])
	else:
		print("  KNOWN -> now fixed, promote to a check: %s (%s)" % [name, detail])

func _physics(n: int) -> void:
	for i in n:
		await physics_frame

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _press(action: String, pressed: bool) -> void:
	var ev = InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _key(code: int, pressed: bool) -> void:
	var ev = InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _state_name(ai) -> String:
	var ctl = ai.get_node("AIController")
	if ctl.machine == null or ctl.machine.current_state == null:
		return "?"
	return ctl.machine.current_state.get_name()

func _actors(scene) -> Array:
	var out: Array = []
	for a in scene.get_node("Actors").get_children():
		if not a.is_queued_for_deletion():
			out.append(a)
	return out

func _equip(scene, actor, path: String):
	var holder = actor.get_node("WeaponHolder")
	if holder.current_weapon != null:
		holder.drop_weapon(false)
	var w = load(path).instantiate()
	scene.add_child(w)
	w.global_position = actor.global_position + Vector2(0, -300)
	await _physics(2)
	holder._equip_weapon(w)
	await _physics(3)
	return w

func _run() -> void:
	am = root.get_node_or_null("/root/ArenaManager")
	tm = root.get_node_or_null("/root/TeamManager")
	sm = root.get_node_or_null("/root/ScoreManager")
	settings = root.get_node_or_null("/root/SettingsManager")
	audio = root.get_node_or_null("/root/AudioManager")
	# Direct property sets only — the setters persist to the user's config.
	settings.win_mode = 0
	settings.ai_count = 3
	settings.score_target = 10
	settings.match_duration_seconds = 120.0
	settings.auto_attack_enabled = false

	print("--- match A: ArenaHazards, score target ---")
	change_scene_to_file("res://Scenes/Arenas/ArenaHazards.tscn")
	await _frames(6)
	var scene = current_scene
	var hud = scene.get_node("HUD")
	var player = null
	var ais: Array = []
	for a in _actors(scene):
		if a.is_player:
			player = a
		else:
			ais.append(a)

	# Countdown banner
	var wm = hud.get_node("%WinnerMessage")
	_check("countdown banner has no WINS!", wm.text.begins_with("START IN") and not wm.text.contains("WINS"),
			"'%s'" % wm.text)

	# Health bars follow the team colour
	await _frames(2)
	var bad_bars := 0
	for a in _actors(scene):
		var fill = a.get_node("HealthBar2D/SubViewport/Fill")
		if not fill.color.is_equal_approx(a.get_node("Components/Health")._team_color()):
			bad_bars += 1
	_check("health bars match team colour", bad_bars == 0, "%d mismatched" % bad_bars)

	# Health nodes in the "actors" group (direct-run startup order emulated)
	var before_regs: int = tm._teams.size()
	tm._register_existing_actors()
	await _frames(2)
	var extra: int = tm._teams.size() - before_regs
	_known("Health nodes register as actors on direct arena runs", extra > 0, "+%d registrations" % extra)
	for k in tm._teams.keys().duplicate():
		if String(k.name) == "Health":
			tm.unregister_actor(k)
	await _frames(2)

	await create_timer(3.6).timeout
	_check("countdown reaches PLAYING", am._state == 2, "state=%d" % am._state)

	# Esc pauses and unpauses during play
	_key(KEY_ESCAPE, true)
	await _frames(3)
	_key(KEY_ESCAPE, false)
	await _frames(2)
	var paused_by_esc: bool = paused
	_key(KEY_ESCAPE, true)
	await _frames(3)
	_key(KEY_ESCAPE, false)
	await _frames(2)
	_check("Esc opens and closes the pause menu", paused_by_esc and not paused,
			"after 1st Esc paused=%s, after 2nd=%s" % [paused_by_esc, paused])
	if paused:
		scene.get_node("PauseMenu").visible = false
		paused = false
		await _frames(2)

	tm._swap_timer.stop()

	# Touch DROP works repeatedly; Drop_Weapon never stays held
	var holder = player.get_node("WeaponHolder")
	var drop_btn = hud.get_node("TouchControls/%DropButton")
	var drops_ok := 0
	for i in 2:
		await _equip(scene, player, "res://Scenes/Weapons/Sword.tscn")
		var held = holder.current_weapon
		# What a finger does to a TouchScreenButton with an action set.
		_press(String(drop_btn.action), true)
		await _physics(4)
		_press(String(drop_btn.action), false)
		await _physics(4)
		if holder.current_weapon != held:
			drops_ok += 1
		await create_timer(0.7).timeout
	_check("touch DROP works every time", drops_ok == 2 and not Input.is_action_pressed("Drop_Weapon"),
			"%d/2 drops, still held=%s" % [drops_ok, Input.is_action_pressed("Drop_Weapon")])
	if holder.current_weapon != null:
		holder.drop_weapon(false)

	# Hazard damage keeps the enemy's kill credit
	var a1 = ais[0]
	var b1 = ais[1]
	tm.set_team(a1, 1)
	tm.set_team(b1, 2)
	var hazard = scene.get_node("World/Hazards/SpikeStrip")
	var bh = b1.get_node("Components/Health")
	var a_before: int = sm.get_score(a1)
	bh.take_damage(10.0, a1)
	hazard._cooldowns.clear()
	bh.current_health = 5.0
	hazard._cooldowns[b1.get_instance_id()] = 0.0
	b1.global_position = hazard.global_position + Vector2(0, -20)
	var waited := 0
	while not bh.is_dead() and waited < 120:
		await physics_frame
		waited += 1
	await _frames(2)
	_check("spikes finish off the victim", bh.is_dead(), "died after %d ticks" % waited)
	_check("hazard never scores", not sm._scores.has(hazard), "hazard registered=%s" % sm._scores.has(hazard))
	_check("attacker gets the kill", sm.get_score(a1) == a_before + 1, "score %d -> %d" % [a_before, sm.get_score(a1)])

	# Respawn starts at rest
	var c1 = ais[2]
	var ch = c1.get_node("Components/Health")
	c1.linear_velocity = Vector2(250.0, 900.0)
	ch.die()
	while ch.is_dead():
		await physics_frame
	await _physics(1)
	_check("respawn clears death velocity", c1.linear_velocity.length() < 60.0, "v=%s" % c1.linear_velocity)
	while bh.is_dead():
		await physics_frame
	await create_timer(1.6).timeout   # let respawn invulnerability lapse

	# Hits on invulnerable targets
	tm.set_team(a1, 1)
	tm.set_team(b1, 2)
	var sword = await _equip(scene, a1, "res://Scenes/Weapons/Sword.tscn")
	bh._invulnerability_timer = 1.5
	var dur: int = sword.current_durability
	sword._recent_hits.clear()
	sword._on_body_entered(b1)
	await _physics(1)
	_known("hits on invulnerable targets cost durability", sword.current_durability < dur,
			"durability %d -> %d" % [dur, sword.current_durability])
	bh._invulnerability_timer = 0.0

	# Swing vs an enemy already touching the blade
	tm.set_team(c1, 2)
	c1.freeze = true
	a1.freeze = true
	await _physics(2)
	c1.global_position = a1.global_position + Vector2(70.0 * a1.facing_direction, 0.0)
	await _physics(40)
	var hp_mid: float = ch.current_health
	for i in 4:
		sword._attack_cooldown_timer = 0.0
		sword.attack()
		await _physics(40)
	_known("swings never re-hit an overlapping enemy", is_equal_approx(ch.current_health, hp_mid),
			"hp %.0f -> %.0f over 4 swings" % [hp_mid, ch.current_health])
	c1.freeze = false
	a1.freeze = false
	a1.get_node("WeaponHolder").drop_weapon(false)

	# Landing sound right after a jump
	for o in ais:
		o.get_node("AIController").is_ai = false
	await create_timer(1.0).timeout
	var land_clips: Array = audio._land_variants.duplicate()
	if audio.land_sound:
		land_clips.append(audio.land_sound)
	var seen: Dictionary = {}
	for n in audio.get_children():
		seen[n.get_instance_id()] = true
	_press("Jump", true)
	var early_land := false
	for tick in 5:
		await physics_frame
		if tick == 1:
			_press("Jump", false)
		for n in audio.get_children():
			if seen.has(n.get_instance_id()):
				continue
			seen[n.get_instance_id()] = true
			if n is AudioStreamPlayer and land_clips.has(n.stream):
				early_land = true
	_known("landing sound plays right after every jump", early_land, "land sfx within 5 ticks=%s" % early_land)
	for o in ais:
		o.get_node("AIController").is_ai = true

	# Timed tie goes to the first-registered actor (the player)
	var saved: Dictionary = sm._scores.duplicate()
	for k in sm._scores.keys():
		sm._scores[k] = 0
	sm._scores[player] = 3
	sm._scores[ais[1]] = 3
	var leader = sm.get_leader()
	_known("score ties crown the player", leader == player, "leader=%s" % (leader.name if leader else "none"))
	for k in saved.keys():
		if sm._scores.has(k):
			sm._scores[k] = saved[k]

	# Low-HP armed AI stuck in Retreat
	var x = ais[1]
	for o in ais:
		tm.set_team(o, 1)
	tm.set_team(player, 2)
	var xh = x.get_node("Components/Health")
	xh.current_health = 25.0
	await _equip(scene, x, "res://Scenes/Weapons/Spear.tscn")
	player.freeze = true
	player.global_position = x.global_position + Vector2(100.0, -10.0)
	await create_timer(1.0).timeout
	var s1 := _state_name(x)
	player.global_position.x = x.global_position.x + (600.0 if x.global_position.x < 0.0 else -600.0)
	await create_timer(4.0).timeout
	_known("low-HP AI never leaves Retreat", s1 == "Retreat" and _state_name(x) == "Retreat",
			"%s -> %s" % [s1, _state_name(x)])
	player.freeze = false

	# Play Again keeps the old weapons
	scene.get_node("WeaponSpawner")._spawn_wave()
	await _physics(3)
	var w_before: int = get_nodes_in_group("weapons").size()
	am.restart_match()
	await _physics(6)
	var w_after: int = get_nodes_in_group("weapons").size()
	_known("Play Again keeps last match's weapons", w_before > 0 and w_after >= w_before,
			"%d -> %d" % [w_before, w_after])
	await create_timer(3.6).timeout

	# Post-round title uses raw node names
	var winner = null
	for a in _actors(scene):
		if not a.is_player:
			winner = a
			break
	sm.add_score(winner, 10)
	await _frames(2)
	var title: String = scene.get_node("PostRoundMenu").get_node("%Title").text
	_known("post-round shows raw node names", title.begins_with("@"), "'%s'" % title)
	paused = false
	await _frames(2)

	print("--- match B: ArenaFlat, timed, quit to menu ---")
	settings.win_mode = 1
	settings.match_duration_seconds = 6.0
	settings.ai_count = 1
	change_scene_to_file("res://Scenes/Arenas/ArenaFlat.tscn")
	await _frames(6)
	await create_timer(3.6).timeout
	current_scene.get_node("PauseMenu")._on_quit_to_menu_pressed()
	await _frames(6)
	await create_timer(8.0).timeout
	_known("timed match keeps running in the main menu", am._state == 3,
			"ArenaManager state in menu=%d" % am._state)

	print("=== audit_regression_probe: %s (%d known open) ===" % ["ALL PASS" if _fails == 0 else "%d FAILED" % _fails, _known_open])
	quit(1 if _fails > 0 else 0)
