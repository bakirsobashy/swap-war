# Decisions

The choices behind Swap-War, one entry each: the situation, what was decided, and what it costs.

## 1. Fighters are rigid bodies moved by forces

**Context.** The jam pitch was a goofy physics brawler: hits should shove bodies around, and fighters should wobble rather than move like a tidy platformer character.

**Decision.** Each fighter is a `RigidBody2D` with rotation locked. Movement is applied in `_integrate_forces` with forces and impulses, never by writing `linear_velocity` for walking; horizontal speed is capped by clamping it. The wobble ("the butt moves first") is purely visual: a child `VisualBody` lags behind the velocity and leans into it, so the physics body stays stable and easy to control.

**Consequences.** Knockback, weapon contact damage and being thrown off ledges come for free from the physics engine. In exchange, movement is harder to tune than a `CharacterBody2D`: friction and ground detection are written by hand (contact normals in `_integrate_forces`, a ray for one-way slopes), and tests that need a still target have to freeze it, because bodies drift under contact.

## 2. The AI bakes a graph from the tiles instead of using waypoints

**Context.** The first AI followed hand-placed waypoints (`Pathfinder.gd`). Every arena needed its own hand-placed waypoint groups, and every new need (several routes up the stairs, avoiding spikes, knowing what a jump can reach) meant more hand-placed data.

**Decision.** Rebuild navigation around a graph baked from each arena's `TileMapLayer` when it loads. Runs of floor become platforms; pairs of platforms become edges (walk, jump up, jump across, drop down) if the jump physics can make it, with limits taken from measured jump heights and distances and a safety margin. Hazard areas split platforms and add cost, and A\* plans over the result. Marker nodes in the scene (`block`, `force_link`, `hazard_region`) correct the bake by hand where it's wrong.

**Consequences.** A new arena gets navigation automatically, and the bots route around spikes by jumping them. The cost is code: the graph, baker, A\* and route executor are about 1,800 lines, and the executor needs a stuck-recovery ladder (micro-jump, replan, blacklist the failed edge for 3 seconds) because a physics body doesn't always land where the graph expects. The old waypoint plan is kept in the roadmap for history, marked as superseded.

## 3. Decisions in a state machine, movement in the route executor

**Context.** Bots need to pick goals (get a weapon, chase someone, run away) and also execute movement precisely. Mixing both in one script made every behaviour change risky.

**Decision.** Split them. Six states (Idle, Patrol, SeekWeapon, ApproachEnemy, Attack, Retreat) choose a goal; the route executor owns move, jump and drop while a route is active; a hazard-escape override runs last and wins over everything. The AI writes to the same virtual inputs a player presses, so bots use the player's movement and combat code. All tuning lives in one table, `AIDifficulty.gd`.

**Consequences.** States stay short (45 to 150 lines each) and can be tested one at a time. Direct moves that skip the router, like kiting, must go through `AIController.safe_move`, which refuses steps off a deadly ledge or into a hazard; forgetting that is the main way to reintroduce old bugs. There is one difficulty profile so far; more are new rows in the table.

## 4. Preview the swap before it happens

**Context.** Teams are re-rolled every 10 seconds. Without a warning, your ally can turn into an enemy and hit you on the very next frame, which feels random rather than tense.

**Decision.** `TeamManager` rolls the next teams 2 seconds early and announces them. The HUD timer and an arrow over each fighter show the colour they're about to become, and the swap then applies exactly the roll that was shown. Bots get a short reaction window after the swap in which they hold their state instead of resetting, then re-target.

**Consequences.** Players can see the betrayal coming and back off, which turns the swap into a decision instead of a coin flip. Rolling early needs care: the pre-roll must still guarantee at least two teams, and a stopped timer or restarted match must clear the preview. `swap_preview_probe` checks all of that.

## 5. Headless probe scripts instead of a unit-test framework

**Context.** Most bugs worth catching only show up in a live match: physics, timers, signals between autoloads, AI decisions over many frames. A unit-test framework would mostly test functions in isolation.

**Decision.** Write probe scripts in `Tools/` that boot real arenas headless with `godot --headless -s`, run live matches or targeted scenarios, and exit non-zero on failure. A runner (`run_probes.ps1`, `run_probes.sh`) also fails any probe that printed a `SCRIPT ERROR`, because a script error only aborts the current function and can leave a crashed probe exiting 0. Every bug reproduced in the October 2026 audit has a probe that replays it. CI runs the whole suite on every push and pull request.

**Consequences.** The probes test what players actually see, at the cost of speed (the full suite takes a few minutes) and some non-determinism: a live-physics AI probe can occasionally fail on a borderline jump. CI reruns a failed probe once and reports it as flaky with a warning, rather than hiding it or turning the build red for noise. Probes also follow a few rules because `-s` scripts compile before autoloads exist: load scripts at runtime, no typed references to game classes, and reach autoloads through guarded node paths.
