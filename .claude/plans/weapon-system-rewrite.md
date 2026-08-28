# Plan: Weapon System Rewrite

## 1. Goal

Replace the single `Weapon` class with a small, consistent weapon system that supports five weapons across two categories:

- **Melee**: Sword, Spear, Fork
- **Ranged**: Pistol, Rifle

Each weapon has fixed, globally consistent stats (damage, attack/fire rate, critical chance, durability / hardness). Weapons degrade and can break: melee weapons lose durability each time they deal damage; ranged weapons lose durability each time they fire a projectile. Attack animations differ by weapon type: swords slash (arc up/down), spears and forks poke straight forward, guns fire projectiles.

## 2. Non-Goals

- No procedural/stat-randomized weapons; each weapon archetype has a single fixed stat profile.
- No reloading, ammo pickups, or magazine system.
- No weapon throwing changes beyond the existing drop/throw behavior.
- No changes to player movement, AI state machine, or team system.
- No new UI in this phase (HUD weapon display is out of scope).

## 3. Weapon Archetype Stats

Each weapon keeps the same stats everywhere in the game. Stats are declared in a single `WeaponDatabase` resource so tuning happens in one place.

| Weapon | Category | Damage | Rate | Crit % | Durability | Notes |
|--------|----------|--------|------|--------|------------|-------|
| Sword  | Melee    | 25     | 0.5s | 10%    | 20 hits    | Slash arc |
| Spear  | Melee    | 18     | 0.6s | 15%    | 15 hits    | Poke |
| Fork   | Melee    | 14     | 0.5s | 12%    | 12 hits    | Poke (twin prongs, same behavior as spear) |
| Pistol | Ranged   | 12     | 0.35s| 8%     | 12 shots   | Single shot, short range |
| Rifle  | Ranged   | 22     | 0.25s| 12%    | 25 shots   | Single shot, long range |

Hardness is represented as a flat durability counter (uses until break). Attack speed and damage are fixed; only durability decreases during a match.

## 4. High-Level Architecture

```
WeaponBase (RigidBody2D)
├── MeleeWeapon
│   ├── Sword (slash arc)
│   ├── Spear (poke)
│   └── Fork (poke)
└── RangedWeapon
    ├── Pistol
    └── Rifle

WeaponDatabase (autoload / named resource)
├── WeaponData entries keyed by weapon name
└── Provides stats for each archetype

Projectile (RigidBody2D or Area2D)
├── Fired by RangedWeapon
├── Carries damage, crit, source, team
└── Dies on impact or timeout
```

`WeaponHolder` stays in place but works against the `WeaponBase` API:
- `current_weapon: WeaponBase`
- `attack()` delegates to the weapon.
- `is_holding_weapon()` remains unchanged.

`Actor-Movement._update_attack()` already calls `weapon.attack()`, so no change is required there.

## 5. File Layout

```
Scripts/
├── Weapons/
│   ├── WeaponBase.gd        # extends RigidBody2D, common pickup/drop/facing logic
│   ├── MeleeWeapon.gd       # shared melee attack + hit handling
│   ├── RangedWeapon.gd      # shared gun fire + projectile spawn
│   ├── WeaponDatabase.gd    # autoload or resource with all weapon stats
│   ├── Sword.gd             # slash animation override
│   ├── Spear.gd             # poke override
│   ├── Fork.gd              # poke override
│   ├── Pistol.gd            # pistol override
│   ├── Rifle.gd             # rifle override
│   └── Projectile.gd        # bullet / arrow logic
└── Components/
    └── WeaponHolder.gd      # typed against WeaponBase, unchanged public API

Scenes/Weapons/
├── Sword.tscn              # update base script reference
├── Spear.tscn
├── Fork.tscn
├── Pistol.tscn
└── Rifle.tscn
```

## 6. WeaponData Resource

`WeaponData` is a small `Resource` used by the database:

```gdscript
class_name WeaponData
extends Resource

@export var weapon_name: String = ""
@export var category: String = "melee"   # "melee" or "ranged"
@export var damage: float = 10.0
@export var attack_cooldown: float = 0.5
@export var critical_chance: float = 0.0   # 0.0..1.0
@export var durability: int = 10            # hits for melee, shots for ranged
@export var knockback: float = 300.0
@export var attack_thrust_distance: float = 32.0
@export var attack_thrust_duration: float = 0.15
@export var slash_arc_degrees: float = 90.0   # only for sword slash
@export var projectile_speed: float = 600.0  # only for ranged
@export var projectile_lifetime: float = 1.0   # only for ranged
@export var texture: Texture2D = null
```

