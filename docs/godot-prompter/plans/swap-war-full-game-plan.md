# Swap-War — Full Game Development Plan

> From Brackeys Game Jam prototype to a polished single-player vs AI arena brawler for **web** and **mobile**.
> Version 1.0 — 2026-09-12

---

## Executive Summary

The current prototype has a working Godot 4.7 physics foundation: `RigidBody2D` actors move, jump, pick up physics weapons, take damage, respawn, and score kills. The central team-swap mechanic is wired. The prototype is **not yet a game** because menus, audio, round lifecycle, and several loop-breaking bugs are missing or broken.

This plan locks scope, fixes the critical bugs, builds the missing shell, and then expands content. The goal is a **self-contained single-player vs AI brawler** that can ship on web (itch.io) and mobile.

---

## Vision Lock

| Decision | Value |
|----------|-------|
| **Scope** | Single-player vs AI only. No progression for this release. |
| **Platforms** | Web (primary) and mobile (Android/iOS). |
| **Match size** | 1 human player + up to 3 AI actors. |
| **Combat system** | Physics-weapon collisions kept. Weapons are pickable, throwable, melee-swingable, and ranged-fireable. Attack button is retained. |
| **Win conditions** | Player selects in the menu: **Score Target** (first to N kills) or **Timed Score** (most kills in M minutes). Last-team-standing can be added later as a stretch. |
| **Team swap cadence** | **10–15 seconds** (slower than the original 5 s for more strategic clarity). |
| **Mobile controls** | On-screen buttons: left, right, jump, attack, pause. |
| **Audio** | Procedural/placeholder sounds first. Final asset pass happens before release. |
| **Tutorial** | Static “How to Play” screen is mandatory. In-game tutorial match is a stretch goal. |
| **One-way platforms / drop-through** | Keep. Fix the layer-3 drop-through check in `Actor-Movement.gd`. Preserve all existing platform geometry and AI navigation. |

---

## Current State from Audit

### What Works

- Physics-driven movement on a `RigidBody2D` actor.
- Visual body lag/lean feedback.
- Pickupable physics weapons (sword, spear, fork, pistol, rifle).
- Damage/knockback on held-weapon collision.
- Team manager with periodic random team assignment.
- Score manager with kill tracking.
- AI state machine with idle, approach, attack, retreat, and seek-weapon states.
- Basic HUD showing team timer and scoreboard.

### Top Critical Bugs

1. **Ground detection uses non-authoritative physics state** — `Actor-Movement.gd` calls `PhysicsServer2D.body_get_direct_state()` inside `_integrate_forces` instead of using the passed `state`.
2. **AI AttackState only attacks once per engagement** — it sets `wants_attack = true` only on enter.
3. **Kill scoring credits stale attackers** — `WeaponHolder.last_attacker` is never cleared on respawn.
4. **AI cannot recover from broken/unarmed state** — broken weapons are never replaced; unarmed AI retreats forever.
5. **Actors are baked into the arena scene** — `arena.tscn` contains `Actors/Actor` and `Actors/EnemyA` instead of runtime spawning.
6. **No death plane / kill zone** — actors knocked off platforms fall forever.
7. **No main menu, pause menu, or post-round restart flow** — winner banner auto-restarts after 5 s.
8. **Game is completely silent** — `AudioManager` exports are empty and no audio files exist.
9. **Drop-through check needs fixing** — `Actor-Movement.gd` must verify the current ground contact is actually on layer 3 before disabling mask bit 3. Existing one-way platforms and AI navigation must be preserved.
10. **AI facing can flip away from target after knockback** — `Actor-Movement` overwrites `facing_direction` with knockback velocity.

---

## Phase Breakdown

### Phase 1 — Shell & Round Flow (Weeks 1–2)

**Goal:** The prototype feels like a real game. You can start a match from a menu, pause it, finish it, and start another.

**Prerequisite for this phase:** none. These systems are mostly new and can be built in parallel with a test arena.

#### 1.1 Main Menu

**New files:**
- `Scenes/UI/MainMenu.tscn`
- `Scripts/UI/MainMenu.gd`

