extends CanvasLayer

const SOUND_ON := preload("res://Assets/ui/ui-2.0/scribble_ui/x1/icons/sound_on.png")
const SOUND_OFF := preload("res://Assets/ui/ui-2.0/scribble_ui/x1/icons/sound_off.png")
const MUSIC_ON := preload("res://Assets/ui/ui-2.0/scribble_ui/x1/icons/music_on.png")
const MUSIC_OFF := preload("res://Assets/ui/ui-2.0/scribble_ui/x1/icons/music_off.png")
## Rows that don't apply right now (the unused match limit, a muted volume) fade.
const INACTIVE_TINT := Color(1, 1, 1, 0.4)
## AIStepper item 0 is "1 bot".
const AI_COUNT_MIN := 1

@onready var main_panel: Control = %MainPanel
@onready var options_panel: PanelContainer = %OptionsPanel
@onready var help_panel: PanelContainer = %HelpPanel
@onready var settings_panel: PanelContainer = %SettingsPanel
@onready var touch_layout_editor: Control = %TouchLayoutEditor

@onready var ai_stepper: Stepper = %AIStepper
@onready var arena_stepper: Stepper = %ArenaStepper
@onready var mode_stepper: Stepper = %ModeStepper
@onready var score_label: Label = %ScoreLabel
@onready var score_row: Control = %ScoreRow
@onready var score_slider: HSlider = %ScoreSlider
@onready var score_value: Label = %ScoreValue
@onready var duration_label: Label = %DurationLabel
@onready var duration_row: Control = %DurationRow
@onready var duration_slider: HSlider = %DurationSlider
@onready var duration_value: Label = %DurationValue

@onready var sfx_slider: HSlider = %SFXSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_toggle: Button = %SFXToggle
@onready var music_toggle: Button = %MusicToggle
@onready var corner_sound: Button = %CornerSound
@onready var corner_music: Button = %CornerMusic
@onready var touch_stepper: Stepper = %TouchStepper
@onready var auto_attack_check: CheckButton = %AutoAttackCheck

## First control focused by a keyboard/gamepad navigation press, per panel.
@onready var _default_focus: Dictionary = {
	main_panel: %PlayBtn,
	options_panel: %StartMatchBtn,
	help_panel: %HelpBackBtn,
	settings_panel: %SFXToggle,
}

var _ai_count := 3
var _win_mode := SettingsManager.WinMode.SCORE_TARGET
var _score_target := 10
var _match_duration := 120.0
var _arena_index := 0

func _ready() -> void:
	if SettingsManager:
		_ai_count = SettingsManager.ai_count
		_win_mode = SettingsManager.win_mode
		_score_target = SettingsManager.score_target
		_match_duration = SettingsManager.match_duration_seconds
		_arena_index = _path_to_index(SettingsManager.selected_arena_path)

	_populate_arena_options()
	_update_options_ui()
	_update_settings_ui()
	_show_panel(main_panel)

func _unhandled_input(event: InputEvent) -> void:
	if touch_layout_editor.visible:
		return
	for panel: Control in _default_focus:
		if panel.visible:
			MenuFocus.focus_on_nav(event, _default_focus[panel])
			return

func _show_panel(panel: Control) -> void:
	main_panel.visible = false
	options_panel.visible = false
	help_panel.visible = false
	settings_panel.visible = false
	touch_layout_editor.visible = false
	panel.visible = true
	# Drop focus left on a now-hidden button; the next nav press re-seeds it.
	var focused := get_viewport().gui_get_focus_owner()
	if focused:
		focused.release_focus()

func _on_play_pressed() -> void:
	_show_panel(options_panel)
	_update_options_ui()

func _on_how_to_play_pressed() -> void:
	_show_panel(help_panel)

func _on_settings_pressed() -> void:
	_show_panel(settings_panel)
	_update_settings_ui()

func _on_customize_touch_pressed() -> void:
	# The panel's visibility_changed runs the editor's enter lifecycle.
	_show_panel(touch_layout_editor)

func _on_touch_editor_closed() -> void:
	# Editor BACK returns to SETTINGS (the plain back button goes to main).
	_show_panel(settings_panel)

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_back_pressed() -> void:
	_show_panel(main_panel)

func _on_start_match_pressed() -> void:
	if SettingsManager:
		SettingsManager.set_match_options(_ai_count, _win_mode, _score_target, _match_duration)
		SettingsManager.set_arena_path(ArenaDatabase.get_arena_path_by_index(_arena_index))
	get_tree().change_scene_to_file(SettingsManager.selected_arena_path)

func _on_ai_stepper_changed(index: int) -> void:
	_ai_count = index + AI_COUNT_MIN
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

