extends Node

@export var sfx_enabled: bool = true
@export var music_enabled: bool = true
@export var sfx_volume_db: float = -6.0
@export var music_volume_db: float = -12.0

# Gameplay sounds
@export var hit_sound: AudioStream
@export var death_sound: AudioStream
@export var jump_sound: AudioStream
@export var land_sound: AudioStream
@export var melee_attack_sound: AudioStream
@export var ranged_attack_sound: AudioStream
@export var team_swap_sound: AudioStream
@export var win_sound: AudioStream
@export var pickup_sound: AudioStream
@export var drop_sound: AudioStream
@export var music_sound: AudioStream

const KENNEY_DIR := "res://Assets/audio/sfx/kenney/"
const DEFAULT_MUSIC_PATH := "res://Assets/audio/music/Street-Chaos.ogg"

## Gameplay sound library — Kenney packs (CC0; Assets/audio/sfx/kenney/License.txt).
## Each event plays a random clip from its list; gain_db evens out the packs'
## loudness (measured RMS), pitch is the random pitch jitter. An export set on
## the autoload overrides the library for that event. Gunshots stay on the
## project's own fire.mp3: the Kenney packs have no gun sounds.
const LIBRARY := {
	&"hit": {"clips": ["impactPunch_medium_000", "impactPunch_medium_001", "impactPunch_medium_002",
			"impactPunch_medium_003", "impactPunch_medium_004"], "gain_db": 2.0, "pitch": 0.1},
	&"death": {"clips": ["impactPunch_heavy_000", "impactPunch_heavy_001", "impactPunch_heavy_002",
			"impactPunch_heavy_003", "impactPunch_heavy_004"], "gain_db": 2.0, "pitch": 0.1},
	&"jump": {"clips": ["phaseJump1", "phaseJump2"], "gain_db": -6.0, "pitch": 0.05},
	&"land": {"clips": ["impactSoft_medium_000", "impactSoft_medium_001", "impactSoft_medium_002",
			"impactSoft_medium_003", "impactSoft_medium_004"], "gain_db": -8.0, "pitch": 0.1},
	&"melee": {"clips": ["knifeSlice", "knifeSlice2"], "gain_db": 0.0, "pitch": 0.08},
	&"ranged": {"clips": ["res://Assets/audio/vfx/fire.mp3"], "gain_db": 0.0, "pitch": 0.05},
	&"team_swap": {"clips": ["threeTone2"], "gain_db": -4.0, "pitch": 0.0},
	&"win": {"clips": ["jingles_PIZZI02"], "gain_db": 0.0, "pitch": 0.0},
	&"pickup": {"clips": ["drawKnife2", "drawKnife3"], "gain_db": 10.0, "pitch": 0.1},
	&"drop": {"clips": ["impactMetal_light_000", "impactMetal_light_001", "impactMetal_light_002",
			"impactMetal_light_003", "impactMetal_light_004"], "gain_db": -2.0, "pitch": 0.1},
}

## event -> Array[AudioStream] (the library clips, loaded once).
var _library_clips: Dictionary = {}

# UI sounds
@export var ui_click_sound: AudioStream
@export var ui_hover_sound: AudioStream
@export var ui_toggle_sound: AudioStream
@export var ui_touch_sound: AudioStream

var _sfx_bus: int = 0
var _music_bus: int = 0

func _ready() -> void:
	_load_default_ui_sounds()
	_load_default_gameplay_sounds()
	_setup_audio_buses()
	_start_default_music()

func _load_default_ui_sounds() -> void:
	if not ui_click_sound:
		ui_click_sound = load("res://Assets/ui/Sounds/click-a.ogg")
	if not ui_hover_sound:
		ui_hover_sound = load("res://Assets/ui/Sounds/click-b.ogg")
	if not ui_toggle_sound:
		ui_toggle_sound = load("res://Assets/ui/Sounds/switch-a.ogg")
	if not ui_touch_sound:
		ui_touch_sound = load("res://Assets/ui/Sounds/tap-a.ogg")

## Load every library clip once. A clip name without a path lives in KENNEY_DIR.
func _load_default_gameplay_sounds() -> void:
	for event in LIBRARY:
		var clips: Array[AudioStream] = []
		for clip_name: String in LIBRARY[event]["clips"]:
			var path := clip_name if clip_name.begins_with("res://") else KENNEY_DIR + clip_name + ".ogg"
			var clip := load(path) as AudioStream
			if clip:
				clips.append(clip)
			else:
				push_warning("AudioManager: missing sound '%s'" % path)
		_library_clips[event] = clips

