# Plan: Actor AI State Machine Rewrite

## 1. Goal

Replace the monolithic `Scripts/Components/AIController.gd` with a clean, class-based finite state machine (FSM) that drives the existing `Actor-Movement` controller through virtual inputs (`move_direction`, `wants_jump`, `wants_attack`, `wants_drop`, `aim_direction`).

The AI must keep working with the current RigidBody2D physics, weapon pickup, team system, health/respawn, and the existing arena layout — without adding new scene nodes to the actor beyond the existing `AIController`.

## 2. Non-Goals

- No change to player input handling.
- No change to weapon physics, combat math, or damage rules.
- No new dependencies or addons.
- No full A* pathfinder or NavigationRegion2D baking; navigation stays local and uses raycasts plus a small set of hand-placed stair waypoints.
- No animation system changes (the actor has no AnimationPlayer yet).
- No debug prints in the final AIController (see §14 Debug policy).

## 3. High-Level Architecture

```
Actor (RigidBody2D)
└── AIController (Node, Scripts/Components/AIController.gd)
    ├── StateMachine (RefCounted)
    │   └── current_state: State
    ├── Sensors (RefCounted)
    │   ├── finds weapons, enemies, threats
    │   ├── computes aim_direction
    ├── Pathfinder (RefCounted)
    │   └── combines raycast checks and stair waypoints to produce a navigation target
    ├── Navigator (RefCounted)
    │   └── turns a world target into move/jump/drop commands
    │       (with jump cooldown to prevent hop-spam)
    └── States (all RefCounted, one script each)
        ├── IdleState
        ├── SeekWeaponState
        ├── ApproachEnemyState
        ├── AttackState
        └── RetreatState
```

The StateMachine, Sensors, Navigator, and State instances are created in `AIController._ready()`. They are not scene nodes, so the actor scene stays unchanged except for the `AIController` script reference.

### Scene changes

- Add a `World/StairWaypoints` node group in `Scenes/arena.tscn` containing `Marker2D` nodes on each traversable stair/ramp. Each waypoint is tagged with a `target_level` metadata (`"bottom"`, `"mid"`, or `"top"`) so the pathfinder can build an ordered sequence for the full ramp. These replace the old `Stairs` markers and are consumed by the new `Pathfinder` helper.

## 4. File Layout

Keep `AIController` in place to avoid scene churn, and put the FSM library under a new `Scripts/AI/` folder:

```
Scripts/
├── AI/
│   ├── StateMachine.gd        # owns states and transitions
│   ├── State.gd               # abstract base class for all states
│   ├── Sensors.gd             # perception / world queries
│   ├── Pathfinder.gd          # waypoint + raycast target selection
│   ├── Navigator.gd           # movement-command generation from a target
│   └── States/
│       ├── IdleState.gd
│       ├── SeekWeaponState.gd
│       ├── ApproachEnemyState.gd
│       ├── AttackState.gd
│       └── RetreatState.gd
└── Components/
    └── AIController.gd        # rewritten, but same resource path
```

## 5. State Base Class

`Scripts/AI/State.gd`

```gdscript
class_name State
extends RefCounted

var machine: StateMachine = null

## Called once when the state becomes active.
func enter() -> void:
    pass

## Called once when the state is deactivated.
func exit() -> void:
    pass

## Mirrors _process. Meant for timers/logic that don't need physics.
func update(delta: float) -> String:
    return ""

## Mirrors _physics_process. Return a state name to transition, or "" to stay.
func physics_update(delta: float) -> String:
    return ""

func get_name() -> String:
    return "State"
```

States receive `machine` so they can call `machine.transition_to("SomeState")`. They read shared data and write virtual inputs through `machine.owner` (the AIController), which acts as the blackboard.

## 6. StateMachine

`Scripts/AI/StateMachine.gd`

