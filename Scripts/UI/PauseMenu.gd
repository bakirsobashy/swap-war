class_name PauseMenu
extends CanvasLayer

const MainMenuScene := "res://Scenes/UI/MainMenu.tscn"

@onready var panel: PanelContainer = %Panel
@onready var resume_btn: Button = %ResumeBtn

var _post_round_menu: CanvasLayer = null

func _ready() -> void:
	layer = 11
	visible = false
	# ALWAYS, not WHEN_PAUSED: a WHEN_PAUSED node gets no _input while the
	# game runs, so Esc could never open the menu (only unpause it).
	process_mode = PROCESS_MODE_ALWAYS
	# Both PauseMenu and PostRoundMenu are added via call_deferred; wait one frame
	# before looking up the sibling so it actually exists.
	await get_tree().process_frame
	_post_round_menu = get_parent().get_node_or_null("PostRoundMenu") as CanvasLayer

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("Pause"):
		if _post_round_menu and _post_round_menu.visible:
			return
		_toggle_pause()

func _unhandled_input(event: InputEvent) -> void:
	if visible:
		MenuFocus.focus_on_nav(event, resume_btn)

## Losing focus (alt-tab, a browser tab switch) or going to the background
## (a call on a phone) pauses, so the match and its clock wait for the player.
## Android's Back toggles the menu like Esc (quit_on_go_back is off).
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			pause_for_interruption()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if is_inside_tree():
				toggle_pause()

## Opens the menu if the match is running; never closes it (focus can bounce
## out twice) and leaves the post-round screen alone.
func pause_for_interruption() -> void:
	if not is_inside_tree() or visible or get_tree().paused:
		return
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
