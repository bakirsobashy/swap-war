# Trust No One — Game Development Plan

## Game Pitch
A chaotic single-screen 2D physics platformer fighter for the Brackeys Game Jam.
2–4 capsule characters share an arena. Every 5 seconds, everyone’s team color randomizes.
Same color = allies (no damage). Different color = enemies (score on kill).
1–2 human players plus AI fill the arena. Since human players are part of the random pool,
you can suddenly become enemies with the person sitting next to you — that is the theme.

## Core Loop
- Spawn all actors in a tilemap arena.
- Free-for-all / team-swapping combat.
- Score by killing actors on different team colors.
- Win by score target, timed score, or last-team-standing.

## Movement Design (Final)
- `RigidBody2D` with `lock_rotation = true`.
- Movement is force/impulse based for physics feel.
- The goofy “butt moves first” look is achieved purely in the `VisualBody` child node:
  position lags behind velocity and rotation leans into movement.
- No free-rotation upright torque battle — stable and controllable.

## Scene Architecture

### `Arena.tscn`
```
Arena (Node2D)
├── World
│   ├── TileMapLayer              # platforms, walls, hazards
│   ├── KillZones (Area2D)        # pits / out of bounds
│   └── SpawnPoints (Node2D)
│       ├── Marker2D
│       ├── Marker2D
│       └── ...
├── Actors (Node2D)               # spawned at runtime
├── Camera2D
├── Effects (Node2D)              # particles, trails
└── HUD (CanvasLayer)
    ├── TeamTimerLabel
    ├── ScoreBoard
    ├── ActorHealthBars           # spawned per actor
    └── WinnerMessage
```

### `Actor.tscn` (single scene for player + AI)
```
Actor (RigidBody2D)
├── CollisionShape2D              # CapsuleShape2D, vertical
├── GroundCheck (RayCast2D)       # jump + grounded state
├── VisualBody (Node2D)           # lags behind physics body
│   └── Sprite2D                  # color-tinted capsule sprite, rotated 90°
├── Hitbox (Area2D)               # active during attack
├── Hurtbox (Area2D)
└── Components (Node)
    ├── Health                    # damage / death / respawn
    ├── TeamMember                # team id + color update
    └── Combatant                 # attack state + cooldown
```

### Autoloads
- `TeamManager` — 5-second timer, assigns random teams, emits `team_changed`
- `ScoreManager` — tracks kills per actor
- `AudioManager` (optional) — global music / SFX bus control

## Core Systems

### 1. RigidBody2D Movement
Use `_integrate_forces(state)`.

- **Run:** `apply_force(Vector2(input_x * run_force, 0))`, cap `linear_velocity.x`
- **Jump:** `apply_central_impulse(Vector2(0, -jump_impulse))` when grounded
- **Air control:** weaker force via `air_force_multiplier`
- **Friction:** manual `linear_velocity.x *= friction` per tick (ground vs air)
- **Ground check:** RayCast2D from bottom of capsule
- Settings: `lock_rotation = true`, `can_sleep = false`, low friction, zero bounce

### 2. Visual Body Lag & Lean
`VisualBody` is a child `Node2D`:
- Position lerps toward a small offset opposite to velocity (butt drag).
- Rotation lerps toward a lean angle derived from horizontal velocity.
- Facing direction controlled by `VisualBody.scale.x`.
- Sprite itself rotated 90° because the Kenney capsule texture is drawn horizontally.

### 3. Combat
- Attack button enters attack state for ~0.3 s.
- Hitbox `Area2D` enabled for ~0.12 s in front of actor.
- On `area_entered` against a Hurtbox:
  - Check `TeamMember.is_same_team(other)` → ignore if true
  - Otherwise: deal damage, apply knockback impulse, screenshake, hit flash
- Damage ~30 HP, max HP 100 → 3–4 hits to kill
- Death → particles → respawn after ~1.5 s with brief invulnerability

### 4. Team System
`TeamManager` autoload:
- Timer set to 5 s, looping
- On timeout: assign each actor a random team from a small pool (e.g., Red, Blue, Green)
- Emit `team_changed(teams: Dictionary[actor, team_id])`
- Each `TeamMember` updates sprite `modulate`
- UI plays sound + flash to telegraph the swap

