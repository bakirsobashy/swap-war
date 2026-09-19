extends "res://Scripts/AI/State.gd"

## The exchange state. Core fix (audit bug: attack-once freeze): while in
## range, wants_attack is HELD true every tick — the weapons self-throttle
## their own cooldowns, so a held intent IS the correct pacing. Ranged fire
## additionally gates on LOS and the aim actually pointing at the enemy (the
## sensor's per-refresh scatter roll shows up here — a bad roll holds fire
## until the next re-roll). Melee keeps contact spacing; ranged kites back
## while firing when the enemy closes inside half the stand-off.

const MIN_TIME := 0.25           # hysteresis before chasing again (range flip-flop)
const AIM_DOT_GATE := 0.96       # ~16 degrees — ranged fire only roughly on target
const KITE_RATIO := 0.5          # inside this fraction of the stand-off: back off
const MELEE_CROWD_RATIO := 0.3   # inside this fraction of reach: stop body-pushing


var _state_timer := 0.0


func get_name() -> String:
	return "Attack"


func enter() -> void:
	# Attack owns direct control — drop any running nav goal first.
	owner.nav_cancel()
	owner.move_direction = 0.0
	owner.wants_jump = false
	owner.wants_drop = false
	owner.wants_attack = false
	_state_timer = MIN_TIME


func physics_update(delta: float) -> String:
	_state_timer -= delta

	# Recover a weapon before continuing to fight (it may have broken mid-swing).
	var unarmed_transition := _transition_if_unarmed()
	if unarmed_transition:
		return unarmed_transition

	var enemy: Node2D = owner.sensors.nearest_enemy
	if not enemy or not owner.sensors.is_valid_target(enemy):
		return "Idle"

	var dist: float = owner.actor.global_position.distance_to(enemy.global_position)

	# Low health and enemy close: disengage.
	if owner.health_ratio() <= owner.retreat_health_ratio \
			and dist <= owner.retreat_range:
		return "Retreat"

	# Out of reach again: resume the chase (after the hysteresis window, so
	# the two states don't flip-flop on the range boundary every tick).
	if dist > owner.attack_reach():
		if _state_timer <= 0.0:
			return "ApproachEnemy"
		return ""

	if not owner.ai_attack_enabled:
		return ""

	var weapon = owner.weapon_holder.current_weapon
	if weapon != null and is_instance_valid(weapon) and weapon.is_ranged():
		_ranged_exchange(enemy, dist)
	else:
		_melee_exchange(enemy, dist)
	return ""


## Ranged duel: fire only with clear LOS and the aim on target; kite back
## when the enemy crowds inside half the stand-off distance.
func _ranged_exchange(enemy: Node2D, dist: float) -> void:
	if owner.sensors.has_los_to_enemy:
		var to_enemy: Vector2 = (enemy.global_position
				- owner.actor.global_position).normalized()
		if owner.aim_direction.dot(to_enemy) > AIM_DOT_GATE:
			owner.wants_attack = true
	if dist < owner.combat_standoff() * KITE_RATIO:
		_kite_away(enemy)


## Melee exchange: swing every tick in range (the weapon paces itself) and
## keep a hair of spacing so we don't body-push through the target.
func _melee_exchange(enemy: Node2D, dist: float) -> void:
	owner.wants_attack = true
	if dist < owner.attack_reach() * MELEE_CROWD_RATIO:
		_kite_away(enemy)


func _kite_away(enemy: Node2D) -> void:
	var away: float = signf(owner.actor.global_position.x - enemy.global_position.x)
	if away == 0.0:
		away = -signf(owner.actor.facing_direction)
	owner.move_direction = away


## Unarmed mid-exchange (weapon broke): the hub rules apply — a known weapon
## wins, a close enemy means evade, otherwise back to the hub for Patrol.
## This is also the broken-weapon fix (audit bug #4): is_armed() flips false
## the tick after _break_weapon() and we go re-arm instead of shadowboxing.
func _transition_if_unarmed() -> String:
	if owner.is_armed():
		return ""
	if owner.sensors.best_weapon != null:
		return "SeekWeapon"
	var enemy: Node2D = owner.sensors.nearest_enemy
	if enemy and owner.sensors.is_valid_target(enemy) \
			and owner.actor.global_position.distance_to(enemy.global_position) <= owner.retreat_range:
		return "Retreat"
	return "Idle"