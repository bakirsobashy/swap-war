extends SceneTree

## Headless probe for the touch controls layout editor + custom layout apply.
##
##   (a) Persistence round-trip — [touch_layout] section: set -> file ->
##       in-memory -> clear -> section gone.
##   (b) Editor behavior — enter/exit lifecycle (emulation flags, layer
##       visibility, sticks suppressed, actions blanked), selection of all
##       five controls + selection box / +- pair tracking, overlay exclusion,
##       drag with on-canvas clamping + commit, +- stepping with limits,
##       RESET, exit restores the emulation flags.
##   (c) Game-side apply — HUD with a custom dict: per-control denormalized
##       positions/scales, re-denormalize on viewport resize, partial dict
##       falls back per-control, stale keys are inert, clear returns the
##       procedural layout.
##   (d) layout_probe contract — a custom dict really changes the layout
##       (proving the force-default in layout_probe is load-bearing).
##
## This probe legitimately exercises the SAVING APIs — it is the ONLY probe
## allowed to: SettingsManager setters rewrite the whole config file, so the
## dev's user://swap_war_settings.cfg is backed up at the start and restored
## at the end (the flow is linear; _check never aborts).
##
## HEADLESS CAVEAT: parsed InputEventScreenTouch does NOT dispatch to
## Node._input under the headless display server (verified empirically), so
## editor touch events are fed directly to editor._input() — everything
## downstream of the handler is the real code.
##
## `-s` discipline: runtime load() only, untyped vars for game nodes, no
## game-class annotations, settings via guarded node-path access.

const CFG_PATH := "user://swap_war_settings.cfg"

var _fails: int = 0
var _cfg_existed := false
var _cfg_bytes := PackedByteArray()

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_backup_config()
	await _probe()
	_restore_config()
	var verdict := "ALL PASS"
	if _fails > 0:
		verdict = "%d FAILURES" % _fails
	print("\n=== touch_layout_editor_probe: %s ===" % verdict)
	quit(1 if _fails > 0 else 0)

func _backup_config() -> void:
	var f := FileAccess.open(CFG_PATH, FileAccess.READ)
	if f:
		_cfg_existed = true
		_cfg_bytes = f.get_buffer(f.get_length())
		f.close()

func _restore_config() -> void:
	if _cfg_existed:
		var f := FileAccess.open(CFG_PATH, FileAccess.WRITE)
		if f:
			f.store_buffer(_cfg_bytes)
			f.close()
	else:
		var d := DirAccess.open("user://")
		if d and d.file_exists("swap_war_settings.cfg"):
			d.remove("swap_war_settings.cfg")

