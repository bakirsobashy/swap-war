# Plan: Weapon System Rewrite

## 1. Goal

Replace the single `Weapon` class with a small, consistent weapon system that supports five weapons across two categories:

- **Melee**: Sword, Spear, Fork
- **Ranged**: Pistol, Rifle

Each weapon has fixed, globally consistent stats (damage, attack/fire rate, critical chance, durability). Weapons degrade and can break:
- Melee weapons lose durability each time they successfully deal damage to an enemy.
- Ranged weapons use a magazine system: each shot consumes one durability; when the magazine empties the gun instantly breaks.

Attack animations differ by weapon type:
- **Sword**: 45° slash that swings up or down depending on the sword's current vertical position, then returns.
- **Spear / Fork**: straight forward poke.
- **Pistol / Rifle**: fire a projectile toward the aimed direction.

Player guns aim at the mouse cursor. AI guns aim at the target with a 0.2-second smoothing rotation.

Weapons are spawned from the sky at `WeaponSpawnPoint` markers every 10 seconds (3 per wave for now) and also from chests placed in the arena.

## 2. Non-Goals

- No procedural/stat-randomized weapons; each weapon archetype has a single fixed stat profile.
- No reloading, ammo pickups, or magazine refills outside a fresh weapon spawn.
- No weapon throwing changes beyond the existing drop/throw behavior.
- No changes to player movement, team system, or core AI state machine (only AI attack range and aim smoothing).
- No final VFX/sounds in this phase; placeholders only.
- No HUD weapon display in this phase.

## 3. Weapon Archetype Stats

Stats are declared in the autoloaded `WeaponDatabase`. Every instance of a weapon archetype starts with the same stats.

| Weapon | Category | Damage | Cooldown | Crit % | Durability | Magazine | Knockback | Notes |
|--------|----------|--------|----------|--------|------------|----------|-----------|-------|
| Sword  | Melee    | 25     | 0.50s    | 10%    | 20 hits    | —        | 400       | 45° up/down slash |
| Spear  | Melee    | 18     | 0.60s    | 15%    | 15 hits    | —        | 350       | Poke |
| Fork   | Melee    | 14     | 0.50s    | 12%    | 12 hits    | —        | 320       | Poke, uses own sprite |
| Pistol | Ranged   | 12     | 0.35s    | 8%     | —          | 6 shots  | 150       | Projectile |
| Rifle  | Ranged   | 22     | 0.25s    | 12%    | —          | 15 shots | 200       | Projectile |

Melee durability = successful hits on enemies. Ranged durability = magazine size = shots fired.

Critical hits multiply damage by 1.5× and get a placeholder visual flash on hit.

## 4. High-Level Architecture

```
WeaponBase (RigidBody2D)
├── MeleeWeapon
│   ├── Sword (45° slash up/down)
│   ├── Spear (poke)
│   └── Fork (poke, own stats/sprite)
└── RangedWeapon
    ├── Pistol
    └── Rifle

WeaponDatabase (autoload)
├── WeaponData entries keyed by weapon name
└── Provides fixed stats for each archetype

Projectile (Area2D)
├── Fired by RangedWeapon
├── Carries damage, crit, source, team
├── Uses bullet sprite (effect_blast / effect_shot)
└── Dies on impact or timeout

WeaponSpawner (Node in Arena)
├── SkySpawnPoints (Marker2D group "weapon_spawn_points")
├── 10-second timer
└── Spawns 3 weapons per wave, melee more common

Chest (Area2D scene)
├── Spawns a weapon on some trigger/timer
└── Continuous or limited spawns (placeholder for now)
```

`WeaponHolder` stays in place but works against `WeaponBase`.

## 5. File Layout

