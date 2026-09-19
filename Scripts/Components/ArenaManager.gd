extends Node

enum MatchState { IDLE, PREPARE, PLAYING, POST_ROUND }

const ActorScene := preload("res://Scenes/actor.tscn")
const PauseMenuScene := preload("res://Scenes/UI/PauseMenu.tscn")
const PostRoundMenuScene := preload("res://Scenes/UI/PostRoundMenu.tscn")

@export var prepare_countdown: float = 3.0
@export var winner_message_duration: float = 5.0

## IDLE until an arena scene is actually set up: the autoload exists before
## any scene does (main menu, probe mode), and a countdown ticking there both
## corrupts the state (PLAYING "starts" with no match) and crashes on the null
## current_scene when an arena is freed mid-countdown.
var _state: MatchState = MatchState.IDLE
var _match_timer: float = 0.0
var _countdown_timer: float = 0.0
var _spawned_actors: Array[Node] = []
var _pause_menu: CanvasLayer = null
var _post_round_menu: CanvasLayer = null
var _win_reason: String = ""
var _win_mode: SettingsManager.WinMode = SettingsManager.WinMode.SCORE_TARGET

func _ready() -> void:
	if ScoreManager:
		ScoreManager.match_won.connect(_on_match_won)
	if _is_arena_scene():
		_setup_arena()
	else:
		get_tree().scene_changed.connect(_on_scene_changed)

func _on_scene_changed() -> void:
	if _is_arena_scene():
		_setup_arena()

func _is_arena_scene() -> bool:
	var scene := get_tree().current_scene
	if not scene:
		return false
	var path := scene.scene_file_path
	# Support the legacy arena scene and any scene under Scenes/Arenas/.
	if path == "res://Scenes/arena.tscn" or path.begins_with("res://Scenes/Arenas/"):
		return true
	# Fallback: treat any scene with the expected arena structure as an arena.
	return scene.has_node("World/SpawnPoints") and scene.has_node("Actors")

func _setup_arena() -> void:
	_load_match_config()
	_setup_menus()
	_start_match()

func _process(delta: float) -> void:
	match _state:
		MatchState.IDLE:
			pass
		MatchState.PREPARE:
			_countdown_timer -= delta
			_update_countdown_display()
			if _countdown_timer <= 0.0:
				_start_playing()
		MatchState.PLAYING:
			_match_timer -= delta
			if _match_timer <= 0.0 and _win_mode == SettingsManager.WinMode.TIMED_SCORE:
				_end_match_by_time()

func _load_match_config() -> void:
	if not SettingsManager:
		return
	_win_mode = SettingsManager.win_mode
	if ScoreManager:
		ScoreManager.score_to_win = SettingsManager.score_target
		ScoreManager.track_score = (_win_mode == SettingsManager.WinMode.SCORE_TARGET)
	_match_timer = SettingsManager.match_duration_seconds

func _setup_menus() -> void:
	_pause_menu = PauseMenuScene.instantiate()
	get_tree().current_scene.call_deferred("add_child", _pause_menu)
	_post_round_menu = PostRoundMenuScene.instantiate()
	get_tree().current_scene.call_deferred("add_child", _post_round_menu)

func _start_match() -> void:
	_state = MatchState.PREPARE
	_countdown_timer = prepare_countdown
	_match_timer = _get_match_duration()
	_win_reason = ""
	_despawn_actors()
	if ScoreManager:
		ScoreManager.reset_scores()
	if TeamManager:
		TeamManager.team_count = 3
		if TeamManager._swap_timer:
			TeamManager._swap_timer.start()
	_spawn_actors()
	_show_countdown_display()

func _get_match_duration() -> float:
	if SettingsManager:
		return SettingsManager.match_duration_seconds
	return 60.0

func restart_match() -> void:
	_start_match()

func _spawn_actors() -> void:
	var ai_count := 3
	if SettingsManager:
		ai_count = SettingsManager.ai_count

	var spawn_points := _get_spawn_points()
	if spawn_points.is_empty():
		push_warning("No spawn points found in World/SpawnPoints")
		return

	var used_indices: Array[int] = []

	# Spawn player
	var player := _spawn_actor(true, spawn_points, used_indices)
	if player:
		_spawned_actors.append(player)

	# Spawn AI
	for i in range(ai_count):
		var ai := _spawn_actor(false, spawn_points, used_indices)
		if ai:
			_spawned_actors.append(ai)

	# Register all spawned actors with TeamManager
	for actor in _spawned_actors:
		if TeamManager:
			TeamManager.register_actor(actor)

	if TeamManager:
		TeamManager.randomize_teams()

