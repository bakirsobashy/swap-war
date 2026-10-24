# Menu UI 2.0: plan

**Status:** implemented 2026-10-24 with steppers (decision 1). See "Implementation notes" at the end for where the build deviates from this plan. **Scope:** menus only (main menu and its sub-panels, pause, post-round, and the frame of the touch-layout editor). The in-game HUD, touch controls, floating numbers and team timer stay as they are for now.

**Source kit:** `Assets/ui/ui-2.0/` contains "Scribble UI: Notebook Doodle": wobbly ink outlines, hatched pencil shadows, a yellow highlighter accent, lined notebook paper, and the fonts Patrick Hand (body) and Cabin Sketch Bold (titles). It ships a ready-made Godot theme plus x1 / x1.5 / x2 art sets.

Mockups (rendered from the kit's real PNGs and fonts at the game's 1152×648 base canvas) are in `mockups/`:

| # | Screen | Mockup |
|---|---|---|
| 1 | Main menu | `mockups/1_main_menu.png` |
| 2 | Match options (PLAY) | `mockups/2_match_options.png` |
| 3 | Settings | `mockups/3_settings.png` |
| 4 | How to play | `mockups/4_how_to_play.png` |
| 5 | Pause (in game) | `mockups/5_pause_menu.png` |
| 6 | Post-round (in game) | `mockups/6_post_round.png` |

The game world behind 5 and 6 is a placeholder drawing. In the real game it is the live arena, dimmed.

---

## 1. Design language