```
Scripts/
├── Weapons/
│   ├── WeaponData.gd        # resource definition (already created)
│   ├── WeaponDatabase.gd    # autoload with fixed stats
│   ├── WeaponBase.gd        # common pickup/drop/facing/aim
│   ├── MeleeWeapon.gd       # shared melee attack/hit/durability
│   ├── Sword.gd             # 45° slash animation
│   ├── Spear.gd             # poke, sets weapon_name = "Spear"
│   ├── Fork.gd              # poke, sets weapon_name = "Fork"
│   ├── RangedWeapon.gd      # shared gun fire/aim/durability
│   ├── Pistol.gd            # sets weapon_name = "Pistol"
│   ├── Rifle.gd             # sets weapon_name = "Rifle"
│   ├── Projectile.gd        # bullet logic
│   ├── WeaponSpawner.gd     # sky spawner
│   └── Chest.gd             # chest spawner
└── Components/
    ├── WeaponHolder.gd      # typed against WeaponBase
    └── AIController.gd      # small change for ranged aim smoothing

Scenes/Weapons/
├── Sword.tscn
├── Spear.tscn
├── Fork.tscn
├── Pistol.tscn
├── Rifle.tscn
└── Projectile.tscn

Scenes/
├── Chest.tscn
└── arena.tscn              # add WeaponSpawnPoints + Chests
```

## 6. WeaponData Resource

```gdscript
class_name WeaponData
extends Resource

@export var weapon_name: String = ""
@export var category: String = "melee"          # "melee" or "ranged"
@export var damage: float = 10.0
@export var attack_cooldown: float = 0.5
@export var critical_chance: float = 0.0          # 0.0..1.0
@export var durability: int = 10                 # melee hits / ranged magazine size
@export var knockback: float = 300.0
@export var attack_thrust_distance: float = 32.0  # melee thrust distance
@export var attack_thrust_duration: float = 0.15  # melee attack window
@export var slash_arc_degrees: float = 45.0      # sword only
@export var projectile_speed: float = 600.0      # ranged only
@export var projectile_lifetime: float = 1.0     # ranged only
@export var texture: Texture2D = null
```

## 7. WeaponDatabase

Autoload `WeaponDatabase` registers the five profiles in `_ready()`.

Key method: `get_data(name: String) -> WeaponData`.

Values:
- Sword: damage 25, cooldown 0.5, crit 0.10, durability 20, knockback 400, slash_arc 45°
- Spear: damage 18, cooldown 0.6, crit 0.15, durability 15, knockback 350
- Fork: damage 14, cooldown 0.5, crit 0.12, durability 12, knockback 320
- Pistol: damage 12, cooldown 0.35, crit 0.08, durability 6 (magazine), projectile speed 550, lifetime 0.7
- Rifle: damage 22, cooldown 0.25, crit 0.12, durability 15 (magazine), projectile speed 900, lifetime 1.0

## 8. WeaponBase

Replaces `Scripts/Weapons/Weapon.gd`. Holds:
- `weapon_name: String`
- `_data: WeaponData`
- `current_durability: int`
- `_holder`, `_socket`, `_target_facing`

Public API:
- `pick_up(holder, socket)` / `drop()`
- `set_facing(facing)`
- `attack()` virtual
- `is_attacking()` virtual
- `is_held()`
- `is_broken()`
- `get_attack_range()` virtual
- `get_hand_socket()`
- `_local_weapon_rotation()`
- `_update_follow_transform()`
- `get_aim_direction()` → returns cursor direction for player, target direction for AI

Aim handling:
- For the player, aim comes from `_holder` via `aim_direction` (already set by `Actor-Movement._update_aim()`).
- For AI, aim is already computed in `Sensors._update_aim()` and published as `owner.aim_direction`.

WeaponBase reads `_holder.aim_direction` when held.

## 9. MeleeWeapon

Extends `WeaponBase`.

- Tracks `_attack_cooldown_timer`, `_attack_timer`, `_is_attacking`, `_recent_hits`.
- `attack()` starts the attack window if not broken/on cooldown.
- Body collision while attacking damages enemies, applies 1.5× crit, decrements durability by 1 on successful hit, and applies knockback.
- Per-actor hit cooldown prevents multi-frame damage.
- When durability reaches 0, `_break_weapon()` drops it from the holder, spawns a placeholder break effect, and queues free.

