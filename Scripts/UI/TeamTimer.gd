class_name TeamTimer
extends Control

## Team-swap countdown badge (Notebook Doodle): a paper disc with a highlighter
## ring that empties clockwise and an ink digit. During TeamManager's swap
## preview (PREVIEW_LEAD s before a swap) the digit takes the PLAYER's next
## team colour — ink-outlined, the light colours are faint on paper — and a
## "SWAP!" tag appears, matching the overhead ActorMarker preview.

const DISC_TEXTURE := preload("res://Assets/ui/ui-2.0/scribble_ui/x1/buttons/round_normal.png")
## round_normal.png's ink circle: centre (35.5, 35.5), diameter 56, in 74x76.
const DISC_ART_CENTER := Vector2(35.5, 35.5)
const DISC_ART_DIAMETER := 56.0
const RING_INSET := 9.0
const RING_WIDTH := 7.0
const RING_TRACK := Color(0.882, 0.863, 0.804)
const RING_FILL := Color(1.0, 0.894, 0.361)     # kit highlighter
const PREVIEW_OUTLINE := 8

@export var pulse_start_seconds: int = 3
@export var tick_sound: AudioStream = preload("res://Assets/ui/Sounds/switch-b.ogg")

@onready var _digit: Label = $Digit
@onready var _swap_tag: Label = $SwapTag

var _last_displayed_second: int = -1
var _pulse_time: float = 0.0
var _fraction: float = 1.0
var _stopped := false
var _preview_on := false
var _preview_color: Color = TeamPalette.INK


func _ready() -> void:
	var tm := get_node_or_null("/root/TeamManager")
	if tm:
		tm.next_teams_rolled.connect(_on_next_teams_rolled)
		tm.next_teams_cleared.connect(_on_preview_cleared)
		tm.team_changed.connect(_on_preview_cleared.unbind(1))
	_apply_digit_style()


func _process(delta: float) -> void:
	var pulsing := not _stopped and _last_displayed_second > 0 \
			and _last_displayed_second <= pulse_start_seconds
	if pulsing:
		_pulse_time += delta * 8.0
		var pulse := 1.0 + 0.08 * sin(_pulse_time)
		scale = Vector2(pulse, pulse)
		pivot_offset = size * 0.5
	else:
		scale = Vector2.ONE


func _draw() -> void:
	var center := size * 0.5
	var diameter := minf(size.x, size.y) - 12.0
	var s := diameter / DISC_ART_DIAMETER
	var disc_size := DISC_TEXTURE.get_size() * s
	draw_texture_rect(DISC_TEXTURE, Rect2(center - DISC_ART_CENTER * s, disc_size), false)
	var radius := diameter * 0.5 - RING_INSET
	draw_arc(center, radius, 0.0, TAU, 64, RING_TRACK, RING_WIDTH, true)
	if _fraction > 0.0:
		draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * _fraction, 64, RING_FILL, RING_WIDTH, true)


## Call every frame with the remaining swap time and total interval. `stopped`
## (sudden death / post-round) shows a dash instead of a frozen "1".
func update_timer(time_left: float, interval: float, stopped: bool = false) -> void:
	_stopped = stopped
	if stopped:
		_digit.text = "-"
		_last_displayed_second = -1
		_set_fraction(0.0)
		return
	var display_seconds := maxi(1, int(ceil(time_left)))
	if display_seconds != _last_displayed_second:
		if display_seconds <= pulse_start_seconds:
			_play_tick()
		_last_displayed_second = display_seconds
		_digit.text = str(display_seconds)
	_set_fraction(clampf(time_left / interval, 0.0, 1.0) if interval > 0.0 else 0.0)


func _set_fraction(value: float) -> void:
	if not is_equal_approx(value, _fraction):
		_fraction = value
		queue_redraw()


func _on_next_teams_rolled(next_teams: Dictionary) -> void:
	_preview_on = true
	_preview_color = TeamPalette.INK
	for actor in next_teams:
		if is_instance_valid(actor) and "is_player" in actor and bool(actor.is_player):
			_preview_color = TeamPalette.color(int(next_teams[actor]))
			break
	_apply_digit_style()


func _on_preview_cleared() -> void:
	_preview_on = false
	_apply_digit_style()


func _apply_digit_style() -> void:
	if _digit == null:
		return
	_swap_tag.visible = _preview_on
	var coloured := _preview_on and _preview_color != TeamPalette.INK
	_digit.add_theme_color_override("font_color", _preview_color if coloured else TeamPalette.INK)
	_digit.add_theme_constant_override("outline_size", PREVIEW_OUTLINE if coloured else 0)


## For probes: is the swap preview showing, and in which colour.
func is_preview_on() -> bool:
	return _preview_on


func get_preview_color() -> Color:
	return _preview_color


func _play_tick() -> void:
	if AudioManager and tick_sound:
		AudioManager.play_sfx(tick_sound, 0.0)
