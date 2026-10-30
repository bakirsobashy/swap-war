extends SceneTree

## Headless probe: free an actor mid-death-window.
##
## Health.die() awaits a 1.5s SceneTreeTimer, then calls _respawn(). If the
## actor is freed during that window (Play Again on the results screen frees
## armed actors outright via ArenaManager._despawn_actors), the timer still
## fires — it is owned by the tree, not the actor — and the coroutine may
## attempt to resume on a freed instance. Whether Godot 4.7 silently drops
## that resume or errors ("previously freed instance") is an engine question,
## so this probe settles it empirically.
##
##   - Control: die() WITHOUT freeing -> respawned at full HP (validates the
##     rig; the hazard probe covers this too, but a same-rig control makes the
##     negative result below trustworthy).
##   - Test: die() -> queue_free() at ~0.33s (mid-window) -> run past 1.5s.
##     In-process the probe can only prove it stayed alive; the REAL gate is
##     the outer console scan for "SCRIPT ERROR" (standard probe discipline).
##   - Freed holder: an armed actor freed WITHOUT dropping (the abrupt-free
##     path, e.g. _despawn_actors), melee and ranged. Freed instances compare
##     non-null, so a weapon that only checks `if not _holder` keeps following
##     the freed socket (SCRIPT ERROR every tick) and stays "held" forever.
##     The weapon must release itself: not held, unfrozen, ground layer,
##     pickable — and a melee hit landing mid-swing in the gap deals no
##     damage (the swing window closes instead of carrying over).
##
## `-s` mode discipline: runtime load() only, untyped vars, no game-class
## annotations, zero direct autoload references (the TeamManager swap timer is
## stopped via guarded node-path access so teams stay put).

var _fails: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _probe()
	var verdict := "ALL PASS"
	if _fails > 0:
		verdict = "%d FAILURES" % _fails
	print("\n=== death_free_probe: %s ===" % verdict)
	quit(1 if _fails > 0 else 0)