| Element | Kit piece / value | Used for |
|---|---|---|
| Background | `decor/paper_lined.png` tiled, plus a 2 px `#EBA6A6` margin line | Main menu screens and the touch-layout editor |
| Card | `panel/panel.png` (9-slice 40/40/46/48, hatched shadow) | Every sub-panel, pause, post-round |
| Primary action | ~~`PrimaryButton` (yellow highlighter)~~ dropped: it looked like hover (see Implementation notes) | PLAY, START MATCH, RESUME, PLAY AGAIN now use the white styles |
| Secondary actions | `Button` / `ButtonAlt` (white; alternate them down a list so the wobble doesn't look copy-pasted) | Everything else |
| Back / close | `IconButton` (round) with `arrow_left` (sub-panels, top-left) or `close` (overlays, top-right) | Replaces the full-width BACK buttons and saves a whole row of height on every panel |
| Titles | `TitleLabel` (main title), `HeaderLabel` (panel titles): Cabin Sketch on a highlighter stroke | "SWAP-WAR", "SETTINGS", "PAUSED", … |
| Body text | Patrick Hand, ink `#1F1F1F`; hints in soft ink `#5A564E` | Row labels, hints, help text |
| Toggles | `CheckButton` switch, or a round `IconButton` with on/off icons | Auto Attack (switch); sound/music mute (icon) |
| Sliders | Kit `HSlider` (track, yellow fill, ink grabber; grey dashed grabber when disabled) | Volumes, score target, time limit |
| In-game dim | Full-rect `ColorRect`, `#1F1F1F` at about 40 % alpha | Behind pause and post-round |
| States | Built into the kit: hover (lifts and turns yellow), pressed (sinks into its shadow), disabled (dashed, grey), focus (dashed ring for keyboard/gamepad) | All buttons |

**Resolution:** the project has no viewport size set, so it runs at Godot's default 1152×648 canvas with `canvas_items` / `expand`. Use the **x1** art set (made for 1280×720). It reads about 11 % larger relative to the screen, which is fine. Font sizes come down slightly from the kit's defaults: Button 32, body 26–28, HeaderLabel 50, TitleLabel 100. Confirm these in the engine.

---

## 2. Asset hygiene (do first)

1. **Keep** `Assets/ui/ui-2.0/scribble_ui/x1/` and `scribble_ui/fonts/` (the OFL license files must ship with the fonts).
2. **Add an empty `.gdignore`** to `ui-2.0/extras/`, `scribble_ui/demo/`, `scribble_ui/themes/`, `scribble_ui/x1_5/` and `scribble_ui/x2/`. Reasons:
   - The kit's demo scenes and themes point at `res://scribble_ui/...`, which doesn't exist here, so they would raise broken-dependency errors.
   - x1.5 and x2 would roughly triple the export size for art we don't use.
   - The README says `extras/` is not meant for import.
3. The project's default texture filter is linear (not overridden), which is right for this art. Default import settings are fine.
4. Leave `Assets/ui/ui_spritesheet.PNG`, `swap_war_theme.tres` and `new_theme.tres` alone. `new_theme.tres` still drives `HUD.tscn` and `FloatingNumber.tscn`. Retire the unused ones in the in-game UI phase.

## 3. The theme: `Assets/ui/Themes/menu_theme.tres` (new)

- Copy `scribble_ui/themes/scribble_theme_1280x720.tres` and rewrite every `res://scribble_ui/` path to `res://Assets/ui/ui-2.0/scribble_ui/`.
- Apply the font-size tweaks from §1.
- Add these type variations:
  - `RowLabel`: Label, 28
  - `HintLabel`: Label, 20, soft ink
  - `ValueLabel`: Label, 28, centered (stepper and slider readouts)
  - `SubHeaderLabel`: Cabin Sketch 30, no highlight ("controls" / "rules")
- Apply it **per scene**: set it on a root Control, never as the project-wide GUI theme. A project theme would leak `default_font` into the HUD, which we're not touching yet.
- `CanvasLayer` can't hold a theme. MainMenu, PauseMenu and PostRoundMenu each get one full-rect `Root` Control that carries the theme and parents their panels. Unique names (`%MainPanel`, `%Panel`, `%Title`, …) are owner-scoped, so the scripts' `@onready` lookups keep working after the reparent. Update the `parent=` and connection `from=` paths in the `.tscn`.
  - **Exception:** keep the `TouchLayoutEditor` instance as a direct child of MainMenu. Its nested CanvasLayers depend on the explicit visibility lifecycle described in CLAUDE.md.

## 4. Screen by screen

### 4.1 Main menu (`Scenes/UI/MainMenu.tscn` → MainPanel)
- `TextureRect` (IMG_0882) → `Paper` (TextureRect, tile `paper_lined`, Expand Mode = Ignore Size, Stretch = Tile) plus a `MarginLine` ColorRect.
- `MainPanel` stops being a card. Buttons sit directly on the paper, as in the kit demo. Keep the node (scripts toggle it) but turn it into a full-rect Control holding a VBox.
- `Title` → `TitleLabel` "SWAP-WAR", plus a `HintLabel` tagline: "teams re-shuffle every 10 seconds. trust no one."
- Buttons, 320 wide and 64 tall:
  - PlayBtn → `PrimaryButton` + `play` icon
  - HowToPlayBtn → `ButtonAlt` + help icon (see the open decisions)
  - SettingsBtn → `Button` + `settings` icon
  - QuitBtn → `ButtonAlt` + `quit` icon
- **New:** `SoundToggle` and `MusicToggle` round `IconButton`s (toggle mode) in the top-right corner, sharing the Settings mute handlers.
- **New, decor only** (`mouse_filter = IGNORE`): two clouds, a star sparkle, a cross sparkle, and `arrow_doodle` with a slightly rotated "start here!" HintLabel pointing at PLAY.
- Initial focus: `PlayBtn.grab_focus()`, so the dashed focus ring works for keyboard/gamepad.

### 4.2 Match options (OptionsPanel)
- `Title` → `HeaderLabel` "MATCH OPTIONS". `OptionsBackBtn` → round `arrow_left` IconButton in the card's top-left (same `_on_back_pressed`).
- Rows: a `RowLabel` on the left, the control on the right.
  - **Opponents**: Stepper "1 bot / 2 bots / 3 bots" (replaces the 1–3 AISlider)
  - **Arena**: Stepper fed from `ArenaDatabase.get_arena_names()` (replaces the OptionButton)
  - **Win Mode**: Stepper "Score Target / Timed Score" (replaces the OptionButton)
  - **Score Target**: HSlider + `ValueLabel` "10"
  - **Time Limit**: HSlider + `ValueLabel` "2:00"
- The slider that doesn't apply to the chosen win mode gets `editable = false` (kit greys it). This matches `ArenaManager`: the score target only ends a match in SCORE_TARGET (`track_score`), and the timer only ends one in TIMED_SCORE (`ArenaManager.gd:64`).
- `StartMatchBtn` → `PrimaryButton` + `play`.

### 4.3 Settings (SettingsPanel)
- `HeaderLabel` "SETTINGS" + round back arrow.
- **Sound** / **Music**: round toggle IconButton (`sound_on`/`sound_off`, `music_on`/`music_off`) + HSlider. When muted, the slider is greyed (`editable = false`).
- **Touch Controls**: Stepper "Auto / Always / Hidden" (replaces the OptionButton).
- **Auto Attack**: `CheckButton` switch + HintLabel "swings & fires for you".
- `CustomizeTouchBtn` → `Button` + `settings` icon, text shortened to **"EDIT TOUCH LAYOUT"** (the old text overflows a 64 px kit button).

### 4.4 How to play (HelpPanel)
- Wider card (~940×580). `HeaderLabel` + back arrow.
- The single long `HelpText` label becomes two columns, which keeps it under 648 px tall:
  - **controls**: key → action rows, then a "touch" block
  - **rules**: bullet rows; the swap rule is first, in full ink, with a star bullet
- Same wording as today, split into rows.

### 4.5 Pause (`Scenes/UI/PauseMenu.tscn`)
- `Root` → `Dim` ColorRect (stops mouse) → `Panel` card (keeps `%Panel`).
- `HeaderLabel` "PAUSED" + round `close` IconButton (→ existing `_on_resume_pressed`).
- ResumeBtn → `PrimaryButton` + `play`; RestartBtn → `ButtonAlt` + `restart`; QuitBtn → `Button` + `home`. All 340 wide, because "QUIT TO MENU" plus an icon needs more than 300.
- `ResumeBtn.grab_focus()` when shown.
- No script logic changes.

### 4.6 Post-round (`Scenes/UI/PostRoundMenu.tscn`)
- Same `Root` / `Dim` / card pattern.
- `%Title` → `HeaderLabel` ("ZACK WINS!" / "DRAW!"). Keep the `%Title` name: `audit_regression_probe` reads it.
- Win reason → `HintLabel` under the title.
- `Scoreboard` Label → a VBox of rows built in code, **sorted by kills**: winner gets `hud/star_full`, others a rank number; then name, then "N kills" right-aligned, with a notebook-line separator. A team-color dot per row is optional (`TeamManager.get_team(actor)`).
- PlayAgainBtn → `PrimaryButton` + `restart`; MainMenuBtn → `Button` + `home`.

### 4.7 Touch-layout editor frame (`Scenes/UI/TouchLayoutEditor.tscn`)
- Theme → `menu_theme.tres`. `Background` → tiled paper.
- `BackButton` → round `arrow_left` IconButton. `ResetButton` → `ButtonAlt` + `restart`. `MinusButton` / `PlusButton` → `SquareButton`.
- **Keep every node name**: `touch_layout_editor_probe` looks up `%SelectionBox`, `%MinusButton`, `%PlusButton`, `%OverlayLayer` and `%TouchControls`.
- `SelectionBox` can stay a StyleBoxFlat but in ink `#1F1F1F` with a highlighter tint, so it matches.
- The `TouchControls` art itself is in-game UI and is not restyled now.

## 5. Code changes (small, all in `Scripts/UI/`)

| File | Change |
|---|---|
| **new** `Stepper.gd` + `Scenes/UI/Stepper.tscn` | `class_name Stepper extends HBoxContainer`: two 44 px round IconButtons (`arrow_left`/`arrow_right`) around a `ValueLabel`; `@export var items: PackedStringArray`, `selected`, `wrap := true`, `signal item_selected(index: int)`, `set_selected_no_signal(i)`; clicks play `AudioManager.play_ui_click()`. **Same signal signature as OptionButton**, so the existing handlers stay. |
| `MainMenu.gd` | `@onready` types OptionButton → Stepper; `.selected = x` → `set_selected_no_signal(x)`; `_populate_arena_options` fills `items`; `_on_ai_slider_changed(float)` → `_on_ai_stepper_changed(index)` (`index + 1`); `_update_options_ui` sets slider `editable` by win mode and formats duration as `m:ss`; `_refresh_audio_icons()` swaps mute icons and is called from the toggle handlers and `_update_settings_ui()`; corner toggles reuse `_on_sfx_toggled` / `_on_music_toggled`; `sfx_check` / `music_check` become `Button`, `auto_attack_check` becomes `CheckButton` (`toggled` and `set_pressed_no_signal` are unchanged on BaseButton). |
| `PostRoundMenu.gd` | Build score rows (sorted) instead of joining one string. |
| `PauseMenu.gd`, `TouchLayoutEditor.gd` | None. New buttons connect to the existing methods. |

`SettingsManager` setters still persist immediately, exactly as now. No settings-file format changes.

## 6. Order of work

1. Asset hygiene (§2) + `menu_theme.tres` (§3). Check: headless boot shows no missing-dependency errors.
2. Main menu screen (4.1).
3. `Stepper` + match options (4.2).
4. Settings + mute toggles (4.3).
5. How to play (4.4).
6. Pause + post-round (4.5, 4.6). They share the Dim/card pattern.
7. Touch-layout editor frame (4.7).
8. Update CLAUDE.md (key files: `menu_theme.tres`, `Stepper`) and add a memory note if anything surprising turns up.

## 7. Verification

- **Smoke:** `Godot --headless --path . --quit-after 300`. No `SCRIPT ERROR`, no "Failed loading resource".
- **Probes:** `pwsh Tools/run_probes.ps1` all green. The ones at risk:
  - `touch_layout_editor_probe` (editor node names)
  - `audit_regression_probe` (PauseMenu `_on_quit_to_menu_pressed`, PostRoundMenu `%Title`)
  - `layout_probe` (shouldn't change, but run it)
- **Optional new `Tools/menu_probe.gd`:** instantiate MainMenu and check:
  - stepper arrows wrap and emit `item_selected`
  - the win-mode switch flips which slider is `editable`
  - mute toggles swap icons

  It must never press START or call the persisting setters, and it must follow the probe discipline in CLAUDE.md.
- **Visual:** run the game windowed and screenshot each panel at 1152×648 and at a wide phone aspect (e.g. 2400×1080 window). Compare against `mockups/`.
- **Input:** keyboard/gamepad (Tab/arrows move the dashed focus ring through every control; Esc still pauses/unpauses), mouse hover/press states, and touch (stepper and back buttons ≥ 44 canvas px; the touch→mouse emulation contract is untouched).

## 8. Open decisions (recommendation first)

1. **Steppers instead of dropdowns** for Opponents / Arena / Win Mode / Touch Controls *(recommended: friendlier on touch and fits the doodle look)*. The alternative is to keep the OptionButtons and add `OptionButton` + `PopupMenu` styles to the theme (paper popup, highlighter hover). No script changes then, but the kit has no down-arrow icon.
2. **HOW TO PLAY icon**: the kit has no "help" icon. The mockup uses `levels` as a placeholder. Either draw a matching `help.png` (a doodled "?") or drop icons from the secondary buttons.
3. **Quick mute toggles** on the main menu corner *(recommended, cheap)*. Optionally add them to the pause card too.
4. **Team-color dots** on the post-round scoreboard *(optional; teams swap constantly, so the dot shows the final team)*.

---

## Implementation notes (2026-10-24)

Built as planned, except for these deliberate changes:

- **Mute buttons are not `toggle_mode`.** A toggled kit `IconButton` shows its yellow "pressed" style while on, so "sound on" would look stuck down. They are plain buttons: a press flips `SettingsManager.sfx_enabled` / `music_enabled` and `_refresh_audio_ui()` swaps the icon on both the Settings row and the main-menu corner.
- **Lazy focus instead of `grab_focus()` on open.** `Scripts/UI/MenuFocus.gd` focuses the panel's default control on the first `ui_*` navigation press, so mouse and touch players never see the dashed focus ring and keyboard/gamepad players get it on their first press. MainMenu, PauseMenu and PostRoundMenu use it.
- **Plus/minus icons:** the kit has none, and Cabin Sketch's "+" / "−" glyphs are tiny at a size that fits a 60 px button. `Assets/ui/ui-2.0/custom/plus.png` and `minus.png` are derived from the kit's `close.png` stroke, kept outside the vendor folder.
- **Layout editor `SIZE_BUTTON_GAP` 8 → 14**, so the square buttons' hatched shadow clears the selection box.
- **No `PrimaryButton` anywhere.** The kit's primary style (yellow) looked identical to its hover state (also yellow, just lifted), so PLAY / START MATCH / RESUME / PLAY AGAIN read as "stuck in hover". They use the white `Button` / `ButtonAlt` (still alternating down each list), and yellow now means only hover/pressed. The variation is still defined in `menu_theme.tres` but unused.
- **Copy tweaks:** pause "RESTART MATCH" → "RESTART"; post-round reason reworded ("first to the score target" / "time's up!"); the plural is handled ("1 kill").
- **Still open:** the HOW TO PLAY icon is the `levels` placeholder (decision 2). The post-round names show raw node names; that's the known open audit bug and isn't part of this work. Pause/post-round dimming doesn't cover the HUD or touch controls (they sit on higher CanvasLayers); leave that for the in-game UI pass.
- **Verification:** headless smoke boot is clean; `pwsh Tools/run_probes.ps1` passes all 13 probes, including the new `Tools/menu_probe.gd` (23 checks). Windowed screenshots were compared against `mockups/` at 1152×648 and 1440×648.

## Follow-up: touch controls reskin (2026-10-24)

The in-game touch controls now use the kit's touch art. The art came from a later kit drop that has been merged into `ui-2.0`; the duplicate `Assets/ui/controls` folder was deleted.

- **Kept the twin-stick system:** `TouchControls` + `VirtualStick`, the layout editor, auto attack and the emulation contract are unchanged. The kit's own touch scripts are not used.
- **Move stick:** yellow knob. **Aim stick:** pink knob (`custom/stick_knob_aim*.png`, recolored to match the attack button).
- **Stick behavior:** both fade to 60 % when idle and show the sunk pressed knob while held. The 80 px well geometry is unchanged.
- **Buttons:** jump / attack / drop use the kit's yellow / pink / blue art at 0.65 of native size (about 1.35× the old 64 px buttons), in the same approved stack. Pause is the kit's round button with the pause icon baked in (`custom/touch_pause_*.png`), at 0.85.
- **Scale contract:** button scale = layout scale × saved mult × art scale. `touch_layout_editor_probe` checks it through `get_art_scale()`.