```gdscript
class_name StateMachine
extends RefCounted

var owner: AIController
var current_state: State = null
var states: Dictionary = {}  # String -> State

func _init(ai_controller: AIController) -> void:
    owner = ai_controller

func register(name: String, state: State) -> void:
    states[name] = state
    state.machine = self

func transition_to(name: String) -> void:
    if not states.has(name):
        push_error("Unknown AI state: %s" % name)
        return
    if current_state:
        current_state.exit()
    current_state = states[name]
    current_state.enter()

func update(delta: float) -> void:
    if not current_state:
        return
    var next := current_state.update(delta)
    if next:
        transition_to(next)

func physics_update(delta: float) -> void:
    if not current_state:
        return
    var next := current_state.physics_update(delta)
    if next:
        transition_to(next)
```

The machine is built in `AIController._ready()` with the five concrete states. Initial state is `Idle`.

## 7. AIController (Owner / Blackboard)

`Scripts/Components/AIController.gd` keeps its public output variables so `Actor-Movement` does not need changes:

```gdscript
class_name AIController
extends Node

# Virtual inputs read by Actor-Movement.gd
var move_direction: float = 0.0
var wants_jump: bool = false
var wants_attack: bool = false
var wants_drop: bool = false
var aim_direction: Vector2 = Vector2.RIGHT

@export var is_ai: bool = true

@export_group("Sensing")
@export var detection_radius: float = 600.0
@export var weapon_seek_radius: float = 800.0
@export var reaction_time: float = 0.2
@export var target_switch_cooldown: float = 0.5

@export_group("Combat")
@export var attack_range: float = 80.0
@export var low_health_ratio: float = 0.3
@export var retreat_range: float = 120.0
@export var retreat_safe_distance: float = 250.0
@export var ai_attack_enabled: bool = true

@export_group("Navigation")
@export var layer_height_threshold: float = 50.0
@export var jump_height_threshold: float = 40.0
@export var drop_height_threshold: float = 60.0
@export var wall_check_distance: float = 24.0
@export var edge_check_depth: float = 60.0
@export var jump_cooldown: float = 0.4

var actor: RigidBody2D
var weapon_holder: WeaponHolder = null
var health: Health = null
var team_member: TeamMember = null

var sensors: Sensors
var pathfinder: Pathfinder
var navigator: Navigator
var machine: StateMachine
```

Responsibilities:
- Cache node references (`WeaponHolder`, `Health`, `TeamMember`).
- Build and own the state machine.
- Own Sensors and Navigator.
- React to external events (`team_changed`, `died`, `health_changed`, respawn) by invalidating targets and resetting to `Idle`.
- Disable itself for player actors (`is_player == true`).

Lifecycle:
```gdscript
func _ready() -> void:
    actor = get_parent() as RigidBody2D
    # disable for players
    if actor and "is_player" in actor and actor.is_player:
        is_ai = false
    _cache_components()
    sensors = Sensors.new(self)
    pathfinder = Pathfinder.new(self)
    navigator = Navigator.new(self)
    machine = StateMachine.new(self)
    _register_states()
    machine.transition_to("Idle")
    _connect_events()

var _was_dead: bool = false

func _physics_process(delta: float) -> void:
    if not is_ai or not actor:
        return

    # Detect respawn: Health disables process_mode on death and restores it later.
    if _was_dead and actor.process_mode != Node.PROCESS_MODE_DISABLED:
        _was_dead = false
        sensors.invalidate_targets()
        machine.transition_to("Idle")

    # reset one-shot inputs each tick; states set them
    wants_jump = false
    wants_attack = false
    wants_drop = false
    move_direction = 0.0

    sensors.update(delta)
    pathfinder.update(delta)
    navigator.update(delta)
    machine.physics_update(delta)
    _publish_aim()

func _process(delta: float) -> void:
    if not is_ai or not actor:
        return
    machine.update(delta)

func _publish_aim() -> void:
    aim_direction = sensors.aim_direction

func _cache_components() -> void:
    weapon_holder = actor.get_node_or_null("WeaponHolder") as WeaponHolder
    health = actor.get_node_or_null("Components/Health") as Health
    team_member = actor.get_node_or_null("Components/TeamMember") as TeamMember
    if health:
        health.died.connect(_on_actor_died)
```

### Event reactions

