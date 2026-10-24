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
  - `layout_probe` — HUD/touch-control rects on-canvas and non-overlapping at three resolutions, with touch controls on and off (goal chip beside the pause button vs. in the corner)
  - `touch_stick_probe` — VirtualStick analog capture, deadzone, down-hysteresis, multi-touch, release safety, keyboard protection
  - `auto_attack_probe` — melee proximity auto-swing + aim lock, negatives (far/off/ally/dead), ranged touch-only auto-fire, hold-last guard
  - `touch_layout_editor_probe` — layout persistence round-trip, editor selection/drag/resize/clamps, gameplay denormalized apply + resize + procedural fallback, config backup/restore
  - `death_free_probe` — death/respawn while the actor is freed mid-await (no resumed-coroutine errors)
  - `menu_probe` — Menu UI 2.0: lazy keyboard focus, Stepper wrap/emit + match-state wiring, win-mode row greying + m:ss, mute icon/slider, pause close button, post-round DRAW/reason/sorted starred rows
  - `swap_preview_probe` — player arrow + 2 s swap-colour preview: preview timing/colours, swap applies the previewed roll, clears on swap/stop/restart, arrow only on the player and hidden while dead, two-team guarantee on pre-rolls
  - `audit_regression_probe` — replays every bug reproduced in the 2026-10 audit (`docs/godot-prompter/plans/AUDIT_REPORT_2026-10.md`) in live matches: fixed ones FAIL on regression, open ones print `KNOWN (open)` (promote to a check when fixed)

  Run them all with `pwsh Tools/run_probes.ps1` — it also fails a probe that printed a `SCRIPT ERROR` (a script error only aborts the current function, so a crashed probe can still exit 0).

  **Probe discipline** (`-s` mode compiles the script before autoloads register): runtime `load()` only, untyped vars, no game-class annotations, no direct autoload references (guarded node-path access like `root.get_node_or_null("/root/TeamManager")` is fine).

- **Reimport assets headlessly** (useful after pulling changes or on CI)
  ```powershell
  D:\Apps\godot\Godot_v4.7.1-stable_win64.exe --headless --editor --quit
  ```

## Project overview