func _check(ok: bool, what: String) -> void:
	print("  %s: %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1

func _spawn_actor(inst: Node, x: float) -> Node:
	var actor = load("res://Scenes/actor.tscn").instantiate()
	actor.get_node("AIController").is_ai = false
	actor.position = Vector2(x, 78.0)
	inst.get_node("Actors").add_child(actor)
	return actor

func _probe() -> void:
	# Keep teams stable for the probe's lifetime (discipline: stop the swap
	# timer; a mid-probe swap is harmless here but noise is noise).
	var team_manager = root.get_node_or_null("/root/TeamManager")
	if team_manager:
		for ch in team_manager.get_children():
			if ch is Timer:
				ch.stop()

	var inst = load("res://Scenes/Arenas/ArenaHazards.tscn").instantiate()
	root.add_child(inst)
	current_scene = inst
	await physics_frame
	await physics_frame

	print("\n=== control: die() -> 1.5s -> respawn (no free) ===")
	var ctrl = _spawn_actor(inst, -400.0)
	var ctrl_health = ctrl.get_node("Components/Health")
	ctrl_health.take_damage(999.0)
	_check(bool(ctrl_health.is_dead()), "control: actor died from 999 damage")
	for i in 130:                     # ~2.2s > 1.5s window
		await physics_frame
	_check(not bool(ctrl_health.is_dead())
			and absf(float(ctrl_health.current_health) - 100.0) < 0.01,
			"control: respawned at full hp (got %.1f, dead=%s)"
			% [float(ctrl_health.current_health), str(ctrl_health.is_dead())])
	ctrl.queue_free()
	await physics_frame

	print("\n=== test: die() -> freed at ~0.33s -> window elapses ===")
	var victim = _spawn_actor(inst, 400.0)
	var victim_health = victim.get_node("Components/Health")
	victim_health.take_damage(999.0)
	_check(bool(victim_health.is_dead()), "test: actor died from 999 damage")
	for i in 20:                      # ~0.33s — inside the 1.5s await window
		await physics_frame
	_check(not victim.is_inside_tree() or victim.get_parent() != null,
			"test: pre-free sanity (actor still in tree)")
	victim.queue_free()
	await physics_frame
	await physics_frame
	_check(not is_instance_valid(victim), "test: actor freed mid-window")
	# Run well past the 1.5s timer: if the coroutine resumed on the freed
	# instance, the error lands inside these frames. Surviving to the end
	# means the process held; the SCRIPT ERROR scan happens outside.
	for i in 150:                     # ~2.5s > 1.5s window remainder
		await physics_frame
	print("  INFO: resume window elapsed; scan console above for engine errors")

	print("\n=== freed holder: armed actor freed without dropping ===")
	# West floor, clear of the spike strip; 200 px apart so no PickupArea
	# reaches another scenario's weapon.
	var bystander = _spawn_actor(inst, -250.0)
	await physics_frame               # TeamMember registers deferred; set_team
	await physics_frame               # first would skip its tree_exited cleanup
	if team_manager:
		team_manager.set_team(bystander, 2)
	await _probe_freed_holder(inst, "res://Scenes/Weapons/Sword.tscn", -450.0, bystander, true)
	await _probe_freed_holder(inst, "res://Scenes/Weapons/Pistol.tscn", -650.0, bystander, false)
	bystander.queue_free()
	await physics_frame

	inst.queue_free()
	await physics_frame

func _probe_freed_holder(inst: Node, path: String, x: float, bystander: Node, melee: bool) -> void:
	var label: String = path.get_file().get_basename()
	var team_manager = root.get_node_or_null("/root/TeamManager")
	var owner_actor = _spawn_actor(inst, x)
	await physics_frame
	await physics_frame
	if team_manager:
		team_manager.set_team(owner_actor, 1)
	var w = load(path).instantiate()
	inst.add_child(w)
	var ground_layer: int = w.collision_layer
	# Outside the PickupArea, so the explicit equip below is the only pickup.
	w.global_position = owner_actor.global_position + Vector2(0, -300)
	await physics_frame
	await physics_frame
	owner_actor.get_node("WeaponHolder")._equip_weapon(w)
	for i in 3:                       # pick_up() defers the freeze
		await physics_frame
	_check(bool(w.is_held()) and bool(w.freeze), "%s: setup: equipped and frozen in hand" % label)
	if melee:
		# Melee only damages while a swing is open, so free the holder mid-swing.
		w.attack()
		_check(bool(w.is_attacking()), "%s: setup: swing in progress" % label)

	# free(), not queue_free(): the weapon must not get a tick before the
	# checks below. It doesn't care how its holder went — only that it never
	# dropped it.
	owner_actor.free()
	_check(not is_instance_valid(owner_actor) and bool(w.is_held()),
			"%s: setup: holder freed, weapon still holds the stale reference" % label)

	if melee:
		# A HitBox contact in the tick before _physics_process notices used to
		# hand the freed holder to TeamMember.is_same_team (SCRIPT ERROR).
		var bh = bystander.get_node("Components/Health")
		bh._invulnerability_timer = 0.0
		var hp_before := float(bh.current_health)
		w._on_hit_box_body_entered(bystander)
		_check(absf(float(bh.current_health) - hp_before) < 0.01,
				"%s: a hit after the holder is freed deals no damage (hp %.1f -> %.1f)"
				% [label, hp_before, float(bh.current_health)])

	for i in 10:
		await physics_frame
	_check(is_instance_valid(w), "%s: weapon outlives its holder" % label)
	if not is_instance_valid(w):
		return
	_check(not bool(w.is_held()), "%s: released (is_held false)" % label)
	_check(not bool(w.freeze), "%s: unfrozen" % label)
	_check(int(w.collision_layer) == ground_layer,
			"%s: back on the ground layer (got %d, want %d)" % [label, int(w.collision_layer), ground_layer])
	_check(bool(w.can_be_picked_up()), "%s: pickable again" % label)
	if melee:
		_check(not bool(w.is_attacking()), "%s: swing window closed, not carried to the next holder" % label)
	w.queue_free()
	await physics_frame