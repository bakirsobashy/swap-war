extends Control

## Scoreboard team marker: a filled circle with an ink outline (Notebook
## Doodle). Drawn in code so it stays crisp and recolours on every swap.

const OUTLINE_WIDTH := 2.0

var color: Color = Color.WHITE:
	set(value):
		color = value
		queue_redraw()

func _init() -> void:
	custom_minimum_size = Vector2(18, 18)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - OUTLINE_WIDTH * 0.5
	draw_circle(center, radius, color, true, -1.0, true)
	draw_circle(center, radius, TeamPalette.INK, false, OUTLINE_WIDTH, true)
