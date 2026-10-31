extends SceneTree

## Headless probe for hit & kill feel, phase 1
## (docs/godot-prompter/plans/hit-and-kill-feel.md).
##
##   A. Wiring — HitFeel autoload present (hit-stop off by default under
##      headless), ArenaBase carries the Stains layer (z -1) and a camera that
##      takes shake trauma, ArenaFlat's Background draws under the stains.
##   B. Hit-stop — the player's hits (dealt or taken) freeze time and restore
##      it to exactly 1.0 on the real clock; AI-vs-AI hits never touch it;
##      overlapping freezes extend to the latest end, never add up; a pause
##      mid-freeze restores at once and blocks new ones; the master switch
##      silences everything.
##   C. Shake — the player's hit adds camera trauma, AI-vs-AI hits don't, the
##      offset moves while shaking and decays back to exactly zero.
##   D. Stains — a damage kill adds exactly one stain near the death spot in
##      the victim's death-time colour; it survives the respawn and a team
##      change; the player's kill freezes time; an off-map (KillZone) death
##      adds no stain and splashes inside the view; the cap retires the
##      oldest; ArenaManager's Play Again sweep clears them.
##   E. Plumbing + pop — a projectile hands its flight direction to Health;
##      a kill spawns the white death pop and a droplet burst along the blow.
##
## `-s` discipline: runtime load() only, untyped vars, no game-class
## annotations, autoloads via guarded /root paths. Wall-clock waits use
## timers that ignore time_scale (hit-stop scales it).

var _fails: int = 0
var hf = null

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	hf = root.get_node_or_null("/root/HitFeel")
	_check(hf != null, "A: HitFeel autoload present")
	if hf == null:
		quit(1)
		return
	_check(not bool(hf.hitstop_enabled), "A: hit-stop defaults off under headless (timing probes)")
	# Teams must stay put for the colour checks.
	var team_manager = root.get_node_or_null("/root/TeamManager")
	if team_manager:
		for ch in team_manager.get_children():
			if ch is Timer:
				ch.stop()

	await _probe()

	hf.end_hitstop()
	hf.hitstop_enabled = false
	hf.enabled = true
	var verdict := "ALL PASS"
	if _fails > 0:
		verdict = "%d FAILURES" % _fails
	print("\n=== hit_feel_probe: %s ===" % verdict)
	quit(1 if _fails > 0 else 0)

