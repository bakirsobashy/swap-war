extends CanvasLayer

const MainMenuScene := "res://Scenes/UI/MainMenu.tscn"

@onready var panel: PanelContainer = %Panel
@onready var title_label: Label = %Title
@onready var scoreboard_label: Label = %Scoreboard

func _ready() -> void:
	layer = 12
	visible = false
	process_mode = PROCESS_MODE_WHEN_PAUSED

func show_post_round(winner: Node, scores: Dictionary, win_reason: String) -> void:
	visible = true
	get_tree().paused = true

	if winner:
		title_label.text = "%s WINS!" % winner.name.to_upper()
	else:
		title_label.text = "DRAW!"

	var lines: Array[String] = []
	lines.append("Win: %s" % win_reason)
	for actor in scores.keys():
		var score: int = scores[actor]
		lines.append("%s: %d kills" % [actor.name, score])
	scoreboard_label.text = "
".join(lines)

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
