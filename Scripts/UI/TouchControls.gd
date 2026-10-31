extends CanvasLayer

## Twin-stick touch controls for mobile/web play.
##
## Buttons here are TouchScreenButtons so multi-touch works (hold a stick
## while pressing Jump or Drop); Control buttons would only respond to the
## emulated mouse, and mouse-from-touch emulation only ever tracks the FIRST
## finger on screen. The two analog sticks are the single deliberate
## exception: VirtualStick nodes consume raw touch events (TouchScreenButton
## has no analog strength) — they inject Move actions via Input.action_press
## and expose the aim vector through get_aim_stick_value().

const MARGIN: float = 24.0
const GAP: float = 14.0
## Seconds without any touch before the controls hide (AUTO mode only).
const IDLE_HIDE_DELAY: float = 4.0

## The five touch controls. The layout editor and probes read this through the
## instance (single source of truth). Pause is not a touch control — the HUD's
## own pause button (top-right) serves touch and mouse alike.
const CONTROL_NAMES: Array[String] = ["MoveStick", "AimStick", "JumpButton", "AttackButton", "DropButton"]
## Size-multiplier limits for the saved custom layout (editor steps 0.1).
const SIZE_MULT_MIN: float = 0.5
const SIZE_MULT_MAX: float = 2.0
## Rects stay this far inside the canvas — layout_probe asserts
## canvas.encloses(rect.grow(0.5)), so >= 1.0 keeps custom layouts passing it.
const CANVAS_MARGIN: float = 1.0
## The Notebook Doodle touch art is drawn for 720p at its native size (jump
## 148 px), too tall to stack above the aim stick, so buttons draw at this
## fraction of it. Folded into node.scale (= layout scale * saved mult * art
## scale) so the full-resolution textures stay crisp at large layout scales.
## Sticks scale their own art (VirtualStick.ART_SCALE) and are 1.0 here.
const BUTTON_ART_SCALE := {
	"JumpButton": 0.65,
	"AttackButton": 0.65,
	"DropButton": 0.65,
}

## VirtualStick referenced through a preload path (never its class_name) so
## headless `-s` probes can load this script before the class registry is
## populated — the NavBaker/NavGraph precedent.
const VirtualStickScript := preload("res://Scripts/UI/VirtualStick.gd")

## Editor instances (the in-menu layout editor) show the REAL controls for
## WYSIWYG editing but never touch the emulation contract, never hide on
## idle, never gate visibility on settings, and never inject gameplay input.
@export var editor_mode := false

@onready var _drop_button: TouchScreenButton = %DropButton
@onready var _move_stick: VirtualStickScript = %MoveStick
@onready var _aim_stick: VirtualStickScript = %AimStick
@onready var _jump_button: TouchScreenButton = %JumpButton
@onready var _attack_button: TouchScreenButton = %AttackButton

var _last_activity_msec: int = 0
var _held_touches: int = 0

func _ready() -> void:
	# Keep processing while paused: _process is the touch->mouse emulation
	# authority, and it must turn emulation ON for the pause menu's buttons.
	process_mode = PROCESS_MODE_ALWAYS
	if editor_mode:
		_enter_editor_mode()
		return
	_visibility_changed()
	if SettingsManager:
		SettingsManager.settings_loaded.connect(_visibility_changed)
		SettingsManager.setting_changed.connect(_visibility_changed)
	get_viewport().size_changed.connect(_layout_buttons)
	_layout_buttons()
	_last_activity_msec = Time.get_ticks_msec()

func _enter_editor_mode() -> void:
	# Neutralize gameplay side effects on this menu-only instance:
	_move_stick.capture_enabled = false
	_aim_stick.capture_enabled = false
	_jump_button.action = &""       # blanked: a press anywhere cannot inject Jump
	_attack_button.action = &""     # same for Attack
	_drop_button.action = &""       # and Drop
	get_viewport().size_changed.connect(_layout_buttons)
	_layout_buttons()
	# No SettingsManager connects (a settings flip in the menu must not pop
	# the controls); no action restore — this instance never returns to
	# gameplay (gameplay HUDs instantiate their own non-editor instance).

func _process(_delta: float) -> void:
	# Editor instances never touch the emulation authority — in the menu the
	# flag must stay at its true default so phone taps work — and never
	# idle-hide (the editor owns this instance's visibility).
	if editor_mode:
		return
	# While paused, the only interactive UI is the pause / post-round menus,
	# whose buttons are Controls — touches must emulate mouse clicks there.
	# During play, emulation must stay OFF: the Attack action is bound to the
	# left mouse button, so with emulation on every first-finger tap anywhere
	# on screen would fire the held weapon and warp aim to the tap point.
	Input.emulate_mouse_from_touch = get_tree().paused
	# AUTO mode: hide after a while with no touches at all (a held finger
	# counts as activity, so a thumb resting on Move never hides the controls).
	if not visible or _held_touches > 0:
		return
	if SettingsManager == null or SettingsManager.touch_controls_mode != SettingsManager.TouchControlsMode.AUTO:
		return
	if Time.get_ticks_msec() - _last_activity_msec > IDLE_HIDE_DELAY * 1000.0:
		visible = false

