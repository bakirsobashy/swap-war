extends Node

enum MatchState { IDLE, PREPARE, PLAYING, POST_ROUND }

const ActorScene := preload("res://Scenes/actor.tscn")
const PauseMenuScene := preload("res://Scenes/UI/PauseMenu.tscn")
const PostRoundMenuScene := preload("res://Scenes/UI/PostRoundMenu.tscn")

@export var prepare_countdown: float = 3.0
## How long the "GO!" banner stays up after the countdown.
const GO_BANNER_SECONDS := 0.8

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

## Display names: the player is always "YOU"; AIs take these in order. Set as
## the node names so every screen (HUD rows, post-round title) agrees.
const PLAYER_NAME := "YOU"
const AI_NAMES: Array[String] = ["Zack", "Mark", "John", "Stacy"]

## Timed mode ended level at the top: no swaps, the next kill wins.
var _sudden_death: bool = false

func _ready() -> void:
	if ScoreManager:
		ScoreManager.match_won.connect(_on_match_won)
		ScoreManager.score_changed.connect(_on_score_changed)
	# Always listen: booting straight into an arena (F6 / command line) used
	# to skip this, so Quit -> Play from the menu spawned nothing.
	get_tree().scene_changed.connect(_on_scene_changed)
	if _is_arena_scene():
		_setup_arena()

func _on_scene_changed() -> void:
	if _is_arena_scene():
		_setup_arena()
	else:
		# Left the arena (quit to menu): stop the match clock, or a timed
		# match keeps running and "ends" inside the main menu.
		_state = MatchState.IDLE
		_sudden_death = false
		_spawned_actors.clear()

## True once the round is decided (post-round screen up). Health uses it to
## skip a pending respawn so the last victim doesn't pop back behind the menu.
func is_match_over() -> bool:
	return _state == MatchState.POST_ROUND

func _is_arena_scene() -> bool:
	var scene := get_tree().current_scene
	if not scene:
		return false
	var path := scene.scene_file_path
	# Any scene under Scenes/Arenas/ is an arena.
	if path.begins_with("res://Scenes/Arenas/"):
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
	_sudden_death = false
	_despawn_actors()
	_clear_match_leftovers()
	if ScoreManager:
		ScoreManager.reset_scores()
	if TeamManager:
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
		player.name = PLAYER_NAME
		_spawned_actors.append(player)

	# Spawn AI
	for i in range(ai_count):
		var ai := _spawn_actor(false, spawn_points, used_indices)
		if ai:
			ai.name = AI_NAMES[i % AI_NAMES.size()]
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

	# Also remove any leftover actors not tracked (e.g. baked actors we delete later).
	# remove_child first: a queued-but-present "YOU" would force the fresh
	# actor's name to be auto-suffixed.
	var actors_container := get_tree().current_scene.get_node_or_null("Actors")
	if actors_container:
		for child in actors_container.get_children():
			if TeamManager:
				TeamManager.unregister_actor(child)
			actors_container.remove_child(child)
			child.queue_free()

## Play Again must start clean: the previous round's weapons (held ones are
## released when their actor goes), bullets in flight, effects and stains.
func _clear_match_leftovers() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	for w in get_tree().get_nodes_in_group("weapons"):
		if scene.is_ancestor_of(w):
			w.queue_free()
	for p in get_tree().get_nodes_in_group("projectiles"):
		p.queue_free()
	var effects := scene.get_node_or_null("Effects")
	if effects:
		for e in effects.get_children():
			e.queue_free()
	var stains := scene.get_node_or_null("Stains")
	if stains and stains.has_method("clear"):
		stains.clear()
	var spawner := scene.get_node_or_null("WeaponSpawner")
	if spawner and spawner.has_method("reset_waves"):
		spawner.reset_waves()

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
		# "3 · 2 · 1 · GO!" — show_message only re-pops when the digit changes.
		hud.show_message(str(int(ceil(_countdown_timer))))

func _start_playing() -> void:
	_state = MatchState.PLAYING
	var hud := _get_hud()
	if hud:
		hud.show_message("GO!")
		get_tree().create_timer(GO_BANNER_SECONDS).timeout.connect(_hide_go_banner)
	# Opening drop at "GO": nobody can attack unarmed, so without it the
	# first sky wave (~7 s in) was dead time.
	var scene := get_tree().current_scene
	var spawner := scene.get_node_or_null("WeaponSpawner") if scene else null
	if spawner and spawner.has_method("spawn_opening_wave"):
		spawner.spawn_opening_wave()

func _end_match_by_time() -> void:
	if _state != MatchState.PLAYING or _sudden_death:
		return
	var leaders: Array = ScoreManager.get_leaders() if ScoreManager else []
	if leaders.size() > 1:
		# Level at the top (plan 1.6): swaps stop, the next kill decides it.
		# Ties used to go silently to whoever registered first — the player.
		_sudden_death = true
		if TeamManager and TeamManager._swap_timer:
			TeamManager._swap_timer.stop()
		var hud := _get_hud()
		if hud:
			hud.show_message("SUDDEN DEATH!")
			get_tree().create_timer(2.0).timeout.connect(_hide_sudden_death_banner)
		return
	_state = MatchState.POST_ROUND
	_win_reason = "Time Up"
	_show_post_round(leaders[0] if leaders.size() == 1 else null)

func _hide_go_banner() -> void:
	var hud := _get_hud()
	if hud and _state == MatchState.PLAYING and not _sudden_death:
		hud.hide_winner()

## HUD goal chip: seconds left in a timed match (counts during PREPARE too).
func get_match_time_left() -> float:
	return maxf(_match_timer, 0.0)

func is_timed_match() -> bool:
	return _win_mode == SettingsManager.WinMode.TIMED_SCORE

func is_sudden_death() -> bool:
	return _sudden_death

func _hide_sudden_death_banner() -> void:
	var hud := _get_hud()
	if hud and _state == MatchState.PLAYING:
		hud.hide_winner()

func _on_score_changed(actor: Node, _score: int) -> void:
	if not _sudden_death or _state != MatchState.PLAYING or _score <= 0:
		return
	_state = MatchState.POST_ROUND
	_win_reason = "Sudden Death"
	_show_post_round(actor)

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