### 5. AI
`AIController` attached to AI actors with states:
- **Idle** — hop in place
- **Patrol** — walk toward a random point
- **ChaseEnemy** — find nearest actor on a different team
- **Attack** — close distance and press attack
- **Retreat** — run from nearby enemy if low HP

AI retargets immediately when teams change.

### 6. Win / Round Flow
`ArenaManager` node:
- Spawn all actors at `Marker2D` spawn points
- Start `TeamManager` timer
- Listen for kills, update score
- Detect win condition → show winner → offer restart

## Collision Layers (suggested)
| Layer | Use |
|-------|-----|
| 1 | World / platforms |
| 2 | Actor bodies |
| 3 | Hitboxes |
| 4 | Hurtboxes |
| 5 | KillZones |

Hitbox mask = layer 4 only. Hurtbox mask = layer 3 only. Actor body mask = layer 1 + 2.

## Input Mapping
Player 1:
- `Move_Left` — A / Left Arrow
- `Move_Right` — D / Right Arrow
- `Jump` — W / Up Arrow / Space
- `Attack` — J / Right Ctrl

Player 2:
- `P2_Left` / `P2_Right`
- `P2_Jump`
- `P2_Attack`

## 7-Day Implementation Schedule

### Day 1 — Stable Physics Actor
- Set collision layers.
- Build `Actor.tscn` with capsule collision, RayCast2D ground check, laggy `VisualBody`.
- Implement `_integrate_forces()` run/jump/friction logic.
- Build a test arena floor + walls.
- Camera follows Player 1.

**Skills:** `physics-system`, `player-controller`, `2d-essentials`

### Day 2 — Combat
- Create `Health` component (max HP, `take_damage`, `died` signal).
- Create `Hitbox`/`Hurtbox` component pattern.
- Attack state + timed hitbox.
- Knockback via `apply_central_impulse()`.
- Death → particles → respawn.
- Add a second actor for 2P testing.

**Skills:** `component-system`, `physics-system`

### Day 3 — Team System + AI
- Create `TeamManager` autoload.
- Create `TeamMember` component.
- Implement 5-second color randomization.
- Disable friendly fire.
- Create `AIController` with state machine.
- Spawn system for 2–4 actors.

**Skills:** `state-machine`, `component-system`, `event-bus`

### Day 4 — Arena + Hazards
- Build one complete arena with TileMapLayer.
- Add KillZones (pits), spike hazards.
- Add a moving platform if time (`AnimatableBody2D`).
- Camera bounds / death plane.

**Skills:** `2d-essentials`, `physics-system`

### Day 5 — UI, Audio, Juice
- HUD: team timer, health bars, scoreboard, winner text.
- Main menu + pause menu.
- SFX: jump, land, punch, hit, death, team-swap cue.
- Background music.
- Screenshake, hit flash, death particles, landing dust.
- Short freeze-frame on kill.

**Skills:** `godot-ui`, `hud-system`, `audio-system`, `particles-vfx`

### Day 6 — Playtest + Balance
- Tune physics: mass, force, damping, friction.
- Tune AI: range, reaction time, jump logic.
- Test local multiplayer input mapping.
- Build 2nd / 3rd arena if time.
- Bug fixing.

**Skills:** `input-handling`, `godot-debugging`

### Day 7 — Export + Submit
- Web export (primary for jams).
- Windows export as backup.
- Itch.io page with controls + theme statement.
- Final balance pass.
- Submit to Brackeys Jam.

**Skills:** `export-pipeline`

## Team Swap UX
Add a strong audiovisual cue when teams change:
- Sound cue
- Flash each actor to new color
- HUD countdown shows next swap
Without this, the swap feels unfair instead of fun.

## Risk Mitigation
- If movement is too slidey, raise `ground_friction`.
- If too slow, raise `run_force` or `max_run_speed`.
- If 4 actors is chaotic, default to 3.
- If AI is too hard, reduce their attack range and give them a reaction delay.
- Joints/chain weapon only if Day 5+ tasks are already done.

## Stretch Goals (after core works)
- Chain/flail weapon using `PinJoint2D`
- Powerups (speed boost, shield)
- More arenas
- AI difficulty variants
