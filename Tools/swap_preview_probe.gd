extends SceneTree

## Player arrow + swap preview (docs/godot-prompter/plans/player-arrow-and-swap-preview.md).
## Live match in ArenaFlat with the AI switched off:
##   - the preview fires PREVIEW_LEAD (2 s) before a swap, every marker shows
##     its actor's rolled next colour, and the swap applies exactly that roll
##   - the preview clears after the swap, when the timer stops, and on restart
##   - only the player carries the arrow; it follows the actor, hides when dead
##   - pre-rolled teams keep the two-team guarantee
## Probe discipline: runtime access only, untyped vars, autoloads via /root.

var tm = null
var am = null
var _fails := 0
var _rolled_at := -1.0
var _rolled_teams: Dictionary = {}
var _cleared := 0

func _init() -> void:
	call_deferred("_run")

func _check(name: String, ok: bool, detail: String) -> void:
	print("  %s: %s (%s)" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		_fails += 1

func _actors() -> Array:
	var out: Array = []
	for a in current_scene.get_node("Actors").get_children():
		if not a.is_queued_for_deletion():
			out.append(a)
	return out

func _palette(team_id: int) -> Color:
	return load("res://Scripts/Components/TeamPalette.gd").color(team_id)

func _on_rolled(next: Dictionary) -> void:
	_rolled_at = tm.time_to_swap()
	_rolled_teams = next.duplicate()

func _on_cleared() -> void:
	_cleared += 1

func _run() -> void:
	tm = root.get_node_or_null("/root/TeamManager")
	am = root.get_node_or_null("/root/ArenaManager")
	var settings = root.get_node_or_null("/root/SettingsManager")
	var audio = root.get_node_or_null("/root/AudioManager")
	settings.win_mode = 0
	settings.ai_count = 3
	audio.sfx_enabled = false
	tm.next_teams_rolled.connect(_on_rolled)
	tm.next_teams_cleared.connect(_on_cleared)

	change_scene_to_file("res://Scenes/Arenas/ArenaFlat.tscn")
	for i in 6:
		await process_frame
	var actors := _actors()
	var player = null
	for a in actors:
		if a.is_player:
			player = a
		else:
			a.get_node("AIController").is_ai = false

	# Only the player wears the arrow, and it shows from the start.
	await create_timer(0.3).timeout
	var arrows := 0
	var player_marker = player.get_node("ActorMarker")
	for a in actors:
		if a.get_node("ActorMarker").is_player_marker():
			arrows += 1
	_check("only the player has the arrow", arrows == 1 and player_marker.is_player_marker(), "%d arrows" % arrows)
	_check("player arrow visible", player_marker.is_visible_in_tree(), "visible=%s" % player_marker.is_visible_in_tree())
	var ai_marker = actors[1].get_node("ActorMarker") if actors[0] == player else actors[0].get_node("ActorMarker")
	_check("AI markers hidden outside the preview", not ai_marker.visible, "visible=%s" % ai_marker.visible)

	# Swap preview timing and content: run a short 3 s swap cycle.
	await create_timer(3.6).timeout          # countdown -> PLAYING
	_rolled_at = -1.0
	tm._swap_timer.start(3.0)
	var waited := 0.0
	while _rolled_at < 0.0 and waited < 4.0:
		await create_timer(0.02).timeout
		waited += 0.02
	_check("preview fires PREVIEW_LEAD before the swap", absf(_rolled_at - tm.PREVIEW_LEAD) <= 0.1,
			"rolled with %.2f s left" % _rolled_at)
	await process_frame
	var shown_ok := true
	for a in actors:
		var m = a.get_node("ActorMarker")
		var want: Color = _palette(int(_rolled_teams.get(a, -1)))
		if not m.is_preview_on() or not m.get_preview_color().is_equal_approx(want):
			shown_ok = false
	_check("every marker shows its actor's next colour", shown_ok and _rolled_teams.size() == actors.size(),
			"%d actors, %d rolled" % [actors.size(), _rolled_teams.size()])
	var ai_vis := false
	for a in actors:
		if a != player and a.get_node("ActorMarker").visible:
			ai_vis = true
	_check("AI chips appear during the preview", ai_vis, "an AI marker visible=%s" % ai_vis)

	# The swap applies exactly the previewed roll, then the preview clears.
	var cleared_before := _cleared
	while tm.time_to_swap() > 0.0 and tm.time_to_swap() < tm.PREVIEW_LEAD + 0.5:
		await create_timer(0.02).timeout
		if _cleared > cleared_before:
			break
	await process_frame
	var applied_ok := true
	for a in actors:
		if tm.get_team(a) != int(_rolled_teams.get(a, -1)):
			applied_ok = false
	_check("swap applies exactly the previewed teams", applied_ok, "teams=%s" % [_rolled_teams.values()])
	var any_on := false
	for a in actors:
		if a.get_node("ActorMarker").is_preview_on():
			any_on = true
	_check("preview clears after the swap", not any_on and tm.get_next_team(player) == -1, "still on=%s" % any_on)

	# Timer stopped mid-preview (post-round / sudden death) clears it.
	tm._swap_timer.start(2.5)
	await create_timer(0.8).timeout          # inside the 2 s window
	var on_before: bool = player_marker.is_preview_on()
	tm._swap_timer.stop()
	await create_timer(0.2).timeout
	_check("stopping the timer clears the preview", on_before and not player_marker.is_preview_on(),
			"before=%s after=%s" % [on_before, player_marker.is_preview_on()])

	# Restart (Play Again) mid-preview clears it too.
	tm._swap_timer.start(2.5)
	await create_timer(0.8).timeout
	var on_before2: bool = player_marker.is_preview_on()
	tm._swap_timer.start(10.0)
	await create_timer(0.2).timeout
	_check("restarting the timer clears the preview", on_before2 and not player_marker.is_preview_on(),
			"before=%s after=%s" % [on_before2, player_marker.is_preview_on()])

	# The arrow follows the player and hides while dead.
	tm._swap_timer.stop()
	await create_timer(0.2).timeout
	var dx: float = absf(player_marker.global_position.x - player.global_position.x)
	_check("arrow sits over the player", dx < 0.5 and player_marker.global_position.y < player.global_position.y - 50.0,
			"dx=%.1f dy=%.1f" % [dx, player_marker.global_position.y - player.global_position.y])
	var ph = player.get_node("Components/Health")
	ph.die()
	await process_frame
	_check("arrow hidden while dead", not player_marker.is_visible_in_tree(), "visible=%s" % player_marker.is_visible_in_tree())
	while ph.is_dead():
		await physics_frame
	await process_frame
	_check("arrow back after respawn", player_marker.is_visible_in_tree(), "visible=%s" % player_marker.is_visible_in_tree())

	# Pre-rolled teams keep the two-team guarantee.
	var saved: Dictionary = tm._teams.duplicate()
	tm._teams.clear()
	tm._teams[actors[0]] = 0
	tm._teams[actors[1]] = 0
	var same := 0
	for i in 300:
		var r: Dictionary = tm._roll_teams()
		if r[actors[0]] == r[actors[1]]:
			same += 1
	tm._teams = saved
	_check("pre-rolled teams never leave everyone allied", same == 0, "%d/300 all-same" % same)

	print("=== swap_preview_probe: %s ===" % ("ALL PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails > 0 else 0)
