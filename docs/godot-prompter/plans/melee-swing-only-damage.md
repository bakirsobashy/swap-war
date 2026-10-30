# Plan: melee damages only on the swing (passive contact damage removed)

**Status:** implemented 2026-10-30 (see "Implementation notes" at the end). **Date:** 2026-10-30. Closes design flaw 6 in `AUDIT_REPORT_2026-10.md` ("Holding a sword damages anyone you walk into").

## Decision

**Remove passive contact damage.** A held melee weapon deals damage only during its swing window (`_is_attacking`), at most once per victim per swing. A blade resting on an enemy, or an enemy walking into it, does nothing.

**Physical collision stays.** Held blades still physically block and shove actors (Vision Lock: "physics-weapon collisions kept"). Only the damage changes.

Ranged weapons and projectiles don't change. Guns have no contact damage today.

---

## What passive damage does today

There are two damage paths. Both are live whenever the weapon is held, and neither checks `_is_attacking`:

- **RigidBody contact.** `WeaponBase._ready` connects the weapon's own `body_entered` (contact monitor, `HELD_MASK` includes actors) to `_on_body_entered`. `MeleeWeapon` overrides that hook to deal damage.
- **HitBox Area2D.** `Sword`, `Spear` and `Fork` each connect `HitBox.body_entered` to the same `_on_body_entered` in their `_ready`.

The only pacing is the per-victim cooldown (`_recent_hits`, equal to `attack_cooldown`). As a result:

1. **The attack button mostly adds reach** (audit flaw 6). Aiming the blade at an enemy, or walking into one, is a full hit: damage, crit roll, knockback, and −1 durability.
2. **Treadmill.** Each hit knocks the victim off the blade (320–400 knockback plus the 0.3 s stun). Walking back in is a new contact, so it's another hit as soon as the cooldown allows. `decision_probe` freezes its dummies because of this ("drifts east forever under the held sword's contact knockback").
3. **Damage nobody decided to deal.** During the 0.35 s swap reaction window, `AIController` silences every input, and the hazard-escape override silences `wants_attack`. The blade keeps hitting anyway. The player gets no telegraph: you can be hit by an enemy that never swung.
4. **Durability drains from bumps.** Durability is meant to count attacks that landed.
5. **Swings that should land get refused.** `_recent_hits` measures wall-clock ms (`Time.get_ticks_msec()`), but the swing cooldown counts physics ticks. A held attack (the AI, Auto Attack) swings again after exactly `attack_cooldown` of game time. ms rounding, or a frame hitch that runs several physics ticks back to back, can make that gap read as slightly *under* the cooldown. The gate then refuses a swing at a body still on the blade.

## Options considered

| Option | Verdict |
|---|---|
| A. Keep passive damage (status quo) | **No.** Leaves all five problems above. |
| **B. Swing-only damage** | **Chosen.** The attack input becomes the only source of melee damage, and the swing animation is the telegraph. The AI already swings whenever it's in reach, so its damage output barely changes. Fixes 1–5. |
| C. Chip damage on contact (e.g. 25 %, no knockback) | **No.** Two damage rules to learn. Keeps 3 and 4 (damage nobody chose, durability bleed) and needs its own pacing gate. |
| D. B, plus held blades stop colliding with actors | **Not now.** Breaks the vision lock. Actors never collide with each other, so the held blade is the only thing that stops an armed actor walking straight through an enemy. If the shove without damage feels odd in play, decide this separately. |

## Who is affected

- **Mouse/keyboard player:** has to click to deal melee damage. The **Auto Attack** setting (default off) still auto-swings within 90 px on PC and touch, so it covers the old "just walk into them" play.
- **Touch player:** ATTACK button or Auto Attack. No change to controls.
- **AI:** no code change expected. `AttackState` holds `wants_attack` while in reach, `ApproachEnemyState` swings when in reach on the move, and `RetreatState` cover-fire swings too. It only loses hits it never chose to make (swap window, hazard escape).
- **Thrown/dropped weapons:** no change; they deal no damage today. Once melee stops overriding the RigidBody `_on_body_entered` hook, the hook is free for the full-game plan's thrown-weapon damage (phase 4).

## Design

### `MeleeWeapon.gd`

