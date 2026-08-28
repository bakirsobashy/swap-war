extends Node

signal team_changed(teams: Dictionary)
signal actor_registered(actor: Node)
signal actor_unregistered(actor: Node)

@export var swap_interval: float = 5.0
@export var team_count: int = 3

var _teams: Dictionary = {}  # Node -> int
var _swap_timer: Timer = null

func _ready() -> void:
	_swap_timer = Timer.new()
	_swap_timer.wait_time = swap_interval
	_swap_timer.one_shot = false
	_swap_timer.timeout.connect(_on_swap_timeout)
	add_child(_swap_timer)
	_swap_timer.start()

	call_deferred("_register_existing_actors")
	call_deferred("randomize_teams")

func register_actor(actor: Node) -> void:
	if not actor:
		return
	if _teams.has(actor):
		return
	_teams[actor] = 0
	actor.tree_exited.connect(_on_actor_tree_exited.bind(actor))
	actor_registered.emit(actor)

func unregister_actor(actor: Node) -> void:
	if not _teams.has(actor):
		return
	_teams.erase(actor)
	actor_unregistered.emit(actor)

func get_team(actor: Node) -> int:
	if not actor:
		return 0
	return _teams.get(actor, 0)

func set_team(actor: Node, team_id: int) -> void:
	if not actor:
		return
	_teams[actor] = team_id
	var team_member := actor.get_node_or_null("Components/TeamMember") as TeamMember
	if team_member:
		team_member.team_id = team_id

func get_actors_on_team(team_id: int) -> Array:
	var result: Array = []
	for actor in _teams.keys():
		if _teams[actor] == team_id:
			result.append(actor)
	return result

func randomize_teams() -> void:
	var actors := _teams.keys()
	if actors.is_empty():
		return

	for actor in actors:
		var new_team := randi() % team_count
		set_team(actor, new_team)

	team_changed.emit(_teams.duplicate())
	if AudioManager:
		AudioManager.play_team_swap()

func _register_existing_actors() -> void:
	var tree := get_tree()
	if not tree:
		return
	for actor in tree.get_nodes_in_group("actors"):
		register_actor(actor)

func _on_swap_timeout() -> void:
	randomize_teams()

func _on_actor_tree_exited(actor: Node) -> void:
	unregister_actor(actor)
