# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

Godot is installed at `D:\Apps\godot\Godot_v4.7.1-stable_win64.exe` and is not on PATH. Use the full path, or substitute `godot` if you have added it to PATH locally.

- **Open the project in the Godot editor**
  ```powershell
  D:\Apps\godot\Godot_v4.7.1-stable_win64.exe -e --path .
  ```

- **Run the game** (plays the main scene configured in `project.godot`)
  ```powershell
  D:\Apps\godot\Godot_v4.7.1-stable_win64.exe --path .
  ```

- **Run a specific scene**
  ```powershell
  D:\Apps\godot\Godot_v4.7.1-stable_win64.exe --path . Scenes/arena.tscn
  D:\Apps\godot\Godot_v4.7.1-stable_win64.exe --path . Scenes/actor.tscn
  ```

- **Reimport assets headlessly** (useful after pulling changes or on CI)
  ```powershell
  D:\Apps\godot\Godot_v4.7.1-stable_win64.exe --headless --editor --quit
  ```

- **Tests / lint**
  There is no test framework (e.g. GUT) or linter (e.g. gdlint) configured yet.

## Project overview

This is a Godot 4.7 2D physics platformer fighter for the Brackeys Game Jam. The full design is in `docs/godot-prompter/plans/trust-no-one-game-plan.md`.

Key files:

- `project.godot` — project settings; main scene is `res://Scenes/arena.tscn`.
- `Scenes/arena.tscn` — the level. Root `Node2D` with `World` (TileMapLayer + `SpawnPoints/Marker2D` + a ground sword), `Actors`, static `Camera2D`, and `Effects`.
- `Scenes/actor.tscn` — the player / dummy character. Root `RigidBody2D` with a capsule collision shape, `RayCast2D` ground check, laggy/leaning `VisualBody`, `WeaponSocket` (frozen `RigidBody2D`), and `PickupArea`.
- `Scripts/Actor-Movement.gd` — movement controller attached to the actor root.
- `Scenes/Actor_Body.gd` — visual-feedback script attached to `VisualBody`.
- `Scripts/Components/WeaponHolder.gd` — handles auto-pickup and dropping of weapons.
- `Scripts/Components/Health.gd` — HP, damage, death, and respawn.
- `Scripts/Components/TeamMember.gd` — team ID used for friendly-fire checks.
- `Scripts/Weapons/Weapon.gd` — base class for pickupable physics weapons.
- `Scripts/Weapons/Sword.gd` — sword-specific overrides (e.g., `attack()` thrust).
- `Scenes/Weapons/Sword.tscn` — the simple sword pickup scene.

## Architecture notes

- **Physics-driven movement.** The actor is a `RigidBody2D` with `lock_rotation = true`. Movement is applied in `_integrate_forces` using `state.apply_force` and `state.apply_central_impulse`, not by setting `linear_velocity` directly. Horizontal speed is capped by clamping `linear_velocity.x`.
- **Friction model.** Ground and air friction are applied manually each physics tick by scaling `linear_velocity.x`, but only when no movement input is held.
- **Ground detection.** A single `RayCast2D` named `GroundCheck` points down from the actor and is disabled for one frame after a jump to prevent double-jumps.
- **Visual juice.** `Actor_Body.gd` separates visual feedback from physics logic. It lerps the `VisualBody` position opposite to velocity and leans/rotates the sprite into movement. The "butt drag" look is purely visual; the physics body stays upright.
- **Pickupable weapons.** Weapons are `RigidBody2D` bodies with their own collision. When an unarmed actor's `PickupArea` overlaps a weapon, `WeaponHolder` calls `Weapon.pick_up()`, which freezes the weapon as a kinematic follower of the actor's `WeaponSocket` and adds a collision exception with the holder.
- **Combat.** Held weapons deal damage on body collision. Each victim has a per-actor cooldown (`cooldown_per_actor`). Knockback comes from the weapon's velocity at impact. A held weapon never damages its own holder. Friendly fire is blocked via `TeamMember`.
- **Death / respawn.** `Health.die()` hides the actor, drops the weapon where they died, and respawns the actor at a random `SpawnPoints/Marker2D` after 1.5 s.
- **Level geometry.** The `TileMapLayer` uses `Assets/PNG/spritesheet_default.png` as a `TileSetAtlasSource`. Every defined atlas tile has a full-tile collision polygon, so all painted tiles are solid.
- **Arena structure.** `Scenes/arena.tscn` follows the planned hierarchy under `World` (geometry + `SpawnPoints`), `Actors` (runtime-spawned/player actors), static `Camera2D`, and `Effects`.
- **Camera.** `Camera2D` is static and zoomed to frame the whole arena; it no longer follows any actor.
- **Input map** (defined in `project.godot`):
  - `Move_Left` — `A`
  - `Move_Right` — `D`
  - `Jump` — `Space`, `W`, `Up Arrow`
  - `Attack` — `J`, `Right Ctrl`
- **Renderer / physics settings.** The project uses Forward Plus and the Jolt Physics engine (`physics/3d/physics_engine="Jolt Physics"`). Display stretch is `canvas_items` / `expand`.

## Collision layers

| Layer | Use |
|-------|-----|
| 1 | World / platforms |
| 2 | Actor bodies |
| 3 | Reserved / future |
| 4 | Weapon bodies |
| 5 | Pickup / interaction areas |

- Actor body: layer 2, mask 1 + 2 + 4.
- Weapon body: layer 4, mask 1 + 2 + 4.
- `PickupArea`: layer 5, mask 4.

## Gotchas

- **Generated files.** The `.godot/` directory is generated and ignored by `.gitignore`. Do not hand-edit files inside it.
- **Case sensitivity.** Node/script folders use mixed capitalization (`Scenes`, `Scripts`, `Assets`). Godot resource paths are case-sensitive, so keep paths exactly as referenced in `.tscn` files.
- **Avoid baking actor instances.** `Scenes/arena.tscn` references `Scenes/actor.tscn` as an external `instance=ExtResource(...)`. When modifying the arena via scripts, do not use `PackedScene.pack()` on an instantiated tree unless you intend to bake the actor into the arena.
- **Scene UID cache.** New `.tscn` files may not immediately get a stable UID in the `.godot/uid_cache.bin`. If a scene fails to instantiate with "Scene instance is missing", remove the `uid://...` prefix from the `ext_resource` reference in the parent scene and let Godot resolve by path.