`WeaponDatabase.gd` (autoloaded as `WeaponDatabase`):

```gdscript
extends Node

var _data: Dictionary = {}   # String -> WeaponData

func _ready() -> void:
    _register("Sword",  ... )
    _register("Spear",  ... )
    _register("Fork",   ... )
    _register("Pistol", ... )
    _register("Rifle",  ... )

func get_data(name: String) -> WeaponData:
    return _data.get(name, null)

func _register(...) -> void:
    var d := WeaponData.new()
    d.weapon_name = name
    ...
    _data[name] = d
```

Alternatives considered:
- Keep stats as `@export` fields on each weapon scene. Rejected because the user wants stats to be consistent, and duplicating exports across five scenes makes tuning error-prone.
- Use JSON. Rejected because a typed GDScript resource is easier to wire into the Inspector and safer to refactor.

Chosen: autoloaded `WeaponDatabase` with typed `WeaponData` resources.

## 7. WeaponBase

`Scripts/Weapons/WeaponBase.gd` replaces `Scripts/Weapons/Weapon.gd`. It keeps all existing pickup/drop/facing logic but removes stat fields and attack behavior, which move to subclasses.

Responsibilities:
- Hold `_holder`, `_socket`, `_target_facing`.
- `pick_up(holder, socket)` and `drop()` (unchanged logic).
- `set_facing(facing)`.
- `_update_follow_transform()` so the weapon tracks the actor's socket.
- Declare abstract/virtual `attack()`, `is_attacking()`, `get_hand_socket()`, `_local_weapon_rotation()`.
- Expose `get_weapon_name()` so the subclass reports its archetype name.
- Durability is read from `WeaponDatabase` at `_ready()` and stored in `current_durability`.

```gdscript
class_name WeaponBase
extends RigidBody2D

var weapon_name: String = ""
var _data: WeaponData = null
var current_durability: int = 0
var _holder: RigidBody2D = null
var _socket: Node2D = null
var _target_facing: float = 1.0

func _ready() -> void:
    add_to_group("weapons")
    _data = WeaponDatabase.get_data(weapon_name)
    if _data:
        current_durability = _data.durability
    contact_monitor = true
    max_contacts_reported = 4

func attack() -> void:
    push_warning("WeaponBase.attack() called on abstract weapon")

func is_attacking() -> bool:
    return false

func is_held() -> bool:
    return _holder != null

func is_broken() -> bool:
    return current_durability <= 0

func pick_up(...) -> void:   # same as current Weapon.gd
func drop() -> void:          # same as current Weapon.gd
func set_facing(facing) -> void:  # same
func _update_follow_transform() -> void:  # same
```

## 8. MeleeWeapon

`Scripts/Weapons/MeleeWeapon.gd` extends `WeaponBase`.

Responsibilities:
- Track `_attack_cooldown_timer`, `_attack_timer`, `_is_attacking`.
- Implement `attack()` respecting `attack_cooldown` from the database.
- On body collision while attacking, apply damage plus critical hit chance, decrement durability when damage actually lands, and apply knockback.
- Keep per-actor hit cooldown to prevent multi-frame damage spam.

Critical hits: roll `randf() < _data.critical_chance`; if true, multiply damage by a fixed `CRITICAL_MULTIPLIER` (e.g. `1.5`).

Durability loss: only decrement when the weapon successfully deals damage to an enemy (not walls, not teammates).

Break behavior: when durability reaches 0, the weapon is immediately dropped from the holder and becomes a non-functional debris body (or is queued free). The holder is left unarmed.

