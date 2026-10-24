class_name HUD
extends CanvasLayer

## In-match HUD (Notebook Doodle, menu_theme): paper scoreboard card, swap
## timer badge, goal chip (score target / match clock / sudden death) and the
## centre banner. Every Control ignores the mouse — Attack is mouse-bound.

const TeamDotScript := preload("res://Scripts/UI/TeamDot.gd")
const LEADER_STAR := preload("res://Assets/ui/ui-2.0/scribble_ui/x1/hud/star_small_full.png")
## Goal chip: gap to the touch pause button / to the canvas corner.
const CHIP_GAP := 14.0
const CHIP_CORNER_MARGIN := 22.0
## Long banner texts ("SUDDEN DEATH!", "X WINS!") drop to this size.
const BANNER_SHORT_MAX_CHARS := 3
const BANNER_LONG_FONT_SIZE := 72

@onready var _score_board: VBoxContainer = %ScoreBoard
@onready var _team_timer: TeamTimer = %TeamTimer
@onready var _winner_message: Label = %WinnerMessage
@onready var _top_bar: Control = %TopBar
@onready var _goal_chip: Control = %GoalChip
@onready var _goal_label: Label = %GoalLabel
## Untyped: its script API (uses_touch_controls, get_control_rect) isn't on
## the CanvasLayer base, and TouchControls.gd has no class_name.
@onready var _touch_controls = $TouchControls

## actor -> {"row", "dot", "name", "score", "star"}
var _rows: Dictionary = {}
var _row_font_size: int = 0
var _banner_tween: Tween = null

func _ready() -> void:
	if TeamManager:
		TeamManager.team_changed.connect(_on_team_changed)
		TeamManager.actor_registered.connect(_on_actor_registered)
		TeamManager.actor_unregistered.connect(_on_actor_unregistered)
	if ScoreManager:
		ScoreManager.score_changed.connect(_on_score_changed)

	get_viewport().size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()

	call_deferred("_build_initial_ui")

func _process(_delta: float) -> void:
	_update_team_timer()
	_update_goal_chip()

## Shift the top bar below any notch/status-bar inset and shrink the
## scoreboard font on narrow windows (phones in portrait).
func _apply_responsive_layout() -> void:
	var insets: Vector4 = SafeAreaUtil.get_canvas_insets(get_viewport())
	_top_bar.offset_top = insets.y
	_top_bar.offset_bottom = 110.0 + insets.y

	# Size the fonts off the real WINDOW width: under canvas_items stretch with
	# the expand aspect the canvas is never narrower than the 1152-unit base,
	# so comparing canvas width would make these branches unreachable.
	var window_width := float(DisplayServer.window_get_size().x)
	if window_width < 500.0:
		_row_font_size = 15
	elif window_width < 800.0:
		_row_font_size = 18
	else:
		_row_font_size = 0    # theme sizes
	for actor in _rows:
		_apply_row_font(_rows[actor])

func _build_initial_ui() -> void:
	for c in _score_board.get_children():
		c.queue_free()
	_rows.clear()

	if not TeamManager:
		return

	for actor in TeamManager._teams.keys():
		_on_actor_registered(actor)

func _on_actor_registered(actor: Node) -> void:
	if _rows.has(actor) or not is_instance_valid(actor):
		return

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)

	var dot: Control = TeamDotScript.new()
	row.add_child(dot)

	var name_label := Label.new()
	# Actor node names are the display names (ArenaManager: "YOU" + AI names),
	# so the scoreboard and the post-round screen always agree.
	name_label.text = actor.name
	var is_player := "is_player" in actor and bool(actor.is_player)
	name_label.theme_type_variation = &"ScoreYouLabel" if is_player else &"ScoreNameLabel"
	name_label.custom_minimum_size = Vector2(84, 0)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)

	var score_label := Label.new()
	score_label.theme_type_variation = &"ScoreValueLabel"
	score_label.custom_minimum_size = Vector2(28, 0)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(score_label)

	# Leader star; modulate (not visibility) so rows keep one width.
	var star := TextureRect.new()
	star.texture = LEADER_STAR
	star.custom_minimum_size = Vector2(20, 20)
	star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	star.modulate.a = 0.0
	row.add_child(star)

	_rows[actor] = {"row": row, "dot": dot, "name": name_label, "score": score_label, "star": star}
	_score_board.add_child(row)
	_apply_row_font(_rows[actor])
	_update_row(actor)
	_update_leader()

func _on_actor_unregistered(actor: Node) -> void:
	var entry: Dictionary = _rows.get(actor, {})
	if not entry.is_empty():
		entry["row"].queue_free()
		_rows.erase(actor)
	_update_leader()

func _on_team_changed(_teams: Dictionary) -> void:
	for actor in _rows.keys():
		_update_row(actor)

