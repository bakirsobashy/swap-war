extends CanvasLayer

const ArenaScene := "res://Scenes/arena.tscn"

@onready var main_panel: PanelContainer = %MainPanel
@onready var options_panel: PanelContainer = %OptionsPanel
@onready var help_panel: PanelContainer = %HelpPanel
@onready var settings_panel: PanelContainer = %SettingsPanel

@onready var ai_label: Label = %AILabel
@onready var ai_slider: HSlider = %AISlider
@onready var score_label: Label = %ScoreLabel
@onready var score_slider: HSlider = %ScoreSlider
@onready var duration_label: Label = %DurationLabel
@onready var duration_slider: HSlider = %DurationSlider
@onready var mode_option: OptionButton = %ModeOption

@onready var sfx_slider: HSlider = %SFXSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_check: CheckBox = %SFXCheck
@onready var music_check: CheckBox = %MusicCheck
@onready var touch_option: OptionButton = %TouchOption

var _ai_count := 3
var _win_mode := SettingsManager.WinMode.SCORE_TARGET
var _score_target := 10
var _match_duration := 120.0

func _ready() -> void:
	if SettingsManager:
		_ai_count = SettingsManager.ai_count
		_win_mode = SettingsManager.win_mode
		_score_target = SettingsManager.score_target
		_match_duration = SettingsManager.match_duration_seconds

	_update_options_ui()
	_update_settings_ui()
	_show_panel(main_panel)

func _show_panel(panel: Control) -> void:
	main_panel.visible = false
	options_panel.visible = false
	help_panel.visible = false
	settings_panel.visible = false
	panel.visible = true

func _on_play_pressed() -> void:
	_show_panel(options_panel)
	_update_options_ui()

func _on_how_to_play_pressed() -> void:
	_show_panel(help_panel)

func _on_settings_pressed() -> void:
	_show_panel(settings_panel)
	_update_settings_ui()

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_back_pressed() -> void:
	_show_panel(main_panel)

func _on_start_match_pressed() -> void:
	if SettingsManager:
		SettingsManager.set_match_options(_ai_count, _win_mode, _score_target, _match_duration)
	get_tree().change_scene_to_file(ArenaScene)

func _on_ai_slider_changed(value: float) -> void:
	_ai_count = int(value)
	_update_options_ui()

func _on_score_slider_changed(value: float) -> void:
	_score_target = int(value)
	_update_options_ui()

func _on_duration_slider_changed(value: float) -> void:
	_match_duration = value
	_update_options_ui()

func _on_mode_option_changed(index: int) -> void:
	_win_mode = index as SettingsManager.WinMode
	_update_options_ui()

func _on_sfx_volume_changed(value: float) -> void:
	if SettingsManager:
		SettingsManager.set_audio_settings(value, SettingsManager.music_volume_db, SettingsManager.sfx_enabled, SettingsManager.music_enabled)

func _on_music_volume_changed(value: float) -> void:
	if SettingsManager:
		SettingsManager.set_audio_settings(SettingsManager.sfx_volume_db, value, SettingsManager.sfx_enabled, SettingsManager.music_enabled)

func _on_sfx_toggled(enabled: bool) -> void:
	if SettingsManager:
		SettingsManager.set_audio_settings(SettingsManager.sfx_volume_db, SettingsManager.music_volume_db, enabled, SettingsManager.music_enabled)

func _on_music_toggled(enabled: bool) -> void:
	if SettingsManager:
		SettingsManager.set_audio_settings(SettingsManager.sfx_volume_db, SettingsManager.music_volume_db, SettingsManager.sfx_enabled, enabled)

func _on_touch_mode_changed(index: int) -> void:
	if SettingsManager:
		SettingsManager.set_touch_controls_mode(index as SettingsManager.TouchControlsMode)

func _update_options_ui() -> void:
	ai_label.text = "AI Count: %d" % _ai_count
	ai_slider.set_value_no_signal(_ai_count)
	score_label.text = "Target: %d" % _score_target
	score_slider.set_value_no_signal(_score_target)
	duration_label.text = "Duration: %d s" % int(_match_duration)
	duration_slider.set_value_no_signal(_match_duration)
	mode_option.selected = _win_mode

func _update_settings_ui() -> void:
	if not SettingsManager:
		return
	sfx_slider.set_value_no_signal(SettingsManager.sfx_volume_db)
	music_slider.set_value_no_signal(SettingsManager.music_volume_db)
	sfx_check.set_pressed_no_signal(SettingsManager.sfx_enabled)
	music_check.set_pressed_no_signal(SettingsManager.music_enabled)
	touch_option.selected = SettingsManager.touch_controls_mode

func _play_click() -> void:
	if AudioManager:
		AudioManager.play_ui_click()
