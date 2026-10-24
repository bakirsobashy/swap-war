extends Node2D

## Overhead marker on every actor (instanced in actor.tscn above the health
## bar, on the actor root so it doesn't lean with VisualBody).
##   - Player: a white, ink-outlined downward arrow, always shown, so you can
##     find yourself after every reshuffle. During a swap preview it fills
##     with your NEXT team colour.
##   - AIs: nothing, except during the swap preview, when a small chip in the
##     actor's next team colour appears.
## The preview is TeamManager's early roll (next_teams_rolled, PREVIEW_LEAD
## seconds before the swap); it blinks during the final BLINK_WINDOW seconds
## and is shown even when the colour won't change ("you stay green").
## Drawn in code: crisp at any zoom, no textures, no SubViewport.

const ARROW_SIZE := Vector2(26.0, 18.0)     # player arrow (width, height)
const CHIP_SIZE := Vector2(16.0, 11.0)      # AI preview chip
const OUTLINE_COLOR := TeamPalette.INK
const OUTLINE_WIDTH := 3.0
const ARROW_FILL := Color.WHITE
const BOB_AMPLITUDE := 3.0
const BOB_SPEED := 4.0
const BLINK_WINDOW := 1.0                   # final seconds before the swap
const BLINK_HZ := 4.0

var _actor: Node = null
var _is_player := false
var _base_y := 0.0
var _clock := 0.0
var _preview_on := false
var _preview_color := Color.WHITE

func _ready() -> void:
	_actor = get_parent()
	_base_y = position.y
	z_index = 20
	# ArenaManager sets is_player before the actor enters the tree.
	_is_player = _actor != null and "is_player" in _actor and bool(_actor.is_player)
	var tm := get_node_or_null("/root/TeamManager")
	if tm:
		tm.next_teams_rolled.connect(_on_next_teams_rolled)
		tm.next_teams_cleared.connect(_on_preview_cleared)
		tm.team_changed.connect(_on_teams_changed)

func _process(delta: float) -> void:
	_clock += delta
	visible = _is_player or _preview_on
	if not visible:
		return
	if _is_player:
		position.y = _base_y + sin(_clock * BOB_SPEED) * BOB_AMPLITUDE
	queue_redraw()

func _draw() -> void:
	var show_preview := _preview_on and _blink_phase_on()
	if _is_player:
		_draw_triangle(ARROW_SIZE, _preview_color if show_preview else ARROW_FILL)
	elif show_preview:
		_draw_triangle(CHIP_SIZE, _preview_color)

## Downward-pointing triangle, tip at the node origin's bottom edge.
func _draw_triangle(size: Vector2, fill: Color) -> void:
	var pts := PackedVector2Array([
		Vector2(-size.x * 0.5, -size.y),
		Vector2(size.x * 0.5, -size.y),
		Vector2(0.0, 0.0),
	])
	draw_colored_polygon(pts, fill)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, OUTLINE_COLOR, OUTLINE_WIDTH, true)

## Steady until the final BLINK_WINDOW seconds, then on/off at BLINK_HZ.
func _blink_phase_on() -> bool:
	var tm := get_node_or_null("/root/TeamManager")
	if tm == null or tm.time_to_swap() > BLINK_WINDOW:
		return true
	return fmod(_clock * BLINK_HZ, 1.0) < 0.5

func _on_next_teams_rolled(next_teams: Dictionary) -> void:
	if not next_teams.has(_actor):
		return
	_preview_color = TeamPalette.color(int(next_teams[_actor]))
	_preview_on = true

func _on_preview_cleared() -> void:
	_preview_on = false

func _on_teams_changed(_teams: Dictionary) -> void:
	_preview_on = false

## For probes: is the preview showing, and in which colour.
func is_preview_on() -> bool:
	return _preview_on

func get_preview_color() -> Color:
	return _preview_color

func is_player_marker() -> bool:
	return _is_player
