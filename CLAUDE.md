# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

Godot is installed at `D:\Apps\godot\Godot_v4.7.1-stable_win64.exe` and is not on PATH. Use the full path, or substitute `godot` if you have added it to PATH locally.

- **Open the project in the Godot editor**
  ```powershell
  D:\Apps\godot\Godot_v4.7.1-stable_win64.exe -e --path .
  ```

- **Run the game** (main scene is `res://Scenes/UI/MainMenu.tscn`; start a match from the menu)
  ```powershell
  D:\Apps\godot\Godot_v4.7.1-stable_win64.exe --path .
  ```

- **Run a specific scene**
  ```powershell
  D:\Apps\godot\Godot_v4.7.1-stable_win64.exe --path . Scenes/Arenas/ArenaHazards.tscn
  D:\Apps\godot\Godot_v4.7.1-stable_win64.exe --path . Scenes/actor.tscn
  ```
  Running an arena scene directly boots a full live match (ArenaManager spawns the player + AIs and runs the countdown).

- **Headless smoke boot** (clean quit after N frames — scan output for `SCRIPT ERROR`)
  ```powershell
  D:\Apps\godot\Godot_v4.7.1-stable_win64.exe --headless --path . --quit-after 300
  ```

- **Tests** — there is no test framework (GUT) or linter. Verification is a suite of headless probe scripts in `Tools/`, run with `-s` (exit code 0 = pass):
  ```powershell
  D:\Apps\godot\Godot_v4.7.1-stable_win64.exe --headless --path . -s Tools/nav_bake_probe.gd
  ```
  - `nav_bake_probe` — graph bake on every arena + hazard split/override contract
  - `nav_astar_probe` — routes, costs, banning, hazard-aware pathing
  - `nav_executor_probe` — live physics nav execution (stairs, strip jump-over, drop ladder, wedge failure)
  - `hazard_damage_probe` — hazard wiring, damage pacing, runtime graph registration
  - `decision_probe` — full AI stack live: engagement, weapon-seek, retreat, team swap, facing, hazard escape/choice/patrol
  - `pickup_cooldown_probe` — dropped-weapon pickup cooldown (tasks #11/#12)

  **Probe discipline** (`-s` mode compiles the script before autoloads register): runtime `load()` only, untyped vars, no game-class annotations, no direct autoload references (guarded node-path access like `root.get_node_or_null("/root/TeamManager")` is fine).

- **Reimport assets headlessly** (useful after pulling changes or on CI)
  ```powershell
  D:\Apps\godot\Godot_v4.7.1-stable_win64.exe --headless --editor --quit
  ```

## Project overview

Godot 4.7 2D physics platformer fighter — **a full game**, originally a Brackeys Game Jam entry. Core mechanic: teams are **randomly re-shuffled every 5 seconds** (TeamManager's swap timer), so allies become enemies mid-fight. Designs: `docs/godot-prompter/plans/trust-no-one-game-plan.md` (original) and `docs/godot-prompter/plans/swap-war-full-game-plan.md` (full-game roadmap; its §4.3 waypoint-based AI approach is **superseded** by the baked platform graph described below).

Key files:

- **Shell / match flow (autoloads in `project.godot`):** `ArenaManager.gd` (match state machine: countdown → playing → post-round; spawns the player + AI count from `SettingsManager`), `TeamManager.gd` (team registry + the 5 s auto-swap timer), `ScoreManager.gd`, `SettingsManager.gd` (win mode, durations, AI count), `AudioManager.gd`, `WeaponDatabase.gd`. Menus under `Scenes/UI/`.
- **Arenas:** `Scenes/Arenas/ArenaBase.tscn` + `ArenaFlat` (62 px tiles), `ArenaPit`, `ArenaHazards` (adds the spike strip) — placeholders; **final arenas will be 62×62-tile at 62 px tiles**. `Scenes/arena.tscn` is the legacy jam arena.
- **Actor:** `Scenes/actor.tscn` — root `RigidBody2D`, capsule shape, `GroundCheck` ray, laggy `VisualBody`, `WeaponSocket`, `PickupArea`, `AIController`, and `Components/` (Health, TeamMember).
- **Movement:** `Scripts/Actor-Movement.gd` on the actor root; `Scenes/Actor_Body.gd` on `VisualBody`.
- **Weapons:** `Scripts/Weapons/WeaponBase.gd` (pickup/freeze/durability; melee `MeleeWeapon.gd`, ranged `RangedWeapon.gd` + `Projectile.gd`), `WeaponData/WeaponDatabase.gd` (stats), `WeaponSpawner.gd` (sky-drops from `weapon_spawn_points` markers every 10 s).
- **AI 2.0 (baked platform-graph navigation):** `Scripts/Components/AIController.gd` (per-tick pipeline + `facing_intent`), `Scripts/AI/` — `NavGraph.gd` (platforms/edges/hazard rects), `NavBaker.gd` (auto-bake from tiles + `nav_overrides` markers), `NavAStar.gd`, `NavExecutor.gd` (edge-by-edge route execution + stuck ladder), `Sensors.gd` (map-wide scans, localization, hazard state), `StateMachine.gd` + `State.gd` + `States/` (Idle, Patrol, SeekWeapon, ApproachEnemy, Attack, Retreat), `AIDifficulty.gd` (the single "normal" tuning table).
- **Hazards:** `Scripts/Components/HazardArea.gd` (Area2D: damage + self-registration into the nav graph); wired as `World/Hazards/SpikeStrip` in `ArenaHazards.tscn`.

## Architecture notes

- **Physics-driven movement.** The actor is a `RigidBody2D` with `lock_rotation = true`. Movement is applied in `_integrate_forces` using `state.apply_force` / `state.apply_central_impulse`, never by setting `linear_velocity` for locomotion. Horizontal speed is capped by clamping `linear_velocity.x` (300 px/s).
- **Friction model.** Ground/air friction scale `linear_velocity.x` each tick, only when no move input is held.
- **Ground detection.** Contact normals (`dot(UP) > 0.3`) inside `_integrate_forces`; `GroundCheck` ray is used for one-way-slope detection and the AI's ground cell. Drop-through: pressing `Move_Down` masks off the one-way layer for 0.3 s.
- **AI pipeline (per physics tick, in order):** respawn detect → reset virtual inputs → `sensors.update` → state machine → `NavExecutor.update` (owns move/jump/drop while a nav goal is active) → **hazard escape override** (in hazard: escape direction wins, everything else silenced) → publish aim + `facing_intent`. The AI consumes the same virtual-input surface as before (`move_direction`, `wants_jump`, `wants_drop`, `wants_attack`, `aim_direction` + new optional `facing_intent`, read via an `in` guard).
- **Baked navigation.** `NavBaker.get_cached(scene)` bakes ONE graph per instantiated arena (WeakRef cache) from the `TileMapLayer`: walkable surface cells → horizontal platform runs → edges (walk / jump_up / jump_across / drop_down) with physics-derived margins (constants in world px, tile size read from the TileSet — never hardcoded). Hazard rects **split platforms** and add cost; A* prefers jumping the spike strip over walking it. `nav_overrides` markers (`block`, `force_link`, `hazard_region`) fix auto-bake mistakes per hand.
- **Decision layer.** Idle is the hub: unarmed+weapon→SeekWeapon; armed+enemy→ApproachEnemy (any distance — **full-map awareness, no sight radii**; LOS only gates ranged fire); unarmed+enemy within `retreat_range`→Retreat; else Patrol. Team swap does NOT tear down state: sensors forget the enemy, re-acquire after `swap_reaction_time`. `AIDifficulty.gd` owns all tuning ("normal" profile only). `AIController.nav_enabled` is the kill-switch back to direct steering.
- **Stuck recovery.** NavExecutor: no-progress 0.75 s → micro-jump → forced replan; edge failure → re-localize + blacklist 3 s; no route → honest `failed` → owning state direct-steers briefly.
- **Combat.** Held weapons deal damage on body contact (held weapons collide with actors; the holder is excluded via collision exception). Each victim has a per-attacker cooldown; knockback comes from weapon velocity at impact; friendly fire blocked via `TeamMember`.
- **Pickupable weapons.** Auto-pickup runs on EVERY actor (players rely on it) when `PickupArea` overlaps a free weapon; fresh drops carry a short pickup cooldown. Freed-holder edge case: a weapon held by a freed actor stays "held" forever (freed instances compare non-null).
- **Death / respawn.** `Health.die()` hides the actor, drops the weapon, respawns at a random spawn marker after 1.5 s. KillZone (below the arenas) kills instantly; `Health.is_dead()` is the public accessor.
- **Input map** (`project.godot`): `Move_Left` A, `Move_Right` D, `Move_Down` S/Down (drop-through), `Jump` Space/W/Up, `Attack` J/Right Ctrl, `Drop_Weapon`, `Pause`. Touch UI: gameplay buttons are `TouchScreenButton`s; mouse-from-touch emulation must stay OFF during play (Attack is mouse-bound) and ON while paused.
- **Renderer / physics.** Forward Plus; Jolt is 3D-only — **2D physics is the default Godot solver**. Display stretch `canvas_items` / `expand`.

## Collision layers

Authoritative source: `Scripts/Components/CollisionConfig.gd` (bit values; layer numbers here are 1-indexed).

| Layer | Use |
|-------|-----|
| 1 | Solid world / platforms |
| 2 | Actor bodies |
| 3 | One-way tiles (45° slope triangles) |
| 4 | Grounded weapon bodies |
| 5 | Pickup / interaction areas |
| 6 | Held weapon bodies |

- Actor body: layer 2, mask 1 + 3 — actors **never** collide with each other or weapons.
- Ground weapon: layer 4, mask 1 + 4; held weapon: layer 6, mask 1 + 2 (contact damage); both switch in `WeaponBase.gd`.
- `PickupArea`: layer 5, mask 4. KillZone: mask 2 + 4 + 6.

## Gotchas

- **Generated files.** `.godot/` is generated and ignored. Do not hand-edit files inside it.
- **Case sensitivity.** Node/script folders use mixed capitalization (`Scenes`, `Scripts`, `Assets`). Godot resource paths are case-sensitive; keep paths exactly as referenced in `.tscn` files.
- **Scene UID cache.** New `.tscn` files may not immediately get a stable UID. If a scene fails to instantiate with "Scene instance is missing", remove the `uid://` prefix from the `ext_resource` in the parent scene and let Godot resolve by path.
- **Tile sizes vary by arena (for now).** `ArenaFlat` uses 62 px tiles; Pit/Hazards still 64 px. Never hardcode a tile size — read `tile_set.tile_size` (the baker and AI already do; final arenas are all 62).
- **The bake reads the instantiated arena.** Inherited arenas override `tile_map_data`; `NavBaker` must see the instantiated `TileMapLayer` (probes `.instantiate()`, never parse `.tscn` bytes).
- **TeamManager's swap timer scrambles teams every 5 s.** Any ad-hoc test rig that expects stable teams must stop its Timer (see `decision_probe.gd`); it also re-randomizes on match start.
- **StairWaypoints nodes are inert dead data.** The old waypoint AI is gone; the nodes stay only because `ArenaFlat` overrides their visibility. Don't build on them.
- **Probe actors need containment.** WeaponHolder auto-pickup is live on every actor (a passive dummy steals drops); free bodies drift under contact knockback (freeze test dummies); stop the swap timer and purge the `weapons` group between scenarios.