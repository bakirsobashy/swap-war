class_name SafeAreaUtil

## Safe-area helpers for notched / rounded-corner phone screens.

## Returns the safe-area insets in canvas units, as (left, top, right, bottom).
## On platforms without a cutout (desktop, headless) this returns (0, 0, 0, 0).
static func get_canvas_insets(viewport: Viewport) -> Vector4:
	var window_size := DisplayServer.window_get_size()
	var safe_rect := DisplayServer.get_display_safe_area()
	if window_size.x <= 0 or window_size.y <= 0:
		return Vector4.ZERO

	# Insets in window pixels.
	var left_px: int = safe_rect.position.x
	var top_px: int = safe_rect.position.y
	var right_px: int = window_size.x - (safe_rect.position.x + safe_rect.size.x)
	var bottom_px: int = window_size.y - (safe_rect.position.y + safe_rect.size.y)

	# Convert window pixels to canvas units using the per-axis canvas/window
	# ratio (with the canvas_items stretch mode the canvas origin maps to the
	# window origin, so proportional per-axis conversion is exact).
	var canvas_size := viewport.get_visible_rect().size
	var scale_x := canvas_size.x / float(window_size.x)
	var scale_y := canvas_size.y / float(window_size.y)

	return Vector4(
		maxf(left_px, 0.0) * scale_x,
		maxf(top_px, 0.0) * scale_y,
		maxf(right_px, 0.0) * scale_x,
		maxf(bottom_px, 0.0) * scale_y
	)