func _spawn_actor(is_player_actor: bool, spawn_points: Array[Marker2D], used_indices: Array[int]) -> Node:
	if spawn_points.is_empty():
		return null

	var index := _pick_unique_index(spawn_points.size(), used_indices)
	if index < 0:
		index = randi() % spawn_points.size()

	var actor := ActorScene.instantiate() as RigidBody2D
	actor.global_position = spawn_points[index].global_position
	actor.add_to_group("actors")

	if "is_player" in actor:
		actor.is_player = is_player_actor

	var actors_container := get_tree().current_scene.get_node_or_null("Actors")
	if actors_container:
		actors_container.add_child(actor)
	else:
		get_tree().current_scene.add_child(actor)

	return actor

func _pick_unique_index(size: int, used: Array[int]) -> int:
	if used.size() >= size:
		return -1
	var available: Array[int] = []
	for i in range(size):
		if not used.has(i):
			available.append(i)
	var chosen := available[randi() % available.size()]
	used.append(chosen)
	return chosen

func _get_spawn_points() -> Array[Marker2D]:
	var result: Array[Marker2D] = []
	var spawn_root := get_tree().current_scene.get_node_or_null("World/SpawnPoints")
	if not spawn_root:
		return result
	for child in spawn_root.get_children():
		if child is Marker2D:
			result.append(child)
	return result

func _despawn_actors() -> void:
	for actor in _spawned_actors:
		if is_instance_valid(actor):
			if TeamManager:
				TeamManager.unregister_actor(actor)
			actor.queue_free()
	_spawned_actors.clear()

	# Also remove any leftover actors not tracked (e.g. baked actors we delete later)
	var actors_container := get_tree().current_scene.get_node_or_null("Actors")
	if actors_container:
		for child in actors_container.get_children():
			if TeamManager:
				TeamManager.unregister_actor(child)
			child.queue_free()

func _show_countdown_display() -> void:
	var hud := _get_hud()
	if hud:
		hud.hide_winner()

## Null-safe HUD lookup: on quit-to-menu during the countdown the old arena is
## freed a frame or two before the replacement scene is added, so _process can
## still tick while current_scene is null.
func _get_hud() -> HUD:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("HUD") as HUD

func _update_countdown_display() -> void:
	var hud := _get_hud()
	if hud:
		var seconds := int(ceil(_countdown_timer))
		hud.show_winner("START IN %d" % seconds)

func _start_playing() -> void:
	_state = MatchState.PLAYING
	var hud := _get_hud()
	if hud:
		hud.hide_winner()

func _end_match_by_time() -> void:
	if _state != MatchState.PLAYING:
		return
	_state = MatchState.POST_ROUND
	_win_reason = "Time Up"
	var winner: Node = null
	if ScoreManager:
		winner = ScoreManager.get_leader()
	_show_post_round(winner)

func _on_match_won(winner: Node, _score: int) -> void:
	if _state != MatchState.PLAYING:
		return
	_state = MatchState.POST_ROUND
	_win_reason = "Score Target"
	_show_post_round(winner)

func _show_post_round(winner: Node) -> void:
	if AudioManager:
		AudioManager.play_win()

	var scores: Dictionary = {}
	if ScoreManager:
		for actor in _spawned_actors:
			if is_instance_valid(actor):
				scores[actor] = ScoreManager.get_score(actor)

	if _post_round_menu:
		_post_round_menu.show_post_round(winner, scores, _win_reason)

	# Stop team swapping and freeze actors
	if TeamManager and TeamManager._swap_timer:
		TeamManager._swap_timer.stop()

	for actor in _spawned_actors:
		if is_instance_valid(actor):
			actor.process_mode = Node.PROCESS_MODE_DISABLED
			# process_mode only stops script callbacks; RigidBody2Ds keep
			# moving under physics integration unless we freeze them too.
			if actor is RigidBody2D:
				actor.freeze = true

func _on_play_again() -> void:
	if _post_round_menu:
		_post_round_menu.hide_post_round()
	restart_match()

func _on_quit_to_menu() -> void:
	if _post_round_menu:
		_post_round_menu.hide_post_round()
	get_tree().change_scene_to_file("res://Scenes/UI/MainMenu.tscn")