func _input(event: InputEvent) -> void:
	# Only real touches count as activity: mouse input must neither keep the
	# controls shown (touchscreen laptops used with a mouse) nor be able to
	# bring hidden controls back.
	if event is InputEventScreenTouch:
		if event.pressed:
			_held_touches += 1
			_last_activity_msec = Time.get_ticks_msec()
			# Any touch on the screen brings hidden controls back.
			if not visible and _should_show_touch_controls():
				visible = true
		else:
			_held_touches = maxi(0, _held_touches - 1)
			_last_activity_msec = Time.get_ticks_msec()
	elif event is InputEventScreenDrag:
		_last_activity_msec = Time.get_ticks_msec()

func _exit_tree() -> void:
	# Scene change mid-hold must not leave injected actions pressed.
	_release_sticks()

## The aim stick has no InputMap action (fake aim actions were rejected) —
## this is the surface Actor-Movement reads. ZERO unless a finger is held
## past the stick's deadzone.
func get_aim_stick_value() -> Vector2:
	if _aim_stick == null:
		return Vector2.ZERO
	return _aim_stick.value

func _visibility_changed() -> void:
	visible = _should_show_touch_controls()
	if not visible:
		# Hidden mid-hold: no finger-lift event will ever arrive.
		_release_sticks()

func _release_sticks() -> void:
	if _move_stick:
		_move_stick.release_stick()
	if _aim_stick:
		_aim_stick.release_stick()

## Whether touch controls are in use at all (settings + device), ignoring the
## AUTO-mode idle hide.
func uses_touch_controls() -> bool:
	return _should_show_touch_controls()

func _should_show_touch_controls() -> bool:
	if editor_mode:
		return true
	if not SettingsManager:
		return true
	match SettingsManager.touch_controls_mode:
		SettingsManager.TouchControlsMode.HIDDEN:
			return false
		SettingsManager.TouchControlsMode.ALWAYS:
			return true
		_:
			return DisplayServer.is_touchscreen_available()

## Position every control for the current viewport, safe-area insets, and
## window size. Called on ready and on every viewport resize.
##
## Layout (user-approved): MoveStick bottom-left, AimStick bottom-right,
## JUMP + ATTACK stacked above the AimStick (ATTACK lowest, nearest the
## resting thumb — matching the old attack-outermost convention), DROP above
## that cluster. (Pause lives in the HUD's top-right corner, not here.)
func _layout_buttons() -> void:
	if not is_inside_tree() or _move_stick == null:
		return

	var viewport := get_viewport()
	var canvas_size: Vector2 = viewport.get_visible_rect().size
	var insets: Vector4 = SafeAreaUtil.get_canvas_insets(viewport)

	# Shrink on small canvases so portrait phones still fit everything.
	var btn_scale: float = get_layout_scale()
	var gap: float = GAP * btn_scale

	for name in CONTROL_NAMES:
		get_control_node(name).scale = Vector2.ONE * (btn_scale * get_art_scale(name))

	# TouchScreenButton draws with the texture's TOP-LEFT at the node position
	# (verified against engine source), so button positions are top-left
	# corners — while the sticks' Sprite2D children are centered, so stick
	# positions are CENTERS.
	var stick_radius: float = VirtualStickScript.BASE_RADIUS * btn_scale
	var side_margin: float = MARGIN * btn_scale
	var bottom_margin: float = insets.w + side_margin
	var stick_bottom: float = canvas_size.y - bottom_margin - stick_radius

	# Sticks: centers at the bottom corners.
	_move_stick.position = Vector2(
		insets.x + side_margin + stick_radius,
		stick_bottom
	)
	_aim_stick.position = Vector2(
		canvas_size.x - insets.z - side_margin - stick_radius,
		stick_bottom
	)

	# Right-side stack above the aim stick, right edges aligned with the
	# stick's well edge: ATTACK, JUMP, DROP going up. The stack base clears
	# the stick's full GRAB radius (well + activation slop) by the gap, so a
	# tap on the stack never lands inside the stick's grab zone.
	var right_edge: float = _aim_stick.position.x + stick_radius
	var grab_radius: float = _aim_stick.get_activation_radius()
	var size_attack: Vector2 = _scaled_size(_attack_button)
	var size_jump: Vector2 = _scaled_size(_jump_button)
	var size_drop: Vector2 = _scaled_size(_drop_button)
	var stack_bottom: float = _aim_stick.position.y - grab_radius - gap
	_attack_button.position = Vector2(
		right_edge - size_attack.x,
		stack_bottom - size_attack.y
	)
	_jump_button.position = Vector2(
		right_edge - size_jump.x,
		_attack_button.position.y - gap - size_jump.y
	)
	_drop_button.position = Vector2(
		right_edge - size_drop.x,
		_jump_button.position.y - gap - size_drop.y
	)


	_apply_saved_layout(canvas_size, btn_scale)

