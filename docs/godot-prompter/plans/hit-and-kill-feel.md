# Plan: hit & kill feel (impact juice + persistent kill stains)

**Status:** phase 1 implemented (needs the probe suite run on a Godot machine, and the Splat Pack pushed); phases 2–3 planned. **Date:** 2026-10-30.

**Decisions (2026-10-30):** stains use the **victim's** colour; off-map deaths get an **edge splash, no stain**; hit-stop is **player-involved only**; the screen-shake toggle ships with the phase 3 settings work (phase 1 shake is gated to the player's fights and kept modest). Splat Pack lives at `Assets/vfx/PNG/`.

## Goals

1. **Hits feel like they land.** A hit you deal or take should be readable and satisfying, and a crit should look and sound different from a normal hit.
2. **Kills are a moment.** A short beat that sells the kill, and confirms it when the kill is yours.
3. **Kill stains (your idea).** Each kill leaves a splat in the victim's colour on the arena background. Stains stay until the match ends, so the arena builds up a painted record of the fight.

Out of scope: weapon balance, knockback values, hitstun (a gameplay change), and the follow camera the 62×62-tile arenas will need. The camera shake is designed so a follow camera can be added on top later.

---

## What a hit / kill does today

- **Hit** (`Health.take_damage`, `Scripts/Components/Health.gd:39`):
  - The sprite is flashed with modulate `1.8` for 0.08 s. On a coloured texture this only brightens it; it never reaches a white flash.
  - 8 **yellow** particles always fly **up**, whatever the hit direction.
  - A floating number in the victim's colour.
  - `play_hit()`, a synthesized placeholder sound.
  - A knockback impulse.
- **Crits** do 1.5× damage and nothing else, so you can't tell a crit from a normal hit.
- **Kill** (`Health.die`): the actor disappears on the same frame, 24 team-colour particles burst, `play_death()` (placeholder) plays, and the actor respawns 1.5 s later. There is no pause and no camera reaction. The killer gets nothing except the scoreboard number going up.
- **Camera:** a static `Camera2D` with no script (`ArenaBase.tscn:233`, zoom 0.55–0.635).
- `Projectile` plays the **actor** hit sound when it hits walls too, so "did I hit?" is ambiguous.
- `take_damage` never learns the hit direction or crit flag, so none of the effects can be directional.

## Verdict on the stain idea: yes

It fits this game better than most games:

- **Team swaps make it a story.** A stain records the victim's colour *at the moment of death*. After a few reshuffles the arena reads as a history of the match: green died here, then red, then green again.
- **It's cheap.** One sprite per kill and no per-frame cost.
- **Kenney / CC0** matches the art we already use (the Kenney fighters, the Kenney-style kit).
- It gives the kill moment a natural **"SPLAT"** beat, which the rest of this plan builds on.

The risks, and how this plan handles them:

| Risk | Mitigation |
|------|------------|
| Stains get confused with live team colour (an actor standing on a stain of its own colour) | Stains sit behind the tiles, at about 0.7 alpha, and are pushed slightly toward ink, so they read as paint rather than as an actor |
| Clutter at choke points and the spike strip | Random variant, flip, rotation and scale; a hard cap with the oldest stain fading out |
| Deaths off the map leave nowhere sensible for a stain | No stain; a splash at the screen edge instead (open question 2) |
| Performance on web/Android | Plain `Sprite2D`s from one atlas, batched, with a cap. **No** paint-canvas `SubViewport`: a 62×62 × 62 px arena is a 3844² render target, about 59 MB of VRAM |

---

## Design

### 0. Hit context (plumbing)

- `Health.take_damage(amount, attacker = null, hit_dir := Vector2.ZERO, is_critical := false)`. The new parameters are optional and trailing, so `HazardArea` and the probes keep working unchanged.
  - **Melee** computes the knockback direction *before* the call (split `_knockback_dir(body)` out of `_apply_knockback`) and passes it in, together with `is_critical`.
  - **Projectile** passes `_velocity.normalized()` and its crit roll.
  - **Hazard** passes `Vector2.UP`.