## One gameplay event: the export override if set, else a random library clip
## with the event's gain and pitch jitter.
func _play_event(event: StringName, override: AudioStream) -> void:
	var entry: Dictionary = LIBRARY[event]
	if override:
		play_sfx(override, entry["pitch"])
		return
	var clips: Array = _library_clips.get(event, [])
	if clips.is_empty():
		return
	play_sfx(clips[randi() % clips.size()], entry["pitch"], entry["gain_db"])

## For probes: every library event resolved to at least one clip.
func get_library_clip_count(event: StringName) -> int:
	return (_library_clips.get(event, []) as Array).size()

func play_sfx(stream: AudioStream, pitch_random: float = 0.0, volume_db: float = 0.0) -> void:
	if not sfx_enabled or not stream:
		return

	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.bus = AudioServer.get_bus_name(_sfx_bus)
	if pitch_random > 0.0:
		player.pitch_scale = 1.0 + randf_range(-pitch_random, pitch_random)
	player.finished.connect(func() -> void: player.queue_free())
	add_child(player)
	player.play()

func play_music(stream: AudioStream) -> void:
	if not music_enabled or not stream:
		return

	_stop_music()
	var player := AudioStreamPlayer.new()
	player.name = "MusicPlayer"
	player.stream = stream
	player.bus = AudioServer.get_bus_name(_music_bus)
	player.autoplay = true
	# Safety net: if the stream cannot loop internally, keep it playing anyway.
	player.finished.connect(player.play)
	add_child(player)

## Play the default background music everywhere (menu + arena).
func _start_default_music() -> void:
	if music_sound == null:
		music_sound = load(DEFAULT_MUSIC_PATH)
		if music_sound is AudioStreamOggVorbis and "loop" in music_sound:
			music_sound.loop = true
	play_music(music_sound)

func stop_music() -> void:
	_stop_music()

func play_hit() -> void:
	_play_event(&"hit", hit_sound)

func play_death() -> void:
	_play_event(&"death", death_sound)

func play_jump() -> void:
	_play_event(&"jump", jump_sound)

func play_land() -> void:
	_play_event(&"land", land_sound)

func play_melee_attack() -> void:
	_play_event(&"melee", melee_attack_sound)

func play_ranged_fire() -> void:
	_play_event(&"ranged", ranged_attack_sound)

func play_team_swap() -> void:
	_play_event(&"team_swap", team_swap_sound)

func play_win() -> void:
	_play_event(&"win", win_sound)

func play_pickup() -> void:
	_play_event(&"pickup", pickup_sound)

func play_drop() -> void:
	_play_event(&"drop", drop_sound)

func play_ui_click() -> void:
	play_sfx(ui_click_sound, 0.0)

func play_ui_hover() -> void:
	play_sfx(ui_hover_sound, 0.0)

func play_ui_toggle() -> void:
	play_sfx(ui_toggle_sound, 0.0)

func play_ui_touch() -> void:
	play_sfx(ui_touch_sound, 0.0)

func _stop_music() -> void:
	var existing := get_node_or_null("MusicPlayer") as AudioStreamPlayer
	if existing:
		existing.stop()
		existing.queue_free()

func set_sfx_volume_db(value_db: float) -> void:
	sfx_volume_db = value_db
	AudioServer.set_bus_volume_db(_sfx_bus, value_db)

func set_music_volume_db(value_db: float) -> void:
	music_volume_db = value_db
	AudioServer.set_bus_volume_db(_music_bus, value_db)

func set_sfx_enabled(enabled: bool) -> void:
	sfx_enabled = enabled

func set_music_enabled(enabled: bool) -> void:
	music_enabled = enabled
	if not enabled:
		_stop_music()
	elif get_node_or_null("MusicPlayer") == null:
		_start_default_music()

func _setup_audio_buses() -> void:
	var master_name := AudioServer.get_bus_name(0)

	_sfx_bus = AudioServer.get_bus_index("SFX")
	if _sfx_bus < 0:
		AudioServer.add_bus()
		_sfx_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_sfx_bus, "SFX")
	AudioServer.set_bus_volume_db(_sfx_bus, sfx_volume_db)
	AudioServer.set_bus_send(_sfx_bus, master_name)

	_music_bus = AudioServer.get_bus_index("Music")
	if _music_bus < 0:
		AudioServer.add_bus()
		_music_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_music_bus, "Music")
	AudioServer.set_bus_volume_db(_music_bus, music_volume_db)
	AudioServer.set_bus_send(_music_bus, master_name)