func _check(ok: bool, what: String) -> void:
	print("  %s: %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1

func _touch_event(index: int, pressed: bool, pos: Vector2) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = pressed
	ev.position = pos
	return ev

func _drag_event(index: int, pos: Vector2) -> InputEventScreenDrag:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	return ev

## A FRESH ConfigFile read of the saved [touch_layout] section.
func _read_file_layout() -> Dictionary:
	var out := {}
	var config := ConfigFile.new()
	if config.load(CFG_PATH) == OK and config.has_section("touch_layout"):
		for key in config.get_section_keys("touch_layout"):
			out[key] = config.get_value("touch_layout", key, null)
	return out

func _positions_snapshot(tc: Node, names: Array) -> Dictionary:
	var out := {}
	for name in names:
		out[name] = tc.get_control_node(name).position
	return out

func _probe() -> void:
	var settings = root.get_node_or_null("/root/SettingsManager")
	_check(settings != null, "setup: SettingsManager autoload present")
	if settings == null:
		return
	var canvas: Vector2 = root.get_visible_rect().size

	print("\n=== (a) persistence round-trip ===")
	settings.set_touch_layout({"MoveStick": Vector3(0.25, 0.75, 1.2)})
	await process_frame
	var file_l: Dictionary = _read_file_layout()
	_check(file_l.has("MoveStick") and file_l["MoveStick"] is Vector3
			and absf(float(file_l["MoveStick"].x) - 0.25) < 0.001
			and absf(float(file_l["MoveStick"].y) - 0.75) < 0.001
			and absf(float(file_l["MoveStick"].z) - 1.2) < 0.001,
			"a: file carries the MoveStick Vector3")
	settings.load_settings()
	_check(settings.touch_layout.has("MoveStick")
			and settings.touch_layout["MoveStick"] is Vector3,
			"a: load_settings restores the dict")
	settings.clear_touch_layout()
	await process_frame
	_check(_read_file_layout().is_empty(), "a: clear empties the file section")
	_check(settings.touch_layout.is_empty(), "a: clear empties the dict")

	print("\n=== (b) editor behavior ===")
	settings.touch_layout = {}    # direct property — no save
	var editor: Node = (load("res://Scenes/UI/TouchLayoutEditor.tscn") as PackedScene).instantiate()
	root.add_child(editor)
	await process_frame
	await process_frame
	editor.visible = true
	await process_frame
	var tc: Node = editor.get_node("%TouchControls")
	var names: Array = tc.get_control_names()
	_check(Input.emulate_touch_from_mouse == true, "b: enter sets emulate_touch_from_mouse")
	_check(Input.emulate_mouse_from_touch == true, "b: enter keeps mouse_from_touch (menu contract)")
	_check(tc.visible == true, "b: enter shows the TouchControls instance")
	_check(editor.get_node("%OverlayLayer").visible == true,
			"b: enter shows the overlay layer")
	# Regression guard for the invisible-controls bug: CanvasLayer.layer is a
	# GLOBAL sort key — nested layers do not stack relative to their parent's
	# canvas, so the editor must use explicit layers above the menu's layer 1.
	_check(tc.layer == 10 and editor.get_node("%OverlayLayer").layer == 11,
			"b: explicit global layers (controls 10, overlay 11) sort above the menu canvas")
	_check(tc.get_node("%MoveStick").capture_enabled == false
			and tc.get_node("%AimStick").capture_enabled == false,
			"b: sticks suppressed in editor mode")
	_check(str(tc.get_node("%JumpButton").action) == ""
			and str(tc.get_node("%AttackButton").action) == "",
			"b: gameplay actions blanked")

	# --- select each control ---
	var all_selected := true
	for name in names:
		editor._input(_touch_event(0, true, tc.get_control_rect(name).get_center()))
		await process_frame
		if editor._selected != name:
			all_selected = false
			print("    (select miss: %s)" % name)
		editor._input(_touch_event(0, false, tc.get_control_rect(name).get_center()))
		await process_frame
	_check(all_selected, "b: tapping each control selects it")

	# --- selection box + pair tracking (re-select AttackButton first — the
	#     loop above left the LAST control selected) ---
	editor._input(_touch_event(0, true, tc.get_control_rect("AttackButton").get_center()))
	await process_frame
	editor._input(_touch_event(0, false, tc.get_control_rect("AttackButton").get_center()))
	await process_frame
	var box: Node = editor.get_node("%SelectionBox")
	var minus_b: Node = editor.get_node("%MinusButton")
	var plus_b: Node = editor.get_node("%PlusButton")
	var padded: Rect2 = tc.get_control_rect("AttackButton").grow(8.0)
	var box_rect: Rect2 = box.get_global_rect()
	_check(box.visible and absf(box_rect.position.x - padded.position.x) < 0.51
			and absf(box_rect.position.y - padded.position.y) < 0.51,
			"b: selection box wraps the control (padded 8)")
	_check(minus_b.visible and plus_b.visible, "b: minus/plus pair visible with a selection")
	var m_rect: Rect2 = minus_b.get_global_rect()
	var pair_above: bool = m_rect.end.y <= padded.position.y
	var pair_below: bool = m_rect.position.y >= padded.end.y
	_check(pair_above or pair_below, "b: pair sits clear of the box (above or below)")
	_check(root.get_visible_rect().encloses(m_rect.grow(0.5)), "b: pair stays on-canvas")

	# --- overlay exclusion (the pair is VISIBLE while a control is selected,
	#     so the exclusion path is genuinely exercised) ---
	editor._input(_touch_event(0, true, plus_b.get_global_rect().get_center()))
	await process_frame
	_check(editor._selected == "AttackButton",
			"b: tapping the plus button never changes the selection")
	editor._input(_touch_event(0, false, plus_b.get_global_rect().get_center()))
	await process_frame

	# --- drag with clamping + commit ---
	editor._input(_touch_event(1, true, tc.get_control_rect("JumpButton").get_center()))
	await process_frame
	_check(editor._selected == "JumpButton", "b: drag starts by selecting JumpButton")
	var before_pos: Vector2 = tc.get_control_node("JumpButton").position
	# Drag left-up: the procedural JumpButton sits ~3px from the canvas right
	# edge — dragging right would clamp (covered by the far-drag check below).
	editor._input(_drag_event(1, tc.get_control_rect("JumpButton").get_center() + Vector2(-120.0, -60.0)))
	await process_frame
	var after_pos: Vector2 = tc.get_control_node("JumpButton").position
	_check(absf(after_pos.x - (before_pos.x - 120.0)) < 0.51
			and absf(after_pos.y - (before_pos.y - 60.0)) < 0.51,
			"b: drag moves the control by the pointer delta")
	editor._input(_drag_event(1, Vector2(-5000.0, -5000.0)))
	await process_frame
	var clamped_rect: Rect2 = tc.get_control_rect("JumpButton")
	_check(root.get_visible_rect().encloses(clamped_rect.grow(0.5)),
			"b: far off-canvas drag clamps the control on-canvas")
	editor._input(_touch_event(1, false, Vector2(-5000.0, -5000.0)))
	await process_frame
	var entry: Variant = settings.touch_layout.get("JumpButton")
	var node_pos: Vector2 = tc.get_control_node("JumpButton").position
	_check(entry is Vector3
			and absf(float(entry.x) * canvas.x - node_pos.x) < 0.51
			and absf(float(entry.y) * canvas.y - node_pos.y) < 0.51,
			"b: drag release commits the clamped position")
	_check(_read_file_layout().get("JumpButton") is Vector3,
			"b: committed entry saved to the file")

	# --- + / - stepping with limits ---
	editor._input(_touch_event(0, true, tc.get_control_rect("JumpButton").get_center()))
	await process_frame
	editor._adjust_selected(0.1)
	await process_frame
	var mult: float = float(settings.touch_layout["JumpButton"].z)
	_check(absf(mult - 1.1) < 0.011, "b: plus steps mult 1.0 -> 1.1 (got %.3f)" % mult)
	_check(absf(float(tc.get_control_node("JumpButton").scale.x)
			- tc.get_layout_scale() * mult * tc.get_art_scale("JumpButton")) < 0.011,
			"b: applied scale = layout scale * mult * art scale")
	for i in 12:
		editor._adjust_selected(0.1)
	await process_frame
	_check(absf(float(settings.touch_layout["JumpButton"].z) - 2.0) < 0.011,
			"b: mult clamps at 2.0")
	for i in 18:
		editor._adjust_selected(-0.1)
	await process_frame
	_check(absf(float(settings.touch_layout["JumpButton"].z) - 0.5) < 0.011,
			"b: mult clamps at 0.5")

	# --- RESET ---
	editor._on_reset_pressed()
	await process_frame
	_check(settings.touch_layout.is_empty() and _read_file_layout().is_empty(),
			"b: RESET clears the saved layout")

	# --- exit restores the flags ---
	editor.visible = false
	await process_frame
	_check(Input.emulate_touch_from_mouse == false, "b: exit restores emulate_touch_from_mouse")
	_check(Input.emulate_mouse_from_touch == true, "b: exit keeps menu-contract mouse_from_touch")
	_check(tc.visible == false, "b: exit hides the TouchControls instance")
	editor.queue_free()
	await process_frame
	await process_frame

	print("\n=== (c) game-side apply ===")
	# DropButton at (0.7, 0.1) denormalizes cleanly — values near the right
	# edge would engage the on-canvas clamp (covered by the (b) far-drag test).
	settings.touch_layout = {"MoveStick": Vector3(0.2, 0.8, 1.5), "DropButton": Vector3(0.7, 0.1, 0.6)}
	var hud: Node = (load("res://Scenes/HUD.tscn") as PackedScene).instantiate()
	root.add_child(hud)
	await process_frame
	await process_frame
	var gtc: Node = hud.get_node("TouchControls")
	var gcanvas: Vector2 = root.get_visible_rect().size
	var ms_pos: Vector2 = gtc.get_control_node("MoveStick").position
	_check(absf(ms_pos.x - 0.2 * gcanvas.x) < 0.51 and absf(ms_pos.y - 0.8 * gcanvas.y) < 0.51,
			"c: MoveStick denormalized (position x %.0f, y %.0f)" % [ms_pos.x, ms_pos.y])
	_check(absf(float(gtc.get_control_node("MoveStick").scale.x) - gtc.get_layout_scale() * 1.5) < 0.011,
			"c: MoveStick scale = btn_scale * 1.5")
	var db_pos: Vector2 = gtc.get_control_node("DropButton").position
	_check(absf(db_pos.x - 0.7 * gcanvas.x) < 0.51 and absf(db_pos.y - 0.1 * gcanvas.y) < 0.51,
			"c: DropButton denormalized (position x %.0f, y %.0f)" % [db_pos.x, db_pos.y])
	_check(absf(float(gtc.get_control_node("DropButton").scale.x)
			- gtc.get_layout_scale() * 0.6 * gtc.get_art_scale("DropButton")) < 0.011,
			"c: DropButton scale = btn_scale * 0.6 * art scale")

	# Resize: positions re-denormalize to the new canvas.
	root.size = Vector2i(1080, 1920)
	await process_frame
	await process_frame
	var gcanvas2: Vector2 = root.get_visible_rect().size
	var ms_pos2: Vector2 = gtc.get_control_node("MoveStick").position
	_check(absf(ms_pos2.x - 0.2 * gcanvas2.x) < 0.51 and absf(ms_pos2.y - 0.8 * gcanvas2.y) < 0.51,
			"c: resize re-denormalizes positions")

	# Procedural snapshot at this canvas (dict cleared) — the reference for
	# fallback + clear assertions.
	settings.touch_layout = {}
	gtc._layout_buttons()
	await process_frame
	var procedural: Dictionary = _positions_snapshot(gtc, names)

	# Partial dict + stale key: saved control custom, others procedural.
	settings.touch_layout = {"JumpButton": Vector3(0.3, 0.3, 1.0), "GhostButton": Vector3(0.1, 0.1, 1.0)}
	gtc._layout_buttons()
	await process_frame
	var jb_pos: Vector2 = gtc.get_control_node("JumpButton").position
	_check(absf(jb_pos.x - 0.3 * gcanvas2.x) < 0.51 and absf(jb_pos.y - 0.3 * gcanvas2.y) < 0.51,
			"c: partial dict applies the saved control")
	var others_procedural := true
	for name in names:
		if name != "JumpButton" and gtc.get_control_node(name).position != procedural[name]:
			others_procedural = false
	_check(others_procedural, "c: unsaved controls keep procedural positions (per-control fallback)")

	# Clear -> procedural returns.
	settings.touch_layout = {}
	gtc._layout_buttons()
	await process_frame
	var cleared_matches := true
	for name in names:
		if gtc.get_control_node(name).position != procedural[name]:
			cleared_matches = false
	_check(cleared_matches, "c: clear returns the procedural layout")

	print("\n=== (d) layout_probe contract ===")
	# Prove the force-default in layout_probe is load-bearing: a custom dict
	# really changes the applied layout.
	settings.touch_layout = {"MoveStick": Vector3(0.05, 0.05, 1.0)}
	gtc._layout_buttons()
	await process_frame
	var custom_pos: Vector2 = gtc.get_control_node("MoveStick").position
	var differs := absf(custom_pos.x - procedural["MoveStick"].x) > 1.0 \
			or absf(custom_pos.y - procedural["MoveStick"].y) > 1.0
	_check(differs, "d: a custom dict changes the applied layout")
	settings.touch_layout = {}
	gtc._layout_buttons()
	await process_frame
	_check(gtc.get_control_node("MoveStick").position == procedural["MoveStick"],
			"d: forcing {} restores the procedural layout (what layout_probe does)")

	hud.queue_free()
	await process_frame