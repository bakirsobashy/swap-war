class_name PauseMenu
extends CanvasLayer

const MainMenuScene := "res://Scenes/UI/MainMenu.tscn"

@onready var panel: PanelContainer = %Panel

var _post_round_menu: CanvasLayer = null

func _ready() -> void:
	layer = 11
	visible = false
	process_mode = PROCESS_MODE_WHEN_PAUSED
	# Both PauseMenu and PostRoundMenu are added via call_deferred; wait one frame
	# before looking up the sibling so it actually exists.
	await get_tree().process_frame
	_post_round_menu = get_parent().get_node_or_null("PostRoundMenu") as CanvasLayer

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("Pause"):
		if _post_round_menu and _post_round_menu.visible:
			return
		_toggle_pause()

func _toggle_pause() -> void:
	if get_tree().paused and not visible:
		return
	visible = not visible
	get_tree().paused = visible

## Public entry point for UI buttons (touch/mouse) that need to toggle pause.
func toggle_pause() -> void:
	if _post_round_menu and _post_round_menu.visible:
		return
	_toggle_pause()

func _on_resume_pressed() -> void:
	visible = false
	get_tree().paused = false

func _on_restart_pressed() -> void:
	visible = false
	get_tree().paused = false
	if ArenaManager:
		ArenaManager.restart_match()

func _on_quit_to_menu_pressed() -> void:
	visible = false
	get_tree().paused = false
	get_tree().change_scene_to_file(MainMenuScene)

func _play_click() -> void:
	if AudioManager:
		AudioManager.play_ui_click()
