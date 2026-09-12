class_name KillZone
extends Area2D

## Instantly kills any actor body that enters this area (the death plane).

@export var enabled: bool = true

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if not enabled:
		return
	if not body.is_in_group("actors"):
		return

	var health := body.get_node_or_null("Components/Health") as Health
	if not health:
		return

	# Let Health handle the death sequence (particles, respawn, score attribution).
	health.die()