Godot 4.7 2D physics platformer fighter — **a full game**, originally a Brackeys Game Jam entry. Core mechanic: teams are **randomly re-shuffled every 10 seconds** (TeamManager's swap timer), so allies become enemies mid-fight. Designs: `docs/godot-prompter/plans/trust-no-one-game-plan.md` (original) and `docs/godot-prompter/plans/swap-war-full-game-plan.md` (full-game roadmap; its §4.3 waypoint-based AI approach is **superseded** by the baked platform graph described below).

Key files:

- **Shell / match flow (autoloads in `project.godot`):** `ArenaManager.gd` (match state machine: countdown → playing → post-round; spawns the player + AI count from `SettingsManager`), `TeamManager.gd` (team registry + the 10 s auto-swap timer; rolls the next teams `PREVIEW_LEAD` = 2 s early and emits `next_teams_rolled`, so the swap applies exactly what was previewed), `ScoreManager.gd`, `SettingsManager.gd` (win mode, durations, AI count, touch mode, auto attack, custom touch layout), `AudioManager.gd`, `WeaponDatabase.gd`. Menus under `Scenes/UI/`.
- **Menu UI 2.0 ("Notebook Doodle" kit):** art + fonts in `Assets/ui/ui-2.0/scribble_ui/x1/` and `scribble_ui/fonts/` (the kit's `demo/`, `themes/`, `x1_5/`, `x2/` and `extras/` are `.gdignore`d — they reference `res://scribble_ui/` and would bloat exports). Our own additions to the kit live in `Assets/ui/ui-2.0/custom/` (plus/minus icons, the pink aim-stick knob recolored from the kit knob, the pause touch button = kit round button + pause icon baked in). The kit's `x1/touch/` art came from a later kit drop (merged in; that drop's touch *scripts* are deliberately unused — single stick, lowercase auto-added actions, mouse-as-finger fallback that would break the Attack/emulation contract). `Assets/ui/Themes/menu_theme.tres` = the kit's 1280×720 theme with paths rewritten, font sizes tuned for the 1152×648 canvas, plus `RowLabel`/`HintLabel`/`KeyLabel`/`ValueLabel`/`SubHeaderLabel` and a paper tooltip. Applied **per scene** on a full-rect `Root` Control (MainMenu, PauseMenu, PostRoundMenu, TouchLayoutEditor, HUD) — never project-wide (world-space nodes like FloatingNumber set their own font). `Scripts/UI/Stepper.gd` (`Scenes/UI/Stepper.tscn`) is the `< value >` OptionButton replacement (same `item_selected(index)` signature); `Scripts/UI/MenuFocus.gd` focuses a panel's default control on the first ui_* navigation press so mouse/touch players never see the focus ring. Plan + mockups: `docs/godot-prompter/plans/menu-ui-2.0/`.
- **In-match HUD 2.0** (`Scenes/HUD.tscn`, plan + mockups in `docs/godot-prompter/plans/hud-ui-2.0/`): paper `CardPanel` scoreboard (`TeamDot.gd` ink-outlined dots, the player's name on a highlighter, star on the single leader), `TeamTimer` badge (paper disc + highlighter ring drawn in code, Cabin Sketch digit; during TeamManager's swap preview the digit takes the **player's next team colour with an ink outline** and a "SWAP!" tag shows; a dash while the swap timer is stopped), the **goal chip** (`%GoalChip`: "first to N" / live "m:ss" via `ArenaManager.get_match_time_left()` / "SUDDEN DEATH") just left of the touch pause button while `TouchControls.uses_touch_controls()` (ignores the AUTO idle-hide) and the button sits top-right, else in the corner, and the `BannerLabel` centre banner ("3 · 2 · 1 · GO!", pops only when the text changes). Every HUD Control is `mouse_filter = IGNORE` — Attack is mouse-bound. `HealthBar2D` is drawn in code (ink-outlined paper pill, team fill; `get_fill_color()` for probes); `FloatingNumber` is team-coloured Patrick Hand with an ink outline (fades via node modulate so the outline fades too). `TeamPalette.COLORS` = the fighter sprites' fills (#37D98C/#FC5C65/#9179FF/#FFB600) + `TeamPalette.INK` for every outline around team colour. Sizes are in world units — arena cameras zoom out (~0.54×).
- **Arenas:** `Scenes/Arenas/ArenaBase.tscn` + `ArenaFlat` (62 px tiles), `ArenaPit`, `ArenaHazards` (adds the spike strip) — placeholders; **final arenas will be 62×62-tile at 62 px tiles**.
- **Actor:** `Scenes/actor.tscn` — root `RigidBody2D`, capsule shape, `GroundCheck` ray, laggy `VisualBody`, `WeaponSocket`, `PickupArea`, `AIController`, `ActorMarker` (`Scripts/UI/ActorMarker.gd`: the player's white overhead arrow + every actor's next-colour preview, drawn in code), and `Components/` (Health, TeamMember). Team colours: `Scripts/Components/TeamPalette.gd` is the only table.
- **Movement:** `Scripts/Actor-Movement.gd` on the actor root; `Scenes/Actor_Body.gd` on `VisualBody`.
- **Weapons:** `Scripts/Weapons/WeaponBase.gd` (pickup/freeze/durability; melee `MeleeWeapon.gd`, ranged `RangedWeapon.gd` + `Projectile.gd`), `WeaponData/WeaponDatabase.gd` (stats), `WeaponSpawner.gd` (sky-drops from `weapon_spawn_points` markers every 10 s).
- **AI 2.0 (baked platform-graph navigation):** `Scripts/Components/AIController.gd` (per-tick pipeline + `facing_intent`), `Scripts/AI/` — `NavGraph.gd` (platforms/edges/hazard rects), `NavBaker.gd` (auto-bake from tiles + `nav_overrides` markers), `NavAStar.gd`, `NavExecutor.gd` (edge-by-edge route execution + stuck ladder), `Sensors.gd` (map-wide scans, localization, hazard state), `StateMachine.gd` + `State.gd` + `States/` (Idle, Patrol, SeekWeapon, ApproachEnemy, Attack, Retreat), `AIDifficulty.gd` (the single "normal" tuning table).
- **Hazards:** `Scripts/Components/HazardArea.gd` (Area2D: damage + self-registration into the nav graph); wired as `World/Hazards/SpikeStrip` in `ArenaHazards.tscn`.

## Architecture notes

- **Physics-driven movement.** The actor is a `RigidBody2D` with `lock_rotation = true`. Movement is applied in `_integrate_forces` using `state.apply_force` / `state.apply_central_impulse`, never by setting `linear_velocity` for locomotion. Horizontal speed is capped by clamping `linear_velocity.x` (300 px/s).
- **Friction model.** Ground/air friction scale `linear_velocity.x` each tick, only when no move input is held.
- **Ground detection.** Contact normals (`dot(UP) > 0.3`) inside `_integrate_forces`; `GroundCheck` ray is used for one-way-slope detection and the AI's ground cell. Drop-through: pressing `Move_Down` masks off the one-way layer for 0.3 s.
- **AI pipeline (per physics tick, in order):** respawn detect → reset virtual inputs → `sensors.update` → state machine → `NavExecutor.update` (owns move/jump/drop while a nav goal is active) → **hazard escape override** (in hazard: escape direction wins, everything else silenced) → publish aim + `facing_intent`. The AI consumes the same virtual-input surface as before (`move_direction`, `wants_jump`, `wants_drop`, `wants_attack`, `aim_direction` + new optional `facing_intent`, read via an `in` guard).
- **Baked navigation.** `NavBaker.get_cached(scene)` bakes ONE graph per instantiated arena (cached on the scene node's meta — freed with the arena) from the `TileMapLayer`: walkable surface cells → horizontal platform runs → edges (walk / jump_up / jump_across / drop_down) with physics-derived margins (constants in world px, tile size read from the TileSet — never hardcoded). Hazard rects **split platforms** and add cost; A* prefers jumping the spike strip over walking it. `nav_overrides` markers (`block`, `force_link`, `hazard_region`) fix auto-bake mistakes per hand.
- **Decision layer.** Idle is the hub: unarmed+weapon→SeekWeapon; armed+enemy→ApproachEnemy (any distance — **full-map awareness, no sight radii**; LOS only gates ranged fire); unarmed+enemy within `retreat_range`→Retreat; else Patrol. Team swap does NOT tear down state: sensors forget the enemy, re-acquire after `swap_reaction_time`. `AIDifficulty.gd` owns all tuning ("normal" profile only). `AIController.nav_enabled` is the kill-switch back to direct steering.
- **Stuck recovery.** NavExecutor: no-progress 0.75 s → micro-jump → forced replan; edge failure → re-localize + blacklist 3 s; no route → honest `failed` → owning state direct-steers briefly.
- **Combat.** Held weapons deal damage on body contact (held weapons collide with actors; the holder is excluded via collision exception). Each victim has a per-attacker cooldown; knockback comes from weapon velocity at impact; friendly fire blocked via `TeamMember`.
- **Pickupable weapons.** Auto-pickup runs on EVERY actor (players rely on it) when `PickupArea` overlaps a free weapon; fresh drops carry a short pickup cooldown. Freed-holder edge case: a weapon held by a freed actor stays "held" forever (freed instances compare non-null).
- **Death / respawn.** `Health.die()` hides the actor, drops the weapon, respawns at a random spawn marker after 1.5 s. KillZone (below the arenas) kills instantly; `Health.is_dead()` is the public accessor.
- **Input map** (`project.godot`): `Move_Left` A, `Move_Right` D, `Move_Down` S/Down (drop-through), `Jump` Space/W/Up, `Attack` **left mouse button only**, `Drop_Weapon` E, `Pause` Esc. Touch UI is twin-stick: gameplay **buttons** are `TouchScreenButton`s; the two analog sticks (`Scripts/UI/VirtualStick.gd`, instanced as `MoveStick`/`AimStick` in `Scenes/UI/TouchControls.tscn`) are custom Node2D nodes — the deliberate TouchScreenButton exception — consuming raw touch events (independent of the emulation flag) and injecting analog strength via `Input.action_press(action, strength)`. **Art** = Notebook Doodle touch set: stick base + yellow knob (move) / pink knob (aim), drawn at `VirtualStick.ART_SCALE` so the 80 px well (`BASE_RADIUS`, which the layout and grab zone are built on) never moves; sticks fade to `idle_opacity` (0.6) untouched and swap to the sunk pressed knob while held. Buttons draw at `TouchControls.BUTTON_ART_SCALE`, folded into node.scale — **button scale = layout scale × saved mult × art scale** (`get_art_scale(name)`; sticks 1.0), so mult 1.0 still means "automatic size"; pushing the stick down past 65% travel engages `Move_Down` (hysteresis at 50%). Mouse-from-touch emulation must stay OFF during play (Attack is mouse-bound) and ON while paused — `TouchControls._process` is the single authority. Touch aim = the right stick (`TouchControls.get_aim_stick_value()` → `Actor-Movement._get_target_aim`; holds the last direction on release, faces before first use). **Auto Attack** (`SettingsManager.auto_attack_enabled`, default off) auto-swings melee within 90 px aiming at the enemy (PC too) and auto-fires ranged while the aim stick is deflected (touch-only); the manual ATTACK input always works alongside. **Custom layout**: Settings → EDIT TOUCH LAYOUT opens `Scenes/UI/TouchLayoutEditor.tscn` (instanced in MainMenu; its `TouchControls` instance runs `editor_mode = true` — no action injection, no stick capture, no emulation flips, no settings visibility gating). The editor selects/drags/resizes (ink selection box + ± square-button pair, mult 0.5–2.0) the six controls and persists `[touch_layout]` in the settings file (name → `Vector3(nx, ny, mult)`, positions normalized to canvas size); `TouchControls._layout_buttons` applies it per-control with procedural fallback and on-canvas clamps (`CANVAS_MARGIN`). While the editor is open it owns `Input.emulate_touch_from_mouse` (restored on every exit path).
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
- **TeamManager's swap timer scrambles teams every 10 s.** Any ad-hoc test rig that expects stable teams must stop its Timer (see `decision_probe.gd`); it also re-randomizes on match start.
- **Probe actors need containment.** WeaponHolder auto-pickup is live on every actor (a passive dummy steals drops); free bodies drift under contact knockback (freeze test dummies); stop the swap timer and purge the `weapons` group between scenarios.
- **Parsed touch events don't dispatch headless.** `Input.parse_input_event` with `InputEventScreenTouch/Drag` never reaches `Node._input` under the headless display server (parsed actions and mouse events do dispatch). Probes feed stick events directly to their handlers — see `Tools/touch_stick_probe.gd`.
- **Settings setters persist.** `SettingsManager` setters write `user://swap_war_settings.cfg` immediately — probes must set properties directly, never call the setters (the ONE exception: `touch_layout_editor_probe` legitimately tests save/load and backs up/restores the whole config file).
- **CanvasLayer visibility never follows a hidden Control ancestor.** The layout editor's nested layers (and its `TouchControls` instance) default `visible = false` in the scene and are flipped explicitly by the editor's enter/exit lifecycle. Any UI nesting CanvasLayers under togglable Controls must do the same.
- **Pause / post-round dim covers everything below layer 11.** PauseMenu (layer 11) and PostRoundMenu (12) dim with a full-rect `Dim` ColorRect; the HUD and its TouchControls sit on the default layer 1, so they are dimmed too. The touch PAUSE button still responds through the dim — TouchScreenButtons read raw touches, not GUI picking.
- **Exports drop script-property overrides on non-`@tool` scene instances (sometimes).** The exporter loads and re-saves every scene in editor mode, where a non-tool script is a placeholder; the Stepper's `items` set on its MainMenu instances were silently lost, so web builds showed blank steppers while desktop runs were fine. `Stepper.gd` is `@tool` for this reason. If an exported build loses a value a scene sets on an instanced custom node, make that script `@tool` (guard runtime-only code with `Engine.is_editor_hint()`). Check an export by running its pack on desktop: `godot --main-pack build/web/index.pck`.
- **Build output lives in `build/`** (gitignored except `build/.gdignore`, which stops Godot importing the exported files back into the project).
- **Kit buttons draw past their rect.** Every kit stylebox has expand margins (hatched shadow ~8–12 px right/bottom); hand-positioned buttons need gaps that clear it (the layout editor's `SIZE_BUTTON_GAP` = 14). `IconButton` is 56 px at its natural size — use `expand_icon = true` with a smaller `custom_minimum_size` (Stepper arrows are 48) rather than shrinking content margins.
- **`CanvasLayer.layer` is a GLOBAL sort key.** Nested layers do NOT stack relative to their parent's canvas — the layout editor's TouchControls instance initially sat at the default layer 1, tied with the MainMenu canvas, and the opaque editor background painted over it. Menu-overlay UI must use explicit higher layer numbers (the editor uses 10 for the controls, 11 for the overlay, above the menu's 1).
- **The layout editor owns `emulate_touch_from_mouse` while open.** Restored on every exit path (panel hide, scene teardown via `_exit_tree`); `emulate_mouse_from_touch` stays at the menu-contract `true`.