```gdscript
class_name MeleeWeapon
extends WeaponBase

const CRITICAL_MULTIPLIER: float = 1.5

var _attack_cooldown_timer: float = 0.0
var _attack_timer: float = 0.0
var _is_attacking: bool = false
var _recent_hits: Dictionary = {}

func attack() -> void:
    if not _holder: return
    if is_broken(): return
    if _attack_cooldown_timer > 0.0: return
    _attack_cooldown_timer = _data.attack_cooldown
    _attack_timer = _data.attack_thrust_duration
    _is_attacking = true

func is_attacking() -> bool:
    return _is_attacking

func _physics_process(delta) -> void:
    if not _holder: return
    if _attack_cooldown_timer > 0.0:
        _attack_cooldown_timer -= delta
    if _attack_timer > 0.0:
        _attack_timer -= delta
        if _attack_timer <= 0.0:
            _is_attacking = false
    _update_follow_transform()

func _on_body_entered(body) -> void:
    if not _holder or body == _holder: return
    if not _is_attacking: return
    var health = body.get_node_or_null("Components/Health")
    if not health: return
    if TeamMember.is_same_team(_holder, body): return

    var now := Time.get_ticks_msec() / 1000.0
    if now - _recent_hits.get(body, -INF) < _data.attack_cooldown:
        return
    _recent_hits[body] = now

    var final_damage := _data.damage
    if randf() < _data.critical_chance:
        final_damage *= CRITICAL_MULTIPLIER
    health.take_damage(final_damage, _holder)
    _apply_knockback(body)
    _lose_durability(1)
    if AudioManager:
        AudioManager.play_hit()

func _lose_durability(amount: int) -> void:
    current_durability -= amount
    if current_durability <= 0:
        _break_weapon()

func _break_weapon() -> void:
    # Visual/audio break feedback can be added here.
    if _holder:
        var holder_weapon := _holder.get_node_or_null("WeaponHolder")
        if holder_weapon:
            holder_weapon.drop_weapon()
    queue_free()
```

## 9. Sword (Slash)

`Scripts/Weapons/Sword.gd` extends `MeleeWeapon`.

Override `_update_follow_transform()` or add a separate `SwordVisuals` node to animate a slash arc during `_attack_timer`:

- At rest the sword points forward like current sword.
- During attack, rotate the weapon sprite from `+slash_arc_degrees/2` to `-slash_arc_degrees/2` (or reverse based on facing) over `attack_thrust_duration`.
- The hitbox stays enabled for the whole slash window; the visual rotation creates the "round movement up or down" look.

The `Sword.tscn` keeps `SwordVisuals` with `Sprite2D` and `HandSocket`, plus `CollisionPolygon2D` and `HitBox`.

## 10. Spear & Fork (Poke)

`Scripts/Weapons/Spear.gd` and `Fork.gd` extend `MeleeWeapon`.

Poke animation:
- During `_attack_timer`, thrust the weapon forward by `attack_thrust_distance` along the facing direction, then retract.
- This is the same thrust behavior that currently exists in `Weapon.gd`, just driven by database values.

Fork can reuse the spear script or have its own tiny override that only changes `weapon_name` and visual. For clarity we will give fork its own script that sets `weapon_name = "Fork"`.

Scenes:
- `Spear.tscn` uses `item_spear.png`, a long thin collision polygon, and a hit box.
- `Fork.tscn` uses `item_rod.png` or a recolored spear sprite, a thin collision polygon, and a hit box.

## 11. RangedWeapon

`Scripts/Weapons/RangedWeapon.gd` extends `WeaponBase`.

Responsibilities:
- Track `_fire_cooldown_timer`.
- Implement `attack()` as "fire once" respecting `attack_cooldown`.
- Spawn a `Projectile` from a configurable `Muzzle` marker on the weapon scene.
- Decrement durability on each shot (whether it hits or not), because the breakdown cost is firing.
- Break when durability reaches 0.

```gdscript
class_name RangedWeapon
extends WeaponBase

var _fire_cooldown_timer: float = 0.0

func attack() -> void:
    if not _holder: return
    if is_broken(): return
    if _fire_cooldown_timer > 0.0: return
    _fire_cooldown_timer = _data.attack_cooldown
    _fire_projectile()
    _lose_durability(1)
    if AudioManager:
        AudioManager.play_attack()

func _physics_process(delta) -> void:
    if not _holder: return
    if _fire_cooldown_timer > 0.0:
        _fire_cooldown_timer -= delta
    _update_follow_transform()

func _fire_projectile() -> void:
    var projectile_scene := preload("res://Scenes/Weapons/Projectile.tscn")
    var projectile := projectile_scene.instantiate() as Projectile
    var muzzle := get_node_or_null("Muzzle") as Marker2D
    var spawn_pos := global_position
    var dir := Vector2(_target_facing, 0.0)
    if muzzle:
        spawn_pos = muzzle.global_position
        dir = Vector2(cos(muzzle.global_rotation), sin(muzzle.global_rotation))
    projectile.start(spawn_pos, dir, _data, _holder)
    get_tree().current_scene.add_child(projectile)
```

## 12. Projectile

`Scripts/Weapons/Projectile.gd` is a small `Area2D` or `RigidBody2D` that travels in a straight line and damages the first enemy it touches.

