extends SceneTree

## Headless layout probe for the HUD / touch controls.
## Instantiates the real HUD (which contains TouchControls), resizes the window
## through the Phase 3 target resolutions, and asserts:
##   - every control/touch button rect lies inside the visible canvas rect
##   - no two buttons overlap
##   - the scoreboard (simulated 4-player labels) fits the viewport width
##   - the HUD pause button (the only on-screen pause) is visible in the
##     top-right corner and clear of every touch control
##   - the goal chip is on-canvas, clear of the swap timer, the scoreboard card
##     and the pause button, and centred between the timer and it;
##     every resolution runs with touch controls ALWAYS and HIDDEN
##   - a raw finger tap on the HUD pause button opens the pause menu (touch->
##     mouse emulation is off mid-match, so the Button itself never sees it)

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(400, 800),
	Vector2i(1080, 1920),
	Vector2i(1920, 1080),
]

var _hud: Node = null
var _fails: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# Force the procedural layout even if the developer's own config carries a
	# custom touch layout (direct property set — never persisted).
	var settings = root.get_node_or_null("/root/SettingsManager")
	if settings:
		settings.touch_layout = {}
	var hud_scene: PackedScene = load("res://Scenes/HUD.tscn")
	_hud = hud_scene.instantiate()
	root.add_child(_hud)

	# Simulate 4 players on the scoreboard so label widths are real.
	var score_board: Control = _hud.get_node("%ScoreBoard")
	for i in 4:
		var label := Label.new()
		label.text = "Actor%d\nGreen: 12" % i
		score_board.add_child(label)

	var tc = _hud.get_node("TouchControls")
	for mode in [1, 2]:    # SettingsManager.TouchControlsMode ALWAYS, HIDDEN
		if settings:
			settings.touch_controls_mode = mode    # direct set, never persisted
		tc._visibility_changed()
		for res in RESOLUTIONS:
			root.size = res
			await process_frame
			await process_frame
			_check_resolution(res)
	await _pause_tap_check()
	quit(1 if _fails > 0 else 0)

## A raw finger tap on the HUD pause button opens the pause menu.
func _pause_tap_check() -> void:
	var arena := Node.new()
	arena.name = "Arena"
	root.add_child(arena)
	var pause = load("res://Scenes/UI/PauseMenu.tscn").instantiate()
	arena.add_child(pause)
	var hud = load("res://Scenes/HUD.tscn").instantiate()
	arena.add_child(hud)
	current_scene = arena
	await process_frame
	await process_frame
	var tap := InputEventScreenTouch.new()
	tap.index = 0
	tap.pressed = true
	tap.position = Vector2(300, 300)
	hud._input(tap)
	var miss_ok: bool = not pause.visible
	tap.position = hud.get_node("%PauseButton").get_global_rect().get_center()
	hud._input(tap)
	var hit_ok: bool = pause.visible and paused
	print("pause tap: miss ignored=%s, tap opens pause=%s %s" % [miss_ok, hit_ok, "PASS" if miss_ok and hit_ok else "FAIL"])
	if not (miss_ok and hit_ok):
		_fails += 1
	pause._on_resume_pressed()
	arena.queue_free()
	await process_frame