**Tasks:**
1. Create a CanvasLayer scene with a centered panel.
2. Buttons: **Play**, **How to Play**, **Settings**, **Quit** (desktop only).
3. **Play** opens a pre-match options panel:
   - AI count slider: 1, 2, 3.
   - Win mode selector: **Score Target** / **Timed Score**.
   - Default values: 3 AI, Score Target, target = 10.
4. **How to Play** opens a help panel:
   - Controls (desktop + mobile).
   - Team swap explanation.
   - Pickup weapons, throw weapons, score on kills.
5. **Settings** opens a settings panel:
   - Music volume slider.
   - SFX volume slider.
   - Touch controls toggle (always show / auto / hide).
6. Persist settings with `ConfigFile`.
7. Change `project.godot` `run/main_scene` to `Scenes/UI/MainMenu.tscn`.

#### 1.2 Pause Menu

**New files:**
- `Scenes/UI/PauseMenu.tscn`
- `Scripts/UI/PauseMenu.gd`

**Tasks:**
1. CanvasLayer with `process_mode = WHEN_PAUSED`.
2. Buttons: **Resume**, **Restart Match**, **Quit to Main Menu**.
3. Input action: `Pause` mapped to `Escape` on keyboard.
4. Mobile pause button in top-right of HUD (persistent in match).
5. Pause the scene tree and dim the background.

#### 1.3 Post-Round Screen

**New files:**
- `Scenes/UI/PostRoundMenu.tscn`
- `Scripts/UI/PostRoundMenu.gd`

**Tasks:**
1. Remove the 5-second auto-restart in `Scripts/Components/ArenaManager.gd:46-74`.
2. On match end:
   - Show winner banner.
   - Show final scoreboard: actor name, kills, deaths, final team color.
   - Stop the team-swap timer.
   - Freeze actors (disable input / physics simulation).
3. Buttons: **Play Again**, **Main Menu**.
4. **Play Again** re-runs `ArenaManager._start_match()` with the same settings.
5. **Main Menu** changes scene back to `MainMenu.tscn`.

#### 1.4 Runtime Actor Spawning

**File:** `Scripts/Components/ArenaManager.gd`

**Tasks:**
1. Remove baked `Actors/Actor` and `Actors/EnemyA` from `Scenes/arena.tscn`.
2. Add at least 4 `Marker2D` spawn points under `World/SpawnPoints`.
3. Implement `ArenaManager.spawn_actors(player_count: int, ai_count: int)`:
   - Instantiates `Scenes/actor.tscn`.
   - Sets `global_position` to a random unused `SpawnPoints/Marker2D`.
   - Marks the human actor with `is_player = true` and `player_index = 0`.
   - Marks AI actors with `is_player = false` and assigns `ai_difficulty`.
4. Store spawned actors in an array for round reset.
5. On round reset, despawn old actors and respawn fresh ones.

#### 1.5 Match State Machine

**File:** `Scripts/Components/ArenaManager.gd`

**States:**
- `MENU` — handled by MainMenu scene.
- `PREPARE` — fade in, spawn actors, show 3-2-1 countdown.
- `PLAYING` — run team timer, score, input.
- `POST_ROUND` — freeze, show PostRoundMenu.

**Tasks:**
1. Add `enum MatchState { PREPARE, PLAYING, POST_ROUND }`.
2. Emit signals: `match_started`, `match_ended(winner_actor, reason)`.
3. Win condition dispatcher reads selected mode from a settings/autoload passed by MainMenu.

#### 1.6 Win Conditions

**Files:**
- `Scripts/Components/ScoreManager.gd`
- `Scripts/Components/ArenaManager.gd`

**Score Target mode:**
- Set target at match start (default 10).
- First actor to reach the target wins.
- In case of a tie, continue until one actor leads.

**Timed Score mode:**
- Set duration at match start (default 2:00).
- Actor with the most kills when timer reaches zero wins.
- If tied, sudden-death: team swap disabled, first kill wins.

