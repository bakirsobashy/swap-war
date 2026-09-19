extends "res://Scripts/AI/State.gd"


func get_name() -> String:
	return "Idle"


## Decision hub: pick the next state by priority. Runs every physics tick
## while active, so every condition is re-evaluated against fresh sensors.
##
## Priority (locked decisions #6 and #11):
##   1. unarmed + weapon known      -> SeekWeapon (a weapon beats fighting
##                                      bare-handed — the unarmed AI never
##                                      fights: evade + seek only)
##   2. unarmed + enemy within
##      retreat_range              -> Retreat (a TACTICAL trigger, not a
##                                      sight limit — distance gates the
##                                      choice of response, never knowledge)
##   3. armed + valid enemy         -> ApproachEnemy (ANY distance: an enemy
##                                      across the map is engaged at once)
##   4. otherwise                   -> Patrol (wander with purpose)
func physics_update(_delta: float) -> String:
	owner.move_direction = 0.0
	owner.wants_jump = false
	owner.wants_drop = false
	owner.wants_attack = false

	var enemy: Node2D = owner.sensors.nearest_enemy
	var enemy_valid: bool = owner.sensors.is_valid_target(enemy)

	if not owner.is_armed():
		if owner.sensors.best_weapon != null:
			return "SeekWeapon"
		if enemy_valid and _dist_to(enemy) <= owner.retreat_range:
			return "Retreat"
		return "Patrol"

	if enemy_valid:
		return "ApproachEnemy"

	return "Patrol"


func _dist_to(other: Node2D) -> float:
	return owner.actor.global_position.distance_to(other.global_position)