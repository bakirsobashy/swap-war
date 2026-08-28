extends Node

signal score_changed(actor: Node, score: int)
signal match_won(winner: Node, score: int)

@export var score_to_win: int = 10
@export var track_score: bool = true

var _scores: Dictionary = {}  # Node -> int

func _ready() -> void:
	# Register all actors already in the scene and wire up to future ones.
	call_deferred("_register_existing_actors")
	if TeamManager:
		TeamManager.actor_registered.connect(register_actor)
		TeamManager.actor_unregistered.connect(unregister_actor)

func register_actor(actor: Node) -> void:
	if not actor:
		return
	if not _scores.has(actor):
		_scores[actor] = 0
		var health := actor.get_node_or_null("Components/Health") as Health
		if health:
			health.died.connect(_on_actor_died.bind(actor))

func unregister_actor(actor: Node) -> void:
	if _scores.has(actor):
		_scores.erase(actor)

func get_score(actor: Node) -> int:
	return _scores.get(actor, 0)

func add_score(actor: Node, amount: int = 1) -> void:
	if not actor:
		return
	if not _scores.has(actor):
		register_actor(actor)
	_scores[actor] += amount
	score_changed.emit(actor, _scores[actor])

	if track_score and _scores[actor] >= score_to_win:
		match_won.emit(actor, _scores[actor])

func reset_scores() -> void:
	for actor in _scores.keys():
		_scores[actor] = 0
		score_changed.emit(actor, 0)

func get_leader() -> Node:
	var best: Node = null
	var best_score := -1
	for actor in _scores.keys():
		var s: int = _scores[actor]
		if s > best_score:
			best_score = s
			best = actor
	return best

func _on_actor_died(victim: Node) -> void:
	if not victim:
		return
	var killer := _find_last_attacker(victim)
	if not killer:
		return
	if _is_same_team(killer, victim):
		return
	add_score(killer, 1)

func _find_last_attacker(victim: Node) -> Node:
	# Fallback: last actor who recently damaged this victim is tracked by WeaponHolder.
	var holder := victim.get_node_or_null("WeaponHolder") as WeaponHolder
	if holder and holder.last_attacker:
		return holder.last_attacker
	return null

func _is_same_team(a: Node, b: Node) -> bool:
	return TeamMember.is_same_team(a, b)

func _register_existing_actors() -> void:
	var tree := get_tree()
	if not tree:
		return
	for actor in tree.get_nodes_in_group("actors"):
		register_actor(actor)
