class_name HealthBar2D
extends Node2D

## World-space health bar rendered through a SubViewport so it scales with camera zoom.

@onready var _sub_viewport: SubViewport = $SubViewport
@onready var _bg: ColorRect = $SubViewport/Background
@onready var _fill: ColorRect = $SubViewport/Fill
@onready var _sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	if _sprite and _sub_viewport:
		_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_sprite.texture = _sub_viewport.get_texture()
		_sprite.centered = true

func set_color(color: Color) -> void:
	if _fill:
		_fill.color = color

func update_value(current: float, max_health: float) -> void:
	if not _fill or not _bg:
		return
	var ratio: float = clamp(current / max_health, 0.0, 1.0)
	# Use offset_right instead of size because ColorRect size is clamped
	# by its custom_minimum_size, which would keep the bar full width forever.
	_fill.offset_right = _bg.size.x * ratio
