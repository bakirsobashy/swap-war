class_name HUD
extends CanvasLayer

@onready var _score_board: HBoxContainer = %ScoreBoard
@onready var _team_timer: TeamTimer = %TeamTimer
@onready var _winner_message: Label = %WinnerMessage
@onready var _top_bar: Control = %TopBar

var _actor_labels: Dictionary = {}

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

func _process(delta: float) -> void:
	_update_team_timer()

## Shift the top bar below any notch/status-bar inset and shrink the HUD font
## on narrow viewports (phones in portrait) so the scoreboard never overflows.
func _apply_responsive_layout() -> void:
	var insets: Vector4 = SafeAreaUtil.get_canvas_insets(get_viewport())
	_top_bar.offset_top = insets.y
	_top_bar.offset_bottom = 56.0 + insets.y

	# Size the fonts off the real WINDOW width: under canvas_items stretch with
	# the expand aspect the canvas is never narrower than the 1152-unit base,
	# so comparing canvas width would make these branches unreachable.
	var window_width := float(DisplayServer.window_get_size().x)
	if window_width < 500.0:
		_score_board.add_theme_font_size_override("font_size", 13)
	elif window_width < 800.0:
		_score_board.add_theme_font_size_override("font_size", 16)
	else:
		_score_board.remove_theme_font_size_override("font_size")

func _build_initial_ui() -> void:
	for c in _score_board.get_children():
		c.queue_free()
	_actor_labels.clear()

	if not TeamManager:
		return

	for actor in TeamManager._teams.keys():
		_on_actor_registered(actor)

func _on_actor_registered(actor: Node) -> void:
	if _actor_labels.has(actor):
		return
	if not is_instance_valid(actor):
		return

	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_actor_labels[actor] = label
	_score_board.add_child(label)

	_update_score_label(actor)

func _on_actor_unregistered(actor: Node) -> void:
	var label := _actor_labels.get(actor) as Label
	if label:
		label.queue_free()
		_actor_labels.erase(actor)

func _on_team_changed(_teams: Dictionary) -> void:
	for actor in _actor_labels.keys():
		_update_score_label(actor)

func _on_score_changed(actor: Node, _score: int) -> void:
	_update_score_label(actor)

func show_winner(winner_name: String) -> void:
	if not is_instance_valid(_winner_message):
		return
	if winner_name.is_empty():
		_winner_message.text = "DRAW!"
	else:
		_winner_message.text = "%s WINS!" % winner_name
	_winner_message.visible = true

func hide_winner() -> void:
	if not is_instance_valid(_winner_message):
		return
	_winner_message.visible = false

func _update_score_label(actor: Node) -> void:
	var label := _actor_labels.get(actor) as Label
	if not label:
		return
	var team_id := 0
	if TeamManager:
		team_id = TeamManager.get_team(actor)
	var score := 0
	if ScoreManager:
		score = ScoreManager.get_score(actor)
	var color_name := _team_color_name(team_id)
	label.text = "%s\n%s: %d" % [actor.name, color_name, score]
	label.modulate = _team_color(team_id)

func _update_team_timer() -> void:
	if not TeamManager or not is_instance_valid(TeamManager._swap_timer):
		return
	if not is_instance_valid(_team_timer):
		return
	var remaining := TeamManager._swap_timer.time_left
	_team_timer.update_timer(remaining, TeamManager.swap_interval)

func _team_color(team_id: int) -> Color:
	match team_id:
		0: return Color.GREEN
		1: return Color.RED
		2: return Color.PURPLE
		3: return Color.YELLOW
		_: return Color.WHITE

func _team_color_name(team_id: int) -> String:
	match team_id:
		0: return "Green"
		1: return "Red"
		2: return "Purple"
		3: return "Yellow"
		_: return "??"
