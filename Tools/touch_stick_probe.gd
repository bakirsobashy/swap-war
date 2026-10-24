extends SceneTree

## Headless probe for the VirtualStick twin-stick touch controls.
##
## Feeds REAL InputEventScreenTouch / InputEventScreenDrag events through
## Input.parse_input_event (the same pipeline the touch hardware uses) into
## an instantiated HUD and asserts:
##   - analog strengths land in Input.get_axis (0.5 half-travel, 1.0 full)
##   - center crossing releases the opposite action (no stacking)
##   - down-push hysteresis (not yet at 0.55, engage at 0.7, hold at 0.55,
##     release at 0.45)
##   - two simultaneous sticks on different touch indices
##   - finger lift / hidden mid-hold / scene teardown all release actions
##   - a keyboard-pressed action is never released by the stick
##   - hidden controls never capture a fresh touch
##   - mouse-from-touch emulation stays OFF while unpaused
##
## The window size is left at the default so synthesized touch positions map
## 1:1 onto stick positions.
##
## HEADLESS CAVEAT: parsed InputEventScreenTouch events do NOT dispatch to
## Node._input under the headless display server (verified empirically —
## parsed InputEventAction and mouse events DO dispatch). The handlers are
## therefore invoked directly, and to BOTH sticks, reproducing the engine's
## broadcast so cross-capture/index isolation is genuinely tested. Everything
## downstream of the handler — capture radius, index tracking, deadzone math,
## action injection via Input.action_press, release paths — is the real code
## under test; on hardware the engine's _input dispatch is the same contract
## the TouchScreenButtons already rely on.
##
## `-s` discipline: runtime load() only, untyped vars, no game-class
## annotations, no direct autoload references. Settings are written via DIRECT
## property assignment — the setters persist to user://swap_war_settings.cfg
## and a probe must never clobber the developer's config.

var _fails: int = 0
var _sticks: Array = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var hud: Node = (load("res://Scenes/HUD.tscn") as PackedScene).instantiate()
	root.add_child(hud)
	await process_frame
	await process_frame
	var tc: Node = hud.get_node("TouchControls")
	var move_stick = tc.get_node("%MoveStick")
	var aim_stick = tc.get_node("%AimStick")
	_sticks = [move_stick, aim_stick]
	var settings = root.get_node_or_null("/root/SettingsManager")
	if settings:
		settings.touch_controls_mode = 1      # ALWAYS — direct set, no save
	tc._visibility_changed()

	await _probe(tc, move_stick, aim_stick, settings)

	var verdict := "ALL PASS"
	if _fails > 0:
		verdict = "%d FAILURES" % _fails
	print("\n=== touch_stick_probe: %s ===" % verdict)
	quit(1 if _fails > 0 else 0)

