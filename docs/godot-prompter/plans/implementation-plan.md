# Implementation Plan — Phase 2 revision (Combat feel + hands)

## Current State

Phase 2 base is implemented:

- `Scenes/actor.tscn`: `RigidBody2D` actor with capsule collision, `RayCast2D`, `VisualBody`, `WeaponSocket`, `PickupArea`, `WeaponHolder`, `Health`, `TeamMember`.
- `Scenes/arena.tscn`: arena with static camera, sword on ground, two dummies, spawn points.
- `Scripts/Weapons/Weapon.gd` + `Sword.gd`: pickupable `RigidBody2D` weapon attached via `PinJoint2D`, deals damage on collision.
- `Scripts/Actor-Movement.gd`: run/jump/friction.

Issue: the sword flops too much and trails behind the actor. We want it to lead forward, flip with the actor, and have a visible hand attached to its handle.

## Phase 2 revision goal

Make the held sword feel like it's actively carried in front of the actor, flipping with facing direction through physical forces. Add actor hands that attach to a `HandSocket` on the weapon when armed and hide/disconnect when unarmed.

## Proposed changes

### 1. Sword: add `HandSocket` and reduce floppiness
In `Scenes/Weapons/Sword.tscn`:
- Add `HandSocket` (`Marker2D`) near the base of the handle. Position is a default; designer can tweak in editor later.
- Tighten physics: raise `angular_damp`, lower `inertia`, and/or switch to `DampedSpringJoint2D` with a rest angle that points the blade forward.
- In `Weapon.gd` (or `Sword.gd`), in `_integrate_forces` apply a small steering torque that rotates the blade toward the holder's facing direction. Use `lerp_angle` toward the target rotation, scaled by a `steering_torque` export.

### 2. Weapon attachment: replace `PinJoint2D` with `DampedSpringJoint2D`
In `Weapon.pick_up()`:
- Create a `DampedSpringJoint2D` between holder's `WeaponSocket` and the weapon.
- Set rest length short, stiffness high, damping moderate so the weapon is held firmly but can still swing.
- Set a target/rest angle that points the blade forward (e.g., 90° relative to actor right).

### 3. Flip weapon with actor facing
- `WeaponHolder` reads the actor's facing direction from `Actor-Movement` or from `VisualBody/Sprite2D.flip_h`.
- When facing changes, update the joint's target/rest angle over time rather than instantly, so the sword rotates physically.
- Alternatively, apply a steering torque in `_integrate_forces` toward the current facing angle.

### 4. Actor hand
In `Scenes/actor.tscn`:
- Add `HeldHand` (`Sprite2D`) using `Assets/PNG/Default/character_handGreen.png`.
- `HeldHand` is hidden by default.
- `WeaponHolder` manages it: when a weapon is picked up, show the hand and each frame set its `global_position` to the sword's `HandSocket.global_position` and its `global_rotation` to the sword's `HandSocket.global_rotation`.
- When the weapon is dropped or the actor dies, hide the hand.

### 5. `WeaponHolder` updates
- Add `@onready var _held_hand: Sprite2D = $HeldHand`.
- In `_on_pickup_body_entered`, after `pick_up`, show hand.
- In `drop_weapon`, hide hand.
- In `_process` or `_physics_process`, if holding a weapon, sync hand transform to weapon's `HandSocket`.

### 6. `Actor-Movement` facing export
- Add `var facing_direction: float = 1.0` (1 = right, -1 = left) updated in `_process` when velocity crosses the threshold.
- Expose it so `WeaponHolder` can read it without reaching into the sprite.

## Verification

After revision:
1. Walking into the sword picks it up.
2. The sword stays in front of the actor while moving, flipping gradually when the actor turns.
3. The sword still deals damage and knockback on collision.
4. A hand sprite appears at the sword handle and moves/wobbles with the sword.
5. Dropping the weapon (or dying) hides the hand and drops the sword.
