# Swap-War — Full Project Audit Report

**Scope:** Every `.gd` script, every `.tscn` scene, `project.godot`, docs, and git state.
**Method:** Independent line-by-line review cross-referenced against Godot headless import (clean parse, 2 UID warnings, memory-leak warning at exit) plus an adversarial multi-agent verification pass.
**Status:** Report only — no files were modified by the audit.

---

## 🔴 Critical — game-breaking bugs

**1. Damage numbers always display "50" — never the real value**
`Scripts/Components/Health.gd:61-68` calls `label.start(...)` *before* `effects.add_child(label)`. `FloatingNumber.start()` early-returns because its `@onready _label` is still `null` (node not in tree), and `_ready()` never sets the text afterward. Every floating damage number renders the scene default `"50"` (`Scenes/UI/FloatingNumber.tscn:17`) regardless of actual damage.
*Fix: set the text in `_ready()`, or `add_child` first then `start()`, or make `start()` store the value and have `_ready()` apply it.*

**2. KillZone never removes fallen weapons → weapon spawning permanently stalls**
`Scenes/arena.tscn:249` sets KillZone `collision_mask = 6` (layers 2 Actors + 3 OneWay). All weapon scenes set `collision_layer = 8` (layer 4, "Weapons" — `Sword.tscn:15`, `Pistol.tscn:15`, etc.). `6 & 8 == 0`, so `body_entered` never fires for weapons and the explicit weapons branch in `KillZone.gd:22-27` is **unreachable**. Fallen weapons keep simulating forever; `_active_weapon_count` never decrements, so once `MAX_ACTIVE_WEAPONS` (10) is hit, no more weapons spawn for the rest of the match.
*Fix: mask should be `10` (2 | 8 = Actors + Weapons). The layer-3 bit is pointless here — tiles aren't physics bodies.*

**3. Timed matches end instantly after "Play Again"**
`ArenaManager._match_timer` is only ever assigned in `_load_match_config()` (line 63), which runs once on scene entry. `_start_match()` (lines 71-83) resets the countdown, win reason and scores but **not** `_match_timer`. In TIMED_SCORE mode, the first match drains it to ≤ 0; after restart, `_process()` immediately sees `_match_timer <= 0` and calls `_end_match_by_time()`. Every subsequent timed match ends the moment it starts.

**4. TIMED_SCORE matches can never draw**
`ScoreManager.get_leader()` (lines 50-58) initializes `best_score = -1`, so the first registered actor (score 0) satisfies `0 > -1` and is crowned leader. As long as any actor is registered it never returns `null`, so a 0-0 match always crowns an arbitrary actor and the "DRAW!" path in `HUD.show_winner` / `PostRoundMenu` is unreachable.
*Fix: start at `best_score = 0` (or use strict-greater + explicit tie check).*

---

## 🟠 High — significant bugs

**5. ~~Ranged weapons render upside-down when facing left~~ — FIXED / NOT A BUG**
The author confirmed the current render is correct in-game. The `scale = Vector2(1.0, _target_facing)` in `WeaponBase._update_follow_transform()` is the intended flip for the authored ranged sprites; no change needed.

**6. Doubled attack sound for ranged weapons**
`Actor-Movement._update_attack()` plays `play_attack()` after every `weapon.attack()` (lines 237-239), *and* `RangedWeapon._spawn_projectile_deferred()` plays it again one frame later (`RangedWeapon.gd:66-67`). Pistol/Rifle fire produce two overlapping voices. (Melee additionally plays the sound even when the attack is on cooldown — the call is unconditional.) The full-game-plan doc already flags this duplicate (`swap-war-full-game-plan.md:318`).

**7. Landing sound never plays**
`Actor-Movement._apply_jump()` (lines 209-223) captures `was_grounded := _is_grounded` **after** `_update_ground_state(state)` already ran earlier in `_integrate_forces`. The branch `elif not was_grounded and _is_grounded: AudioManager.play_land()` is therefore always false.

**8. Death/respawn: corpse resurrection + potential freed-object access**
`Health.die()` emits `died` (which synchronously ends the round) then `await create_timer(1.5)` and calls `_respawn()` with no validity guards. (a) A killed actor visibly resurrects during the POST_ROUND screen (`_respawn` sets `visible=true`); (b) if "Play Again" lands inside that 1.5 s window, `_despawn_actors()` queue-frees the actor and the resumed `_respawn()` dereferences freed nodes (`_actor.global_position`, `_actor.set_deferred(...)`).

