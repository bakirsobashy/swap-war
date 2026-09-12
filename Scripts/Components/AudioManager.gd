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
@export var attack_sound: AudioStream
@export var team_swap_sound: AudioStream
@export var win_sound: AudioStream
@export var pickup_sound: AudioStream
@export var drop_sound: AudioStream

# UI sounds
@export var ui_click_sound: AudioStream
@export var ui_hover_sound: AudioStream
@export var ui_toggle_sound: AudioStream
@export var ui_touch_sound: AudioStream

var _sfx_bus: int = 0
var _music_bus: int = 0

func _ready() -> void:
	_load_default_ui_sounds()
	_setup_audio_buses()

func _load_default_ui_sounds() -> void:
	if not ui_click_sound:
		ui_click_sound = load("res://Assets/ui/Sounds/click-a.ogg")
	if not ui_hover_sound:
		ui_hover_sound = load("res://Assets/ui/Sounds/click-b.ogg")
	if not ui_toggle_sound:
		ui_toggle_sound = load("res://Assets/ui/Sounds/switch-a.ogg")
	if not ui_touch_sound:
		ui_touch_sound = load("res://Assets/ui/Sounds/tap-a.ogg")

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
	add_child(player)

func stop_music() -> void:
	_stop_music()

func play_hit() -> void:
	play_sfx(hit_sound, 0.1)

func play_death() -> void:
	play_sfx(death_sound, 0.1)

func play_jump() -> void:
	play_sfx(jump_sound, 0.05)

func play_land() -> void:
	play_sfx(land_sound, 0.1)

func play_attack() -> void:
	play_sfx(attack_sound, 0.1)

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
