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

	inst.queue_free()
	await physics_frame