func _on_score_changed(actor: Node, _score: int) -> void:
	_update_row(actor)
	_update_leader()

func _update_row(actor: Node) -> void:
	var entry: Dictionary = _rows.get(actor, {})
	if entry.is_empty():
		return
	var team_id := TeamManager.get_team(actor) if TeamManager else 0
	entry["dot"].color = _team_color(team_id)
	entry["score"].text = str(ScoreManager.get_score(actor) if ScoreManager else 0)

## Star on the single leader (none while tied or scoreless).
func _update_leader() -> void:
	var leader: Node = ScoreManager.get_leader() if ScoreManager else null
	if leader and ScoreManager.get_score(leader) <= 0:
		leader = null
	for actor in _rows:
		_rows[actor]["star"].modulate.a = 1.0 if actor == leader else 0.0

func _apply_row_font(entry: Dictionary) -> void:
	for key in ["name", "score"]:
		var label: Label = entry[key]
		if _row_font_size > 0:
			label.add_theme_font_size_override("font_size", _row_font_size)
		else:
			label.remove_theme_font_size_override("font_size")

func show_winner(winner_name: String) -> void:
	show_message("DRAW!" if winner_name.is_empty() else "%s WINS!" % winner_name)

## Centre banner (countdown digits, GO!, SUDDEN DEATH!). Pops in when the text
## changes; repeated calls with the same text (every countdown frame) are free.
func show_message(text: String) -> void:
	if not is_instance_valid(_winner_message):
		return
	if _winner_message.visible and _winner_message.text == text:
		return
	_winner_message.text = text
	if text.length() > BANNER_SHORT_MAX_CHARS:
		_winner_message.add_theme_font_size_override("font_size", BANNER_LONG_FONT_SIZE)
	else:
		_winner_message.remove_theme_font_size_override("font_size")
	_winner_message.visible = true
	_pop_banner.call_deferred()

func hide_winner() -> void:
	if not is_instance_valid(_winner_message):
		return
	_winner_message.visible = false

func _pop_banner() -> void:
	if not is_instance_valid(_winner_message):
		return
	_winner_message.pivot_offset = _winner_message.size * 0.5
	if _banner_tween:
		_banner_tween.kill()
	_winner_message.scale = Vector2.ONE * 1.35
	_banner_tween = create_tween()
	_banner_tween.tween_property(_winner_message, "scale", Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _update_team_timer() -> void:
	if not TeamManager or not is_instance_valid(TeamManager._swap_timer):
		return
	if not is_instance_valid(_team_timer):
		return
	var timer: Timer = TeamManager._swap_timer
	_team_timer.update_timer(timer.time_left, TeamManager.swap_interval, timer.is_stopped())

## Goal chip text + placement: just left of the touch pause button while touch
## controls are in use and the button sits in the top-right band; otherwise in
## the canvas corner (desktop, or a custom layout that moved the button away).
func _update_goal_chip() -> void:
	var text := _goal_text()
	_goal_chip.visible = not text.is_empty()
	if text != _goal_label.text:
		_goal_label.text = text
	if not _goal_chip.visible:
		return
	var canvas := get_viewport().get_visible_rect().size
	var insets: Vector4 = SafeAreaUtil.get_canvas_insets(get_viewport())
	var chip_h := _goal_chip.get_combined_minimum_size().y
	var right_edge := canvas.x - insets.z - CHIP_CORNER_MARGIN
	var center_y := insets.y + CHIP_CORNER_MARGIN + chip_h * 0.5
	if _touch_controls and _touch_controls.uses_touch_controls():
		var pause: Rect2 = _touch_controls.get_control_rect("PauseButton")
		if pause.position.y < 160.0 and pause.get_center().x > canvas.x * 0.5:
			right_edge = pause.position.x - CHIP_GAP
			center_y = pause.get_center().y
	# TopBar spans the canvas width and starts at insets.y.
	_goal_chip.offset_right = right_edge - canvas.x
	_goal_chip.offset_left = _goal_chip.offset_right
	_goal_chip.offset_top = center_y - chip_h * 0.5 - _top_bar.offset_top
	_goal_chip.offset_bottom = _goal_chip.offset_top

func _goal_text() -> String:
	if ArenaManager and ArenaManager.is_sudden_death():
		return "SUDDEN DEATH"
	if ArenaManager and ArenaManager.is_timed_match():
		var seconds := ceili(ArenaManager.get_match_time_left())
		return "%d:%02d" % [floori(seconds / 60.0), seconds % 60]
	if ScoreManager:
		return "first to %d" % ScoreManager.score_to_win
	return ""

func _team_color(team_id: int) -> Color:
	return TeamPalette.color(team_id)
