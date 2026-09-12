extends CanvasLayer

## On-screen touch controls that emit input actions for mobile/web play.

@onready var _drop_button: TextureButton = %DropButton

func _ready() -> void:
	_visibility_changed()
	if SettingsManager:
		SettingsManager.settings_loaded.connect(_visibility_changed)
		SettingsManager.setting_changed.connect(_visibility_changed)

func _visibility_changed() -> void:
	visible = _should_show_touch_controls()

func _should_show_touch_controls() -> bool:
	if not SettingsManager:
		return true
	match SettingsManager.touch_controls_mode:
		SettingsManager.TouchControlsMode.HIDDEN:
			return false
		SettingsManager.TouchControlsMode.ALWAYS:
			return true
		_:
			return DisplayServer.is_touchscreen_available()

func _on_drop_button_pressed() -> void:
	var ev := InputEventAction.new()
	ev.action = "Drop_Weapon"
	ev.pressed = true
	Input.parse_input_event(ev)
	if AudioManager:
		AudioManager.play_ui_click()