func _check_resolution(res: Vector2i) -> void:
	print("=== %dx%d (touch %s) ===" % [res.x, res.y, "on" if _hud.get_node("TouchControls").uses_touch_controls() else "off"])
	var canvas: Rect2 = root.get_visible_rect()
	var canvas_size := canvas.size

	var tc := _hud.get_node("TouchControls")
	var rects: Dictionary = {}
	# TouchScreenButtons (Node2D): rect = position + texture size * scale
	# (TouchScreenButton draws with the texture's TOP-LEFT at the node
	# position). The two sticks are custom VirtualStick Node2D nodes: their
	# get_touch_rect() covers the full grab radius (well + activation slop),
	# so the overlap check tests the real touch zones. Sticks are fetched
	# untyped (probe discipline: no game-class annotations).
	for name in ["DropButton", "JumpButton", "AttackButton"]:
		var b: TouchScreenButton = tc.get_node("%" + name)
		rects[name] = Rect2(b.position, b.texture_normal.get_size() * b.scale.abs())
	for name in ["MoveStick", "AimStick"]:
		var s = tc.get_node("%" + name)
		rects[name] = s.get_touch_rect()
	# The HUD's pause button shares the screen with the touch controls.
	var hud_pause = _hud.get_node("%PauseButton")
	rects["HudPause"] = hud_pause.get_global_rect()

	for name in rects:
		var r: Rect2 = rects[name]
		var inside := canvas.encloses(r.grow(0.5))
		print("%s rect=%s inside=%s" % [name, r, "PASS" if inside else "FAIL"])
		if not inside:
			_fails += 1

	var names := rects.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			if rects[names[i]].intersects(rects[names[j]], true):
				print("OVERLAP FAIL: %s <-> %s  %s %s" % [names[i], names[j], rects[names[i]], rects[names[j]]])
				_fails += 1

	var score_board: Control = _hud.get_node("%ScoreBoard")
	var sb_rect := score_board.get_global_rect()
	var fits := canvas.encloses(sb_rect)
	print("ScoreBoard rect=%s fits=%s (canvas %s)" % [sb_rect, "PASS" if fits else "FAIL", canvas_size])
	if not fits:
		_fails += 1

	# The swap timer (top-left) and pause button (top-right) must not sit on
	# top of the centered score labels.
	var timer_rect: Rect2 = _hud.get_node("%TeamTimer").get_global_rect()
	var pause_rect: Rect2 = rects["HudPause"]
	for child in score_board.get_children():
		var label_rect: Rect2 = child.get_global_rect()
		if timer_rect.intersects(label_rect, true):
			print("OVERLAP FAIL: TeamTimer <-> %s  %s %s" % [child.name, timer_rect, label_rect])
			_fails += 1
		if pause_rect.intersects(label_rect, true):
			print("OVERLAP FAIL: PauseButton <-> %s  %s %s" % [child.name, pause_rect, label_rect])
			_fails += 1

	# Goal chip: on-canvas, clear of the timer and the scoreboard card, and of
	# the pause button whenever touch controls are in use.
	var chip_rect: Rect2 = _hud.get_node("%GoalChip").get_global_rect()
	var card_rect: Rect2 = score_board.get_parent().get_global_rect()
	var chip_ok := canvas.encloses(chip_rect) and chip_rect.size.x > 0.0
	print("GoalChip rect=%s inside=%s" % [chip_rect, "PASS" if chip_ok else "FAIL"])
	if not chip_ok:
		_fails += 1
	# The HUD pause button shows in every touch mode, in the top-right corner.
	var active_pause: Rect2 = pause_rect
	var pause_ok: bool = hud_pause.visible and active_pause.get_center().x > canvas_size.x * 0.8 			and active_pause.position.y < 120.0
	print("pause rect=%s visible=%s ok=%s" % [active_pause, hud_pause.visible, "PASS" if pause_ok else "FAIL"])
	if not pause_ok:
		_fails += 1
	var chip_blockers := {"TeamTimer": timer_rect, "ScoreCard": card_rect, "Pause": active_pause}
	for blocker in chip_blockers:
		if chip_rect.intersects(chip_blockers[blocker], true):
			print("OVERLAP FAIL: GoalChip <-> %s  %s %s" % [blocker, chip_rect, chip_blockers[blocker]])
			_fails += 1
	# ...and sits centred between the swap timer and that pause button.
	var mid_x: float = (timer_rect.end.x + active_pause.position.x) * 0.5
	var centred: bool = absf(chip_rect.get_center().x - mid_x) <= 1.0
	print("GoalChip centre x=%.1f mid=%.1f %s" % [chip_rect.get_center().x, mid_x, "PASS" if centred else "FAIL"])
	if not centred:
		_fails += 1
