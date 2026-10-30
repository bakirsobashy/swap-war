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
	_check("countdown banner has no WINS!", (wm.text.is_valid_int() or wm.text == "GO!") and not wm.text.contains("WINS"),
			"'%s'" % wm.text)

	# Health bars follow the team colour
	await _frames(2)
	var bad_bars := 0
	for a in _actors(scene):
		var fill_color: Color = a.get_node("HealthBar2D").get_fill_color()
		if not fill_color.is_equal_approx(a.get_node("Components/Health")._team_color()):
			bad_bars += 1
	_check("health bars match team colour", bad_bars == 0, "%d mismatched" % bad_bars)

	# Health nodes in the "actors" group (direct-run startup order emulated)
	var before_regs: int = tm._teams.size()
	tm._register_existing_actors()
	await _frames(2)
	var extra: int = tm._teams.size() - before_regs
	_check("only actor bodies register as actors (direct-run path)", extra == 0, "+%d registrations" % extra)

	# Display names: the player is YOU, AIs get real names (no @RigidBody2D@N)
	var names: Array = []
	for a in _actors(scene):
		names.append(String(a.name))
	var named_ok: bool = String(player.name) == "YOU"
	for n in names:
		if n.begins_with("@"):
			named_ok = false
	_check("actors carry display names", named_ok, "%s" % [names])

	# Two-team guarantee: with 2 actors no roll may put both on one team
	var pair: Array = [player, ais[0]]
	var saved_teams: Dictionary = tm._teams.duplicate()
	var saved_sfx = audio.sfx_enabled
	audio.sfx_enabled = false
	tm._teams.clear()
	for a in pair:
		tm._teams[a] = 0
	var same := 0
	for i in 200:
		tm.randomize_teams()
		if tm.get_team(pair[0]) == tm.get_team(pair[1]):
			same += 1
	tm._teams = saved_teams
	for a in saved_teams.keys():
		tm.set_team(a, saved_teams[a])
	audio.sfx_enabled = saved_sfx
	_check("a swap never leaves everyone allied", same == 0, "%d/200 rolls all-same-team" % same)

	await create_timer(3.6).timeout
	_check("countdown reaches PLAYING", am._state == 2, "state=%d" % am._state)
	await _physics(4)
	_check("weapons drop at GO", get_nodes_in_group("weapons").size() > 0,
			"%d weapons at match start" % get_nodes_in_group("weapons").size())

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
	# Quiet arena from here on: the GO wave arms the AIs at once, and live
	# fights cost durability, steal kills and shove test actors around.
	# Scenarios that need an AI brain switch that one AI back on.
	for i in ais.size():
		var o = ais[i]
		o.get_node("AIController").is_ai = false
		o.get_node("AIController").move_direction = 0.0
		o.get_node("AIController").wants_attack = false
		# Park the living AIs on the west floor at full health: frozen where
		# the GO fight left it, an AI could stand brushing the spike strip and
		# bleed out during the quiet tests — the kill-credit victim was then
		# already dead when its scenario began (flaky "attacker gets the kill").
		var oh = o.get_node("Components/Health")
		if not oh.is_dead():
			oh.current_health = oh.max_health
			o.global_position = Vector2(-450.0 + 80.0 * i, 78.0)
			o.linear_velocity = Vector2.ZERO
	for a in _actors(scene):
		var wh = a.get_node("WeaponHolder")
		if wh.current_weapon != null:
			wh.drop_weapon(false)
	for w in get_nodes_in_group("weapons"):
		w.queue_free()
	await create_timer(1.0).timeout

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
	# _try_hit is the swing's per-body strike (melee only damages while
	# swinging — the probe calls the strike directly). It marks the victim
	# just before take_damage, so the mark proves the hit got that far and
	# the durability check isn't vacuous.
	sword._try_hit(b1)
	await _physics(1)
	_check("hits on invulnerable targets cost nothing",
			sword._hit_this_swing.has(b1) and sword.current_durability == dur,
			"reached take_damage=%s, durability %d -> %d"
			% [sword._hit_this_swing.has(b1), dur, sword.current_durability])
	bh._invulnerability_timer = 0.0

	# Swing vs an enemy already touching the blade
	tm.set_team(c1, 2)
	c1.freeze = true
	a1.freeze = true
	await _physics(2)
	# Put the enemy where the blade actually points (with its brain off the
	# AI's aim is stale, so facing_direction is not a reliable guide).
	var blade_dir: Vector2 = (sword.global_position - a1.global_position).normalized()
	c1.global_position = a1.global_position + blade_dir * 70.0
	await _physics(40)
	var touching: bool = sword.get_node("HitBox").get_overlapping_bodies().has(c1)
	_check("swing test setup: enemy is touching the blade", touching, "dir=%s" % blade_dir)
	var hp_mid: float = ch.current_health
	for i in 4:
		sword._attack_cooldown_timer = 0.0
		sword.attack()
		await _physics(40)
	_check("swings hit an enemy already touching the blade", ch.current_health < hp_mid or ch.is_dead(),
			"hp %.0f -> %.0f over 4 swings" % [hp_mid, ch.current_health])
	c1.freeze = false
	a1.freeze = false
	a1.get_node("WeaponHolder").drop_weapon(false)

	# Landing sound right after a jump: the takeoff tick used to read as a
	# landing (ground contacts linger). Assert on the PLAYER's own ground
	# state — land sounds from other actors would make an audio check noisy.
	for o in ais:
		o.get_node("AIController").is_ai = false
	var ph = player.get_node("Components/Health")
	while ph.is_dead():
		await physics_frame
	var settle := 0
	while (not player.is_grounded() or absf(player.linear_velocity.y) > 5.0) and settle < 300:
		await physics_frame
		settle += 1
	var grounded_before: bool = player.is_grounded()
	_press("Jump", true)
	var relanded := false
	var lifted := false
	for tick in 6:
		await physics_frame
		if tick == 1:
			_press("Jump", false)
		if not player.is_grounded():
			lifted = true
		elif lifted and player.linear_velocity.y < -50.0:
			relanded = true   # "grounded" while still rising = false landing
	_check("no false landing right after a jump", grounded_before and lifted and not relanded,
			"grounded before=%s, lifted=%s, false landing=%s" % [grounded_before, lifted, relanded])

	# Knockback is no longer clipped to run speed
	var kb = ais[0]
	await create_timer(0.5).timeout
	# Open air, clear of blocks and walls, so geometry can't eat the launch.
	kb.global_position = Vector2(-300.0, -320.0)
	kb.linear_velocity = Vector2.ZERO
	await _physics(2)
	kb.apply_knockback(Vector2(600.0, -100.0))
	var peak := 0.0
	for i in 4:
		await physics_frame
		peak = maxf(peak, absf(kb.linear_velocity.x))
	_check("knockback launches past run speed", peak > 350.0, "peak vx after a 600 hit = %.0f" % peak)

	# Timed tie goes to the first-registered actor (the player)
	var saved: Dictionary = sm._scores.duplicate()
	for k in sm._scores.keys():
		sm._scores[k] = 0
	sm._scores[player] = 3
	sm._scores[ais[1]] = 3
	var leader = sm.get_leader()
	_check("a tie at the top has no single leader", leader == null,
			"leader=%s, leaders=%d" % [(leader.name if leader else "none"), sm.get_leaders().size()])
	for k in saved.keys():
		if sm._scores.has(k):
			sm._scores[k] = saved[k]

	# Low-HP armed AI: Retreat must time out (nothing heals, so the health
	# exit can never fire) and lock out re-retreating for a while.
	var x = ais[1]
	var xc = x.get_node("AIController")
	for o in ais:
		tm.set_team(o, 1)
	tm.set_team(player, 2)
	var xh = x.get_node("Components/Health")
	xh.current_health = 25.0
	xh._invulnerability_timer = 10.0   # fleeing over the spikes must not kill it mid-test
	await _equip(scene, x, "res://Scenes/Weapons/Spear.tscn")
	player.freeze = true
	# The other AIs (enemies of the player) would otherwise kill the frozen
	# threat, which ends the retreat early for the wrong reason.
	var player_h = player.get_node("Components/Health")
	while player_h.is_dead():                # a dead threat is no threat
		await physics_frame
	player_h._invulnerability_timer = 10.0
	await _physics(2)
	xc.is_ai = true
	xc.sensors.invalidate_targets()
	await create_timer(0.4).timeout          # sensors re-acquire the player
	xc.machine.transition_to("Retreat")
	var max_lockout := 0.0
	var left_retreat_at := -1.0
	var t := 0.0
	while t < 6.5:
		await create_timer(0.1).timeout
		t += 0.1
		max_lockout = maxf(max_lockout, xc.retreat_lockout)
		if left_retreat_at < 0.0 and _state_name(x) != "Retreat":
			left_retreat_at = t
	_check("low-HP AI stops fleeing after the retreat timeout",
			max_lockout > 0.0 and left_retreat_at >= 4.5,
			"left Retreat after %.1f s, peak lockout %.1f s, hp %.0f" % [left_retreat_at, max_lockout, xh.current_health])
	player.freeze = false

	# Play Again keeps the old weapons
	scene.get_node("WeaponSpawner")._spawn_wave()
	await _physics(3)
	var w_before: int = get_nodes_in_group("weapons").size()
	am.restart_match()
	await _physics(6)
	var w_after: int = get_nodes_in_group("weapons").size()
	_check("Play Again clears the last match's weapons", w_before > 0 and w_after == 0,
			"%d -> %d" % [w_before, w_after])
	var restart_names: Array = []
	for a in _actors(scene):
		restart_names.append(String(a.name))
	_check("names survive Play Again", restart_names.has("YOU") and not str(restart_names).contains("@"),
			"%s" % [restart_names])
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
	_check("post-round names the winner", title == "%s WINS!" % String(winner.name).to_upper(), "'%s'" % title)
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
	_check("leaving the arena stops the match", am._state == 0,
			"ArenaManager state in menu=%d (0 = IDLE)" % am._state)

	print("--- match C: ArenaFlat, timed tie -> sudden death ---")
	settings.win_mode = 1
	settings.match_duration_seconds = 4.0
	settings.ai_count = 1
	change_scene_to_file("res://Scenes/Arenas/ArenaFlat.tscn")
	await _frames(6)
	tm._swap_timer.stop()
	var duel: Array = _actors(current_scene)
	for a in duel:   # keep it 0-0: no AI, no damage
		a.get_node("Components/Health")._invulnerability_timer = 30.0
		if not a.is_player:
			a.get_node("AIController").is_ai = false
	await create_timer(3.6 + 4.5).timeout   # countdown + clock, nobody scored
	var sd: bool = am._sudden_death and am._state == 2
	_check("timed tie goes to sudden death", sd, "sudden_death=%s state=%d" % [am._sudden_death, am._state])
	if sd:
		sm.add_score(duel[1], 1)
		await _frames(2)
		var t2: String = current_scene.get_node("PostRoundMenu").get_node("%Title").text
		_check("first kill in sudden death wins", am._state == 3 and t2 == "%s WINS!" % String(duel[1].name).to_upper(),
				"state=%d title='%s'" % [am._state, t2])
	paused = false

	print("=== audit_regression_probe: %s (%d known open) ===" % ["ALL PASS" if _fails == 0 else "%d FAILED" % _fails, _known_open])
	quit(1 if _fails > 0 else 0)
