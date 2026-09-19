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
	for i in range(10):
		var path := "%s%d%s" % [digit_prefix, i, digit_suffix]
		var tex := load(path) as Texture2D
		if not tex:
			push_warning("BitmapNumberLabel: failed to load digit texture '%s'" % path)
		_digit_textures.append(tex)

	add_theme_constant_override("separation", digit_separation)


func set_value(value: int, modulate_color: Color = Color.WHITE) -> void:
	value = maxi(value, 0)
	var text := "%d" % value
	_ensure_digit_count(text.length())

	for i in range(text.length()):
		var digit: int = text[i].to_int()
		var rect: TextureRect = _digit_rects[i]
		rect.texture = _digit_textures[digit] if digit < _digit_textures.size() else null
		rect.modulate = modulate_color
		rect.visible = true

	for i in range(text.length(), _digit_rects.size()):
		_digit_rects[i].visible = false


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