**Tasks:**
1. Add `WinMode` enum: `SCORE_TARGET`, `TIMED_SCORE`.
2. Add match configuration to `ArenaManager` or a new `MatchConfig` autoload.
3. ScoreManager emits `score_changed(actor, total)`.
4. ArenaManager listens and checks win conditions.

---

### Phase 2 — Core Feel & Bug Fixes (Weeks 3–4)

**Goal:** The shell from Phase 1 can be tested end-to-end. AI fights back, actors die and respawn correctly, scoring is fair, and movement feels solid.

#### 2.1 Ground Detection & Movement

**Files:**
- `Scripts/Actor-Movement.gd`
- `Scenes/actor.tscn`

**Tasks:**
1. Replace `PhysicsServer2D.body_get_direct_state(get_rid())` in `_check_grounded_by_contacts()` with `state.get_contact_count()` / `state.get_contact_local_normal(i)`.
2. Raise `max_contacts_reported` on the actor root `RigidBody2D` from 4 to 8 or 16.
3. Keep `GroundCheck` RayCast2D as a fallback for edge cases, or remove it and update docs.
4. Tune air friction from `0.98` to `0.90–0.95`.
5. Add a small post-jump ground-disable window (~0.08–0.12 s) to prevent double land/jump audio.
6. Fix drop-through logic without breaking existing platforms:
   - Keep `Move_Down` input action and all existing one-way platform tiles.
   - In `_is_on_one_way_slope()`, check the contacted body’s collision layer via the passed `state` (use `state.get_contact_collider_object(i).collision_layer` or the collision data) and only return true if the contact is on layer 3.
   - Keep `_start_drop_through()` but make it safe: disable mask bit 3 only when the actor is actually standing on a layer-3 surface.
   - Do not delete `_is_on_one_way_slope()` or `_start_drop_through()`.
7. Align actor collision mask to documented `13` (layers 1+2+4) instead of current `15`, while still allowing mask bit 3 to be toggled for drop-through.

#### 2.2 AI Combat Fixes

**Files:**
- `Scripts/AI/States/AttackState.gd`
- `Scripts/Components/AIController.gd`
- `Scripts/Actor-Movement.gd`

**Tasks:**
1. In `AttackState.physics_update(delta)`, set `owner.wants_attack = true` every frame while the enemy is in attack range.
2. Keep `move_direction = sign(enemy_delta_x)` during Attack so AI does not turn away.
3. Expose `WeaponBase.is_ready()` and use it in AttackState to respect cooldowns.
4. In `AIController._on_team_changed()`, force immediate target refresh (bypass reaction timer).
5. Prevent `Actor-Movement` from overriding `facing_direction` with knockback velocity. Use the intended movement direction or AI target direction instead.

#### 2.3 Weapon AI Behaviors

**Files:**
- `Scripts/Weapons/WeaponBase.gd`
- `Scripts/Weapons/MeleeWeapon.gd`
- `Scripts/Weapons/RangedWeapon.gd`
- `Scripts/AI/States/SeekWeaponState.gd`
- `Scripts/AI/States/ApproachEnemyState.gd`

**Tasks:**
1. Expose `is_broken()` on `WeaponBase` (true when durability <= 0).
2. Add transition from Attack/Approach to SeekWeapon when current weapon is broken.
3. In `SeekWeaponState`, drop the current broken weapon before picking up a new one.
4. Add an **Unarmed Combat** state:
   - Weak punch/kick with short range.
   - Used when no weapon is nearby.
   - Transitions to SeekWeapon if a weapon enters sensor range.
5. Fix weapon spawn jitter in `WeaponSpawner.gd` and `Chest.gd` so weapons land on platforms, not off ledges.

#### 2.4 Kill Attribution & Scoring Rules

**Files:**
- `Scripts/Components/WeaponHolder.gd`
- `Scripts/Components/Health.gd`
- `Scripts/Components/ScoreManager.gd`

**Tasks:**
1. Add `KillSource` enum: `WEAPON`, `WORLD`, `SELF`.
2. Add timestamp to `last_attacker`.
3. Clear `last_attacker` in `Health._respawn()`.
4. Ignore attacker attributions older than ~3 seconds.
5. Only credit kills inside `Health.take_damage()` when HP reaches zero.
6. For world kills (falling), check recent attacker; if none, award no kill or award to nearest enemy.
7. ScoreManager records kills by source for stats.

