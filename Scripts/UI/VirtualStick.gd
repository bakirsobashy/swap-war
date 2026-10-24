class_name VirtualStick
extends Node2D

## Twin-stick analog control for touch play. One deliberate exception to the
## "gameplay touch = TouchScreenButton" rule: TouchScreenButton fires binary
## actions only, while this node injects ANALOG strength via
## Input.action_press(action, strength) (Input.get_axis reads live strengths).
## Buttons stay TouchScreenButtons; only the two sticks are this node.
##
## Consumes RAW InputEventScreenTouch/ScreenDrag — those exist independently
## of the mouse-from-touch emulation flag, so sticks work during play with
## emulation OFF (Attack is mouse-bound; emulation must stay off then).
##
## Never calls set_input_as_handled(): children receive _input before parents,
## and consuming here would starve TouchControls' idle-hide activity tracker
## (a resting thumb would read as no activity and AUTO mode would hide the
## controls mid-hold).

enum Role { MOVE, AIM }

# Injected gameplay actions (project input map).
const ACTION_LEFT: StringName = &"Move_Left"
const ACTION_RIGHT: StringName = &"Move_Right"
const ACTION_DOWN: StringName = &"Move_Down"

# Geometry in LOCAL px — the node's scale (set by TouchControls layout per
# viewport) carries resolution, so every value below is resolution-free.
const BASE_SPRITE_SCALE: float = 2.5   # 64px well texture -> 160px
const BASE_RADIUS: float = 32.0 * BASE_SPRITE_SCALE      # 80
const KNOB_SPRITE_SCALE: float = 1.0   # 64px knob at native size
const KNOB_RADIUS: float = 32.0 * KNOB_SPRITE_SCALE      # 32
## Knob edge reaches well edge at full deflection.
const MAX_DEFLECTION: float = BASE_RADIUS - KNOB_RADIUS  # 48
## Radial deadzone, fraction of MAX_DEFLECTION (12px). Replaces the InputMap
## deadzone, which Input.action_press injection bypasses.
const DEADZONE_RATIO: float = 0.25
## Down-push = drop-through. Engage at 65% of travel, release at 50% — the
## hysteresis kills boundary flutter, and 0.65 sits far above a running
## diagonal so platform-drop is never accidental. Holding down matches PC
## (held Move_Down suppresses jump on one-ways — same as holding S).
const DOWN_PRESS_RATIO: float = 0.65
const DOWN_RELEASE_RATIO: float = 0.50
## Touches landing this far outside the well still grab it.
const ACTIVATION_SLOP: float = 12.0

@export var role: Role = Role.MOVE

@onready var _base: Sprite2D = $Base
@onready var _knob: Sprite2D = $Knob

## Per-axis deflection in [-1, 1]; Vector2.ZERO when idle or deadzoned.
## The AIM stick exposes this to Actor-Movement through TouchControls.
var value: Vector2 = Vector2.ZERO
## True while THIS stick owns a finger (even inside the deadzone).
var is_held: bool = false
## When false the stick ignores raw touch events entirely. TouchControls
## clears this on its editor-mode instance so layout-editor drags own every
## finger. (Sticks must stay drawn for WYSIWYG; _input ordering — children
## first — means a capture here would fight the editor panel's handler.)
var capture_enabled: bool = true

var _touch_index: int = -1
var _down_engaged: bool = false
## Actions currently pressed BY THIS STICK — guarantees we never
## Input.action_release() an action a held keyboard key owns.
var _owned_actions: Dictionary = {}

func _ready() -> void:
	# Parent layer is PROCESS_MODE_ALWAYS; be explicit so the stick behaves
	# the same if ever instanced elsewhere.
	process_mode = PROCESS_MODE_ALWAYS
	_base.scale = Vector2.ONE * BASE_SPRITE_SCALE
	_knob.scale = Vector2.ONE * KNOB_SPRITE_SCALE
	_knob.position = Vector2.ZERO

func _exit_tree() -> void:
	# Actions live in the global Input singleton — a freed stick must never
	# leave Move_Left pressed behind (scene change mid-hold).
	release_stick()

func _input(event: InputEvent) -> void:
	if not capture_enabled:
		return
	# Hidden UI must never capture or inject. is_visible_in_tree() does not
	# reliably reflect CanvasLayer.visible for Node2D children, so check the
	# parent layer explicitly.
	var layer := get_parent()
	if layer is CanvasLayer and not (layer as CanvasLayer).visible:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _touch_index == -1:
			var local := _to_local(touch.position)
			# Activation test is LOCAL length vs LOCAL radius — the touch
			# position has already been divided by the node scale.
			if local.length() <= BASE_RADIUS + ACTIVATION_SLOP:
				_touch_index = touch.index
				is_held = true
				_update_value(local)
		elif not touch.pressed and touch.index == _touch_index:
			release_stick()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_index:
			_update_value(_to_local(drag.position))

func _to_local(canvas_pos: Vector2) -> Vector2:
	# Raw 2D events arrive in CANVAS coordinates under the canvas_items
	# stretch. This transform includes the CanvasLayer, node position, AND
	# node scale, so the result lands in the local units every geometry
	# constant above is defined in.
	return get_global_transform_with_canvas().affine_inverse() * canvas_pos

## Canvas-space grab radius (activation zone scaled by layout scale).
func get_activation_radius() -> float:
	return (BASE_RADIUS + ACTIVATION_SLOP) * scale.x

## Canvas-space touch rect for Tools/layout_probe.gd — covers the full grab
## radius, not just the visible well (the layer transform is identity).
func get_touch_rect() -> Rect2:
	var r := get_activation_radius()
	return Rect2(position - Vector2(r, r), Vector2(r * 2.0, r * 2.0))

func _update_value(local_pos: Vector2) -> void:
	var offset := local_pos.limit_length(MAX_DEFLECTION)
	if offset.length() < DEADZONE_RATIO * MAX_DEFLECTION:
		value = Vector2.ZERO
	else:
		value = offset / MAX_DEFLECTION   # linear per-axis analog ramp
	_knob.position = offset
	if role == Role.MOVE:
		_apply_move_actions()

func _apply_move_actions() -> void:
	# Crossing center swaps both strengths in the same call — no stuck state.
	_set_action_strength(ACTION_LEFT, maxf(-value.x, 0.0))
	_set_action_strength(ACTION_RIGHT, maxf(value.x, 0.0))
	# Down push with hysteresis (engage 0.65, release 0.50 of travel).
	var down := maxf(value.y, 0.0)
	if not _down_engaged and down >= DOWN_PRESS_RATIO:
		_down_engaged = true
	elif _down_engaged and down <= DOWN_RELEASE_RATIO:
		_down_engaged = false
	_set_action_strength(ACTION_DOWN, 1.0 if _down_engaged else 0.0)

func _set_action_strength(action: StringName, strength: float) -> void:
	if strength > 0.0:
		# Idempotent while held: overwrites the strength each call, and
		# Input.get_axis reads the live strengths -> analog movement force.
		Input.action_press(action, strength)
		_owned_actions[action] = true
	elif _owned_actions.has(action):
		# Only release what THIS stick pressed — never a held keyboard key.
		Input.action_release(action)
		_owned_actions.erase(action)

## Finger lift, UI hidden mid-hold, settings flip, scene teardown.
func release_stick() -> void:
	_touch_index = -1
	is_held = false
	value = Vector2.ZERO
	_down_engaged = false
	_knob.position = Vector2.ZERO
	if role == Role.MOVE:
		for action in _owned_actions.keys():
			Input.action_release(action)
		_owned_actions.clear()