```gdscript
func _on_team_changed(_teams: Dictionary) -> void:
    sensors.invalidate_targets()
    machine.transition_to("Idle")

func _on_actor_died() -> void:
    _was_dead = true
    # process_mode will be disabled by Health; _physics_process detects respawn.

func _on_health_changed(current: float, max_health: float) -> void:
    # Let the current state react; Attack/Approach may choose to retreat.
    pass
```

## 8. Sensors

`Scripts/AI/Sensors.gd` is the perception layer. It runs every physics frame and provides clean data to states.

```gdscript
class_name Sensors
extends RefCounted

var owner: AIController

var nearest_enemy: Node2D = null
var nearest_weapon: Weapon = null
var aim_direction: Vector2 = Vector2.RIGHT
var is_grounded: bool = false
var wall_ahead: bool = false
var gap_ahead: bool = false
var platform_above: bool = false
var platform_below: bool = false

var _reaction_timer: float = 0.0
var _target_switch_timer: float = 0.0
var _unreachable_timer: float = 0.0
```

### Update flow

`func update(delta: float)` performs, in order:

1. Decrement `_reaction_timer`, `_target_switch_timer`.
2. When `_reaction_timer <= 0`, refresh enemy/weapon targets (subject to `_target_switch_timer`).
3. Update aim toward `nearest_enemy` if present, otherwise forward.
4. Update ground/wall/gap/platform flags via raycasts and contact normals.
5. Call `_track_unreachable(delta)`; if the enemy stays on a different vertical layer for too long, `is_target_unreachable()` returns true.

### Target selection

Targets are chosen by **nearest straight-line distance**. The AI is **sticky**: it keeps the current enemy unless that enemy becomes invalid (dead, same team, out of detection range), and target switching is gated by `target_switch_cooldown`.

```gdscript
const UNREACHABLE_TIMEOUT: float = 1.5

func refresh_targets() -> void:
    # Weapons: always pick nearest free weapon.
    nearest_weapon = _find_nearest_weapon()

    # Enemies: sticky. Only re-evaluate when the cooldown allows.
    if _target_switch_timer <= 0.0 or not _is_valid_target(nearest_enemy):
        var candidate := _find_nearest_enemy()
        if candidate != nearest_enemy:
            nearest_enemy = candidate
            _target_switch_timer = owner.target_switch_cooldown
            _unreachable_timer = 0.0

func _find_nearest_enemy() -> Node2D:
    var best: Node2D = null
    var best_dist := owner.detection_radius
    for a in owner.actor.get_tree().get_nodes_in_group("actors"):
        if a == owner.actor: continue
        if not _is_valid_target(a): continue
        var d := owner.actor.global_position.distance_to(a.global_position)
        if d < best_dist:
            best_dist = d
            best = a
    return best

func _is_valid_target(other: Node) -> bool:
    if not is_instance_valid(other):
        return false
    # ignore dead actors
    var health := other.get_node_or_null("Components/Health") as Health
    if health and health._is_dead:
        return false
    # ignore same team
    return not TeamMember.is_same_team(owner.actor, other)

func is_valid_target(other: Node) -> bool:
    return _is_valid_target(other)

func _track_unreachable(delta: float) -> void:
    if not nearest_enemy:
        _unreachable_timer = 0.0
        return
    var dy := nearest_enemy.global_position.y - owner.actor.global_position.y
    if abs(dy) > owner.layer_height_threshold:
        _unreachable_timer += delta
    else:
        _unreachable_timer = 0.0

func _find_nearest_weapon() -> Weapon:
    var best: Weapon = null
    var best_dist := owner.weapon_seek_radius
    for w in owner.actor.get_tree().get_nodes_in_group("weapons"):
        var weapon := w as Weapon
        if not weapon: continue
        if not is_instance_valid(weapon): continue
        if weapon.is_held(): continue
        var d := owner.actor.global_position.distance_to(weapon.global_position)
        if d < best_dist:
            best_dist = d
            best = weapon
    return best

func is_target_unreachable() -> bool:
    return _unreachable_timer > UNREACHABLE_TIMEOUT
```