- **One damage path: the HitBox.** Connect `HitBox.body_entered` once, in `MeleeWeapon._ready`. Delete the three identical connects from `Sword`/`Spear`/`Fork._ready` (Sword keeps its slash transform; Spear/Fork keep their thrust offset).
- **Stop overriding `_on_body_entered`.** The RigidBody contact hook falls back to `WeaponBase`'s no-op.
- **Replace `_recent_hits` with a per-swing set.** The swing cooldown already paces hits: every melee weapon's window is shorter than its cooldown (Sword 0.20 / 0.5 s, Spear 0.18 / 0.6 s, Fork 0.16 / 0.4 s).

```gdscript
var _hit_this_swing: Dictionary = {}   # victim -> true, cleared per swing

func attack() -> void:
	# ...existing guards, timers, sound...
	_hit_this_swing.clear()
	# Bodies already on the blade (audit #13): body_entered won't fire for them.
	var hit_box := get_node_or_null("HitBox") as Area2D
	if hit_box:
		for body in hit_box.get_overlapping_bodies():
			_try_hit(body)

func _on_hit_box_body_entered(body: Node) -> void:
	# Damage only during the swing window — a resting blade is harmless.
	if _is_attacking:
		_try_hit(body)

## One swing hits each victim at most once. Same body as today's
## _on_body_entered minus the wall-clock cooldown: team check, crit roll,
## take_damage() -> bool, knockback, hit sound, durability.
func _try_hit(body: Node) -> void:
	if not _holder or body == _holder or _hit_this_swing.has(body):
		return
	# ...health / same-team checks...
	_hit_this_swing[body] = true
	# ...crit, take_damage, knockback, sound, _lose_durability(1)...
```

Mark the victim before `take_damage()`, so a blocked hit (invulnerable target) is still that victim's one chance this swing. That matches today's behaviour.

### `WeaponBase.gd`

No value changes. Rewrite the `HELD_MASK` comment ("needed for melee contact damage"): the actor bit now only gives held weapons their physical push. Damage comes from the melee HitBox during a swing. Keep `contact_monitor` for the future thrown-damage hook.

### Docs

- `CLAUDE.md` → Architecture notes → **Combat**: replace "Held weapons deal damage on body contact … Each victim has a per-attacker cooldown" with "melee damages only during the swing (HitBox, once per victim per swing); held weapons still physically collide with actors".
- `AUDIT_REPORT_2026-10.md`: flaw 6 → ✅ fixed; §7 item 2.
- `decision_probe.gd` `_spawn_dummy` comment: the freeze is still needed, because swing knockback pushes. Reword the "contact knockback" reason.

## Testing

**New `Tools/melee_swing_probe.gd`.** Add it to `run_probes.ps1` and the CLAUDE.md probe list. Usual probe rig: stop the swap timer, freeze bodies, purge the `weapons` group between scenarios.

1. **Resting blade is harmless.** Enemy on the blade for 2 s, no swing: HP and durability unchanged. *(The core regression.)*
2. **Walking into the blade is harmless.** Teleport the enemy onto the blade from outside (a new contact): no damage.
3. **One swing, one hit.** Enemy on the blade for the whole window: exactly one hit (HP drops by `damage` or the crit value), durability −1.
4. **Held swings all land.** Back-to-back swings paced by the cooldown, like the AI: N swings give N hits. Guards against problem 5.
5. **Mid-window entry.** A Spear thrust reaches a body that's only in range while extended: hit.
6. **Teams.** An ally on the blade during a swing takes no damage. After a team swap makes them an enemy, the next swing hits.
7. **Multi-target.** Two enemies on the blade: one swing hits both.

**Existing probes:**

- `audit_regression_probe`, "hits on invulnerable targets cost nothing": it calls `sword._recent_hits.clear()` and `sword._on_body_entered(b1)`. After the change the first is a SCRIPT ERROR, and the second is a no-op, so the check would **pass vacuously**. Switch it to `sword._try_hit(b1)`. The #13 swing test runs unchanged.
- `decision_probe` S12 (melee at a ledge lip, "lands a hit") is the live check that AI swings connect without passive damage helping. It must stay green. S1 asserts reaching Attack, not damage.
- `auto_attack_probe` measures swings, not damage, so it's unaffected.

Then run `pwsh Tools/run_probes.ps1` and play a few matches by hand: melee should feel responsive, and the AI should still win a fair share of melee duels.

## Risks to watch

