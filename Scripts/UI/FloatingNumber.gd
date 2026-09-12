class_name FloatingNumber
extends Node2D

## Shows a damage number, floats upward in world space, then fades out and frees.

@export var float_speed: float = 30.0
@export var lifetime: float = 1.0

@onready var _label: Label = $Label

var _timer: float = 0.0

func _ready() -> void:
	if not _label:
		return
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _label.label_settings:
		_label.label_settings = _label.label_settings.duplicate()
	if _pending_color:
		_label.label_settings.font_color = _pending_color
		_pending_color = Color.WHITE

var _pending_color: Color = Color.WHITE

func start(value: float, color: Color, _offset: Vector2 = Vector2.ZERO) -> void:
	_pending_color = color
	_timer = lifetime
	if not _label:
		return
	_label.text = str(int(round(value)))
	if _label.label_settings:
		_label.label_settings.font_color = color
	else:
		_label.modulate = color

func _process(delta: float) -> void:
	if _timer <= 0.0:
		return

	position += Vector2.UP * float_speed * delta
	_timer -= delta

	var t: float = clamp(_timer / lifetime, 0.0, 1.0)
	if _label and _label.label_settings:
		var c: Color = _label.label_settings.font_color
		c.a = t
		_label.label_settings.font_color = c
	elif _label:
		_label.modulate.a = t

	if _timer <= 0.0:
		queue_free()
