extends SceneTree

## Headless probe for the dropped-weapon pickup cooldown + nearby auto-pickup.
## Verifies:
##   1. a fresh (never dropped) weapon inside the PickupArea IS picked up
##   2. right after drop_weapon(), the weapon is NOT pickable and a forced
##      pickup attempt does NOT re-equip it
##   3. the pick_up() guard itself also refuses the fresh drop
##   4. once the delay has passed (stamp in the past), pickup works again
##   5. drop with a DIFFERENT weapon already overlapping the area equips that
##      weapon immediately (the dropped one stays on the ground)
##   6. drop_weapon(false) — the death path — does NOT auto-pick anything
##
## NOTE: deliberately no typed references to game classes (WeaponHolder etc.)
## here — in `-s` script mode autoload identifiers are not registered while the
## probe script itself compiles, and a typed cast would drag those scripts into
## an early compile that fails with "Identifier not found: <autoload>".

var _fails: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var actor: Node = (load("res://Scenes/actor.tscn") as PackedScene).instantiate()
	var sword: Node = (load("res://Scenes/Weapons/Sword.tscn") as PackedScene).instantiate()
	root.add_child(actor)
	root.add_child(sword)
	await process_frame
	await process_frame

	var holder: Node = actor.get_node("WeaponHolder")

	# 1. Fresh weapon: picked up normally.
	holder._on_pickup_body_entered(sword)
	_check(holder.current_weapon == sword, "fresh weapon should be picked up")

	# 2. Drop it -> cooldown active, forced re-entry must not re-equip.
	holder.drop_weapon()
	await process_frame
	await process_frame
	_check(sword.is_held() == false, "weapon should be on the ground after drop")
	_check(sword.can_be_picked_up() == false, "fresh drop should NOT be pickable")
	holder._on_pickup_body_entered(sword)
	_check(holder.current_weapon == null, "forced pickup of fresh drop must NOT re-equip")

	# 3. The authoritative pick_up() guard refuses too (bypasses WeaponHolder).
	sword.pick_up(actor, actor.get_node("WeaponSocket"))
	_check(sword.is_held() == false, "pick_up() guard must refuse fresh drop")

	# 4. Delay passed -> pickup works again.
	sword._pickup_allowed_at_msec = 0
	_check(sword.can_be_picked_up() == true, "weapon should be pickable after delay")
	holder._on_pickup_body_entered(sword)
	_check(holder.current_weapon == sword, "weapon should be re-pickable after delay")

	# 5. Drop with a different weapon already overlapping the area:
	#    the nearby weapon is equipped immediately, the dropped one is not.
	var sword_b: Node = (load("res://Scenes/Weapons/Sword.tscn") as PackedScene).instantiate()
	root.add_child(sword_b)
	sword_b.global_position = actor.global_position
	# Keep the weapon glued to the falling actor across the physics steps below.
	sword_b.linear_velocity = actor.linear_velocity
	# Let the physics server step so the PickupArea actually registers the overlap.
	await physics_frame
	await physics_frame
	# The armed actor ignored sword_b's body_entered (stale overlap) — confirm
	# no pickup happened while armed.
	_check(holder.current_weapon == sword, "armed actor must not pick up while holding")
	holder.drop_weapon()
	_check(holder.current_weapon == sword_b, "nearby weapon should be equipped immediately on drop")
	_check(sword.is_held() == false, "dropped weapon must stay on the ground")
	_check(sword.can_be_picked_up() == false, "dropped weapon must still be on cooldown")

	# 6. Death path: drop_weapon(false) leaves the actor empty-handed even
	#    though a pickable weapon may be overlapping (sword's cooldown is reset
	#    here so it IS a valid pickup candidate).
	sword._pickup_allowed_at_msec = 0
	holder.drop_weapon(false)
	_check(holder.current_weapon == null, "death drop must not auto-pick a nearby weapon")
	_check(sword_b.is_held() == false, "dropped weapon_b must stay on the ground")

	var verdict := "ALL PASS"
	if _fails > 0:
		verdict = "%d FAILURES" % _fails
	print(verdict)
	quit(1 if _fails > 0 else 0)

func _check(ok: bool, what: String) -> void:
	var verdict := "FAIL"
	if ok:
		verdict = "PASS"
	print("%s: %s" % [verdict, what])
	if not ok:
		_fails += 1