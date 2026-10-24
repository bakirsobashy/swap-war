class_name HazardArea
extends Area2D

## Damage-dealing zone (static spikes today, timed hazards later).
##
## Two contracts in one node:
##   - DAMAGE: any RigidBody2D with a Health component overlapping this area
##     takes `damage` every `damage_interval` seconds per actor, plus a small
##     knockback pop. Health's own dead-check and post-respawn invulnerability
##     handle the edge cases; dead actors are dropped from the overlap by
##     Health clearing their collision layers.
##   - NAV: group "hazards" membership feeds the nav graph. NavBaker's group
##     scan picks this area up on bake; if a graph is already cached on an
##     ancestor (arena) node — hazard spawned after the bake — the deferred
##     _register_nav adds it to the live graph, and _exit_tree removes it.
##     The registration cost is `nav_cost_multiplier` (A* avoids walking
##     through here; the split segments make "through" a real cost).
##
## Compile-safety: no autoload references; game classes are duck-typed, so
## headless `-s` probes can instantiate scenes containing this script.

const NavBakerScript := preload("res://Scripts/AI/NavBaker.gd")

@export var damage: float = 15.0
## Per-actor hit cooldown in seconds. The first hit lands immediately on
## contact; this paces the ones after (not per-frame damage spam).
@export var damage_interval: float = 0.5
## Impulse applied on each hit (a small pop upward by default).
@export var knockback_impulse: Vector2 = Vector2(0.0, -260.0)
## One hit deals max damage instead (e.g. lethal hazard variants).
@export var instant_kill: bool = false
## A* cost multiplier for the floor segment this area covers (4.0 makes
## walking through roughly as costly as eating two hits).
@export var nav_cost_multiplier: float = 4.0

var _cooldowns: Dictionary = {} # body instance id -> seconds until next hit
var _registered_graph: RefCounted = null
var _registered_rect: Rect2 = Rect2()

func _ready() -> void:
	add_to_group("hazards")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# Deferred so the owning scene is fully in the tree (graph meta reachable)
	# and so this never runs inside NavBaker's own group scan.
	call_deferred("_register_nav")

func _exit_tree() -> void:
	if _registered_graph != null and is_instance_valid(_registered_graph):
		_registered_graph.remove_hazard_rect(_registered_rect)
	_registered_graph = null

func _on_body_entered(body: Node) -> void:
	# First contact hits immediately; a re-entry while a hit cooldown is still
	# running (a knockback pop lifting the victim out and dropping them back
	# in) keeps its remaining pacing — that is not fresh contact.
	if not _cooldowns.has(body.get_instance_id()):
		_cooldowns[body.get_instance_id()] = 0.0

func _on_body_exited(body: Node) -> void:
	# Keep an unexpired cooldown so the pop-and-return case above stays paced;
	# drop the entry once it has decayed so the table never accumulates.
	if float(_cooldowns.get(body.get_instance_id(), 0.0)) <= 0.0:
		_cooldowns.erase(body.get_instance_id())

func _physics_process(delta: float) -> void:
	if _cooldowns.is_empty():
		return
	for id in _cooldowns.keys():
		_cooldowns[id] = maxf(float(_cooldowns[id]) - delta, 0.0)
	for body in get_overlapping_bodies():
		var id: int = body.get_instance_id()
		if float(_cooldowns.get(id, 0.0)) > 0.0:
			continue
		var health: Node = _health_of(body)
		if health == null:
			continue
		_cooldowns[id] = damage_interval
		# No attacker: environment damage must not overwrite the enemy who
		# knocked the victim in (the hazard used to take — and score — the kill).
		if instant_kill:
			health.take_damage(health.max_health, null)
		else:
			health.take_damage(damage, null)
		if body is RigidBody2D and not knockback_impulse.is_zero_approx():
			body.apply_central_impulse(knockback_impulse)

## Health duck-typed: actors keep it at Components/Health. Bodies without it
## (weapons, probe dummies) simply are not damageable.
func _health_of(body: Node) -> Node:
	var h: Node = body.get_node_or_null("Components/Health")
	if h == null:
		h = body.get_node_or_null("Health")
	return h

## World rect the nav graph should treat as hazardous. Rectangle shapes only
## (same contract as NavBaker's KillZone/bounds readers); anything else is
## nav-invisible and returns an empty rect.
func get_nav_rect() -> Rect2:
	var cs := _shape_node()
	if cs == null or not (cs.shape is RectangleShape2D):
		return Rect2()
	return NavBakerScript.shape_world_rect(cs)

## Named "CollisionShape2D" first (scene-built hazards); any shape child
## second, so code-built hazards work without naming discipline.
func _shape_node() -> CollisionShape2D:
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null:
		return cs
	for c in get_children():
		if c is CollisionShape2D:
			return c
	return null

## Self-register into a graph that was already baked and cached on an ancestor
## scene node. If no graph is cached yet, do nothing — the next bake's group
## scan picks this area up instead.
func _register_nav() -> void:
	var graph = _cached_graph()
	if graph == null:
		return
	var rect: Rect2 = get_nav_rect()
	if not rect.has_area():
		return
	_registered_rect = rect
	_registered_graph = graph
	graph.add_hazard_rect(rect, nav_cost_multiplier)

func _cached_graph():
	var n: Node = self
	while n != null:
		if n.has_meta("nav_graph"):
			var g = n.get_meta("nav_graph")
			if g != null:
				return g
		n = n.get_parent()
	return null