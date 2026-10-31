extends Control

## Touch controls layout editor — an empty-background screen with the REAL
## touch controls on it (WYSIWYG): tap a control to select it (brown box +
## minus/plus pair above it), drag to reposition, minus/plus to resize
## (0.5x-2.0x in 10% steps). The custom layout persists through
## SettingsManager ([touch_layout] section) and is applied per-control in
## TouchControls._layout_buttons — this editor applies it through the SAME
## path, so what you edit is exactly what you get in gameplay.
##
## Lifecycle is driven by this panel's own visibility flips (MainMenu's
## _show_panel performs them): enter owns the nested layers' visibility and
## the emulation flags; every hide path (BACK, panel switch, scene change
## via _exit_tree) restores them.

## Emitted by BACK — MainMenu owns panel navigation.
signal close_requested()

const SIZE_STEP: float = 0.1
const SELECTION_PADDING: float = 8.0
const SIZE_BUTTON_SIZE := Vector2(72.0, 60.0)
## Clears the menu theme's hatched button shadow (drawn ~12 px past the rect).
const SIZE_BUTTON_GAP: float = 14.0
## Hit-test priority: visible buttons before the sticks' (invisible, larger)
## grab zones — a button dragged inside a stick's zone must stay selectable.
const HIT_TEST_ORDER: Array[String] = ["JumpButton", "AttackButton", "DropButton", "MoveStick", "AimStick"]

@onready var touch_controls: CanvasLayer = %TouchControls
@onready var _overlay_layer: CanvasLayer = %OverlayLayer
@onready var selection_box: Panel = %SelectionBox
@onready var plus_button: Button = %PlusButton
@onready var minus_button: Button = %MinusButton
@onready var _back_button: Button = %BackButton
@onready var _reset_button: Button = %ResetButton

var _active: bool = false
var _selected: String = ""
var _drag_touch_index: int = -1
var _drag_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	# The nested canvases start closed whatever the scene file says: a Godot
	# re-save once dropped TouchControls' `visible = false` and the main menu
	# showed the touch controls until the editor was opened and closed.
	# _enter_editor opens them; CanvasLayers never follow this Control's
	# visibility on their own.
	_overlay_layer.visible = false
	touch_controls.visible = false
	visibility_changed.connect(_on_visibility_changed)
	# CONNECT_DEFERRED: TouchControls also listens to size_changed and
	# re-applies the layout; the deferred call guarantees the box re-tracks
	# AFTER positions update, regardless of connection registration order.
	get_viewport().size_changed.connect(_on_viewport_resized, CONNECT_DEFERRED)
	if get_tree().current_scene == self:
		visible = true    # convenience: the scene is runnable standalone

func _on_visibility_changed() -> void:
	if visible:
		_enter_editor()
	else:
		_exit_editor()

func _enter_editor() -> void:
	_active = true
	_selected = ""
	_drag_touch_index = -1
	# Own the canvases explicitly — CanvasLayer visibility never follows
	# this shown/hidden Control root.
	_overlay_layer.visible = true
	touch_controls.visible = true
	_update_selection_ui()
	# Desktop gets synthetic touch from mouse (WYSIWYG mouse editing);
	# mouse-from-touch stays true (menu contract) so phones can tap the
	# overlay Control buttons. Emulated events carry device -1 — both flags
	# on cannot loop.
	Input.emulate_touch_from_mouse = true
	Input.emulate_mouse_from_touch = true

func _exit_editor() -> void:
	if not _active:
		return
	_active = false
	_selected = ""
	_drag_touch_index = -1
	_overlay_layer.visible = false
	touch_controls.visible = false
	_update_selection_ui()
	Input.emulate_touch_from_mouse = false
	Input.emulate_mouse_from_touch = true    # menu contract (engine default)

func _exit_tree() -> void:
	# Scene change while open must not leak the emulation flags.
	_exit_editor()

func _play_click() -> void:
	if AudioManager:
		AudioManager.play_ui_click()

## One raw-touch code path: phone touches and desktop mouse (via
## emulate_touch_from_mouse) both arrive as InputEventScreenTouch/Drag.
func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if _drag_touch_index != -1:
				return                    # one manipulating finger
			if _over_overlay_ui(t.position):
				return                    # raw _input bypasses GUI consumption
			var hit := _hit_test(t.position)
			if hit != "":
				_selected = hit
				_drag_touch_index = t.index
				_drag_offset = touch_controls.get_control_node(hit).position - t.position
				_update_selection_ui()
		elif t.index == _drag_touch_index:
			_drag_touch_index = -1
			_commit_selected()            # persist the final drag position
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _drag_touch_index and _selected != "":
			_move_selected_to(d.position + _drag_offset)

