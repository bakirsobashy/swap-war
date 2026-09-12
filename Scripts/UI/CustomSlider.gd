extends Control

signal value_changed(value: float)

@export var min_value: float = 0.0:
	set(v):
		min_value = v
		self.value = clampf(value, min_value, max_value)
		_update_visuals()

@export var max_value: float = 100.0:
	set(v):
		max_value = v
		self.value = clampf(value, min_value, max_value)
		_update_visuals()

@export var step: float = 1.0:
	set(v):
		step = maxf(v, 0.001)
		self.value = snappedf(value, step)
		_update_visuals()

@export var value: float = 0.0:
	set(v):
		var new_value := clampf(snappedf(v, step), min_value, max_value)
		if not is_equal_approx(new_value, value):
			value = new_value
			value_changed.emit(value)
		_update_visuals()

@export var tick_count: int = 0:
	set(v):
		tick_count = maxi(v, 0)
		_update_visuals()

@export var tick_size: Vector2 = Vector2(8, 8):
	set(v):
		tick_size = v
		_update_visuals()

@export var empty_tick_color: Color = Color.WHITE:
	set(v):
		empty_tick_color = v
		_update_visuals()

@export var filled_tick_color: Color = Color(0.27, 0.51, 0.71, 1.0):
	set(v):
		filled_tick_color = v
		_update_visuals()

@onready var track: TextureRect = %Track
@onready var fill: TextureRect = %Fill
@onready var handle: TextureRect = %Handle
@onready var ticks: Control = %Ticks

var _dragging := false

func _ready() -> void:
	resized.connect(_update_visuals)
	_update_visuals()

func _update_visuals() -> void:
	if not track or not fill or not handle or not ticks:
		return

	var range := max_value - min_value
	var t := 0.0 if is_zero_approx(range) else (value - min_value) / range

	var half_handle := handle.size.x * 0.5
	var usable_width := maxf(size.x - handle.size.x, 1.0)

	# Center track vertically
	track.position = Vector2(half_handle, (size.y - track.size.y) * 0.5)
	track.size = Vector2(usable_width, track.size.y)

	# Fill grows from left to handle center
	fill.position = track.position
	fill.size = Vector2(half_handle + t * usable_width, track.size.y)

	# Handle follows value
	handle.position = Vector2(half_handle + t * usable_width - half_handle, (size.y - handle.size.y) * 0.5)

	_rebuild_ticks(t)

func _rebuild_ticks(fill_t: float) -> void:
	for child in ticks.get_children():
		child.queue_free()

	if tick_count <= 0:
		return

	var range := max_value - min_value
	var usable_width := maxf(size.x - handle.size.x, 1.0)
	var half_handle := handle.size.x * 0.5
	var track_left := half_handle

	for i in range(tick_count):
		var tick_t := 0.0 if tick_count <= 1 else float(i) / float(tick_count - 1)
		var tick := ColorRect.new()
		tick.size = tick_size
		tick.position = Vector2(
			track_left + tick_t * usable_width - tick_size.x * 0.5,
			(size.y - tick_size.y) * 0.5
		)
		tick.color = filled_tick_color if tick_t <= fill_t else empty_tick_color
		ticks.add_child(tick)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_set_value_from_mouse(event.position.x)
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		_set_value_from_mouse(event.position.x)

func _set_value_from_mouse(x: float) -> void:
	var half_handle := handle.size.x * 0.5
	var usable_width := maxf(size.x - handle.size.x, 1.0)
	var t := clampf((x - half_handle) / usable_width, 0.0, 1.0)
	var raw := min_value + t * (max_value - min_value)
	self.value = snappedf(raw, step)

func _input(event: InputEvent) -> void:
	# Release drag if mouse goes up outside the control
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
