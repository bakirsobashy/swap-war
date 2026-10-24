# Plan: player arrow + swap preview indicator

**Status:** plan only, not implemented. **Date:** 2026-10-24.

## Goals

1. **Player arrow.** A downward triangle above the player's head at all times, so you can find yourself after every reshuffle.
2. **Swap preview.** For the last 2 seconds before each team swap, an indicator above **every** actor shows the colour it will switch to.

Out of scope (per your call): colour-blind team symbols (audit item 3) and the Pit arena.

---

## How it fits today's code

- `TeamManager` rolls the new teams **at the moment of the swap** (`randomize_teams()` on the 10 s `_swap_timer` timeout). Nothing knows the next teams in advance, so the preview needs the roll to happen 2 s early.
- Team colours are duplicated in three places: `Health._team_color()`, `HUD._team_color()` and `TeamTimer.team_colors`. Body/hand textures live in `TeamMember`.
- Above an actor's head today: the health bar at `y = -55` (a child of the actor root, so it doesn't lean with `VisualBody`).

## Design

### 1. One colour table: `TeamPalette`

New `Scripts/Components/TeamPalette.gd` (static, `class_name TeamPalette`) with `color(team_id)`. Health, HUD and TeamTimer use it instead of their own copies. Needed so the indicator, health bar and HUD can never disagree. Plain refactor, no behaviour change.

### 2. `TeamManager`: roll early, apply on time

- Split `randomize_teams()` into `_roll_teams() -> Dictionary` (keeps the two-team guarantee) and `_apply_teams(rolled)`.
- New `PREVIEW_LEAD := 2.0`. In `_process`, when `_swap_timer.time_left <= PREVIEW_LEAD` and nothing is rolled yet: roll, store `_next_teams`, emit `next_teams_rolled(next_teams)`.
- On timeout: apply `_next_teams` (rolling then only if nothing was pre-rolled), clear it, emit `team_changed` as today. **What you're shown is exactly what you get.**
- Clear the preview (emit `next_teams_cleared`) whenever the timer is stopped or restarted: post-round, sudden death, Play Again, quit to menu. Today those call `_swap_timer.stop()/start()` directly; route them through `stop_swaps()`/`restart_swaps()` methods so the preview can't leak.
- An actor registered inside the 2 s window gets a team at apply time and simply shows no preview that round.

Using `time_left` (one clock) instead of a second timer means pause, stop and restart already behave correctly.

### 3. `ActorMarker`: one node above each head

New `Scenes/UI/ActorMarker.tscn` + `Scripts/UI/ActorMarker.gd`, instanced in `actor.tscn` at about `y = -80` (just above the health bar), on the actor root so it doesn't lean.

- Drawn in code with `_draw()` (a polygon): no new art, crisp at any camera zoom, cheap (no SubViewport like the health bars).
- **Player arrow** (only on the actor with `is_player`): downward triangle, white fill with a dark ink outline so it reads on every team colour and background; slow ±3 px bob.
- **Swap preview** (every actor, last 2 s):
  - AIs: a small triangle "chip" in the **next** team's colour appears above the head.
  - The player: the arrow itself fills with the next colour (no second marker stacked on the player).
  - Steady for the first second, blinking (~4 Hz) in the final second, matching the timer's tick sounds at ≤ 3 s.
  - Shown even when the colour won't change, so "you stay green" is readable too.
- Listens to `next_teams_rolled` / `next_teams_cleared` / `team_changed`. Hides automatically while dead (the actor is invisible) and on the post-round screen.

### 4. AI

No AI change. The AI still learns about a swap 0.35 s *after* it happens; the preview is a human advantage, which suits single-player vs AI. If it makes the game too easy, a later balance option is letting harder AIs read `_next_teams`.

## Testing

New `Tools/swap_preview_probe.gd`, added to `run_probes.ps1` and the CLAUDE.md probe list:

- The preview fires 2 s (±1 tick) before the swap, and each actor's marker colour equals its rolled next team.
- The applied teams equal the previewed teams.
- The preview clears after the swap, and on post-round, sudden death, Play Again and quit-to-menu.
- Only the player has the arrow; it follows the actor and hides while dead.
- The two-team guarantee still holds for pre-rolled teams.

The existing `audit_regression_probe` two-team check moves to the new roll function.

## Files

- **New:** `Scripts/Components/TeamPalette.gd`, `Scenes/UI/ActorMarker.tscn`, `Scripts/UI/ActorMarker.gd`, `Tools/swap_preview_probe.gd`
- **Changed:** `TeamManager.gd`, `ArenaManager.gd` (stop/restart via the new methods), `actor.tscn`, `Health.gd`, `HUD.gd`, `TeamTimer.gd`, `audit_regression_probe.gd`, `run_probes.ps1`, `CLAUDE.md`

## Decisions for you (recommended option first)

1. **Arrow colour:** white with an ink outline (always readable), or your current team colour.
2. **AI preview style:** small coloured chip, or the same triangle as the player's arrow.
3. **Preview when the colour stays the same:** show it, or hide it.
4. **HUD:** also tint the swap timer with *your* next colour during the last 2 s? (Recommended: yes, it's one line once the signal exists.)