func _over_overlay_ui(pos: Vector2) -> bool:
	for b: Control in [plus_button, minus_button, _back_button, _reset_button]:
		if b.visible and b.get_global_rect().has_point(pos):
			return true
	return false

func _hit_test(pos: Vector2) -> String:
	for name in HIT_TEST_ORDER:
		if touch_controls.get_control_rect(name).has_point(pos):
			return name
	return ""

## Target canvas position -> normalized entry -> mutate the in-memory dict
## -> re-run the REAL _layout_buttons (applies + clamps). No disk write per
## drag frame.
func _move_selected_to(canvas_pos: Vector2) -> void:
	var canvas := get_viewport().get_visible_rect().size
	var entry := _current_entry(_selected)
	entry.x = canvas_pos.x / canvas.x
	entry.y = canvas_pos.y / canvas.y
	_write_entry(_selected, entry)

func _write_entry(name: String, entry: Vector3) -> void:
	SettingsManager.touch_layout[name] = entry
	touch_controls._layout_buttons()
	_position_selection_ui()

## Drag release / +− press: re-read the APPLIED (possibly clamped) position
## back into the entry — the file always matches the screen — then save.
func _commit_selected() -> void:
	if _selected == "" or SettingsManager == null:
		return
	if not SettingsManager.touch_layout.has(_selected):
		# Bare selection, never dragged or resized — nothing to save.
		return
	var entry: Vector3 = SettingsManager.touch_layout[_selected]
	var node = touch_controls.get_control_node(_selected)
	var canvas := get_viewport().get_visible_rect().size
	entry.x = node.position.x / canvas.x
	entry.y = node.position.y / canvas.y
	SettingsManager.touch_layout[_selected] = entry    # Vector3 is a VALUE type
	SettingsManager.set_touch_layout(SettingsManager.touch_layout)

func _current_entry(name: String) -> Vector3:
	var existing: Variant = SettingsManager.touch_layout.get(name)
	if existing is Vector3:
		return existing
	# First edit of a procedurally-placed control: capture its normalized
	# position; mult 1.0 == the automatic size at any resolution.
	var node = touch_controls.get_control_node(name)
	var canvas := get_viewport().get_visible_rect().size
	return Vector3(node.position.x / canvas.x, node.position.y / canvas.y, 1.0)

func _on_plus_pressed() -> void:
	_adjust_selected(SIZE_STEP)

func _on_minus_pressed() -> void:
	_adjust_selected(-SIZE_STEP)

func _adjust_selected(delta: float) -> void:
	if not _active or _selected == "":
		return
	var entry := _current_entry(_selected)
	entry.z = clampf(entry.z + delta,
			touch_controls.SIZE_MULT_MIN, touch_controls.SIZE_MULT_MAX)
	_write_entry(_selected, entry)
	# A size change can push the control off-canvas — the clamp pulls it
	# back; commit re-syncs the clamped position and saves (discrete change).
	_commit_selected()

func _on_reset_pressed() -> void:
	if not _active:
		return
	if SettingsManager:
		SettingsManager.clear_touch_layout()
	touch_controls._layout_buttons()    # empty dict -> pure procedural
	_position_selection_ui()            # selection kept; box tracks the control "home"

func _on_back_pressed() -> void:
	close_requested.emit()               # MainMenu returns to the SETTINGS panel

func _update_selection_ui() -> void:
	var has: bool = _active and _selected != ""
	selection_box.visible = has
	plus_button.visible = has
	minus_button.visible = has
	if has:
		_position_selection_ui()

## The box wraps the control's HIT-TEST rect (grab radius for sticks,
## texture x scale for buttons) — it marks exactly what a tap selects. The
## minus/plus pair sits above the box, flipping below near the top edge.
func _position_selection_ui() -> void:
	if _selected == "":
		return
	var padded: Rect2 = touch_controls.get_control_rect(_selected).grow(SELECTION_PADDING)
	selection_box.position = padded.position
	selection_box.size = padded.size
	var canvas := get_viewport().get_visible_rect().size
	var pair_w := SIZE_BUTTON_SIZE.x * 2.0 + SIZE_BUTTON_GAP
	var top_y: float = padded.position.y - SIZE_BUTTON_GAP - SIZE_BUTTON_SIZE.y
	if top_y < 0.0:
		top_y = padded.end.y + SIZE_BUTTON_GAP
	var left_x := clampf(padded.get_center().x - pair_w * 0.5, 0.0,
			maxf(canvas.x - pair_w, 0.0))
	minus_button.position = Vector2(left_x, top_y)
	plus_button.position = Vector2(left_x + SIZE_BUTTON_SIZE.x + SIZE_BUTTON_GAP, top_y)

func _on_viewport_resized() -> void:
	if _active and _selected != "":
		_position_selection_ui()