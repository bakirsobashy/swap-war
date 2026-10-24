# In-game HUD 2.0: plan

**Status:** agreed 2026-10-24, not built yet. **Scope:** everything drawn during a match: the HUD, the swap timer, banners, health bars, damage numbers, the overhead marker, and the team palette. The touch controls were already reskinned (see `../menu-ui-2.0/PLAN.md`).

Mockups are in `mockups/`. They are painted over real captures with the kit's art and fonts:

| File | Shows |
|---|---|
| `before_playing.png` / `after_playing.png` | Mid-match during the 2 s swap preview, in the **fighter-matched palette**, with the goal chip in the top right |
| `before_countdown.png` / `after_countdown_banner.png` | The countdown banner. The fighter colors in this one still use the old palette |
| `palette_compare.png` | Today's palette vs. the fighter-matched one, with protanopia / deuteranopia / tritanopia simulation |

## Agreed changes

1. **Scoreboard:** a paper card in the top-left (kit `panel` stylebox).
   - Each row: a team-color dot with an ink outline, the name in ink (Patrick Hand), and the score (Cabin Sketch).
   - The player's row gets a highlighter stroke (kit `title_highlight`) and the leader gets `hud/star_small_full`.
   - Names stay ink; the color lives in the dots.
   - Keep the narrow-window font shrink in `HUD._apply_responsive_layout` and the safe-area offset.
2. **Swap timer** (`TeamTimer`): a paper disc made from the kit's round button art.
   - The ring is drawn in code: pale track plus a highlighter-yellow arc for the time left.
   - The digit is in Cabin Sketch ink. This replaces the random team color every second.
   - **During the swap preview** (TeamManager's early roll), the digit takes *your next team's* color with an ink outline, and a "SWAP!" highlighter tag appears.
   - Keep the last-3-seconds pulse and tick sound.
3. **Center banners** (`HUD.show_message` / `show_winner`): big Cabin Sketch text on a highlighter stroke with a scale-pop tween.
   - The countdown becomes "3 · 2 · 1 · GO!"; today it's "START IN 3", set in `ArenaManager._update_countdown_display`.
   - "SUDDEN DEATH!" and the winner text use the same style.
   - Fixes the current banner, which has no theme and falls back to Godot's default font.
4. **Health bars** (`HealthBar2D`): an ink-outlined paper pill (about 42×10) filled with the team color, replacing the flat 48×6 ColorRect pair. Keep the SubViewport approach, or draw in code.
5. **Damage numbers** (`FloatingNumber`): the kit font in the team color with a **4 px ink outline**, plus a small pop on spawn. Use Patrick Hand rather than Cabin Sketch: the sketch hatching reads dark at this size.
6. **Theme housekeeping:** the HUD moves to `menu_theme.tres`. Then retire `new_theme.tres`, the ScribbleShow font, `Assets/ui/numbers/` with `BitmapNumberLabel`, and `Assets/ui/PNG/ui_circle.png`, once nothing references them. The overhead `ActorMarker` keeps its design; only switch its outline to the kit ink `#1F1F1F`.
7. **Goal chip:** a paper pill **in the top right, just left of the touch pause button**.
   - Score mode: "first to N" (`ScoreManager.score_to_win`).
   - Timed mode: a live "m:ss" clock. That needs a read accessor for `ArenaManager._match_timer`.
   - Sudden death: "SUDDEN DEATH".
   - It reserves the pause button's default slot while touch controls are visible, and slides into the corner when they're hidden (desktop).
8. **Fighter-matched team palette:** `TeamPalette.COLORS` becomes the fighter sprites' fill colors.
   - Green `#37D98C`, red `#FC5C65`, purple `#9179FF`, yellow `#FFB600`, replacing Godot's `GREEN` / `RED` / `PURPLE` / `YELLOW`.
   - This drives the health bars, scoreboard dots, timer preview digit, `ActorMarker` preview, damage numbers and death particles. The fighters are separate sprites and don't change.
   - **Every piece of colored text gets an ink outline** (timer preview digit, damage numbers), because the lighter lavender and amber are faint on paper.
   - Color-blind result: protanopia's worst pair improves from 9 to 34 (CIE76 color difference). Deuteranopia goes from 20 to 16 (green/red), but the fighters already have that weakness. A per-team shape cue would be the real fix; that's a possible later idea, not in this plan.

## Things to watch when building

- **Coordinate with the "audit-fixes-roadmap" session.** It owns the swap preview (`TeamManager.next_teams_rolled`, `ActorMarker`). Check it isn't editing `HUD.gd`, `TeamTimer`, `ActorMarker` or `TeamManager` at the same time.
- **`Tools/layout_probe.gd`** checks that the ScoreBoard fits and that the TeamTimer overlaps nothing, at three resolutions. Add the goal chip to its overlap checks, especially against the touch PauseButton.
- **`audit_regression_probe`** checks "health bars match team colour". It reads `TeamPalette`, so it should keep passing once the bar is restyled, as long as the fill still uses `set_color`.
- The pause and post-round dim still doesn't cover the HUD or touch controls (a CLAUDE.md gotcha). Optionally fix the layer order in this pass.

## Verification

- A headless smoke boot is clean, and `pwsh Tools/run_probes.ps1` is green.
- Windowed captures at 1152×648 and 1440×648, compared against `mockups/after_*.png`: countdown, playing, swap preview, sudden death, and both win modes for the goal chip.
- Touch controls on vs. hidden: the goal chip slot follows the rule in item 7.
