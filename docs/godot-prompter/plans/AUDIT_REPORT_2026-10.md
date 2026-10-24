# Swap-War — Project Audit (October 2026)

**Date:** 2026-10-23 (audit), updated 2026-10-24 (quick fixes, then batch 2)
**Scope:** every script and scene (~60 files), `project.godot`, export presets, assets, both game plans, and the previous `AUDIT_REPORT.md`.
**Method:** line-by-line read, headless smoke boots of the menu and all three arenas, the full probe suite, and live-match reproduction of each suspected bug. The reproductions are now permanent in `Tools/audit_regression_probe.gd`.

**Verdict:** the AI and navigation stack is solid and every probe for it passes. The match flow, UI and touch layer around it had a cluster of player-facing bugs, several of which hit every match. The quick fixes below are done. The rest are still open and are tracked as `KNOWN (open)` lines in the regression probe.

Run the whole suite (fails on non-zero exits **and** on any `SCRIPT ERROR`):

```powershell
pwsh Tools/run_probes.ps1
```

---

## 1. Bugs reproduced in a live match

| # | Status | Bug | Where | Fix |
|---|---|---|---|---|
| 1 | ✅ Fixed | Countdown read "START IN 3 WINS!" | `ArenaManager.gd` used `HUD.show_winner()` | New `HUD.show_message()` |
| 2 | ✅ Fixed | Esc never opened the pause menu during play | `PauseMenu.gd` forced WHEN_PAUSED, so it got no input while playing | Process mode ALWAYS |
| 3 | ✅ Fixed (batch 2) | End screen shows raw node names ("@RIGIDBODY2D@73 WINS!"); after Play Again even the player is `@RigidBody2D@72` | `PostRoundMenu.gd:19,27` | Shared display-name registry (the HUD's names) and a "YOU" marker |
| 4 | ✅ Fixed | Every health bar was always green | `Health.gd` coloured it once, before teams existed | `TeamMember` calls `Health.refresh_bar_color()` on every team change |
| 5 | ✅ Fixed (batch 2) | A landing sound plays right after every jump (the floor still counts as touching one tick after takeoff) | `Actor-Movement.gd:88-96`, `:356-359` | Ignore ground contacts while rising, or the plan's 0.1 s post-jump window (2.1.5) |
| 6 | ✅ Fixed | Touch DROP worked once; Drop_Weapon then stayed held forever and the E key died too | `TouchControls.gd` parsed a press with no release | `DropButton.action = "Drop_Weapon"` (presses and releases like Jump/Attack); the Pause fallback also sends a release |
| 7 | ✅ Fixed | Spikes stole kills and scored themselves (enemy got 0, SpikeStrip +1) | `HazardArea.gd` passed itself as attacker; `ScoreManager` scored any node | Hazards pass no attacker; only registered actors score |
| 8 | ✅ Fixed (batch 2) | Timed-mode ties always go to the player (first registered) | `ScoreManager.gd:50-58` | Detect ties, then sudden death (plan 1.6) |
| 9 | ✅ Fixed (batch 2) | Quit to menu mid Timed match: the clock keeps running and the win jingle plays over the main menu | `ArenaManager.gd:53-65` never resets `_state` | Reset to IDLE when the arena leaves the tree |
| 10 | ✅ Fixed (batch 2) | Play Again keeps the previous match's weapons | `ArenaManager._start_match` only removes actors | Free weapons, projectiles and effects; reset the spawner |
| 11 | ✅ Fixed | Respawn kept the death velocity (~900 px/s downward after a KillZone fall) | `Health._respawn` | Zero linear/angular velocity on respawn |
| 12 | ✅ Fixed (batch 2) | Hits on invulnerable (just-respawned) actors still cost durability and knock back | `MeleeWeapon.gd:73-75`, `Projectile.gd` | `take_damage()` returns whether it landed; skip side effects if not |
| 13 | ✅ Fixed (batch 2) | A swing never re-hits an enemy already touching the blade (damage only on contact *begin*) | `MeleeWeapon.gd` `attack()` only sets timers | On swing, damage the HitBox's overlapping bodies |
| 14 | ✅ Fixed (batch 2) | Low-HP AIs never leave Retreat (exit needs > 40% HP; nothing heals) | `RetreatState.gd:59-60` | Timeout or distance-only exit, or regen/health pickups |
| 15 | ✅ Fixed (batch 2) | Running an arena directly shows 8 scoreboard rows | `Health.gd:24` adds Health to the "actors" group | Delete that line (check every "actors" consumer first) |
| 16 | ✅ Fixed | `layout_probe` errored at every resolution but exited 0 | It looked up the removed `%TeamTimerLabel` | Uses `%TeamTimer`; `run_probes.ps1` now fails on script errors |
| 17 | Open | "Pit Arena" has no pit: Pit and Hazards use byte-identical tile data to the legacy jam arena | `ArenaPit.tscn`, `ArenaHazards.tscn` | Build the real Pit layout (plan 4.1) |
| 18 | ✅ Fixed | A bullet in flight after Play Again errored on its freed shooter (found by the new runner) | `Projectile.gd` | Freed source ends the shot |

### How batch 2 fixed them

- **#3** Actors get real node names at spawn (`YOU`, then Zack/Mark/John/Stacy), so the HUD, the end screen and the scoreboard agree; Play Again removes old actors from the tree first so names never get auto-suffixed.
- **#5** 0.1 s post-jump ground grace in `Actor-Movement` (plan 2.1.5).
- **#8** `ScoreManager.get_leaders()`; a timed tie (including 0-0) goes to **sudden death**: swaps stop, "SUDDEN DEATH!" banner, the next kill wins (plan 1.6).
- **#9** `ArenaManager` returns to IDLE when the scene changes to a non-arena; `scene_changed` is now always connected (also fixes the direct-run Quit → Play bug).
- **#10** Play Again frees weapons, projectiles and effects and resets the spawner. Weapons now also **drop at GO** instead of ~7 s in.
- **#12** `Health.take_damage()` returns whether the hit landed; melee and projectiles skip knockback and durability on a blocked hit.
- **#13** `MeleeWeapon.attack()` damages bodies already overlapping the HitBox (the per-victim cooldown still paces hits). Melee is noticeably stronger in close contact; watch it in the balance pass.
- **#14** An armed AI gives up a Retreat after 5 s and can't retreat again for 6 s (fights instead).
- **#15** Health no longer joins the "actors" group.

Also fixed: the AI-count slider could show "AI Count: 0" (min is now 1); the help text claimed arrow keys move and omitted Drop (E); it now says swaps are every 10 s.

## 2. Likely bugs from reading the code (not reproducible headless)

- ✅ *Fixed (batch 2): facing follows the move stick; the held aim-stick direction only persists while holding a gun.* **On touchscreens the player's facing never followed the move stick.** `_update_facing` skips the player (`Actor-Movement.gd:204-205`) and the touch fallback aims along the current facing (`:322-323`). A phone player who doesn't use the aim stick faces right forever. Biggest mobile bug.
- ✅ *Fixed (batch 2, with #9).* Run an arena directly, then Quit and Play from the menu: nothing spawned (`ArenaManager.gd:28-31` only connects `scene_changed` when the boot scene isn't an arena). Development only.
- ✅ *Fixed (batch 2): `ArenaManager.is_match_over()` stops the pending respawn.* The final victim reappeared at a spawn point behind the end screen; the respawn timer runs while paused (`Health.gd`, `die()`).
- ✅ *Fixed (batch 2): SeekWeapon blacklists a weapon it couldn't reach for 8 s.* An unarmed AI could chase an unreachable weapon forever: straight-line weapon scoring and no blacklist for failed targets (`Sensors.gd:147-168`). Score by `graph.route()` cost.
- ✅ *Fixed (batch 2): both flashes are overbright and restore to plain white.* Hit flash and team-swap flash set `modulate = WHITE` on an already-white sprite, so they're invisible (`Health._flash_hit`, `TeamMember._flash_team_change`).
- Minor: ✅ *fixed (batch 2)* the weapon spawner could exceed its cap by 2 (deferred add; pending spawns now count). Still open: NavExecutor uses `position` where Sensors uses `global_position` (breaks if `Actors` is ever offset).

## 3. Design flaws worth fixing

1. **You can't tell which character is you.** All four look identical and colours reshuffle every 10 s. Add a marker/outline and highlight your scoreboard row.
2. **Teams are colour-only, and red and green are two of the four** — the most common colour-blind pair. Add per-team symbols or a colour-blind palette.
3. ✅ *Partly fixed (batch 2): weapons drop at GO; unarmed attack still missing.* **The first ~7 s are dead time.** No weapons until the first sky drop, and nobody can attack unarmed. Drop weapons at "GO" or add the plan's unarmed shove (2.3.4).
4. ✅ *Fixed (batch 2): a swap re-rolls one actor if everyone landed on one team.* **Swaps could leave no enemies.** Teams are rolled independently: with 1 AI a quarter of swaps make everyone allies for 10 s. Guarantee ≥ 2 teams (plan 4.4.7).
5. ✅ *Fixed (batch 2): a hit opens a 0.3 s stun window (cap 750 px/s, no friction).* **Knockback was capped by run speed** (|vx| clamped to 300 every tick). A short stun window that lifts the cap would make ring-outs possible.
6. **Holding a sword damages anyone you walk into**, so the attack button mostly adds reach. Consider damage only during the swing.
7. **Swaps are hard to read.** The timer digits change to a random team colour every second; add a clear "SWAP!" cue. The AI gets a 0.35 s reaction delay after a swap; the player gets nothing.
8. **Missing feedback:** crits look like normal hits, no kill feed, no deaths or team colours on the end screen, no screenshake or freeze frame.
9. **Static camera.** The planned 62×62-tile arenas (~3,800 px) need a follow or fit-all camera.
10. **Deadly floors look safe.** Flat's pit floor uses the normal ground tile but kills on touch; decorative clouds have collision.
11. **Attack is mouse-only:** no keyboard attack key, no gamepad.

## 4. Tech debt and release blockers

- The touch-control work (twin sticks, auto attack, layout editor) is still uncommitted.
- **Web export isn't set up** although web is the primary platform: no Web preset; Forward+ renderer (check the web build on Compatibility); `export_filter=all_resources` used to ship ~1,360 unreferenced media files (✅ deleted 2026-10-24).
- **Android preset is placeholder:** `com.example.$genname`, no version name, no icons; the app is still named "Brakeys game jam solo" (`project.godot:13`).
- **Performance:** each health bar is its own always-updating SubViewport (`HealthBar2D.tscn`); `BitmapNumberLabel._texture_for_number` calls `load()` every frame. No projectile or particle pooling.
- **Tileset:** `resourses/arenas.tres` has 62 px tiles with 64 px collision polygons.
- **Pause button texture** is loaded from the `.godot/imported` cache path (`TouchControls.tscn`) instead of the PNG.
- ✅ *Cleaned up (2026-10-24):* the dead functions, the unused HUD node, the unused collision masks, the inert StairWaypoints, the legacy `Scenes/arena.tscn`, the one-off `slope_probe`, the root junk file, and 1,363 unreferenced assets (most of the old Kenney UI pack and unused platformer sprites) are gone. Kept on purpose: `AudioManager.play_ui_hover/toggle` (planned menu sounds). **Still to remove once the menu redesign is committed:** the 9 old Kenney button PNGs, `Drawing 2-3.png` and `swap_war_theme.tres` the committed menus still use.
- **Junk:** ✅ the empty `**Related` file is deleted. Still open: the KillZone sits on collision layer 1 (World) and should be on none.
- Exit-time "leaks" are only SFX still playing at quit — harmless.

## 5. Full game plan status (`swap-war-full-game-plan.md`)

| Phase | Done | Partial | Not done |
|---|---|---|---|
| 1 Shell | Menus, saved settings, runtime spawning, match state machine, both win modes, arena select, pause via Esc and touch | End screen (no deaths/team colours, wrong names); pause has no background dim; Quit button also shown on web | `match_started`/`match_ended` signals; Timed sudden death |
| 2 Core feel | State-based ground check, layer-3 drop-through, AI attack loop/facing/re-arming, kill-credit window, KillZone, walls, respawn invulnerability | Invulnerability still allows knockback and durability loss; `max_contacts_reported` still 4 | Post-jump ground window (bug #5); KillSource enum and kill stats; unarmed combat (player has none either) |
| 3 Audio & mobile | Placeholder SFX, buses and sliders; duplicate fire sound; touch controls far beyond the plan; safe areas; auto-hide | Toggle and hover sounds never play | `PlayerInput` abstraction (only needed for local multiplayer) |
| 4 Content | ArenaBase + 3 arenas + selector; AI 2.0 navigation, patrol, retreat; swap-timer pulse and tick | Pit is a copy of the jam arena | Real Pit; moving platform; thrown-weapon damage; Hammer/Dagger/Bomb; durability HUD; difficulty presets + selector; screenshake; freeze frame; pickup VFX; name tags; two-team guarantee; final 62×62 arenas |
| 5 Release | Settings save/load | — | Web preset and asset trim; Android/iOS setup; pooling; profiling; balance pass; reset-to-defaults; final audio and ducking; itch page |

## 6. Previous `AUDIT_REPORT.md`

12 of its 18 items were fixed and #5 was not a bug. #4 (ties) and #8 (post-round resurrection) are half done, #7's fix overshot into bug #5 above, #14 (bar colour) is now fixed, and #18 (AI slider) is now fixed.

## 7. Suggested next order (after batch 2)

Still open from section 1: **#17** (Pit is a copy of the jam arena). Everything else in section 1 is fixed and guarded by `Tools/audit_regression_probe.gd`.

1. **Readability:** a YOU marker/outline on the player, a colour-blind-safe team identity (design 1-2), a clear swap cue (7).
2. **Combat:** an unarmed shove (design 3), consider removing passive contact damage (6), crit/kill feedback (8).
3. **Content:** the real Pit layout (#17), then the Phase 4 list (moving platform, thrown weapons, new weapons, difficulty presets).
4. **Release:** Web export preset + Compatibility check + asset trim, Android preset, health-bar SubViewports.

When you fix an open item, flip its `_known(...)` line in `Tools/audit_regression_probe.gd` to `_check(...)` so it stays fixed.
