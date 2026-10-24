extends Node

signal team_changed(teams: Dictionary)
signal actor_registered(actor: Node)
signal actor_unregistered(actor: Node)
## PREVIEW_LEAD seconds before a swap: the teams the swap WILL apply
## (actor -> team id). ActorMarker shows each actor's next colour from it.
signal next_teams_rolled(next_teams: Dictionary)
## The pending preview is gone (swap applied, timer stopped or restarted).
signal next_teams_cleared()

## How long before a swap the next teams are rolled and previewed.
const PREVIEW_LEAD := 2.0

@export var swap_interval: float = 10.0
@export var team_count: int = 4

var _teams: Dictionary = {}  # Node -> int
var _swap_timer: Timer = null
## Teams rolled early for the coming swap (actor -> team id); empty = none.
var _next_teams: Dictionary = {}

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

## Roll and apply new teams right now (match start). Drops any pending preview.
func randomize_teams() -> void:
	if _teams.is_empty():
		return
	_clear_preview()
	_apply_teams(_roll_teams())

## Next team for `actor` from the pending preview, or -1 when none is showing.
func get_next_team(actor: Node) -> int:
	return _next_teams.get(actor, -1)

## Seconds until the next swap (0 while the timer is stopped).
func time_to_swap() -> float:
	if _swap_timer == null or _swap_timer.is_stopped():
		return 0.0
	return _swap_timer.time_left

func _process(_delta: float) -> void:
	if _swap_timer == null:
		return
	if _next_teams.is_empty():
		if not _teams.is_empty() and not _swap_timer.is_stopped() \
				and _swap_timer.time_left <= PREVIEW_LEAD:
			_next_teams = _roll_teams()
			next_teams_rolled.emit(_next_teams.duplicate())
	elif _swap_timer.is_stopped() or _swap_timer.time_left > PREVIEW_LEAD + 0.1:
		# Stopped (post-round, sudden death, probes) or restarted (Play Again)
		# under a live preview: it no longer describes a coming swap.
		_clear_preview()

## One roll for every registered actor. Never leaves everyone allied (plan
## 4.4.7): with 1 AI a quarter of independent rolls used to put both actors
## on one team for 10 s.
func _roll_teams() -> Dictionary:
	var actors := _teams.keys()
	var rolled: Array[int] = []
	for actor in actors:
		rolled.append(randi() % team_count)
	_ensure_two_teams(rolled)
	var out: Dictionary = {}
	for i in actors.size():
		out[actors[i]] = rolled[i]
	return out

func _ensure_two_teams(rolled: Array[int]) -> void:
	if rolled.size() >= 2 and team_count >= 2 and rolled.count(rolled[0]) == rolled.size():
		var i := randi() % rolled.size()
		rolled[i] = (rolled[i] + 1 + randi() % (team_count - 1)) % team_count

## Apply a roll to the CURRENT registry: actors that left since the roll are
## skipped, actors that joined get a fresh team (they simply had no preview).
func _apply_teams(rolled: Dictionary) -> void:
	var actors := _teams.keys()
	var values: Array[int] = []
	var fresh := false
	for actor in actors:
		if rolled.has(actor):
			values.append(rolled[actor])
		else:
			values.append(randi() % team_count)
			fresh = true
	if fresh:
		_ensure_two_teams(values)
	for i in actors.size():
		set_team(actors[i], values[i])
	team_changed.emit(_teams.duplicate())
	if AudioManager:
		AudioManager.play_team_swap()

func _clear_preview() -> void:
	if _next_teams.is_empty():
		return
	_next_teams.clear()
	next_teams_cleared.emit()

func _register_existing_actors() -> void:
	var tree := get_tree()
	if not tree:
		return
	for actor in tree.get_nodes_in_group("actors"):
		register_actor(actor)

func _on_swap_timeout() -> void:
	if _teams.is_empty():
		_clear_preview()
		return
	# Apply exactly what was previewed (roll now only if no preview happened,
	# e.g. a swap interval shorter than PREVIEW_LEAD).
	var rolled: Dictionary = _next_teams.duplicate() if not _next_teams.is_empty() else _roll_teams()
	_clear_preview()
	_apply_teams(rolled)

func _on_actor_tree_exited(actor: Node) -> void:
	unregister_actor(actor)
