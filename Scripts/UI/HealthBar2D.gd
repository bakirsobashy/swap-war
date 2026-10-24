class_name HealthBar2D
extends Node2D

## World-space health pill (Notebook Doodle): an ink-outlined paper capsule
## with a team-colour fill. Drawn in code, so it stays crisp at any camera
## zoom (no SubViewport) and recolours instantly on a team swap.

## World units. Arena cameras zoom out (~0.54x on the hazard arena), so this
## lands around 32x9 px on screen with a ~1.6 px ink outline.
const SIZE := Vector2(60.0, 16.0)
const OUTLINE := 3
const FILL_INSET := 4.5
const PAPER := Color(1.0, 0.996, 0.973)

var _color: Color = Color.WHITE
var _ratio: float = 1.0
var _frame := StyleBoxFlat.new()
var _fill := StyleBoxFlat.new()

func _init() -> void:
	_frame.bg_color = PAPER
	_frame.border_color = TeamPalette.INK
	_frame.set_border_width_all(OUTLINE)
	_frame.set_corner_radius_all(8)
	_frame.anti_aliasing = true
	_fill.set_corner_radius_all(4)
	_fill.anti_aliasing = true

func set_color(color: Color) -> void:
	_color = color
	queue_redraw()

func update_value(current: float, max_health: float) -> void:
	_ratio = clampf(current / max_health, 0.0, 1.0) if max_health > 0.0 else 0.0
	queue_redraw()

## For probes: the team colour the fill is drawn in.
func get_fill_color() -> Color:
	return _color

func _draw() -> void:
	var rect := Rect2(-SIZE * 0.5, SIZE)
	draw_style_box(_frame, rect)
	var inner := rect.grow(-FILL_INSET)
	if _ratio > 0.0 and inner.size.x > 0.0:
		_fill.bg_color = _color
		draw_style_box(_fill, Rect2(inner.position, Vector2(inner.size.x * _ratio, inner.size.y)))