- Health remembers `_last_hit_dir` for `die()`.
- `Health.die(off_map := false)`. `KillZone` passes `true`. Everything else is unchanged, including the hide, the drop, the 1.5 s await and the respawn contract.
- Any effect that needs the actor is spawned **before** the await in `die()`, and never touches the actor after it (this keeps `death_free_probe` safe).

### 1. `HitFeel` autoload: one entry point, one tuning table

New `Scripts/Components/HitFeel.gd`, registered as an autoload after `AudioManager`.

- `on_hit(victim, attacker, amount, dir, is_crit)` and `on_kill(victim, killer, dir, off_map)`. Health calls these with guards, the same way it already calls `AudioManager`. They fan out to hit-stop, shake, `ImpactFX`, `StainLayer` and audio.
- A `TUNING` dictionary owns every number. It works like `AIDifficulty`: there is a single table to tweak.
- `enabled` is a kill-switch. Timing-sensitive probes switch it off, the same way `AIController.nav_enabled` works.

**Hit-stop** sets `Engine.time_scale = 0.05` for N real milliseconds, using a timer that ignores time scale and keeps running while paused.

- Overlapping requests extend the stop to the latest end time. They never add up.
- Time scale is forced back to 1.0 on pause, on post-round, on scene change and in `_exit_tree`. A real-clock check in `_process` acts as a safety net.
- Time scale also slows UI tweens, so a time scale that got stuck would be very visible. That is why the restore is defended on every path.

**When it fires.** Hit-stop is for **the player's own fights only**. With 3 to 7 AIs hitting each other constantly, a freeze on every AI hit would feel like lag, and it would also slow the swap clock.

| Event | Hit-stop | Shake (trauma) |
|-------|----------|----------------|
| AI hits AI | — | — |
| Player hits an enemy | 45 ms | 0.15 |
| Player gets hit | 60 ms | 0.30 |
| Crit involving the player | 85 ms | +0.15 |
| AI kills AI (on screen) | — | 0.10 |
| Player gets a kill / dies | 120 ms | 0.45 |

### 2. Camera shake: `Scripts/Arena/ArenaCamera.gd`

The script goes on `ArenaBase`'s `Camera2D`.

- It uses the trauma model: `shake = trauma²`, trauma decays at about 1.6/s, and the offset is sampled from noise.
- The maximum offset is set in **screen px divided by zoom**, so the shake looks the same in every arena.
- It moves the offset only, with **no rotation**. The whole arena is framed, and rotating would show the empty space past the walls.
- It runs on unscaled time, so the shake keeps moving during a hit-stop. Shaking through the freeze is what sells the impact.
- It writes to `offset` as an additive layer, so a later follow camera (driving `position`) composes with it.
- New setting `SettingsManager.screen_shake_enabled` (default on), with a toggle row in Settings for accessibility.

### 3. Victim reaction (per actor, no global cost)

- **A real white flash.** A `canvas_item` shader (`Assets/Shaders/hit_flash.gdshader`, `uniform float flash`, which mixes the texture toward white) on a per-actor local material. It goes full white for one frame, then fades out over about 80 ms.
  - This **replaces** the modulate flash and its timer-restore lambda. Modulate then belongs only to the invulnerability flicker, which removes the "a flash restores the other flash" class of bug.
- **Kick and squash.** `Actor_Body.gd` gets `punch(dir, strength)`.
  - The visual body kicks up to 8 px along `dir` and squashes to about (1.2, 0.85).
  - It springs back over about 0.15 s.
  - The kick is added to the existing lag-target offset, so the lean and the lag still work.

### 4. Impact particles: `Scripts/FX/ImpactFX.gd`

