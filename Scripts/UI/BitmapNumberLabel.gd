class_name BitmapNumberLabel
extends HBoxContainer

## Displays a non-negative integer as a row of digit textures.

@export var digit_prefix: String = "res://Assets/ui/numbers/ui_num"
@export var digit_suffix: String = ".png"
@export var digit_size: Vector2 = Vector2(32, 32)
@export var digit_separation: int = 2

var _digit_textures: Array[Texture2D] = []
var _digit_rects: Array[TextureRect] = []


func _ready() -> void:
	# Load single digits 0-9.
	for i in range(10):
		var path := "%s%d%s" % [digit_prefix, i, digit_suffix]
		var tex := load(path) as Texture2D
		if not tex:
			push_warning("BitmapNumberLabel: failed to load digit texture '%s'" % path)
		_digit_textures.append(tex)

	add_theme_constant_override("separation", digit_separation)


func set_value(value: int, modulate_color: Color = Color.WHITE) -> void:
	value = maxi(value, 0)

	# Use a single composed sprite for common values like 10 if the artist provided one.
	var composed: Texture2D = _texture_for_number(value)
	if composed:
		_ensure_digit_count(1)
		var rect: TextureRect = _digit_rects[0]
		rect.texture = composed
		rect.modulate = modulate_color
		rect.visible = true
		for i in range(1, _digit_rects.size()):
			_digit_rects[i].visible = false
		return

	var text := "%d" % value
	_ensure_digit_count(text.length())

	for i in range(text.length()):
		var rect: TextureRect = _digit_rects[i]
		var token: String = text[i]
		var tex: Texture2D = _texture_for_token(token)
		rect.texture = tex
		rect.modulate = modulate_color
		rect.visible = true

	for i in range(text.length(), _digit_rects.size()):
		_digit_rects[i].visible = false


func _texture_for_token(token: String) -> Texture2D:
	# Single digits; tokens "0" through "9" map to the first 10 textures.
	var idx := token.to_int()
	if idx >= 0 and idx < _digit_textures.size():
		return _digit_textures[idx]
	return null


func _texture_for_number(value: int) -> Texture2D:
	# Prefer a pre-composed multi-digit sprite when available (e.g. "10").
	var composed_path := "%s%d%s" % [digit_prefix, value, digit_suffix]
	var composed_tex := load(composed_path) as Texture2D
	if composed_tex:
		return composed_tex
	return _digit_textures[value] if value >= 0 and value < _digit_textures.size() else null


func _ensure_digit_count(count: int) -> void:
	while _digit_rects.size() < count:
		var rect := TextureRect.new()
		rect.custom_minimum_size = digit_size
		rect.size = digit_size
		rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		add_child(rect)
		_digit_rects.append(rect)


func clear() -> void:
	for rect in _digit_rects:
		rect.visible = false