#### 2.5 Death Plane & Respawn

**Files:**
- `Scenes/KillZone.tscn` (new)
- `Scripts/Components/KillZone.gd` (new)
- `Scripts/Components/Health.gd`
- `Scenes/arena.tscn`

**Tasks:**
1. Create `KillZone` scene: `Area2D` with `CollisionShape2D` covering the bottom of the arena.
2. Connect `body_entered` to `Health.die(source = WORLD)`.
3. Place one `KillZone` instance below each arena floor.
4. Add screen-edge boundary collision boxes to prevent walking off the side.
5. Respawn invulnerability:
   - Disable collision with weapons/actors for ~1.5 s after respawn.
   - Add flashing visual via a dedicated overlay Sprite2D.
   - Restore collision and normal color when timer ends.
6. Move spawn markers away from edges and common sightlines.

---

### Phase 3 — Audio & Mobile (Weeks 5–6)

**Goal:** The game sounds like a game and plays on a phone.

#### 3.1 Audio System + Placeholder Sounds

**Files:**
- `Scripts/Components/AudioManager.gd`

**Tasks:**
1. Fix empty `AudioManager` exports by generating procedural WAV/OGG placeholders.
2. Required sounds:
   - jump
   - land
   - melee attack swing
   - ranged fire
   - hit / impact
   - death
   - weapon pickup
   - weapon throw / drop
   - team swap cue
   - win jingle
   - UI click / hover
   - background music loop
3. Use `AudioStreamGenerator` or import tiny synthesized clips.
4. Create audio buses: Master, Music, SFX. Add volume sliders in Settings.
5. Remove duplicate ranged attack sound: `Actor-Movement.gd` and `RangedWeapon.gd` both call `AudioManager.play_attack()`. Keep only the weapon’s call.
6. Hook sounds to gameplay events:
   - `Actor-Movement`: jump, land.
   - `MeleeWeapon` / `RangedWeapon`: attack.
   - `Health`: hit, death.
   - `WeaponHolder`: pickup, drop/throw.
   - `TeamManager`: team swap.
   - `ArenaManager`: win.
   - UI buttons: click/hover.

#### 3.2 Input Abstraction Layer

**New files:**
- `Scripts/Components/PlayerInput.gd`

**Tasks:**
1. Create an input component attached to the actor.
2. Exports:
   - `is_player: bool`
   - `player_index: int` (0 for human, 1+ reserved for future P2)
3. Public properties:
   - `move_left: bool`
   - `move_right: bool`
   - `jump_pressed: bool`
   - `jump_held: bool`
   - `attack_pressed: bool`
   - `attack_held: bool`
   - `drop_weapon_pressed: bool` (optional)
   - `pause_pressed: bool`
4. On desktop, read keyboard actions (`Move_Left`, `Move_Right`, `Jump`, `Attack`, `Pause`).
5. On mobile, read virtual button states.
6. Refactor `Actor-Movement.gd` to use `PlayerInput` instead of direct `Input` calls.

#### 3.3 Touch Controls

**New files:**
- `Scenes/UI/TouchControls.tscn`
- `Scripts/UI/TouchControls.gd`

**Tasks:**
1. CanvasLayer with `TouchScreenButton` nodes:
   - Left arrow
   - Right arrow
   - Jump
   - Attack
   - Pause
2. Anchor to screen corners with safe-area margins.
3. Auto-hide after a few seconds of no touch, reappear on any touch.
4. Support a setting to keep them always visible.
5. Scale button sizes based on screen DPI / window size.

#### 3.4 UI Scaling & Safe Areas

**Files:**
- `Scenes/HUD.tscn`
- `Scripts/UI/HUD.gd`

**Tasks:**
1. Use Godot anchors and `ControlLayout` presets for 16:9, notched, and tablet screens.
2. Clamp HUD elements inside safe margins.
3. Test target resolutions: 400×800, 1080×1920, 1920×1080.
4. Health bars should not overlap on small screens; scale or stack them.

