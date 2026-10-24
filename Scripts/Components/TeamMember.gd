class_name TeamMember
extends Node

@export var team_id: int = 0:
	set(value):
		var changed := team_id != value
		team_id = value
		_update_visuals()
		if changed:
			_flash_team_change()

static func is_same_team(a: Node, b: Node) -> bool:
	var a_team := a.get_node_or_null("Components/TeamMember") as TeamMember
	var b_team := b.get_node_or_null("Components/TeamMember") as TeamMember
	if not a_team or not b_team:
		return false
	return a_team.team_id == b_team.team_id

func _ready() -> void:
	_update_visuals()
	call_deferred("_register_with_manager")

func _register_with_manager() -> void:
	var actor := get_parent().get_parent()
	if actor and TeamManager:
		TeamManager.register_actor(actor)
		TeamManager.set_team(actor, team_id)

func _flash_team_change() -> void:
	var actor := get_parent().get_parent() as Node2D
	if not actor:
		return
	var body := actor.get_node_or_null("VisualBody/Sprite2D") as Sprite2D
	if not body:
		return
	var original_mod := body.modulate
	body.modulate = Color.WHITE
	var tree := get_tree()
	if tree:
		# Weak capture: a swap can fire just before the actor is freed (match
		# end), and a strong capture of a freed sprite prints the engine's
		# "Lambda capture ... was freed" warning. The WeakRef never dies, so
		# the timer body just no-ops instead.
		var body_ref: WeakRef = weakref(body)
		tree.create_timer(0.15).timeout.connect(func() -> void:
			var sprite := body_ref.get_ref() as Sprite2D
			if sprite:
				sprite.modulate = original_mod
		)

func _update_visuals() -> void:
	var actor := get_parent().get_parent() as Node2D
	if not actor:
		return

	var body_sprite := actor.get_node_or_null("VisualBody/Sprite2D") as Sprite2D
	var hand_sprite := actor.get_node_or_null("HeldHand") as Sprite2D

	var body_tex := _team_body_texture(team_id)
	var hand_tex := _team_hand_texture(team_id)

	if body_sprite and body_tex:
		body_sprite.texture = body_tex
	if hand_sprite and hand_tex:
		hand_sprite.texture = hand_tex

	var health := actor.get_node_or_null("Components/Health")
	if health and health.has_method("refresh_bar_color"):
		health.refresh_bar_color()

func _team_body_texture(team: int) -> Texture2D:
	match team:
		0:
			return preload("res://Assets/PNG/Default/character_roundGreen.png")
		1:
			return preload("res://Assets/PNG/Default/character_roundRed.png")
		2:
			return preload("res://Assets/PNG/Default/character_roundPurple.png")
		3:
			return preload("res://Assets/PNG/Default/character_roundYellow.png")
		_:
			return preload("res://Assets/PNG/Default/character_roundGreen.png")

func _team_hand_texture(team: int) -> Texture2D:
	match team:
		0:
			return preload("res://Assets/PNG/Default/character_handGreen.png")
		1:
			return preload("res://Assets/PNG/Default/character_handRed.png")
		2:
			return preload("res://Assets/PNG/Default/character_handPurple.png")
		3:
			return preload("res://Assets/PNG/Default/character_handYellow.png")
		_:
			return preload("res://Assets/PNG/Default/character_handGreen.png")