## 10. Sword Slash Animation

The sword has a visual node (same `SwordVisuals` structure as now). At rest the sword points forward, matching `_local_weapon_rotation()`.

During an attack (`_attack_timer > 0`):
- Read the current local rotation. If it is at or above the forward/rest angle, rotate downward by `slash_arc_degrees / 2` and return.
- If it is below the forward/rest angle, rotate upward by `slash_arc_degrees / 2` and return.
- The hitbox `HitBox` stays active for the entire attack window.
- After `_attack_timer` expires, the sword returns to its forward/rest angle.

This creates a back-and-forth 45° slash arc with no forward component.

## 11. Spear & Fork

Extend `MeleeWeapon`. Use the existing thrust behavior: during `_attack_timer`, add `attack_thrust_distance` to the follow offset along the facing direction, then retract.

`Spear.gd` sets `weapon_name = "Spear"`.
`Fork.gd` sets `weapon_name = "Fork"` and uses a different sprite texture.

## 12. RangedWeapon

Extends `WeaponBase`.

- Tracks `_fire_cooldown_timer`.
- `attack()` fires one projectile if not broken/on cooldown.
- Decrements `current_durability` by 1 per shot.
- When durability reaches 0, instantly break (drop + placeholder effect + queue free).
- Aim direction comes from `_holder.aim_direction`.
- For AI, aim direction smoothing is handled by the actor/AI controller, not the weapon.
- Spawns `Projectile` at the `Muzzle` marker position and rotation.
- Override `get_attack_range()` to return `projectile_speed * projectile_lifetime * 0.8`.

## 13. AI Ranged Aim Smoothing

In `AIController`, add a small lag when the current weapon is ranged so the gun rotates toward the target more gradually.

Options considered:
- Smooth inside `RangedWeapon`. Rejected: weapon should not know it is held by AI vs player.
- Smooth inside `Actor-Movement._update_aim()` when `is_player == false` and ranged weapon is held. This is the cleanest spot because it already updates aim every frame.

Implementation:
- `Actor-Movement` reads whether the held weapon is ranged (via `WeaponHolder.current_weapon` and a `is_ranged()` helper on `WeaponBase`).
- If ranged and AI, lerp `aim_direction` toward the target direction over ~0.2s.
- The weapon reads `aim_direction` as usual, so the gun rotation itself does not need extra smoothing logic.

## 14. Projectile

`Projectile` extends `Area2D`.

- `start(pos, dir, data, source)` sets position, velocity, data, source, and lifetime.
- `_physics_process(delta)` moves forward and counts down lifetime.
- `_on_body_entered(body)` ignores the source and teammates, damages enemies with crit chance, applies small knockback, plays placeholder hit effect, then queue_free.
- Passes through one-way platforms (same collision-mask behavior as player bullets; world collision mask can be set to world only if we want bullets blocked by solid walls, or include nothing if bullets should pass through everything except actors — user said "pass through", so we will set mask to actor bodies only or actor + world solids).

Clarified: projectiles pass through one-way platforms; they still collide with teammates without dealing damage.

Visual: use `effect_blast.png` or `effect_shot.png` as the bullet sprite.

## 15. WeaponHolder Changes

- Change `current_weapon` type to `WeaponBase`.
- Add optional `on_weapon_broken(weapon)` callback hook so break effects can be handled cleanly.
- Public API stays the same.

## 16. AI Attack Range & Weapon Picking

`ApproachEnemyState._is_in_attack_range()` uses `weapon.get_attack_range()` so AI respects melee reach and ranged projectile reach.

For weapon seeking (`SeekWeaponState` / `IdleState`):
- If multiple weapons are within range at the same distance, prefer ranged weapons.
- Otherwise pick nearest.