func _on_arena_option_changed(index: int) -> void:
	_arena_index = index
	_update_options_ui()

func _on_sfx_volume_changed(value: float) -> void:
	if SettingsManager:
		SettingsManager.set_audio_settings(value, SettingsManager.music_volume_db, SettingsManager.sfx_enabled, SettingsManager.music_enabled)

func _on_music_volume_changed(value: float) -> void:
	if SettingsManager:
		SettingsManager.set_audio_settings(SettingsManager.sfx_volume_db, value, SettingsManager.sfx_enabled, SettingsManager.music_enabled)

## Sound/music buttons (Settings rows and the main-screen corner) flip the flag.
func _on_sfx_toggle_pressed() -> void:
	if SettingsManager:
		_on_sfx_toggled(not SettingsManager.sfx_enabled)

func _on_music_toggle_pressed() -> void:
	if SettingsManager:
		_on_music_toggled(not SettingsManager.music_enabled)

func _on_sfx_toggled(enabled: bool) -> void:
	if SettingsManager:
		SettingsManager.set_audio_settings(SettingsManager.sfx_volume_db, SettingsManager.music_volume_db, enabled, SettingsManager.music_enabled)
	_refresh_audio_ui()

func _on_music_toggled(enabled: bool) -> void:
	if SettingsManager:
		SettingsManager.set_audio_settings(SettingsManager.sfx_volume_db, SettingsManager.music_volume_db, SettingsManager.sfx_enabled, enabled)
	_refresh_audio_ui()

func _on_touch_mode_changed(index: int) -> void:
	if SettingsManager:
		SettingsManager.set_touch_controls_mode(index as SettingsManager.TouchControlsMode)

func _on_auto_attack_toggled(enabled: bool) -> void:
	if SettingsManager:
		SettingsManager.set_auto_attack_enabled(enabled)

func _update_options_ui() -> void:
	ai_stepper.set_selected_no_signal(_ai_count - AI_COUNT_MIN)
	arena_stepper.set_selected_no_signal(_arena_index)
	mode_stepper.set_selected_no_signal(_win_mode)
	score_slider.set_value_no_signal(_score_target)
	score_value.text = str(_score_target)
	duration_slider.set_value_no_signal(_match_duration)
	duration_value.text = "%d:%02d" % [floori(_match_duration / 60.0), int(_match_duration) % 60]
	# Only one limit ends a match (ArenaManager: the score target in
	# SCORE_TARGET, the timer in TIMED_SCORE), so grey out the other.
	var by_score := _win_mode == SettingsManager.WinMode.SCORE_TARGET
	_set_row_active(score_label, score_row, score_slider, by_score)
	_set_row_active(duration_label, duration_row, duration_slider, not by_score)

func _set_row_active(label: Control, row: Control, slider: Slider, active: bool) -> void:
	var tint := Color.WHITE if active else INACTIVE_TINT
	label.modulate = tint
	row.modulate = tint
	slider.editable = active

func _populate_arena_options() -> void:
	arena_stepper.items = PackedStringArray(ArenaDatabase.get_arena_names())
	arena_stepper.set_selected_no_signal(_arena_index)

func _path_to_index(path: String) -> int:
	for i in range(ArenaDatabase.ARENAS.size()):
		if ArenaDatabase.ARENAS[i]["path"] == path:
			return i
	return ArenaDatabase.get_default_index()

func _update_settings_ui() -> void:
	if not SettingsManager:
		return
	sfx_slider.set_value_no_signal(SettingsManager.sfx_volume_db)
	music_slider.set_value_no_signal(SettingsManager.music_volume_db)
	touch_stepper.set_selected_no_signal(SettingsManager.touch_controls_mode)
	auto_attack_check.set_pressed_no_signal(SettingsManager.auto_attack_enabled)
	_refresh_audio_ui()

## Mute icons on both button pairs; a muted channel's volume slider fades out.
func _refresh_audio_ui() -> void:
	if not SettingsManager:
		return
	var sfx_on := SettingsManager.sfx_enabled
	var music_on := SettingsManager.music_enabled
	for button: Button in [sfx_toggle, corner_sound]:
		button.icon = SOUND_ON if sfx_on else SOUND_OFF
	for button: Button in [music_toggle, corner_music]:
		button.icon = MUSIC_ON if music_on else MUSIC_OFF
	sfx_slider.editable = sfx_on
	sfx_slider.modulate = Color.WHITE if sfx_on else INACTIVE_TINT
	music_slider.editable = music_on
	music_slider.modulate = Color.WHITE if music_on else INACTIVE_TINT

func _play_click() -> void:
	if AudioManager:
		AudioManager.play_ui_click()