```gdscript
class_name Projectile
extends Area2D

var _data: WeaponData = null
var _source: Node = null
var _velocity: Vector2 = Vector2.ZERO
var _life_timer: float = 0.0

func start(pos: Vector2, dir: Vector2, data: WeaponData, source: Node) -> void:
    global_position = pos
    _data = data
    _source = source
    _velocity = dir.normalized() * data.projectile_speed
    _life_timer = data.projectile_lifetime
    rotation = dir.angle()

func _physics_process(delta) -> void:
    position += _velocity * delta
    _life_timer -= delta
    if _life_timer <= 0.0:
        queue_free()

func _on_body_entered(body) -> void:
    if body == _source: return
    if TeamMember.is_same_team(_source, body): return
    var health = body.get_node_or_null("Components/Health")
    if health:
        var final_damage := _data.damage
        if randf() < _data.critical_chance:
            final_damage *= 1.5
        health.take_damage(final_damage, _source)
        # Optional: small knockback on projectile impact.
    queue_free()
```

Using `Area2D` avoids bullet physics weirdness and gives reliable one-shot hit detection.

## 13. WeaponHolder Changes

Only the type changes and the optional break callback:

```gdscript
var current_weapon: WeaponBase = null
```

No other public API changes. `drop_weapon()` and `_on_pickup_body_entered()` continue to work because `WeaponBase` exposes the same methods as the old `Weapon`.

## 14. AI Attack Range

`ApproachEnemyState._is_in_attack_range()` currently uses `weapon.follow_offset.length() + weapon.attack_thrust_distance`. For ranged weapons we should use a much larger range. Add a helper in `WeaponBase`:

```gdscript
func get_attack_range() -> float:
    return _data.attack_thrust_distance   # melee
```

Override in `RangedWeapon`:

```gdscript
func get_attack_range() -> float:
    return _data.projectile_speed * _data.projectile_lifetime * 0.8
```

Then `ApproachEnemyState` can do:

```gdscript
if weapon:
    attack_reach = max(owner.attack_range, weapon.get_attack_range())
```

## 15. Arena / Spawn Changes

- Replace the two swords in `Scenes/arena.tscn` with a mix of weapons, or add all five weapons to test.
- Alternatively, keep existing swords and add new weapon pickups around the arena.
- Ensure each weapon scene has:
  - `RigidBody2D` with `WeaponBase` subclass script.
  - `collision_layer = 8` (weapon body).
  - `collision_mask = 11` (world + actors).
  - Visuals node with sprite, hand socket, and muzzle marker for guns.
  - Collision shape and `HitBox` Area2D for melee.

## 16. Actor-Movement Changes

Minimal:
- No changes needed to `_update_attack()` because it calls `weapon.attack()` and `WeaponBase` keeps that method.
- No input map changes.

## 17. Implementation Order

1. Create `WeaponData` resource.
2. Create `WeaponDatabase` autoload with the five weapon profiles.
3. Create `WeaponBase` from current `Weapon.gd`, removing stats/attack logic.
4. Create `MeleeWeapon` and move hit/cooldown/durability logic there.
5. Create `RangedWeapon` and `Projectile`.
6. Create `Sword`, `Spear`, `Fork`, `Pistol`, `Rifle` scripts/scenes.
7. Update `WeaponHolder` to type against `WeaponBase`.
8. Update `ApproachEnemyState` to use `get_attack_range()`.
9. Replace/update weapon pickups in `Scenes/arena.tscn`.
10. Run and tune.

## 18. Verification Steps

1. Each weapon can be picked up and dropped.
2. Sword slash visually arcs.
3. Spear and fork thrust straight forward.
4. Pistol and rifle fire projectiles that travel and damage enemies.
5. Melee durability decreases only on successful hits.
6. Ranged durability decreases per shot.
7. A weapon breaks after its durability uses and is removed.
8. AI can use melee and ranged weapons (range calculation updated).
9. Critical hits occasionally deal increased damage.

## 19. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Refactoring breaks existing sword behavior | Keep `WeaponBase` API compatible with old `Weapon`; test sword first after base migration. |
| Ranged AI feels unfair or broken | Use `get_attack_range()` so AI respects actual projectile travel distance; tune later. |
| Projectile hits the shooter | Spawn projectile slightly forward at a `Muzzle` marker and ignore `source` body. |
| Durability causes weapons to vanish too fast | Start with generous durability values and tune after play-testing. |
| Visual slash is hard to read | Keep the arc moderate (90°) and align it with the existing `SwordVisuals` node. |