## 17. Weapon Spawner

`WeaponSpawner` is a Node added to `Scenes/arena.tscn`.

- Reads all `Marker2D` nodes in group `weapon_spawn_points` placed in the sky.
- Every 10 seconds, picks 3 spawn points and drops a weapon from each.
- Spawn randomness is weighted so melee weapons are more common than guns.
- Spawned weapon is given a small downward velocity so it falls to the ground.
- Weapons that fall off the world or despawn are handled by the existing physics/cleanup.

Spawn weights (example):
- Sword: 25%
- Spear: 25%
- Fork: 25%
- Pistol: 12.5%
- Rifle: 12.5%

## 18. Chest Spawner

`Chest` is a new `Area2D` scene placed in the arena.

- Has a cooldown and spawns a weapon when triggered (or on a timer).
- For now, spawns continuously with a cooldown.
- Spawns use the same weighted random table as the sky spawner.
- Placeholder open/close animation and sound.

## 19. Active Gun Limit

`WeaponSpawner` tracks the number of `RangedWeapon` instances in the scene (via the `weapons` group and `is_ranged()` check). If the limit is reached, sky/chest spawns only produce melee weapons until a gun is picked up/broken.

Suggested limit: 3 active guns on the ground at once.

## 20. Actor-Movement Changes

Two small changes:
1. When the held weapon is ranged and the actor is AI, smooth `aim_direction` toward the target over 0.2s in `_update_aim()`.
2. No changes to `_update_attack()`; it still calls `weapon.attack()`.

## 21. Arena Scene Changes

- Remove the two existing static `Sword` pickups (or keep one and replace the other).
- Add `World/WeaponSpawnPoints` node with `Marker2D` children in the sky, each in group `weapon_spawn_points`.
- Add a `WeaponSpawner` node under `World` that references these points.
- Add a few `Chest` instances under `World`.

## 22. Implementation Order

1. Create `WeaponDatabase` autoload and register five profiles in `project.godot`.
2. Create `WeaponBase` from existing `Weapon.gd`.
3. Create `MeleeWeapon` base.
4. Create `Sword`, `Spear`, `Fork` scripts and scenes.
5. Create `Projectile` scene/script.
6. Create `RangedWeapon` base, `Pistol`, `Rifle` scripts and scenes.
7. Update `WeaponHolder` to use `WeaponBase`.
8. Add `is_ranged()` helpers and update `ApproachEnemyState` / `IdleState` weapon preference.
9. Add AI ranged aim smoothing in `Actor-Movement._update_aim()`.
10. Create `WeaponSpawner` script and `Chest` scene.
11. Update `Scenes/arena.tscn` with spawn points, spawner, and chests.
12. Run and tune.

## 23. Verification Steps

1. All five weapons can be picked up and dropped.
2. Sword slashes 45° up/down and returns.
3. Spear and fork poke forward.
4. Pistol fires 6 shots then breaks; rifle fires 15 shots then breaks.
5. Projectiles use a sprite, travel straight, damage enemies, ignore/don't damage teammates.
6. Melee durability decreases only on successful enemy hits.
7. Broken weapons vanish with a placeholder effect.
8. Critical hits occasionally deal 1.5× damage with a placeholder flash.
9. AI can use ranged weapons; it keeps distance and aims smoothly.
10. Weapons spawn from sky every 10 seconds (3 per wave) and from chests.
11. Active gun limit is respected.
12. AI prefers a gun over a melee weapon when distances are equal.

## 24. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Refactoring breaks existing sword | Keep `WeaponBase` API compatible; test sword first. |
| Ranged AI too oppressive | Start with low damage/rate; tune after playtest. |
| Projectiles feel hard to see | Use a clear bullet sprite and add placeholder muzzle flash. |
| Spawner floods arena | Cap active guns and cap total spawned weapons if needed. |
| Sword slash looks wrong | Start with 45° and tune in editor after visual check. |
