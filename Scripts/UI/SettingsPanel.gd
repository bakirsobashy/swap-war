class_name SettingsPanel
extends PanelContainer

## Audio / touch-controls / auto-attack settings card, shared by the main menu
## and the in-match pause menu. Every change goes straight through the
## SettingsManager setters, so it is persisted and applied immediately (the
## live TouchControls re-gate on setting_changed mid-match).

## The back arrow was pressed (the owning menu decides where to go).
signal back_requested
## EDIT TOUCH LAYOUT was pressed (main menu only — the editor is a menu tool).
signal customize_touch_requested
## Sound or music was muted/unmuted (the main menu mirrors it on its corner).
signal audio_changed

const SOUND_ON := preload("res://Assets/ui/ui-2.0/scribble_ui/x1/icons/sound_on.png")
const SOUND_OFF := preload("res://Assets/ui/ui-2.0/scribble_ui/x1/icons/sound_off.png")
const MUSIC_ON := preload("res://Assets/ui/ui-2.0/scribble_ui/x1/icons/music_on.png")
const MUSIC_OFF := preload("res://Assets/ui/ui-2.0/scribble_ui/x1/icons/music_off.png")
## A muted channel's volume slider fades out.
const INACTIVE_TINT := Color(1, 1, 1, 0.4)

## Off in the pause menu: the touch-layout editor only runs from the main menu.
@export var show_touch_layout_button := true

@onready var sfx_slider: HSlider = %SFXSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_toggle: Button = %SFXToggle
@onready var music_toggle: Button = %MusicToggle
@onready var touch_stepper: Stepper = %TouchStepper
@onready var auto_attack_check: CheckButton = %AutoAttackCheck
@onready var customize_touch_btn: Button = %CustomizeTouchBtn

func _ready() -> void:
	customize_touch_btn.visible = show_touch_layout_button
	$VBox/Spacer.visible = show_touch_layout_button    # no gap above a hidden button
	refresh()

static func sound_icon(enabled: bool) -> Texture2D:
	return SOUND_ON if enabled else SOUND_OFF

static func music_icon(enabled: bool) -> Texture2D:
	return MUSIC_ON if enabled else MUSIC_OFF

## Re-read every control from SettingsManager (call whenever the panel opens).
func refresh() -> void:
	if not SettingsManager:
		return
	sfx_slider.set_value_no_signal(SettingsManager.sfx_volume_db)
	music_slider.set_value_no_signal(SettingsManager.music_volume_db)
	touch_stepper.set_selected_no_signal(SettingsManager.touch_controls_mode)
	auto_attack_check.set_pressed_no_signal(SettingsManager.auto_attack_enabled)
	_refresh_audio_ui()

## First control for keyboard/gamepad focus (MenuFocus).
func get_default_focus() -> Control:
	return sfx_toggle

func toggle_sound() -> void:
	if SettingsManager:
		SettingsManager.set_audio_settings(SettingsManager.sfx_volume_db, SettingsManager.music_volume_db,
				not SettingsManager.sfx_enabled, SettingsManager.music_enabled)
	_refresh_audio_ui()
	audio_changed.emit()

func toggle_music() -> void:
	if SettingsManager:
		SettingsManager.set_audio_settings(SettingsManager.sfx_volume_db, SettingsManager.music_volume_db,
				SettingsManager.sfx_enabled, not SettingsManager.music_enabled)
	_refresh_audio_ui()
	audio_changed.emit()

func _on_back_pressed() -> void:
	back_requested.emit()

## DEFAULTS: audio, touch mode and auto attack back to factory values.
func _on_defaults_pressed() -> void:
	if SettingsManager:
		SettingsManager.reset_settings_to_defaults()
	refresh()
	audio_changed.emit()

func _on_customize_touch_pressed() -> void:
	customize_touch_requested.emit()

func _on_sfx_toggle_pressed() -> void:
	toggle_sound()

func _on_music_toggle_pressed() -> void:
	toggle_music()

func _on_sfx_volume_changed(value: float) -> void:
	if SettingsManager:
		SettingsManager.set_audio_settings(value, SettingsManager.music_volume_db, SettingsManager.sfx_enabled, SettingsManager.music_enabled)

func _on_music_volume_changed(value: float) -> void:
	if SettingsManager:
		SettingsManager.set_audio_settings(SettingsManager.sfx_volume_db, value, SettingsManager.sfx_enabled, SettingsManager.music_enabled)

func _on_touch_mode_changed(index: int) -> void:
	if SettingsManager:
		SettingsManager.set_touch_controls_mode(index as SettingsManager.TouchControlsMode)

func _on_auto_attack_toggled(enabled: bool) -> void:
	if SettingsManager:
		SettingsManager.set_auto_attack_enabled(enabled)

## Mute icons; a muted channel's volume slider fades out.
func _refresh_audio_ui() -> void:
	if not SettingsManager:
		return
	var sfx_on := SettingsManager.sfx_enabled
	var music_on := SettingsManager.music_enabled
	sfx_toggle.icon = sound_icon(sfx_on)
	music_toggle.icon = music_icon(music_on)
	sfx_slider.editable = sfx_on
	sfx_slider.modulate = Color.WHITE if sfx_on else INACTIVE_TINT
	music_slider.editable = music_on
	music_slider.modulate = Color.WHITE if music_on else INACTIVE_TINT

func _play_click() -> void:
	if AudioManager:
		AudioManager.play_ui_click()