**9. Corpse can grab a weapon while dead**
`Health.die()` disables the RigidBody2D (`process_mode`, visibility, deferred mask=0) but **not** the child `PickupArea` (Area2D, layer 16 / mask 8). Area2D `body_entered` is driven by the physics server and is not gated by `process_mode`, so during the 1.5 s death window a corpse still absorbs any overlapping weapon — and `_respawn()` doesn't drop it.

**10. "Freeze actors" at round end doesn't actually freeze them**
`ArenaManager._show_post_round()` (line 232) sets `process_mode = DISABLED`, which for a RigidBody2D only stops script callbacks — the physics server still integrates gravity/motion (and `can_sleep=false`). Actors keep drifting/falling after the round. Should be `freeze = true` (or force sleep).

---

## 🟡 Medium

**11. RefCounted reference-cycle leak in the AI state machine**
`StateMachine.register()` sets `state.machine = self` (strong ref, `State.gd:8`), forming a `dict → State → machine → StateMachine` cycle. GDScript has no cycle collector, so ~6 RefCounted objects leak per AI actor per despawn/restart.

**12. Spawn-point overflow — actors spawn stacked**
`arena.tscn` has only 2 spawn markers (`SpawnLeft`/`SpawnRight`); `_spawn_actors()` spawns 1 player + `ai_count` AIs (default 3) = 4 actors. `_pick_unique_index()` returns -1 once indices are exhausted, and the fallback `randi() % size` reuses an index, so multiple actors overlap (harmless only because actors don't collide — mask excludes layer 2).

**13. Team count forced to 3**
`ArenaManager._start_match()` (line 79) hardcodes `TeamManager.team_count = 3`, ignoring TeamManager's `@export var team_count`. Any designer change is silently reverted at match start; there's no settings path to configure it.

**14. Health bar color never updates on team swap**
`Health._ready()` colors `HealthBar2D` once via `_team_color()`. Team swaps (every `swap_interval`) update body/hand textures and the HUD but not the floating health bar — it keeps the pre-swap team color.

**15. AI RetreatState stuck when enemy is at the same X**
`away = -sign(dx)` is `0.0` when `dx == 0.0` (`RetreatState.gd:16,22`), so the actor applies no force and the exit condition `abs(dx) > retreat_safe_distance` can never become true. Also propagates `facing_direction == 0` into a zero aim vector.

**16. AI divide-by-zero / null health risk**
`AttackState.gd:44`, `ApproachEnemyState.gd:29`, `RetreatState.gd:32` all compute `current_health / max_health` with no null check. `AIController._cache_components()` treats `health` as optional (`get_node_or_null`), so any actor scene lacking `Components/Health` crashes the AI — and `max_health == 0` divides by zero. Latent with the current scene, but a real robustness gap.

**17. PauseMenu's post-round guard is permanently null**
`PauseMenu._ready()` looks up sibling `PostRoundMenu`, but `ArenaManager._setup_menus()` adds PauseMenu first via `call_deferred`, so `PostRoundMenu` isn't a sibling yet → `_post_round_menu` stays null forever and the `_input` guard is dead. Masked today by a redundant check in `_toggle_pause()`, but fragile.

**18. AI-count slider can show "0" while the match spawns 1**
`MainMenu.tscn:105-110` sets only `max_value = 3.0` (default min 0); the label can display "AI Count: 0", but `SettingsManager.set_match_options()` clamps to `clampi(new_ai_count, 1, 3)` → visible mismatch between UI and actual match.

---

## 🟢 Low / gotchas

- **Input map vs. help text drift** — `Attack` is bound to *mouse-left only* (no J / Right Ctrl), `Move_Left/Right` to *A/D only* (no arrow keys), yet `MainMenu.tscn` help text and `CLAUDE.md` claim otherwise. Mouse-aim may be intentional, but the docs mislead.
- **Duplicated / hand-written UIDs** — `HUD.tscn:3` and `TouchControls.tscn:3` share bogus `uid://ct5q6v7gq3w7m` for two *different* scripts (their real `.uid` sidecars are `uid://d1d8qwqwhwb8s` / `uid://ctrg6l82xt3to`). `Sword.tscn` (`uid://cy8rjm7jcdeq6`) and `Spear.tscn` (`uid://cy8rjm7jcdeq7`) differ by one digit — hand-edited. Currently masked by path fallback; will bite when the UID cache rebuilds.
- **`const WeaponBase = preload(...)` shadows the global `class_name`** (`Actor-Movement.gd:3`) — redundant and fragile for the `var weapon: WeaponBase` annotations.
- **AI redundant per-tick physics queries** — `Sensors._update_ground_state()` re-queries `body_get_direct_state` every tick (one-frame stale) when `Actor-Movement.is_grounded()` already exists.
- **`get_nodes_in_group("actors")` double-counts** — `Health._ready()` also adds the Health node to `"actors"`, so AI target scans iterate 2× entries (currently safe only via the `as Node2D` null-cast).
- **`Sensors` ranged-preference tie-break is inert** — `is_equal_approx(d, best_dist)` essentially never matches; the "prefer ranged at equal distance" behavior doesn't happen.
- **AI coupling to `health._is_dead`** (`Sensors.gd:112`) — depends on a private field name; a rename silently breaks target filtering.
- **`_update_attack` runs in `_integrate_forces`** — `Input.is_action_just_pressed` is frame-counter based and can be missed or duplicated when the body-state callback runs more than once per rendered frame; gameplay side-effects belong in `_physics_process`.
- **`project.godot` naming/drift** — `layer_3` is named `"OneWay"` while `CLAUDE.md` calls it "Reserved/future"; actor `collision_mask = 13` ≠ the documented "1 + 2 + 4". Stale docs will mislead future collision/input work.

---

## 🗑️ Dead code (safe to delete)

| File | Why it's dead |
|---|---|
| `Scripts/Weapons/Weapon.gd` (`class_name Weapon`) | Full parallel implementation of the old weapon system; referenced by nothing but itself + stale docs. Superseded by `WeaponBase`/`MeleeWeapon`/`RangedWeapon`. The plan doc explicitly says to delete it. |
| `Scripts/Weapons/Chest.gd` + `Scenes/Weapons/Chest.tscn` | Never instantiated anywhere; also references non-existent autoload `/root/WeaponSpawner`. |
| `Scripts/CameraFollow.gd` | Zero references; camera is static in `arena.tscn`. |
| `Scripts/UI/CustomSlider.gd` + `Scenes/UI/CustomSlider.tscn` | MainMenu uses built-in `HSlider`; the custom slider is also mouse-only (won't work on touch). |
| `RangedWeapon._get_facing_scale()` | Correct fix for the flip bug that's never called. |
| `MeleeWeapon._on_body_entered` `"flash_damage" in body` branch | No `flash_damage` method exists anywhere. |
| `Actor-Movement.gd` `@onready var visual_body` | Never referenced; `_update_visuals` uses `$VisualBody/Sprite2D` directly. |
| `AIController._process → machine.update()` | None of the 5 states override `update()`; per-frame no-op. |
| `State.get_name()` | Never called. |
| `Pathfinder.update()` | Empty stub. |
| `Pathfinder._sequence` + `_release_sequence()` | Member assigned/cleared but never read. |
| `ArenaManager._on_play_again` / `_on_quit_to_menu` | Never connected to any signal; the menu buttons wire their own handlers. |

---

## 🧹 Hygiene / config

- **4 zero-byte junk files** at the repo root — `Display`, `Project`, `Window`, and one whose name contains private-use Unicode chars (git-shows as `**Related`, i.e. `U+F02A`) — untracked, not gitignored, and unreferenced. Accidental shell-redirection artifacts; delete them.
- **`.gitignore` is too loose** — only ignores `.godot/` and `/android/`; those junk files (and similar future accidents) aren't covered.
- **Memory leak at exit** — headless run reported `32 ObjectDB instances` + `7 resources` leaked on arena exit (consistent with the RefCounted-cycle finding above; run with `--verbose` for a full breakdown).

---

## Suggested priority order

1. Fix **KillZone mask** (#2) — it silently degrades a whole match.
2. Fix **`_match_timer` reset** (#3) and **`get_leader()`** (#4) — both break TIMED_SCORE mode outright.
3. Fix **damage-number text** (#1) — every hit shows wrong info.
4. Then **ranged flip** (#5), **double sound** (#6), **landing sound** (#7), **respawn guards** (#8), **corpse pickup** (#9), **freeze mechanism** (#10).
5. Delete the **dead code** list in a single cleanup commit.
6. Tidy **UIDs, input-map docs, `.gitignore`, and root junk files**.
