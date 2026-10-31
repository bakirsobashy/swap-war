class_name KillZone
extends Area2D

## Instantly kills any actor body that enters this area (the death plane).

@export var enabled: bool = true

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if not enabled:
		return

	# Actors: run the normal death/respawn sequence (off-map: no stain, an
	# edge splash instead).
	if body.is_in_group("actors"):
		var health := body.get_node_or_null("Components/Health") as Health
		if health:
			health.die(true)
		return

	# Weapons that fall off the map are removed from play.
	if body.is_in_group("weapons"):
		var weapon := body as WeaponBase
		if weapon and not weapon.is_queued_for_deletion():
			weapon.remove_from_world()
		return