func _check(ok: bool, what: String) -> void:
	print("  %s: %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1

## Touch event through both sticks' handlers (see the headless caveat above),
## one process frame apart.
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

## Canvas position at the given deflection ratio (-1..1 per axis) of a stick.
func _stick_pos(stick, offset: Vector2) -> Vector2:
	return stick.position + offset * (stick.MAX_DEFLECTION * stick.scale.x)

func _probe(tc: Node, move_stick, aim_stick, settings) -> void:
	_check(tc.visible, "setup: touch controls visible in ALWAYS mode")

	print("\n=== analog move + deadzone ===")
	_check(absf(Input.get_axis("Move_Left", "Move_Right")) < 0.001
			and not Input.is_action_pressed("Move_Down"),
			"idle: axis 0, Move_Down not pressed")
	await _touch(0, true, _stick_pos(move_stick, Vector2(0.2, 0.0)))
	_check(move_stick.is_held
			and absf(Input.get_axis("Move_Left", "Move_Right")) < 0.001,
			"deadzone: press near center -> held, axis still 0")
	await _drag(0, _stick_pos(move_stick, Vector2(0.5, 0.0)))
	_check(is_equal_approx(Input.get_axis("Move_Left", "Move_Right"), 0.5),
			"analog: half travel -> axis 0.5")
	await _drag(0, _stick_pos(move_stick, Vector2(1.0, 0.0)))
	_check(is_equal_approx(Input.get_axis("Move_Left", "Move_Right"), 1.0),
			"analog: full travel -> axis 1.0")
	await _drag(0, _stick_pos(move_stick, Vector2(-0.5, 0.0)))
	_check(is_equal_approx(Input.get_axis("Move_Left", "Move_Right"), -0.5),
			"crossing: opposite action released, axis -0.5")

	print("\n=== down-push hysteresis (drop-through) ===")
	await _drag(0, _stick_pos(move_stick, Vector2(0.0, 0.55)))
	_check(not Input.is_action_pressed("Move_Down"),
			"hysteresis: 0.55 travel -> not yet pressed")
	await _drag(0, _stick_pos(move_stick, Vector2(0.0, 0.7)))
	_check(Input.is_action_pressed("Move_Down"),
			"hysteresis: 0.7 travel -> pressed")
	await _drag(0, _stick_pos(move_stick, Vector2(0.0, 0.55)))
	_check(Input.is_action_pressed("Move_Down"),
			"hysteresis: back to 0.55 -> still pressed (no flutter)")
	await _drag(0, _stick_pos(move_stick, Vector2(0.0, 0.45)))
	_check(not Input.is_action_pressed("Move_Down"),
			"hysteresis: 0.45 travel -> released")
	await _touch(0, false, _stick_pos(move_stick, Vector2(0.0, 0.45)))
	_check(absf(Input.get_axis("Move_Left", "Move_Right")) < 0.001
			and not move_stick.is_held,
			"hysteresis: finger lifted, clean state before multi-touch")

	print("\n=== two simultaneous sticks (multi-touch) ===")
	await _touch(0, true, _stick_pos(move_stick, Vector2(-1.0, 0.0)))
	_check(is_equal_approx(Input.get_axis("Move_Left", "Move_Right"), -1.0),
			"multi: finger 0 holds MoveStick full-left")
	await _touch(1, true, aim_stick.position)
	await _drag(1, _stick_pos(aim_stick, Vector2(0.7, -0.7)))
	var aim_val: Vector2 = tc.get_aim_stick_value()
	_check(is_equal_approx(Input.get_axis("Move_Left", "Move_Right"), -1.0),
			"multi: move axis unchanged while the aim stick is used")
	_check(aim_val.dot(Vector2(1.0, -1.0).normalized()) > 0.9,
			"multi: aim value points up-right (got %s)" % aim_val)

	print("\n=== release paths ===")
	await _touch(0, false, _stick_pos(move_stick, Vector2(-1.0, 0.0)))
	_check(absf(Input.get_axis("Move_Left", "Move_Right")) < 0.001
			and not Input.is_action_pressed("Move_Down")
			and not move_stick.is_held,
			"finger lift: axis 0, Move_Down released, stick freed")
	await _touch(1, false, _stick_pos(aim_stick, Vector2(0.7, -0.7)))
	_check(tc.get_aim_stick_value() == Vector2.ZERO,
			"finger lift: aim value zeroed")

	print("\n=== keyboard action protection ===")
	# A held physical A key (Move_Left) while the stick only ever presses
	# Move_Right: the stick's release must not cancel the keyboard's action
	# (the _owned_actions guard releases only what the stick pressed). Note
	# the shared single state per action: if BOTH hold the same action, the
	# stick's release cancels the key too — a documented, accepted edge
	# (touch play has no keyboard).
	Input.action_press("Move_Left", 1.0)
	await _touch(0, true, _stick_pos(move_stick, Vector2(1.0, 0.0)))
	_check(is_equal_approx(Input.get_axis("Move_Left", "Move_Right"), 0.0),
			"keyboard: conflicting inputs cancel on the axis")
	await _touch(0, false, _stick_pos(move_stick, Vector2(1.0, 0.0)))
	_check(is_equal_approx(Input.get_axis("Move_Left", "Move_Right"), -1.0),
			"keyboard: stick release leaves the held key alone")
	Input.action_release("Move_Left")

	print("\n=== hidden mid-hold ===")
	await _touch(0, true, _stick_pos(move_stick, Vector2(0.0, 0.8)))
	_check(Input.is_action_pressed("Move_Down"), "hidden: down engaged before hiding")
	if settings:
		settings.touch_controls_mode = 2      # HIDDEN — direct set, no save
	tc._visibility_changed()
	_check(not tc.visible and not Input.is_action_pressed("Move_Down")
			and absf(Input.get_axis("Move_Left", "Move_Right")) < 0.001,
			"hidden mid-hold: all stick actions released")
	await _touch(0, true, _stick_pos(move_stick, Vector2(0.5, 0.0)))
	_check(not move_stick.is_held
			and absf(Input.get_axis("Move_Left", "Move_Right")) < 0.001,
			"hidden: fresh touch does NOT get captured")
	await _touch(0, false, _stick_pos(move_stick, Vector2(0.5, 0.0)))

	print("\n=== scene teardown mid-hold ===")
	if settings:
		settings.touch_controls_mode = 1      # ALWAYS again
	tc._visibility_changed()
	await _touch(0, true, _stick_pos(move_stick, Vector2(-1.0, 0.0)))
	_check(is_equal_approx(Input.get_axis("Move_Left", "Move_Right"), -1.0),
			"teardown: stick held before the HUD is freed")
	tc.owner.queue_free()
	await process_frame
	await process_frame
	_check(absf(Input.get_axis("Move_Left", "Move_Right")) < 0.001,
			"teardown: actions released when the HUD leaves the tree")

	print("\n=== emulation contract ===")
	_check(not Input.emulate_mouse_from_touch,
			"emulation stays OFF while unpaused (Attack is mouse-bound)")