---

### Phase 4 — Content Expansion (Weeks 7–8+)

**Goal:** More arenas, more weapons, deeper AI, and better feel.

#### 4.1 Arena System

**New files:**
- `Scenes/Arenas/ArenaBase.tscn`
- `Scenes/Arenas/ArenaFlat.tscn`
- `Scenes/Arenas/ArenaPit.tscn`
- `Scenes/Arenas/ArenaHazards.tscn`

**Tasks:**
1. Create `ArenaBase.tscn` with required children:
   - `World/TileMapLayer`
   - `World/SpawnPoints` (min 4 markers)
   - `World/KillZones`
   - `Actors` (empty)
   - `Camera2D`
   - `Effects`
   - `HUD` (CanvasLayer)
2. Inherit each arena scene from `ArenaBase`.
3. Build three distinct arenas:
   - **Flat Classic:** simple flat stage with small platforms.
   - **Vertical Pit:** two main platforms with a central pit.
   - **Moving Hazards:** includes a slow moving platform and spike hazard.
4. Arena selector in MainMenu passes selected arena path to `ArenaManager`.

#### 4.2 Weapons

**Files:**
- `Scripts/Weapons/WeaponBase.gd`
- `Scripts/Weapons/MeleeWeapon.gd`
- `Scripts/Weapons/RangedWeapon.gd`
- `Scripts/Weapons/Projectile.gd`
- `Scripts/Weapons/WeaponDatabase.gd`
- `Scenes/Weapons/*.tscn`

**Tasks:**
1. **Thrown weapon damage:**
   - Enable damage on dropped/thrown weapons when impact velocity is high enough.
   - Add `thrown_by` field so thrower is not self-damaged.
   - Cap damage to avoid one-shot throws.
2. **New weapons:**
   - **Hammer:** slow, high damage, high knockback, low durability.
   - **Dagger:** fast, low damage, high durability, quick attacks.
   - **Bomb / Grenade:** thrown AOE, explodes after short timer or on impact.
3. **Durability HUD:**
   - Show a small bar above the held weapon or next to the health bar.
4. **Weapon spawn balancing:**
   - Centralize spawn weights, cooldowns, and durability in `WeaponDatabase`.
   - Avoid clustering near spawn points or edges.
5. **Remove dead code:**
   - Delete unused `Scripts/Weapons/Weapon.gd` (old base class) if no scene references it.

#### 4.3 AI Depth

**Files:**
- `Scripts/Components/AIController.gd`
- `Scripts/AI/Pathfinder.gd`
- `Scripts/AI/States/IdleState.gd`
- `Scripts/AI/States/RetreatState.gd`

**Tasks:**
1. **Difficulty presets:**
   - Easy: slower reaction, worse aim, retreats often.
   - Normal: balanced.
   - Hard: fast reaction, better aim, prioritizes weapons.
2. **Multi-route navigation:**
   - Extend `Pathfinder.gd` to support multiple waypoint groups (`stair_waypoints_left`, `stair_waypoints_right`, etc.).
3. **Patrol / idle hop:**
   - Add idle hopping animation.
   - Add a simple Patrol state that walks to a random nearby point when no enemy is visible.
4. **Retreat uses navigator:**
   - `RetreatState.gd` should prefer `Pathfinder` output; fall back to “away from enemy” only if no path exists.
5. **Waypoint proximity:**
   - Reduce `PATH_PROXIMITY` from 80 px to roughly half a tile.
6. **Sensors cleanup:**
   - Add `Health.is_dead()` and use it instead of reading private `_is_dead`.

#### 4.4 Juice & Feedback

**Files:**
- `Scenes/Actor_Body.gd`
- `Scripts/Components/Health.gd`
- `Scripts/Components/TeamMember.gd`
- `Scripts/Components/TeamManager.gd`
- `Scripts/UI/HUD.gd`
- `Scripts/Components/CameraShake.gd` (new)

**Tasks:**
1. **Team swap UX:**
   - Flash each actor to its new color.
   - Play distinct team-swap sound.
   - Pulse HUD timer and play a ticking sound when swap is near (< 3 s).