## The automatic resolution scale for the current viewport — the one formula
## for btn_scale, shared by the layout and the editor/probes.
func get_layout_scale() -> float:
	return clampf(get_viewport().get_visible_rect().size.y / 720.0, 0.55, 1.6)

## The six touch controls (CONTROL_NAMES, exposed for editor + probes).
func get_control_names() -> Array[String]:
	return CONTROL_NAMES

## Per-control art scale folded into node.scale (BUTTON_ART_SCALE; sticks 1.0).
func get_art_scale(name: String) -> float:
	return BUTTON_ART_SCALE.get(name, 1.0)

func get_control_node(name: String) -> Node2D:
	match name:
		"MoveStick": return _move_stick
		"AimStick": return _aim_stick
		"JumpButton": return _jump_button
		"AttackButton": return _attack_button
		"DropButton": return _drop_button
	return null

## The rect a tap selects (layout_probe's math exactly): sticks = full grab
## radius, buttons = texture x scale with the texture TOP-LEFT at position.
func get_control_rect(name: String) -> Rect2:
	var node := get_control_node(name)
	if node == null:
		return Rect2()
	if node is VirtualStickScript:
		return (node as VirtualStickScript).get_touch_rect()
	var btn := node as TouchScreenButton
	return Rect2(btn.position, _texture_size(btn) * btn.scale.abs())

## Apply the user's saved layout on top of the procedural placement.
## Per-control: no entry -> keep procedural position/scale. Editor and
## gameplay share this path, so the editor is exactly WYSIWYG.
func _apply_saved_layout(canvas_size: Vector2, btn_scale: float) -> void:
	if SettingsManager == null or SettingsManager.touch_layout.is_empty():
		return
	for name in CONTROL_NAMES:
		# Iterate KNOWN names only — stale dict keys are ignored.
		var entry: Variant = SettingsManager.touch_layout.get(name)
		if entry is Vector3:
			_apply_saved_entry(name, entry, canvas_size, btn_scale)

func _apply_saved_entry(name: String, entry: Vector3, canvas_size: Vector2, btn_scale: float) -> void:
	var node := get_control_node(name)
	if node == null:
		return
	node.scale = Vector2.ONE * (btn_scale * clampf(entry.z, SIZE_MULT_MIN, SIZE_MULT_MAX) * get_art_scale(name))
	var pos := Vector2(entry.x, entry.y) * canvas_size
	if node is VirtualStickScript:
		# Sticks: pos is the center — keep the whole grab radius on-canvas.
		var r: float = (node as VirtualStickScript).get_activation_radius()
		pos.x = clampf(pos.x, CANVAS_MARGIN, maxf(canvas_size.x - r - CANVAS_MARGIN, CANVAS_MARGIN))
		pos.y = clampf(pos.y, CANVAS_MARGIN, maxf(canvas_size.y - r - CANVAS_MARGIN, CANVAS_MARGIN))
	else:
		# NEW scale (set above) drives the clamp size.
		var size := _scaled_size(node as TouchScreenButton)
		pos.x = clampf(pos.x, CANVAS_MARGIN, maxf(canvas_size.x - size.x - CANVAS_MARGIN, CANVAS_MARGIN))
		pos.y = clampf(pos.y, CANVAS_MARGIN, maxf(canvas_size.y - size.y - CANVAS_MARGIN, CANVAS_MARGIN))
	node.position = pos

## On-canvas size of a button: texture x its applied node scale.
func _scaled_size(button: TouchScreenButton) -> Vector2:
	return _texture_size(button) * button.scale.abs()

func _texture_size(button: TouchScreenButton) -> Vector2:
	if button.texture_normal == null:
		return Vector2(48.0, 48.0)
	return button.texture_normal.get_size()

func _on_drop_button_pressed() -> void:
	# Editor instances never inject gameplay input.
	if editor_mode:
		return
	# The button's own `action` presses AND releases Drop_Weapon. Parsing a
	# press here without a release left the action held forever, so only
	# the first DROP (and no later E key press) ever registered.
	if get_tree().paused:
		return
	if AudioManager:
		AudioManager.play_ui_touch()
