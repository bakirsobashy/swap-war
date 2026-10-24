class_name TeamTimer
extends Control

## Visual team-swap countdown: digit sprites + a clockwise-emptying circle ring.

@export var team_colors: Array[Color] = TeamPalette.COLORS
@export var pulse_start_seconds: int = 3
@export var tick_sound: AudioStream = preload("res://Assets/ui/Sounds/switch-b.ogg")

@onready var _circle: TextureProgressBar = $CircleFill
@onready var _digits: BitmapNumberLabel = $Center/Digits

var _last_displayed_second: int = -1
var _current_color: Color = Color.WHITE
var _pulse_time: float = 0.0


func _ready() -> void:
	_current_color = _pick_random_team_color()


func _process(delta: float) -> void:
	if _last_displayed_second <= pulse_start_seconds and _last_displayed_second > 0:
		_pulse_time += delta * 8.0
		var pulse := 1.0 + 0.08 * sin(_pulse_time)
		scale = Vector2(pulse, pulse)
		pivot_offset = size * 0.5
	else:
		scale = Vector2.ONE


## Call every frame with the remaining swap time and total interval.
func update_timer(time_left: float, interval: float) -> void:
	var display_seconds := maxi(1, int(ceil(time_left)))

	if display_seconds != _last_displayed_second:
		_current_color = _pick_random_team_color()
		if display_seconds <= pulse_start_seconds:
			_play_tick()
		_last_displayed_second = display_seconds

	_digits.set_value(display_seconds, _current_color)

	if interval > 0.0:
		_circle.value = 100.0 * (time_left / interval)
	else:
		_circle.value = 0.0


func _pick_random_team_color() -> Color:
	if team_colors.is_empty():
		return Color.WHITE
	if team_colors.size() == 1:
		return team_colors[0]

	# Try to avoid picking the same color twice in a row.
	var attempts := 0
	var chosen := team_colors[randi() % team_colors.size()]
	while chosen.is_equal_approx(_current_color) and attempts < 4:
		chosen = team_colors[randi() % team_colors.size()]
		attempts += 1
	return chosen


func _play_tick() -> void:
	if AudioManager and tick_sound:
		AudioManager.play_sfx(tick_sound, 0.0)
