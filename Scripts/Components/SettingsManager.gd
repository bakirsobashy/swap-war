extends Node

enum WinMode { SCORE_TARGET, TIMED_SCORE }
enum TouchControlsMode { AUTO, ALWAYS, HIDDEN }

const CONFIG_PATH := "user://swap_war_settings.cfg"

signal settings_loaded()

# Audio settings
@export var sfx_volume_db: float = -6.0
@export var music_volume_db: float = -12.0
@export var sfx_enabled: bool = true
@export var music_enabled: bool = true

# UI settings
@export var touch_controls_mode: TouchControlsMode = TouchControlsMode.AUTO
## Auto Attack (default off — manual is the default): melee weapons auto-swing
## at the nearest hostile in reach (aiming at it, on PC too); ranged weapons
## auto-fire while the touch aim stick is deflected (touch-only — PC aims
## with the mouse). The manual ATTACK input always works alongside it.
@export var auto_attack_enabled: bool = false
## Custom touch-control layout: control name -> Vector3(nx, ny, size_mult)
## (nx/ny normalized to canvas size at save time; mult 0.5-2.0 on top of the
## automatic resolution scale). Empty = procedural layout. Applied per-control
## by TouchControls._layout_buttons; edited by the in-menu TouchLayoutEditor.
@export var touch_layout: Dictionary = {}

# Match options (persisted as last-used)
@export var ai_count: int = 3
@export var win_mode: WinMode = WinMode.SCORE_TARGET
@export var score_target: int = 10
@export var match_duration_seconds: float = 120.0
@export var selected_arena_path: String = ArenaDatabase.DEFAULT_PATH

func _ready() -> void:
	load_settings()
	_apply_audio_settings()
	settings_loaded.emit()

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "sfx_volume_db", sfx_volume_db)
	config.set_value("audio", "music_volume_db", music_volume_db)
	config.set_value("audio", "sfx_enabled", sfx_enabled)
	config.set_value("audio", "music_enabled", music_enabled)
	config.set_value("ui", "touch_controls_mode", touch_controls_mode)
	config.set_value("ui", "auto_attack_enabled", auto_attack_enabled)
	config.set_value("match", "ai_count", ai_count)
	config.set_value("match", "win_mode", win_mode)
	config.set_value("match", "score_target", score_target)
	config.set_value("match", "match_duration_seconds", match_duration_seconds)
	config.set_value("match", "selected_arena_path", selected_arena_path)
	# Custom touch layout — one key per control (empty dict writes no section).
	for key in touch_layout.keys():
		config.set_value("touch_layout", key, touch_layout[key])
	var err := config.save(CONFIG_PATH)
	if err != OK:
		push_warning("Failed to save settings: %d" % err)

func load_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load(CONFIG_PATH)
	if err != OK:
		return

	sfx_volume_db = config.get_value("audio", "sfx_volume_db", sfx_volume_db)
	music_volume_db = config.get_value("audio", "music_volume_db", music_volume_db)
	sfx_enabled = config.get_value("audio", "sfx_enabled", sfx_enabled)
	music_enabled = config.get_value("audio", "music_enabled", music_enabled)
	touch_controls_mode = config.get_value("ui", "touch_controls_mode", touch_controls_mode)
	auto_attack_enabled = config.get_value("ui", "auto_attack_enabled", auto_attack_enabled)
	ai_count = config.get_value("match", "ai_count", ai_count)
	win_mode = config.get_value("match", "win_mode", win_mode)
	score_target = config.get_value("match", "score_target", score_target)
	match_duration_seconds = config.get_value("match", "match_duration_seconds", match_duration_seconds)
	selected_arena_path = config.get_value("match", "selected_arena_path", selected_arena_path)
	# Custom touch layout — filter to Vector3 so corrupt entries self-heal
	# on the next save.
	touch_layout.clear()
	if config.has_section("touch_layout"):
		for key in config.get_section_keys("touch_layout"):
			var v: Variant = config.get_value("touch_layout", key, null)
			if v is Vector3:
				touch_layout[key] = v
	if selected_arena_path.is_empty():
		selected_arena_path = ArenaDatabase.DEFAULT_PATH

func _apply_audio_settings() -> void:
	if AudioManager:
		AudioManager.set_sfx_volume_db(sfx_volume_db)
		AudioManager.set_music_volume_db(music_volume_db)
		AudioManager.set_sfx_enabled(sfx_enabled)
		AudioManager.set_music_enabled(music_enabled)

func set_audio_settings(sfx_db: float, music_db: float, sfx_on: bool, music_on: bool) -> void:
	sfx_volume_db = sfx_db
	music_volume_db = music_db
	sfx_enabled = sfx_on
	music_enabled = music_on
	_apply_audio_settings()
	save_settings()

func set_match_options(new_ai_count: int, new_win_mode: WinMode, new_score_target: int, new_duration: float) -> void:
	ai_count = clampi(new_ai_count, 1, 3)
	win_mode = new_win_mode
	score_target = maxi(new_score_target, 1)
	match_duration_seconds = maxf(new_duration, 30.0)
	save_settings()

func set_arena_path(path: String) -> void:
	if path.is_empty():
		selected_arena_path = ArenaDatabase.DEFAULT_PATH
	else:
		selected_arena_path = path
	save_settings()

func set_touch_controls_mode(mode: TouchControlsMode) -> void:
	touch_controls_mode = mode
	save_settings()
	setting_changed.emit()

func set_auto_attack_enabled(enabled: bool) -> void:
	auto_attack_enabled = enabled
	save_settings()
	setting_changed.emit()

## NOTE: no setting_changed here — it is wired to TouchControls'
## _visibility_changed, and a layout value has nothing to do with visibility.
## The layout is re-read by TouchControls._layout_buttons on demand (every
## HUD _ready + viewport resize), like the audio/match setters that don't emit.
func set_touch_layout(layout: Dictionary) -> void:
	touch_layout = layout
	save_settings()

func clear_touch_layout() -> void:
	touch_layout = {}
	save_settings()

signal setting_changed()