- **Clicks during the cooldown are dropped** (`is_action_just_pressed`). This matters more once the click is the only source of damage. Follow-up if it feels bad: a ~0.15 s attack input buffer. Not part of this change.
- **Weapons last longer**, because bumps no longer cost durability. Revisit durability numbers in the balance pass.
- **AI melee damage output** should barely change by the reading above. If duels feel off, compare kills per minute in AI-only matches before and after.
- **Reach.** The AI engages at `attack_range` 80 px and Auto Attack at 90 px. By the scene geometry, both are inside every blade's resting reach, so swings from those distances connect. Probe scenario 3 and decision_probe S12 confirm it live.

## Out of scope

Unarmed shove (design 3), thrown-weapon damage, crit/kill feedback (design 8), the input buffer, and removing the held-blade shove (option D).

## Files

- `Scripts/Weapons/MeleeWeapon.gd`: per-swing hits, single HitBox path, `_try_hit`
- `Scripts/Weapons/Sword.gd`, `Spear.gd`, `Fork.gd`: drop the duplicate HitBox connects
- `Scripts/Weapons/WeaponBase.gd`: `HELD_MASK` comment only
- `Tools/melee_swing_probe.gd` (new), `Tools/run_probes.ps1`
- `Tools/audit_regression_probe.gd`, `Tools/decision_probe.gd` (comment)
- `CLAUDE.md`, `docs/godot-prompter/plans/AUDIT_REPORT_2026-10.md`

## Implementation notes

Built as planned, with two additions:

- **Dropped mid-swing closes the window.** `MeleeWeapon._physics_process` returns early while unheld, so a weapon dropped mid-swing (the holder died) kept `_is_attacking = true` and the leftover window ran on for the next holder. Harmless when the window was only visual; now it gates damage, so an unheld melee weapon resets `_is_attacking` / `_attack_timer`.
- **The audit probe's invulnerable-target check can't pass vacuously.** It calls `_try_hit(b1)` and also asserts the victim was marked in `_hit_this_swing` — the mark is set just before `take_damage()`, so the check proves the strike got that far.

`melee_swing_probe` runs 8 scenarios: the 7 above plus "dropping mid-swing closes the window".

---

## Part 2: when a weapon attacks (decided and implemented 2026-10-30)

**Rule:** an automatic melee swing (the AI, Auto Attack) happens only when an enemy is in the weapon's hit range **and** the actor is looking at it. `MeleeWeapon.can_hit(target)` answers "would a swing launched now hit this body?":

- **Hit range** = the area the swing sweeps, from the weapon's own HitBox shape at rest, stretched forward by its thrust (Spear/Fork `_swing_thrust()`), in the WeaponSocket's frame. The target's capsule is tested against it (three circles along the spine). Nothing is hand-typed. `get_attack_range()` reports the same reach centre-to-centre: sword ~100 px, fork ~170, spear ~190 (old flat value: 80 for all).
- **Looking at it** = the holder faces the target's side (a ~4 px deadzone straight above/below) **and** the blade, which turns gradually after the aim, is where the test is measured from. Right after the aim swings round, can_hit stays false until the blade arrives, like the gun's muzzle gate.

Decisions:

| Question | Decision |
|---|---|
| Manual Attack click | Never gated: always swings. |
| Auto Attack aim help | None. The old lock turned your aim onto the nearest enemy, even one behind you. Now the player aims; Auto Attack only presses attack when `can_hit` is true for some hostile. The fixed 90 px circle is gone too. |
| AI reach | Real per-weapon reach: reach, stand-off (75 %) and the Attack hand-over scale with the weapon. Spear and fork AIs fight from much further away. |
| Ranged Auto Attack | Unchanged (touch-only, fires while the aim stick is held). AI guns already gate on lane + muzzle + range. |

AI wiring: `AIController.melee_swing_ready(enemy)` and `attack_ready(enemy)` (gun gate or blade gate). Used by AttackState's melee exchange, ApproachEnemy's swing-on-the-move and Retreat's cover fire. Because Attack is entered at the very edge of reach, where aim scatter or the blade's shape can still make the swing miss, a melee AI whose swing wouldn't land steps in toward the stand-off (safe_move; not when the enemy is straight above/below). Otherwise it would stand there and never swing.

Tests: `melee_swing_probe` scenario 7 (`can_hit`: just inside/past reach, facing away, blade still turning) and the spear checks in 8. `auto_attack_probe` A/B now aim with the stick and check that aiming away never swings and that the aim is left alone. `decision_probe` S1 waits up to 1 s for the first swing instead of sampling the tick after entering Attack.

Watch: `retreat_range` (120 px, unarmed AIs flee inside it) is now well inside a spear's 190 px reach. Retune if unarmed AIs get poked from outside it.
