extends CanvasLayer

const MainMenuScene := "res://Scenes/UI/MainMenu.tscn"
const WINNER_STAR := preload("res://Assets/ui/ui-2.0/scribble_ui/x1/hud/star_full.png")
## ArenaManager's win reasons, reworded for the subtitle (unknown ones show as-is).
const REASON_TEXT := {
	"Score Target": "first to the score target",
	"Time Up": "time's up!",
	"Sudden Death": "won in sudden death",
}
const ROW_HEIGHT := 46.0
const SEPARATOR_COLOR := Color(0.811765, 0.878431, 0.941176, 1)

@onready var panel: PanelContainer = %Panel
@onready var title_label: Label = %Title
@onready var reason_label: Label = %Reason
@onready var scoreboard: VBoxContainer = %Scoreboard
@onready var play_again_btn: Button = %PlayAgainBtn

func _ready() -> void:
	layer = 12
	visible = false
	process_mode = PROCESS_MODE_WHEN_PAUSED

func _unhandled_input(event: InputEvent) -> void:
	if visible:
		MenuFocus.focus_on_nav(event, play_again_btn)

func show_post_round(winner: Node, scores: Dictionary, win_reason: String) -> void:
	visible = true
	get_tree().paused = true

	if winner:
		title_label.text = "%s WINS!" % winner.name.to_upper()
	else:
		title_label.text = "DRAW!"
	reason_label.text = REASON_TEXT.get(win_reason, win_reason)
	_build_scoreboard(winner, scores)

## One row per actor, most kills first: star (winner) or rank, name, kills.
func _build_scoreboard(winner: Node, scores: Dictionary) -> void:
	for child in scoreboard.get_children():
		scoreboard.remove_child(child)
		child.queue_free()

	var actors: Array = scores.keys().filter(func(a): return is_instance_valid(a))
	actors.sort_custom(func(a, b): return scores[a] > scores[b])
	for i in actors.size():
		if i > 0:
			var line := ColorRect.new()
			line.custom_minimum_size = Vector2(0, 2)
			line.color = SEPARATOR_COLOR
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			scoreboard.add_child(line)
		scoreboard.add_child(_make_row(actors[i], scores[actors[i]], i + 1, actors[i] == winner))

func _make_row(actor: Node, kills: int, rank: int, is_winner: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.add_theme_constant_override("separation", 16)

	var badge: Control
	if is_winner:
		var star := TextureRect.new()
		star.texture = WINNER_STAR
		star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge = star
	else:
		var rank_label := Label.new()
		rank_label.theme_type_variation = &"HintLabel"
		rank_label.text = str(rank)
		rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge = rank_label
	badge.custom_minimum_size = Vector2(40, 0)
	row.add_child(badge)

	var name_label := Label.new()
	name_label.theme_type_variation = &"RowLabel"
	name_label.text = actor.name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	row.add_child(name_label)

	var kills_label := Label.new()
	kills_label.theme_type_variation = &"RowLabel" if is_winner else &"HintLabel"
	kills_label.add_theme_font_size_override("font_size", 28)
	kills_label.text = "%d kill%s" % [kills, "" if kills == 1 else "s"]
	kills_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(kills_label)
	return row

func hide_post_round() -> void:
	visible = false
	get_tree().paused = false

func _on_play_again_pressed() -> void:
	hide_post_round()
	if ArenaManager:
		ArenaManager.restart_match()

func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MainMenuScene)

func _play_click() -> void:
	if AudioManager:
		AudioManager.play_ui_click()