2. **Screenshake:**
   - Short camera shake on heavy hits and kills.
   - Add `CameraShake.gd` as a Camera2D child.
3. **Kill freeze-frame:**
   - 2–4 frame freeze on kill.
4. **Pickup feedback:**
   - Sound + small particle pop + brief color flash.
5. **HUD polish:**
   - Team-colored health bar borders.
   - Actor labels / names.
   - Clamp health bars to viewport.
6. **Fix color flash conflict:**
   - `TeamMember` and `Health` both flash the same `Sprite2D`. Use a dedicated overlay or flash counter so the correct team color is restored.
7. **Team randomization:**
   - Ensure at least two distinct teams exist when there are 3+ actors.

---

### Phase 5 — Polish & Release Prep (Weeks 9–10)

**Goal:** Ship a stable, performant build on web and mobile.

#### 5.1 Web Export

**Tasks:**
1. Compress PNGs and remove unused assets.
2. Enable Godot web export optimizations.
3. Test on Chrome, Firefox, Safari.
4. Ensure touch controls are hidden on desktop.
5. Add itch.io page with controls, theme statement, and screenshots/GIFs.

#### 5.2 Mobile Export

**Tasks:**
1. Configure Android export preset.
2. Configure iOS export preset if tooling is available.
3. Test safe areas on notched devices.
4. Verify touch responsiveness and button sizes.

#### 5.3 Performance Pass

**Files:**
- `Scripts/Weapons/Projectile.gd`
- `Scripts/Components/Health.gd`
- Scene effect nodes

**Tasks:**
1. Pool projectiles instead of spawning/destroying.
2. Pool death particles and hit effects.
3. Cap physics iterations if low-end mobile struggles.
4. Profile a 4-AI match on a low-end device target.

#### 5.4 Balance Sweep

**Tasks:**
1. Tune movement: run force, max speed, jump impulse, air friction.
2. Tune weapons: damage, durability, knockback, attack cooldown.
3. Tune AI: reaction time, attack range, weapon-seek priority, difficulty modifiers.
4. Tune team swap cadence per arena.

#### 5.5 Settings Persistence

**File:** `Scripts/Components/SettingsManager.gd` (new or extend AudioManager)

**Tasks:**
1. Save music/SFX volume, touch-control mode, and last selected match options.
2. Load on game start.
3. Reset to defaults button in Settings.

#### 5.6 Final Audio Pass

**Tasks:**
1. Replace procedural placeholders with real SFX and music.
2. Balance mixer levels.
3. Add ducking for music during team-swap cue.

---

## File Additions Summary

### New Scenes
- `Scenes/UI/MainMenu.tscn`
- `Scenes/UI/PauseMenu.tscn`
- `Scenes/UI/PostRoundMenu.tscn`
- `Scenes/UI/TouchControls.tscn`
- `Scenes/KillZone.tscn`
- `Scenes/Arenas/ArenaBase.tscn`
- `Scenes/Arenas/ArenaFlat.tscn`
- `Scenes/Arenas/ArenaPit.tscn`
- `Scenes/Arenas/ArenaHazards.tscn`
- `Scenes/Weapons/Hammer.tscn`
- `Scenes/Weapons/Dagger.tscn`
- `Scenes/Weapons/Bomb.tscn`

### New Scripts
- `Scripts/UI/MainMenu.gd`
- `Scripts/UI/PauseMenu.gd`
- `Scripts/UI/PostRoundMenu.gd`
- `Scripts/UI/TouchControls.gd`
- `Scripts/Components/PlayerInput.gd`
- `Scripts/Components/KillZone.gd`
- `Scripts/Components/CameraShake.gd`
- `Scripts/AI/States/UnarmedCombatState.gd`
- `Scripts/AI/States/PatrolState.gd` (optional)
- `Scripts/Components/SettingsManager.gd`