### Environment sensing

Ground check mirrors `Actor-Movement._check_grounded_by_contacts()`:

```gdscript
func update_ground_state() -> void:
    var state := PhysicsServer2D.body_get_direct_state(owner.actor.get_rid())
    if not state:
        is_grounded = false
        return
    var up := Vector2.UP
    is_grounded = false
    for i in range(state.get_contact_count()):
        if state.get_contact_local_normal(i).dot(up) > 0.3:
            is_grounded = true
            return
```

Forward raycasts (using `direct_space_state.intersect_ray`):

```gdscript
func update_navigation_rays() -> void:
    var space := owner.actor.get_world_2d().direct_space_state
    var pos := owner.actor.global_position
    var dir := owner.actor.facing_direction
    var radius := 19.0  # actor capsule radius

    # Wall check: short horizontal ray from body edge.
    var wall_origin := pos + Vector2(dir * radius, 0)
    var wall_params := PhysicsRayQueryParameters2D.create(
        wall_origin,
        wall_origin + Vector2(dir * 24.0, 0),
        1 | 4  # world (layer 1) + one-way platforms (layer 3)
    )
    wall_ahead = space.intersect_ray(wall_params).size() > 0

    # Gap check: cast downward a short distance ahead.
    var gap_origin := pos + Vector2(dir * (radius + 16.0), 0)
    var gap_params := PhysicsRayQueryParameters2D.create(
        gap_origin,
        gap_origin + Vector2(0, 60),
        1 | 3
    )
    gap_ahead = space.intersect_ray(gap_params).size() == 0

    # Platform above: cast up and slightly forward.
    var up_origin := pos + Vector2(dir * 8.0, -radius)
    var up_params := PhysicsRayQueryParameters2D.create(
        up_origin,
        up_origin + Vector2(dir * 40.0, -120.0),
        1 | 3
    )
    platform_above = space.intersect_ray(up_params).size() > 0

    # Platform below: cast straight down to see if we can drop.
    var down_params := PhysicsRayQueryParameters2D.create(
        pos,
        pos + Vector2(0, 200),
        1 | 3
    )
    platform_below = space.intersect_ray(down_params).size() > 0
```

> Note: the actor's collision mask in `Scenes/actor.tscn` is `15` (layers 1–4). One-way platforms in the tilemap use layer 3. After respawn `Health._respawn()` sets mask to `11` (layers 1, 2, 4), which removes layer 3 and breaks one-way platform standing. We will fix that as part of this work: change the respawn mask back to `15`.

## 9. Pathfinder

`Scripts/AI/Pathfinder.gd` decides which point in the world the AI should move toward. For same-layer movement it returns the final target directly. For layer transitions it builds an ordered sequence of hand-placed stair waypoints and returns the waypoint the actor should head for right now.

The pathfinder uses hysteresis so that small vertical oscillations near a layer boundary do not flip the stair sequence:

- It commits to `"up"` only when the target is clearly above and the actor has not already reached the top of the stairs.
- It commits to `"down"` only when the target is clearly below and the actor has not already reached the bottom of the stairs.
- Once committed, it keeps the direction until the target is clearly on the same layer (or on the opposite layer, in which case it re-commits).

For a given direction it builds the sequence `[bottom, mid, top]` (up) or `[top, mid, bottom]` (down). The current waypoint is chosen by projecting the actor onto the stair polyline: when the actor is close to a segment it targets the forward waypoint of that segment; when far from the path it heads for the stair entry (first waypoint). Once the actor reaches the current waypoint and the target is on the same layer, or once it reaches the last waypoint, the stair plan is released and the actor navigates directly to the target.

