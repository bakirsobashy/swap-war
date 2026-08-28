extends Node

@export var match_duration_seconds: float = 120.0
@export var winner_message_duration: float = 5.0

var _match_timer: float = 0.0
var _match_active: bool = false
var _winner_shown: bool = false

func _ready() -> void:
	_start_match()
	if ScoreManager:
		ScoreManager.match_won.connect(_on_match_won)

func _process(delta: float) -> void:
	if not _match_active:
		return
	_match_timer -= delta
	if _match_timer <= 0.0 and not _winner_shown:
		_end_match_by_time()

func _start_match() -> void:
	_match_timer = match_duration_seconds
	_match_active = true
	_winner_shown = false
	if ScoreManager:
		ScoreManager.reset_scores()

func _end_match_by_time() -> void:
	_match_active = false
	_winner_shown = true
	var winner: Node = null
	if ScoreManager:
		winner = ScoreManager.get_leader()
	_show_winner(winner)

func _on_match_won(winner: Node, _score: int) -> void:
	if _winner_shown:
		return
	_match_active = false
	_winner_shown = true
	if AudioManager:
		AudioManager.play_win()
	_show_winner(winner)

func _show_winner(winner: Node) -> void:
	var tree := get_tree()
	if not tree:
		return

	var hud := tree.current_scene.get_node_or_null("HUD") as HUD
	if hud:
		hud.show_winner(winner.name if winner else "")
	else:
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.text = "%s WINS!" % winner.name if winner else "DRAW!"
		label.set_anchors_preset(Control.PRESET_CENTER)
		label.size = Vector2(400, 100)
		label.position = -label.size / 2.0
		label.add_theme_font_size_override("font_size", 48)
		var canvas := CanvasLayer.new()
		canvas.add_child(label)
		tree.current_scene.add_child(canvas)
		tree.create_timer(winner_message_duration).timeout.connect(func() -> void:
			canvas.queue_free()
		)

	tree.create_timer(winner_message_duration).timeout.connect(func() -> void:
		if hud:
			hud.hide_winner()
		_start_match()
	)