### Modified Scripts
- `project.godot` — input actions, main scene, autoloads.
- `Scripts/Actor-Movement.gd` — ground detection, input abstraction, friction, facing.
- `Scripts/Components/ArenaManager.gd` — match state machine, spawning, win conditions.
- `Scripts/Components/Health.gd` — kill source, invulnerability, respawn.
- `Scripts/Components/WeaponHolder.gd` — kill attribution, drop logic.
- `Scripts/Components/ScoreManager.gd` — score by source, win checks.
- `Scripts/Components/TeamManager.gd` — public getters, two-team guarantee.
- `Scripts/Components/AudioManager.gd` — placeholder sounds, bus mixing.
- `Scripts/UI/HUD.gd` — public team timer access, health bar polish.
- `Scripts/Weapons/WeaponBase.gd` — `is_broken()`, `is_ready()`, thrown damage.
- `Scripts/Weapons/MeleeWeapon.gd` — thrown damage, hit flash.
- `Scripts/Weapons/RangedWeapon.gd` — duplicate sound fix.
- `Scripts/Weapons/Projectile.gd` — pooling, kill source.
- `Scripts/AI/States/AttackState.gd` — continuous attack, facing.
- `Scripts/AI/States/SeekWeaponState.gd` — drop broken weapon, unarmed fallback.
- `Scripts/AI/States/IdleState.gd` — idle hopping, patrol transition.
- `Scripts/AI/States/RetreatState.gd` — use navigator.
- `Scripts/AI/Pathfinder.gd` — multi-route waypoints, proximity tuning.
- `Scripts/AI/Sensors.gd` — use `Health.is_dead()`.

---

## Milestones

| Week | Milestone | Deliverable |
|------|-----------|-------------|
| 1–2 | Playable Shell | Main menu, pause menu, post-round, placeholder audio, runtime spawn, win conditions |
| 3–4 | Stable Combat | Ground detection, AI attack loop, death plane, kill attribution, respawn invulnerability |
| 5–6 | Mobile Ready | Touch controls, input abstraction, UI scaling, web + mobile exports boot |
| 7–8 | Content | 3 arenas, new weapons, AI difficulty, juice (screenshake, team swap FX) |
| 9–10 | Release Prep | Performance pass, balance, final audio pass, itch.io page, settings persistence |

---

## Risk Register

| Risk | Severity | Mitigation |
|------|----------|------------|
| Menus are hard to test while core combat/AI is broken | High | Build menus in a test arena, then immediately fix top 5 loop-breaking bugs before content |
| Physics combat feels unreliable on mobile | High | Tune weapon hitboxes, add pickup magnetism, test touch input early in Phase 3 |
| Placeholder audio becomes “final” by default | Medium | Label all placeholder exports clearly; schedule final audio pass before release |
| AI difficulty spikes with team-swap chaos | Medium | Add 0.2–0.5 s AI reaction delay after team swaps; test per difficulty preset |
| Mobile buttons obscure screen | Medium | Responsive sizing, auto-hide, optional gesture fallback toggle |
| Scope creep: PvP, online, progression | Low | Lock Phase 5 scope; defer to post-release updates |

---

## Open Decisions

1. **Tutorial**
   - Static “How to Play” screen is planned.
   - In-game guided tutorial match is a stretch goal for Phase 4 if time allows.

2. **One-way platforms**
   - **Resolved: keep them.** The existing arena platform layout and AI navigation must not be touched.
   - Fix `Actor-Movement.gd` so `Move_Down` only disables mask bit 3 when the actor is actually standing on a layer-3 surface. No platform geometry changes.

3. **Player 2 / local multiplayer**
   - Input abstraction keeps the door open. Not in this release.

4. **Monetization / progression**
   - None for this release. Consider unlockable characters/arenas as a future update.

---

## Next Immediate Actions

1. Confirm this plan and remaining open decisions.
2. Create `Scenes/UI/MainMenu.tscn` and `Scripts/UI/MainMenu.gd`.
3. Change `project.godot` main scene to MainMenu.
4. Begin Phase 1 implementation.

**Important:** No existing platform geometry, AI navigation waypoints, or TileMapLayer data in `Scenes/arena.tscn` will be edited without explicit permission. Platform-related work in Phase 2 is limited to fixing the `Actor-Movement.gd` layer-3 check while preserving current behavior.
