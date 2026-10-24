class_name FloatingNumber
extends Node2D

## Damage number (Notebook Doodle): team-coloured Patrick Hand with an ink
## outline. Pops in, floats upward in world space, then fades out and frees.

@export var float_speed: float = 30.0
@export var lifetime: float = 1.0
@export var pop_scale: float = 1.4
@export var pop_seconds: float = 0.15

@onready var _label: Label = $Label

var _timer: float = 0.0
var _pending_color: Color = Color.WHITE

func _ready() -> void:
	# Per-instance settings: the colour is set per hit.
	_label.label_settings = _label.label_settings.duplicate()
	_label.label_settings.font_color = _pending_color
	scale = Vector2.ONE * pop_scale
	create_tween().tween_property(self, "scale", Vector2.ONE, pop_seconds) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func start(value: float, color: Color, _offset: Vector2 = Vector2.ZERO) -> void:
	_pending_color = color
	_timer = lifetime
	if not _label:
		return
	_label.text = str(int(round(value)))
	_label.label_settings.font_color = color

func _process(delta: float) -> void:
	if _timer <= 0.0:
		return

	position += Vector2.UP * float_speed * delta
	_timer -= delta
	# Fade the whole node so the ink outline goes with the fill.
	modulate.a = clampf(_timer / lifetime, 0.0, 1.0)

	if _timer <= 0.0:
		queue_free()
