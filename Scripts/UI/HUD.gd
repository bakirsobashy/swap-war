class_name HUD
extends CanvasLayer

@onready var _score_board: HBoxContainer = %ScoreBoard
@onready var _team_timer_label: Label = %TeamTimerLabel
@onready var _winner_message: Label = %WinnerMessage

var _actor_labels: Dictionary = {}

func _ready() -> void:
	if TeamManager:
		TeamManager.team_changed.connect(_on_team_changed)
		TeamManager.actor_registered.connect(_on_actor_registered)
		TeamManager.actor_unregistered.connect(_on_actor_unregistered)
	if ScoreManager:
		ScoreManager.score_changed.connect(_on_score_changed)

	call_deferred("_build_initial_ui")

func _process(delta: float) -> void:
	_update_team_timer()

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
	var remaining := TeamManager._swap_timer.time_left
	_team_timer_label.text = "Swap: %.1f" % remaining

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