This replaces the two ad-hoc `CPUParticles2D.new()` builders in Health with small configured scenes: `Scenes/FX/HitBurst.tscn` and `Scenes/FX/KillBurst.tscn`. They stay `CPUParticles2D`, because web and Android exports use the Compatibility renderer.

- **Hit:**
  - 6–10 droplets in the victim's colour, using the splat pack's small drop sprites as the particle texture.
  - They spray in a ±35° cone around `hit_dir`, with gravity, and live for 0.35 s.
  - One ink-outlined white "impact star" appears at the contact point for 60 ms (drawn in code, like `TeamDot`).
- **Crit:**
  - Twice the droplets and a bigger star.
  - `FloatingNumber.start(..., is_critical)` pops larger and adds a "!" in the Notebook Doodle style.
- **Kill: the death pop.**
  1. A puppet `Sprite2D` (a copy of the victim's body texture, with the flash shader at 1.0) is spawned in `Effects` at the death spot.
  2. It scales from 1 to 1.25 over 60 ms.
  3. It then bursts into 20–30 droplets across the `hit_dir` hemisphere, and the stain lands at the same time.
  - The puppet lives in `Effects`, so Health's hide/respawn logic is untouched. `_clear_match_leftovers` already wipes `Effects`.

### 5. Kill stains: `Scripts/FX/StainLayer.gd`

A `Stains` Node2D is added to `ArenaBase.tscn` with `z_index = -1`. In `ArenaFlat`, set `Background.z_index = -2` explicitly so the draw order never depends on tree order. The resulting order is: **Background → Stains → World (tiles) → Actors → Effects.**

`add_stain(pos, color, dir)`:
- **Variant:** a random splat from one atlas, so all stains batch into a single draw.
- **Orientation:** a random flip. Directional splashes are rotated along `dir` with ±20° of jitter.
- **Scale:** 0.8–1.2 × base. Base size is about 1.6× the actor's diameter, so it reads at a 0.55 zoom.
- **Colour:** the victim's `TeamPalette` colour **at death**, pushed slightly toward ink (`color.lerp(INK, 0.15)`), at about 0.7 alpha.
- **Position:** the victim's centre plus a short offset along `dir`, so the paint lands where the blow sprays.
- **Landing animation:** scale 0.3 → 1.08 → 1.0 (`TRANS_BACK`, 0.12 s). After that there's no `_process`; the stain is a static sprite.

Lifetime and cleanup:
- **Cap:** 150 stains, set in `TUNING`. Past the cap, the oldest stain fades out over 1 s and is freed. A 2-minute 4-actor match produces about 20–60 kills, so the cap is only a safety net for 8 actors over 10 minutes.
- **Clearing:** `ArenaManager._clear_match_leftovers()` calls `StainLayer.clear()`, so Play Again starts clean. Otherwise the stains are freed along with the arena.
- **Behind the tiles on purpose:** a kill on a platform is half-hidden by the floor and reads as "splattered on the wall behind". A floor decal drawn over the tiles is a possible later addition, not part of v1.
- **Spike-strip kills** leave stains on the spikes, which is free storytelling.
- **Off-map deaths (KillZone):** no stain, but a droplet burst at the bottom edge of the view at the x where the actor fell, so the kill still lands.

**Asset import.**
- Copy only the splats we use into `Assets/FX/splat/` (with the pack's CC0 `License.txt`), packed into one atlas. Don't drop the whole pack in, for the same reason the UI kit's extras are `.gdignore`d.
- The art must be **white-on-alpha** so `modulate` tints it to exactly the `TeamPalette` colour. If the pack's PNGs come pre-coloured, convert them to white once, offline.
- *To check: I couldn't open the Kenney or itch pages from the session's network, so the pack's colours, sizes and drop sprites are still unconfirmed.*

### 6. Audio

- **Replace the synthesized placeholders.**
  - `hit`: 2–3 punchy variants.
  - `crit`: heavier.
  - `kill`: a wet splat layered over a short low thump.
  - Kenney's *Impact Sounds* (CC0) has candidates.
- **New call:** `play_hit(strength, involves_player)`.
  - AI-vs-AI hits play about 6 dB quieter.
  - At most 4 hit voices play at once. Today every call spawns a new `AudioStreamPlayer`, so an 8-actor brawl stacks them up.
- **Projectile wall impacts** get their own quieter thud instead of the actor-hit sound.

### 7. Kill confirmation

- **Killer chip:** a "+1" chip pops above the killer in the killer's colour (Cabin Sketch, ink outline). It shows for every kill, and is bigger when the player is the killer.
- **Scoreboard:** on `score_changed`, the HUD row gives a short scale bump (1.15 → 1.0).

---

## Phases (each one can ship on its own)

1. **The kill moment.**
   - Hit context plumbing, the `HitFeel` autoload, hit-stop, `ArenaCamera` shake, the death pop and `StainLayer` with the splat art.
   - This phase gives the most impact per line of code.
2. **Hit polish.**
   - The flash shader, kick and squash, directional droplets and the impact star, and the crit feedback.
3. **Audio and confirmation.**
   - New sounds and voice limiting, the "+1" chip, the scoreboard bump, and the screen-shake setting.

## Testing

New `Tools/hit_feel_probe.gd`, added to `run_probes.ps1` and to the CLAUDE.md probe list.

- **Hit-stop:**
  - `Engine.time_scale` returns to exactly 1.0 after a hit, and after overlapping hits (the stop lasts until the latest end time; durations never add up).
  - It also returns to 1.0 when the match pauses, ends or changes scene during a stop.
  - AI-vs-AI hits never touch time scale.
- **Shake:** the offset decays back to zero, and stays at zero while the setting is off.
- **Stains:**
  - A damage kill adds exactly one stain at the death spot, in the victim's colour at death.
  - The stain keeps its colour through respawn and through the next team swap.
  - A KillZone death adds no stain.
  - The cap removes the oldest stain first.
  - `restart_match()` clears all stains.
- **Plumbing:** `hit_dir` and `is_critical` reach `ImpactFX` and `FloatingNumber`. A death while the actor is freed mid-await throws no errors (extends the `death_free_probe` scenario).
- **Regressions:** all existing probes still pass. The timing-sensitive ones (`hazard_damage_probe` pacing, `decision_probe`, `auto_attack_probe`) run with `HitFeel.enabled = false`, set through a guarded `/root/HitFeel` lookup.

## Open questions (answered 2026-10-30)

1. **Stain colour:** victim's.
2. **Off-map deaths:** edge splash, no stain.
3. **Hit-stop scope:** player-involved only.
4. **Screen-shake toggle:** phase 3, with the other settings work.
5. **Splat Pack:** added locally at `Assets/vfx/PNG/`, not pushed yet. Still to check once it's in the repo: white vs pre-coloured PNGs, and which files are splats vs drops (StainLayer loads every PNG in the folder for now; curate after).

## Phase 1 as built

- `Health.take_damage(amount, attacker, hit_dir, is_critical)` / `Health.die(off_map)`; melee, projectile and hazard pass their knockback direction, KillZone passes `off_map = true`.
- `HitFeel` autoload (registered last in `project.godot`): `on_hit` / `on_kill`, `TUNING`, `enabled`, `hitstop_enabled` (defaults off under headless — see CLAUDE.md gotchas).
- `ArenaCamera.gd` on ArenaBase's `Camera2D`; `StainLayer.gd` as ArenaBase's `Stains` node (z -1); ArenaFlat's `Background` moved to z -2.
- `ImpactFX.gd`: white death pop (inline flat-white shader), kill burst along the blow, edge splash. Health's old upward death particles are gone; the per-hit yellow particles stay until phase 2.
- `Tools/hit_feel_probe.gd`, added to `run_probes.ps1`.
