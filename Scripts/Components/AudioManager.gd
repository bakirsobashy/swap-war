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

const SOUND_DIR := "res://Assets/audio/vfx/"
const GENERATED_DIR := "res://Assets/audio/generated/"
const DEFAULT_MUSIC_PATH := "res://Assets/audio/music/Street-Chaos.ogg"

# Multi-variant clips (e.g. swing1/swing2, land1/land2): when no export is
# assigned, a random clip from these lists plays for cheap variety.
var _melee_attack_variants: Array[AudioStream] = []
var _land_variants: Array[AudioStream] = []

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

## Library defaults; explicit exports on the autoload still win.
func _load_default_gameplay_sounds() -> void:
	if not jump_sound:
		jump_sound = load(SOUND_DIR + "jump.mp3")
	if not melee_attack_sound:
		_melee_attack_variants = _load_clips(["swing1.mp3", "swing2.mp3"])
	if not land_sound:
		_land_variants = _load_clips(["land1.mp3", "land2.mp3"])
	if not ranged_attack_sound:
		ranged_attack_sound = load(SOUND_DIR + "fire.mp3")
	if not pickup_sound:
		pickup_sound = load(SOUND_DIR + "Pickup.mp3")
	if not win_sound:
		win_sound = load(SOUND_DIR + "win-jingle.mp3")
	if not team_swap_sound:
		team_swap_sound = load(SOUND_DIR + "Transitions.mp3")
	# TODO: synthesized placeholders until final assets arrive.
	if not hit_sound:
		hit_sound = load(GENERATED_DIR + "hit.wav")
	if not death_sound:
		death_sound = load(GENERATED_DIR + "death.wav")
	if not drop_sound:
		drop_sound = load(GENERATED_DIR + "drop.wav")

func _load_clips(file_names: Array) -> Array[AudioStream]:
	var clips: Array[AudioStream] = []
	for file_name in file_names:
		var clip := load(SOUND_DIR + file_name) as AudioStream
		if clip:
			clips.append(clip)
	return clips

func _pick_clip(clips: Array[AudioStream]) -> AudioStream:
	if clips.is_empty():
		return null
	return clips[randi() % clips.size()]

func play_sfx(stream: AudioStream, pitch_random: float = 0.0) -> void:
	if not sfx_enabled or not stream:
		return

	var player := AudioStreamPlayer.new()
	player.stream = stream
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
	play_sfx(hit_sound, 0.1)

func play_death() -> void:
	play_sfx(death_sound, 0.1)

func play_jump() -> void:
	play_sfx(jump_sound, 0.05)

func play_land() -> void:
	play_sfx(land_sound if land_sound else _pick_clip(_land_variants), 0.1)

func play_melee_attack() -> void:
	play_sfx(melee_attack_sound if melee_attack_sound else _pick_clip(_melee_attack_variants), 0.08)

func play_ranged_fire() -> void:
	play_sfx(ranged_attack_sound, 0.05)

func play_team_swap() -> void:
	play_sfx(team_swap_sound, 0.0)

func play_win() -> void:
	play_sfx(win_sound, 0.0)

func play_pickup() -> void:
	play_sfx(pickup_sound, 0.1)

func play_drop() -> void:
	play_sfx(drop_sound, 0.1)

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
