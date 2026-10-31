# Weapon select + DEFAULTS buttons: plan

**Status:** built 2026-10-31. Two deviations from this plan: the Weapons row uses a new `PillButton` theme style (the kit's wide buttons need 64 px of height, more than the 52 px row has), and the Range bar scales within each category (melee reach next to gun range left every melee bar empty).

**Goal:** a CHOOSE WEAPONS screen opened from Match Options. It shows a scrollable grid of weapon cards (art, every stat, an in-game switch) plus INCLUDE ALL. Also a DEFAULTS button in Match Options and one in Settings. The grid must keep working as more weapons are added.

**Decisions (from the Q&A):**
- **DEFAULTS:** resets to factory values instantly, with no confirm dialog.
- **Placement:** CHOOSE WEAPONS is a new "Weapons [5 / 5 ›]" row in the options grid. DEFAULTS is a round reset icon in the top-right of each panel's header, mirroring the back arrow.
- **Stats:** each stat shows its number plus a highlighter bar scaled to the best weapon.
- **Saving:** weapon choices are saved with START MATCH, like the other match options.

## 1. One weapon registry

Today the weapon list lives in two places: stats in `Scripts/Weapons/WeaponDatabase.gd` and scenes in `WeaponSpawner.MELEE_SCENES` / `GUN_SCENES`. That would make every new weapon a two-file edit, and the picker would need a third copy.

- **New fields:** each `WeaponDatabase` entry gains a `"scene"` and an `"icon"`, for example `res://Scenes/Weapons/Sword.tscn` and `res://Assets/PNG/Default/item_sword.png`. The icon fills the existing (unused) `WeaponData.texture`.
- **New API:**
  - `get_names()`, in registry order
  - `get_scene(name)`, `get_icon(name)`
  - `get_range(name)`: melee uses `attack_thrust_distance`; guns use `projectile_speed × projectile_lifetime` (pistol 550, rifle 900)
  - `get_stat_max(stat)`, which scales the bars
- **Adding a weapon** becomes one entry: the spawner and the picker both pick it up.

## 2. Settings

- **New setting:** `SettingsManager.disabled_weapons: PackedStringArray`, saved under `[match]`. Storing the *disabled* list means a weapon added in a later update is **on by default** for players with an old settings file.
- **New API:** `is_weapon_enabled(name)` and `set_disabled_weapons(list)`. START MATCH calls the setter next to `set_match_options`.
- **Factory values** live in one place, `SettingsManager.MATCH_DEFAULTS` / `SETTINGS_DEFAULTS`, used by both DEFAULTS buttons:
  - **Match:** 3 bots, Score Target, 10, 2:00, default arena, all weapons on.
  - **Settings:** SFX −6 dB, music −12 dB, both on, touch Auto, auto attack off. The custom touch layout is not touched; the layout editor has its own RESET.

## 3. Spawner

`WeaponSpawner._pick_weapon_scene` builds its melee and gun lists from the registry, filtered by `is_weapon_enabled`. Melee/gun weighting and the gun cap are unchanged.
- **No melee enabled:** only guns spawn, still capped at `max_active_guns`.
- **No weapons enabled:** can't happen, because the UI always keeps at least one on.

## 4. UI

- **Match Options:**
  - **Weapons row:** a new row with a compact button showing "enabled / total ›". It opens the weapons panel.
  - **DEFAULTS:** a round reset icon in the header's right slot. It resets the panel's values; they're saved on START MATCH, like any other change.
- **`Scenes/UI/WeaponsPanel.tscn`** (+ `WeaponsPanel.gd`) is a new panel in MainMenu's Center.
  - **Header:** back arrow, "WEAPONS", and an INCLUDE ALL button.
  - **Grid:** a `ScrollContainer` (vertical, drag-scrolls on touch) around a 3-column `GridContainer` of cards.
  - **Back:** the back arrow and Android Back return to Match Options.
- **`Scenes/UI/WeaponCard.tscn`** (+ `WeaponCard.gd`), one per registry entry:
  - **Art and name:** a paper card with the weapon art, the name in Cabin Sketch, and a melee/ranged tag.
  - **Stat rows:** label, value, highlighter bar.
    - Damage
    - Attack speed (attacks/s from the cooldown)
    - Crit chance (%)
    - Durability (hits)
    - Knockback
    - Range (px)
  - **"In game" switch:** turning it off fades the card. The last enabled weapon's switch is disabled, with a "keep at least one weapon" hint.
- **Scrollbar style:** `menu_theme.tres` gains a doodle `VScrollBar` style (ink rounded grabber, paper track). The kit has none.
- **Settings panel:** the same reset icon in the header. The pause menu's copy gets it too.

## 5. Files

- **New:**
  - `Scenes/UI/WeaponsPanel.tscn`, `WeaponCard.tscn`
  - `Scripts/UI/WeaponsPanel.gd`, `WeaponCard.gd`
  - `Tools/weapon_select_probe.gd`
- **Changed:**
  - `WeaponDatabase.gd`, `WeaponSpawner.gd`, `SettingsManager.gd`
  - `MainMenu.tscn` / `.gd`, `SettingsPanel.tscn` / `.gd`
  - `menu_theme.tres`, `Tools/menu_probe.gd`, `Tools/run_probes.ps1`, CLAUDE.md

## 6. Verification

- **`weapon_select_probe`:**
  - every registry entry has a loadable scene and icon
  - a disabled weapon never spawns over many picks
  - a weapon missing from a saved disabled list counts as enabled
  - the last enabled weapon can't be switched off
  - INCLUDE ALL re-enables everything
- **`menu_probe` additions:**
  - the Weapons row count follows the toggles
  - the panel opens and Back returns
  - both DEFAULTS buttons restore their factory values
- **Screenshots** at 1152×648 and 1440×648: the options panel with the new row, the weapons grid scrolled, and a card with its switch off.
- **Full suite:** `pwsh Tools/run_probes.ps1`.
