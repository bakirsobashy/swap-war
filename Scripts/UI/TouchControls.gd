extends CanvasLayer

## On-screen touch controls for mobile/web play.
##
## Every button here is a TouchScreenButton so multi-touch works (hold Move
## while pressing Jump or Drop). Control buttons would only respond to the
## emulated mouse, and mouse-from-touch emulation only ever tracks the FIRST
## finger on screen.

const MARGIN: float = 24.0
const GAP: float = 14.0
## Seconds without any touch before the controls hide (AUTO mode only).
const IDLE_HIDE_DELAY: float = 4.0

@onready var _pause_button: TouchScreenButton = %PauseButton
@onready var _drop_button: TouchScreenButton = %DropButton
@onready var _move_left: TouchScreenButton = %MoveLeft
@onready var _move_right: TouchScreenButton = %MoveRight
@onready var _move_down: TouchScreenButton = %MoveDown
@onready var _jump_button: TouchScreenButton = %JumpButton
@onready var _attack_button: TouchScreenButton = %AttackButton

var _last_activity_msec: int = 0
var _held_touches: int = 0

func _ready() -> void:
	# Keep processing while paused so the pause button can unpause the game.
	process_mode = PROCESS_MODE_ALWAYS
	_visibility_changed()
	if SettingsManager:
		SettingsManager.settings_loaded.connect(_visibility_changed)
		SettingsManager.setting_changed.connect(_visibility_changed)
	get_viewport().size_changed.connect(_layout_buttons)
	_layout_buttons()
	_last_activity_msec = Time.get_ticks_msec()

func _process(_delta: float) -> void:
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

func _visibility_changed() -> void:
	visible = _should_show_touch_controls()

func _should_show_touch_controls() -> bool:
	if not SettingsManager:
		return true
	match SettingsManager.touch_controls_mode:
		SettingsManager.TouchControlsMode.HIDDEN:
			return false
		SettingsManager.TouchControlsMode.ALWAYS:
			return true
		_:
			return DisplayServer.is_touchscreen_available()

## Position every button for the current viewport, safe-area insets, and window
## size. Called on ready and on every viewport resize.
func _layout_buttons() -> void:
	if not is_inside_tree() or _move_left == null:
		return

	var viewport := get_viewport()
	var canvas_size: Vector2 = viewport.get_visible_rect().size
	var insets: Vector4 = SafeAreaUtil.get_canvas_insets(viewport)

	# Shrink on small canvases so portrait phones still fit everything.
	var btn_scale: float = clampf(canvas_size.y / 720.0, 0.55, 1.6)

	# Arrows get an extra 1.5x so their touch targets are comfortable; the
	# round buttons are already large.
	var arrow_scale: float = btn_scale * 1.5
	_move_left.scale = Vector2.ONE * arrow_scale
	_move_right.scale = Vector2.ONE * arrow_scale
	_move_down.scale = Vector2.ONE * arrow_scale
	_jump_button.scale = Vector2.ONE * btn_scale
	_attack_button.scale = Vector2.ONE * btn_scale
	_drop_button.scale = Vector2.ONE * btn_scale
	_pause_button.scale = Vector2.ONE * btn_scale

	# TouchScreenButton draws with the texture's TOP-LEFT at the node position
	# (verified against engine source), so positions are top-left corners.
	var size_left: Vector2 = _texture_size(_move_left) * arrow_scale
	var size_right: Vector2 = _texture_size(_move_right) * arrow_scale
	var size_down: Vector2 = _texture_size(_move_down) * arrow_scale
	var size_jump: Vector2 = _texture_size(_jump_button) * btn_scale
	var size_attack: Vector2 = _texture_size(_attack_button) * btn_scale
	var size_drop: Vector2 = _texture_size(_drop_button) * btn_scale
	var size_pause: Vector2 = _texture_size(_pause_button) * btn_scale

	var bottom_margin: float = insets.w + MARGIN * btn_scale

	# Move arrows: bottom-left corner, side by side; Down (drop through one-way
	# platforms) sits at the end of the movement cluster.
	_move_left.position = Vector2(
		insets.x + MARGIN * btn_scale,
		canvas_size.y - bottom_margin - size_left.y
	)
	_move_right.position = _move_left.position + Vector2(size_left.x + GAP, 0.0)
	_move_down.position = _move_right.position + Vector2(size_right.x + GAP, 0.0)

	# Attack/Jump cluster: bottom-right corner, attack outermost, bottoms aligned.
	_attack_button.position = Vector2(
		canvas_size.x - insets.z - MARGIN * btn_scale - size_attack.x,
		canvas_size.y - bottom_margin - size_attack.y
	)
	_jump_button.position = _attack_button.position - Vector2(size_jump.x + GAP, size_attack.y - size_jump.y)

	# Drop hovers above the attack cluster, right-aligned with Attack.
	_drop_button.position = Vector2(
		_attack_button.position.x + size_attack.x - size_drop.x,
		_attack_button.position.y - GAP - size_drop.y
	)
	var drop_label := _drop_button.get_node_or_null("Label") as Control
	if drop_label:
		drop_label.position = Vector2.ZERO
		drop_label.size = _texture_size(_drop_button)

	# Pause: top-right corner.
	_pause_button.position = Vector2(
		canvas_size.x - insets.z - MARGIN * btn_scale - size_pause.x,
		insets.y + MARGIN * btn_scale
	)

func _texture_size(button: TouchScreenButton) -> Vector2:
	if button.texture_normal == null:
		return Vector2(48.0, 48.0)
	return button.texture_normal.get_size()

func _on_drop_button_pressed() -> void:
	# Ignore gameplay inputs while the game is paused.
	if get_tree().paused:
		return
	var ev := InputEventAction.new()
	ev.action = "Drop_Weapon"
	ev.pressed = true
	Input.parse_input_event(ev)
	if AudioManager:
		AudioManager.play_ui_touch()

func _on_pause_button_pressed() -> void:
	# Directly call PauseMenu's toggle so the button works for both touch and mouse.
	# Input.parse_input_event with InputEventAction is unreliable across nodes.
	var pause_menu := get_tree().current_scene.get_node_or_null("PauseMenu") as PauseMenu
	if pause_menu:
		pause_menu.toggle_pause()
	else:
		var ev := InputEventAction.new()
		ev.action = "Pause"
		ev.pressed = true
		Input.parse_input_event(ev)
	if AudioManager:
		AudioManager.play_ui_click()