func _check(ok: bool, what: String) -> void:
	print("  %s: %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1

func _real(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout

## AI off (never a second brain in a probe); team AFTER add_child (the
## team-change flash needs the tree), as in auto_attack_probe.
func _spawn(inst, x: float, team: int, is_player: bool):
	var actor = load("res://Scenes/actor.tscn").instantiate()
	actor.get_node("AIController").is_ai = false
	if is_player:
		actor.is_player = true
	actor.position = Vector2(x, 78.0)
	inst.get_node("Actors").add_child(actor)
	actor.get_node("Components/TeamMember").team_id = team
	return actor

func _closest_team(c: Color) -> int:
	var colors = load("res://Scripts/Components/TeamPalette.gd").COLORS
	var best := -1
	var best_d := INF
	for i in colors.size():
		var k: Color = colors[i]
		var d := Vector3(c.r - k.r, c.g - k.g, c.b - k.b).length()
		if d < best_d:
			best_d = d
			best = i
	return best

func _in_view(cam, pos: Vector2) -> bool:
	var half: Vector2 = cam.get_viewport_rect().size / cam.zoom * 0.5
	var c: Vector2 = cam.get_screen_center_position()
	return Rect2(c - half, half * 2.0).has_point(pos)

func _probe() -> void:
	print("\n=== A: wiring ===")
	var flat = load("res://Scenes/Arenas/ArenaFlat.tscn").instantiate()
	var bg = flat.get_node_or_null("Background")
	var flat_stains = flat.get_node_or_null("Stains")
	_check(bg != null and flat_stains != null and int(bg.z_index) < int(flat_stains.z_index),
			"A: ArenaFlat's Background draws under the stains")
	flat.free()

	# ArenaHazards: live actors provably rest on its floor (top y = 128);
	# everyone spawns WEST of the spike strip [288,352].
	var inst = load("res://Scenes/Arenas/ArenaHazards.tscn").instantiate()
	root.add_child(inst)
	current_scene = inst
	await physics_frame
	await physics_frame
	var stains = inst.get_node_or_null("Stains")
	var cam = inst.get_node_or_null("Camera2D")
	var effects = inst.get_node("Effects")
	_check(stains != null and stains.has_method("add_stain") and int(stains.z_index) == -1,
			"A: arena has the Stains layer at z -1")
	_check(cam != null and cam.has_method("add_trauma") and cam.is_in_group("arena_camera"),
			"A: arena camera takes shake trauma")
	if stains == null or cam == null:
		inst.queue_free()
		return

	var player = _spawn(inst, -400.0, 0, true)
	var enemy = _spawn(inst, -300.0, 1, false)
	var ai1 = _spawn(inst, -200.0, 2, false)
	var ai2 = _spawn(inst, -100.0, 3, false)
	for i in 10:
		await physics_frame
	var ph = player.get_node("Components/Health")
	var eh = enemy.get_node("Components/Health")
	var a1h = ai1.get_node("Components/Health")
	var a2h = ai2.get_node("Components/Health")

	print("\n=== E: plumbing ===")
	var data = load("res://Scripts/Weapons/WeaponData.gd").new()
	data.damage = 1.0
	data.knockback = 0.0
	data.critical_chance = 0.0
	var proj = load("res://Scenes/Weapons/Projectile.tscn").instantiate()
	inst.add_child(proj)
	proj.start(Vector2(-500.0, -200.0), Vector2(1.0, -1.0), data, ai2)
	proj._on_body_entered(enemy)
	_check(eh._last_hit_dir.is_equal_approx(Vector2(1.0, -1.0).normalized()),
			"E: a projectile hands its flight direction to Health (got %s)" % eh._last_hit_dir)

	print("\n=== B: hit-stop ===")
	hf.hitstop_enabled = true
	a1h.take_damage(5.0, ai2, Vector2.RIGHT)
	_check(Engine.time_scale == 1.0 and not hf.is_hitstopped(), "B: an AI-vs-AI hit leaves time alone")
	eh.take_damage(5.0, player, Vector2.LEFT)
	_check(Engine.time_scale < 0.1 and hf.is_hitstopped(),
			"B: the player's hit freezes time (scale %.2f)" % Engine.time_scale)
	await _real(0.25)
	_check(Engine.time_scale == 1.0 and not hf.is_hitstopped(), "B: time restored to exactly 1.0 after the freeze")
	ph.take_damage(5.0, enemy, Vector2.RIGHT)
	_check(hf.is_hitstopped(), "B: the player getting hit freezes time")
	hf.end_hitstop()

	hf.hitstop(100)
	var first_end := int(hf._hitstop_until_msec)
	hf.hitstop(20)
	_check(int(hf._hitstop_until_msec) == first_end, "B: a shorter overlapping freeze never adds up")
	hf.hitstop(400)
	_check(int(hf._hitstop_until_msec) > first_end, "B: a longer overlapping freeze extends to the latest end")
	paused = true
	await process_frame
	await process_frame
	_check(Engine.time_scale == 1.0 and not hf.is_hitstopped(), "B: pausing mid-freeze restores time at once")
	hf.hitstop(100)
	_check(not hf.is_hitstopped(), "B: no freeze starts while paused")
	paused = false

	hf.enabled = false
	eh.take_damage(5.0, player, Vector2.LEFT)
	_check(not hf.is_hitstopped(), "B: master switch off -> no freeze")
	hf.enabled = true

	print("\n=== C: shake ===")
	await _real(0.8)
	_check(float(cam.trauma) == 0.0 and cam.offset == Vector2.ZERO, "C: earlier shake decayed to exactly zero")
	a1h.take_damage(5.0, ai2, Vector2.RIGHT)
	_check(float(cam.trauma) == 0.0, "C: AI-vs-AI hits don't shake")
	eh.take_damage(5.0, player, Vector2.LEFT)
	_check(float(cam.trauma) > 0.0, "C: the player's hit adds trauma (%.2f)" % float(cam.trauma))
	hf.end_hitstop()
	var moved := false
	for i in 30:
		await process_frame
		if cam.offset != Vector2.ZERO:
			moved = true
	_check(moved, "C: the camera offset moves while shaking")
	await _real(1.0)
	_check(float(cam.trauma) == 0.0 and cam.offset == Vector2.ZERO, "C: shake decays back to exactly zero offset")

	print("\n=== D: stains ===")
	var before: int = stains.get_stains().size()
	var victim_color: Color = a1h._team_color()
	var death_pos: Vector2 = ai1.global_position
	a1h.take_damage(999.0, ai2, Vector2.RIGHT)
	_check(bool(a1h.is_dead()), "D: the AI died")
	var list = stains.get_stains()
	_check(list.size() == before + 1, "D: a damage kill adds exactly one stain (%d -> %d)" % [before, list.size()])
	var stain = list[list.size() - 1] if list.size() > 0 else null
	if stain:
		_check(stain.global_position.distance_to(death_pos) < 40.0,
				"D: stain sits at the death spot (%.0f px off)" % stain.global_position.distance_to(death_pos))
		_check(stain.modulate.is_equal_approx(stains.stain_color(victim_color)) and _closest_team(stain.modulate) == 2,
				"D: stain is the victim's death-time colour")

	var pop_found := false
	var burst_found := false
	for e in effects.get_children():
		if e is Sprite2D and e.material != null:
			pop_found = true
		if e is CPUParticles2D and e.direction.dot(Vector2.RIGHT) > 0.99:
			burst_found = true
	_check(pop_found, "E: the kill spawns the white death pop in Effects")
	_check(burst_found, "E: the droplet burst sprays along the blow")

	if stain:
		var tint: Color = stain.modulate
		await _real(1.8)              # respawn wait is 1.5 s
		_check(not bool(a1h.is_dead()), "D: the victim respawned")
		ai1.get_node("Components/TeamMember").team_id = 0
		await process_frame
		_check(is_instance_valid(stain) and stains.get_stains().has(stain) and stain.modulate.is_equal_approx(tint),
				"D: the stain keeps its colour through the respawn and a team change")

	before = stains.get_stains().size()
	eh.take_damage(999.0, player, Vector2.LEFT)
	_check(hf.is_hitstopped() and stains.get_stains().size() == before + 1,
			"D: the player's kill freezes time and stains")
	await _real(0.3)
	_check(Engine.time_scale == 1.0, "D: time restored after the kill freeze")

	before = stains.get_stains().size()
	ai2.global_position = Vector2(-100.0, 5000.0)   # far below the view
	a2h.die(true)
	_check(stains.get_stains().size() == before, "D: an off-map death leaves no stain")
	var splash = effects.get_child(effects.get_child_count() - 1)
	_check(splash is CPUParticles2D and _in_view(cam, splash.global_position),
			"D: an off-map death splashes inside the view (at %s)" % splash.global_position)

	var cap := int(stains.max_stains)
	var oldest = stains.get_stains()[0]
	for i in cap + 5:
		stains.add_stain(Vector2(-600.0 + i, -100.0), Color.WHITE, Vector2.ZERO)
	var after = stains.get_stains()
	_check(after.size() == cap and not after.has(oldest), "D: the cap holds at %d and retires the oldest first" % cap)

	var am = root.get_node_or_null("/root/ArenaManager")
	_check(am != null, "D: ArenaManager autoload present")
	if am:
		am._clear_match_leftovers()
		await process_frame
		await process_frame
		_check(stains.get_stains().size() == 0 and stains.get_child_count() == 0,
				"D: the Play Again sweep clears every stain")

	inst.queue_free()
	await physics_frame