```gdscript
class_name Pathfinder
extends RefCounted

var owner: AIController

const DIRECTION_SWITCH_BUFFER: float = 40.0
const WAYPOINT_REACHED_DIST: float = 50.0
const WAYPOINT_PASS_BUFFER: float = 20.0
const PATH_PROXIMITY: float = 80.0

func _init(ai_controller: AIController) -> void:
    owner = ai_controller

func get_move_target(final_target: Vector2) -> Vector2:
    # Returns final_target directly for same-layer targets, otherwise routes
    # through the ordered stair waypoint sequence.
    pass

func _build_sequence(direction: String) -> Array:
    # Returns [bottom, mid, top] for "up" or [top, mid, bottom] for "down".
    pass

func _select_target_waypoint(pos: Vector2, sequence: Array) -> Marker2D:
    # Projects pos onto the stair polyline and returns the appropriate next
    # waypoint, falling back to the entry waypoint when far from the path.
    pass

func _update_committed_direction(dy: float) -> void:
    # Two-threshold hysteresis, gated by the actor's position relative to the
    # top and bottom stair exits.
    pass

func _find_waypoint(level: String) -> Marker2D:
    # Finds the first marker in group "stair_waypoints" with matching
    # metadata "target_level".
    pass
```

States call `owner.pathfinder.get_move_target(target)` and pass the result to `owner.navigator.navigate_to(...)`.

## 10. Navigator

`Scripts/AI/Navigator.gd` turns a desired world destination (already chosen by `Pathfinder`) into movement commands.

It does **not** do pathfinding; it does local steering with platform detection, and it respects a jump cooldown so the AI doesn't hop-spam:

```gdscript
class_name Navigator
extends RefCounted

var owner: AIController

var _jump_timer: float = 0.0

## Returns suggested move_direction (-1..1), wants_jump, wants_drop.
func navigate_to(target: Vector2) -> Dictionary:
    var result := {"move_direction": 0.0, "wants_jump": false, "wants_drop": false}
    if not owner.actor:
        return result

    var pos := owner.actor.global_position
    var dir := sign(target.x - pos.x)
    var dy := target.y - pos.y
    var same_layer := abs(dy) <= owner.layer_height_threshold

    if dir == 0.0:
        return result

    # Horizontal movement.
    result.move_direction = dir

    # Facing should match movement direction while navigating.
    owner.actor.facing_direction = dir

    # Only request a jump if the cooldown has elapsed.
    var can_jump := _jump_timer <= 0.0 and owner.sensors.is_grounded

    # Wall in front while target is above us -> jump.
    if can_jump and owner.sensors.wall_ahead and dy < -owner.jump_height_threshold:
        result.wants_jump = true

    # Gap in front while target is on the other side -> jump.
    if can_jump and owner.sensors.gap_ahead and same_layer:
        result.wants_jump = true

    # Target is above and a platform is reachable -> jump.
    if can_jump and dy < -owner.jump_height_threshold and owner.sensors.platform_above:
        result.wants_jump = true

    # Target is significantly below and there is ground below -> drop.
    if dy > owner.drop_height_threshold and owner.sensors.platform_below and owner.sensors.is_grounded:
        result.wants_drop = true

    if result.wants_jump:
        _jump_timer = owner.jump_cooldown

    return result

func update(delta: float) -> void:
    if _jump_timer > 0.0:
        _jump_timer -= delta
```

Tunables come from AIController exports:
- `layer_height_threshold`
- `jump_height_threshold`
- `drop_height_threshold`
- `wall_check_distance`
- `edge_check_depth`
- `jump_cooldown`

These support local steering; `Pathfinder` handles layer transitions using the stair waypoints.

## 10. State Designs

All states read from `owner.sensors`, write to `owner.move_direction / wants_*`, and return a state name when they want to transition.

### IdleState

Entry: no movement, aim forward.

Transitions:
- If unarmed and a weapon exists within seek radius → `SeekWeapon`
- If armed and an enemy exists → `ApproachEnemy`
- If unarmed and an enemy is very close → `Retreat` (can't fight back)

```gdscript
func physics_update(delta: float) -> String:
    owner.move_direction = 0.0
    if not owner.sensors.nearest_weapon and not owner.sensors.nearest_enemy:
        return ""
    if owner.weapon_holder and not owner.weapon_holder.is_holding_weapon():
        if owner.sensors.nearest_weapon:
            return "SeekWeapon"
        if owner.sensors.nearest_enemy:
            return "Retreat"
    if owner.sensors.nearest_enemy:
        return "ApproachEnemy"
    return ""
```

### SeekWeaponState

Entry: pick target weapon (cached in Sensors).

Per-frame:
- Use `owner.pathfinder.get_move_target(weapon.global_position)` to choose the immediate movement goal, then `navigate_to(...)` to produce inputs.
- If weapon is no longer free (picked up by someone else) → `Idle`.
- If actor picks up a weapon (`owner.weapon_holder.is_holding_weapon()`) → `ApproachEnemy` or `Idle`.
- If an enemy is very close while unarmed → `Retreat`.

```gdscript
func physics_update(delta: float) -> String:
    var weapon := owner.sensors.nearest_weapon
    if not weapon or weapon.is_held():
        return "Idle"
    var move_target := owner.pathfinder.get_move_target(weapon.global_position)
    var cmd := owner.navigator.navigate_to(move_target)
    owner.move_direction = cmd.move_direction
    owner.wants_jump = cmd.wants_jump
    owner.wants_drop = cmd.wants_drop
    if owner.weapon_holder and owner.weapon_holder.is_holding_weapon():
        return "ApproachEnemy" if owner.sensors.nearest_enemy else "Idle"
    if owner.sensors.nearest_enemy and owner.actor.global_position.distance_to(owner.sensors.nearest_enemy.global_position) < owner.retreat_range:
        return "Retreat"
    return ""
```

### ApproachEnemyState

Entry: pick nearest enemy and reset the unreachable timer so the timeout measures active approach time, not total time the target has been far away.

Per-frame:
- Use `owner.pathfinder.get_move_target(enemy.global_position)` to choose the immediate movement goal, then `navigate_to(...)` to produce inputs.
- If no enemy or enemy invalid → `Idle`.
- If enemy stays on a different unreachable layer for too long → `Idle` (let the next tick pick a new goal).
- If in attack range and roughly facing enemy → `Attack`.
- If health is low and enemy is close → `Retreat`.

Attack-range detection should account for weapon reach. Use the held weapon's follow offset + thrust distance if available, otherwise fall back to `owner.attack_range`.

```gdscript
func _is_in_attack_range(enemy: Node2D) -> bool:
    var range := owner.attack_range
    var weapon := owner.weapon_holder.current_weapon if owner.weapon_holder else null
    if weapon:
        range = max(range, weapon.follow_offset.length() + weapon.attack_thrust_distance)
    return owner.actor.global_position.distance_to(enemy.global_position) <= range

func enter() -> void:
    owner.sensors.reset_unreachable()

func physics_update(delta: float) -> String:
    var enemy := owner.sensors.nearest_enemy
    if not enemy or not owner.sensors.is_valid_target(enemy):
        return "Idle"

    if owner.sensors.is_target_unreachable():
        return "Idle"

    var move_target := owner.pathfinder.get_move_target(enemy.global_position)
    var cmd := owner.navigator.navigate_to(move_target)
    owner.move_direction = cmd.move_direction
    owner.wants_jump = cmd.wants_jump
    owner.wants_drop = cmd.wants_drop

    var health_ratio := owner.health.current_health / owner.health.max_health
    var dist := owner.actor.global_position.distance_to(enemy.global_position)
    if health_ratio <= owner.low_health_ratio and dist <= owner.retreat_range:
        return "Retreat"

    var dx := enemy.global_position.x - owner.actor.global_position.x
    var facing_enemy := sign(dx) == owner.actor.facing_direction
    if facing_enemy and _is_in_attack_range(enemy):
        return "Attack"

    return ""
```

### AttackState

Entry: stop horizontal movement, face the enemy, set `wants_attack = true` once.

Per-frame:
- Keep facing enemy.
- Set `aim_direction` toward enemy (already done in Sensors).
- If enemy leaves attack range → `ApproachEnemy`.
- If no enemy → `Idle`.
- If health low and enemy close → `Retreat`.
- Do not spam attack; the weapon has its own cooldown. The state just sets `wants_attack` in `enter()` and waits a short minimum time before it can leave.

```gdscript
var _min_time: float = 0.25
var _timer: float = 0.0

func enter() -> void:
    owner.move_direction = 0.0
    owner.wants_attack = true
    _timer = _min_time

func physics_update(delta: float) -> String:
    _timer -= delta
    var enemy := owner.sensors.nearest_enemy
    if not enemy:
        return "Idle"
    # Face target
    var dx := enemy.global_position.x - owner.actor.global_position.x
    if dx != 0.0:
        owner.actor.facing_direction = sign(dx)
    if _timer <= 0.0 and not _is_in_attack_range(enemy):
        return "ApproachEnemy"
    return ""
```

### RetreatState

Entry: pick the nearest threat (enemy, or weapon-carrying enemy).

Per-frame:
- Move away from the threat (`-sign(threat.x - actor.x)`).
- Use the pathfinder if the run target crosses a different layer.
- Jump over gaps/walls if needed.
- If health is above threshold and threat is far → `Idle`.
- If unarmed and a weapon is nearby → `SeekWeapon`.

```gdscript
func physics_update(delta: float) -> String:
    var threat := owner.sensors.nearest_enemy
    if not threat:
        return "Idle"
    var dx := threat.global_position.x - owner.actor.global_position.x
    var away := -sign(dx)
    owner.actor.facing_direction = away
    var run_target := owner.pathfinder.get_move_target(owner.actor.global_position + Vector2(away * 100.0, 0.0))
    var cmd := owner.navigator.navigate_to(run_target)
    owner.move_direction = away
    owner.wants_jump = cmd.wants_jump
    owner.wants_drop = false
    if owner.sensors.nearest_weapon and not owner.weapon_holder.is_holding_weapon():
        return "SeekWeapon"
    var health_ratio := owner.health.current_health / owner.health.max_health
    if health_ratio > owner.low_health_ratio and abs(dx) > owner.retreat_safe_distance:
        return "Idle"
    return ""
```

## 11. State Transition Map

```
Idle
 ├── unarmed + weapon in range ───────► SeekWeapon
 ├── armed + enemy in range ──────────► ApproachEnemy
 └── unarmed + enemy too close ───────► Retreat

SeekWeapon
 ├── weapon picked up + enemy ────────► ApproachEnemy
 ├── weapon picked up, no enemy ──────► Idle
 ├── weapon gone / none ──────────────► Idle
 └── enemy too close while unarmed ───► Retreat

ApproachEnemy
 ├── in range + facing ───────────────► Attack
 ├── no enemy / invalid ──────────────► Idle
 └── low health + enemy close ────────► Retreat

Attack
 ├── enemy left range ────────────────► ApproachEnemy
 ├── no enemy ────────────────────────► Idle
 └── low health + enemy close ────────► Retreat

Retreat
 ├── health ok + enemy far ───────────► Idle
 ├── unarmed + weapon nearby ──────────► SeekWeapon
 └── enemy lost ──────────────────────► Idle
```

## 12. Changes to Existing Files

### `Scripts/Components/Health.gd`

Bug fix: respawn mask currently drops layer 3 (one-way platforms).

Change line 121 from:
```gdscript
_actor.set_deferred("collision_mask", 11)
```
to:
```gdscript
_actor.set_deferred("collision_mask", 15)
```

This restores the original arena-scene mask (`15 = layers 1–4`).

### `Scripts/Actor-Movement.gd`

Add a public accessor so the AI doesn't duplicate ground-check logic:

```gdscript
func is_grounded() -> bool:
    return _is_grounded
```

This is read-only and does not change behavior. Sensors can still do its own contact check as a fallback.

No other changes to `Actor-Movement.gd` are required because it already reads the AIController's public variables. The one-way drop duration was also changed from `0.25` to `0.3` seconds.

### `Scenes/actor.tscn`

No structural changes. The `AIController` node keeps its existing script path (`Scripts/Components/AIController.gd`). We only rewrite the script content.

### `Scenes/arena.tscn`

Add a `World/StairWaypoints` node containing `Marker2D` children for every traversable stair/ramp. Each marker has:
- `add_to_group("stair_waypoints")` (or is placed in that group via the Inspector).
- metadata `target_level = "top"` for the upper end of the stair.
- metadata `target_level = "mid"` for an intermediate landing if the ramp is long.
- metadata `target_level = "bottom"` for the lower end of the stair.

The pathfinder uses these to build an ordered sequence for the full ramp. The old `World/Stairs` markers are removed/replaced by this explicit system.

## 13. Scene / Project Settings

No new nodes, no autoloads, no input map changes, no debug exports.

## 14. Configuration Exports on AIController

```gdscript
@export_group("Sensing")
@export var detection_radius: float = 600.0
@export var weapon_seek_radius: float = 800.0
@export var reaction_time: float = 0.2
@export var target_switch_cooldown: float = 0.5

@export_group("Combat")
@export var attack_range: float = 80.0
@export var low_health_ratio: float = 0.3
@export var retreat_range: float = 120.0
@export var retreat_safe_distance: float = 250.0
@export var ai_attack_enabled: bool = true

@export_group("Navigation")
@export var layer_height_threshold: float = 50.0
@export var jump_height_threshold: float = 40.0
@export var drop_height_threshold: float = 60.0
@export var wall_check_distance: float = 24.0
@export var edge_check_depth: float = 60.0
@export var jump_cooldown: float = 0.4
```

These are roughly equivalent to the old AIController exports, renamed for clarity.

## 15. Debug Policy

The final `AIController` and all AI library scripts contain **no print statements**. A stray player-only drop debug print in `Actor-Movement.gd` was also removed. All tuning is done through exported variables in the Inspector. If visual debugging is needed later, it will be added as an optional `_draw()` overlay, not as console spam.

## 16. Implementation Order

1. **Create `Scripts/AI/State.gd`** — base class.
2. **Create `Scripts/AI/StateMachine.gd`** — transition logic.
3. **Create `Scripts/AI/Sensors.gd`** — target finding + environment rays.
4. **Create `Scripts/AI/Pathfinder.gd`** — waypoint + layer routing.
5. **Create `Scripts/AI/Navigator.gd`** — movement-command generation.
6. **Create the five state classes** in `Scripts/AI/States/`.
7. **Rewrite `Scripts/Components/AIController.gd`** — wire everything together, keep public output vars.
8. **Fix `Health._respawn()` collision mask** (11 → 15).
9. **Add `Actor-Movement.is_grounded()` accessor**.
10. **Add `World/StairWaypoints` markers** to `Scenes/arena.tscn`.
11. **Run the game** and observe AI behavior.
12. **Tune exports** (attack range, retreat range, ray distances, waypoint positions) until AI can cross stairs and fight.

## 17. Verification Steps

1. Launch the arena with one player and one AI.
2. Unarmed AI walks to the sword, picks it up.
3. Armed AI chases the player across the arena, including the stair platform.
4. AI attacks when close enough.
5. When teams change, AI stops attacking same-color allies and retargets.
6. AI retreats when low HP.
7. After the AI dies and respawns, it returns to Idle and resumes behavior.
8. Player movement and input are unchanged.

## 18. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Raycast navigation fails on the existing stairs | Use `World/StairWaypoints` markers for layer transitions; tune `layer_height_threshold` and `jump_height_threshold` in the editor if still needed. |
| AI gets stuck in state loops | Force `Idle` on target loss / team change / respawn; keep state transition map explicit. |
| Attack range too short / too long | Read weapon-specific reach and expose `attack_range` export; tune visually. |
| Respawn mask fix breaks something | The original scene mask is 15; restoring it only fixes the bug introduced by `_respawn()`. |
| RefCounted states garbage-collected while in use | Keep references in `StateMachine.states` dictionary and `AIController` holds the machine. |

## 19. Future Extensions (out of scope)

- Patrol state with waypoints.
- Recover/hit-stun state.
- Hierarchical FSM (e.g., `Combat` super-state with `Approach/Attack/Retreat` substates) if states grow.
- Debug draw overlay for raycasts and current state label.
- AI difficulty presets via exported profiles.
