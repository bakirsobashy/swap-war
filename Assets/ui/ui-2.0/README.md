# Scribble UI: "Notebook Doodle" (design A)

A hand-drawn UI kit for Godot 4 to sit alongside Kenney's Scribble Platformer pack.
It has wobbly ink outlines, hatched pencil shadows, a yellow highlighter accent and a notebook-paper background.
Tested in **Godot 4.3**; it should work in any Godot 4.2 or newer.

```
scribble_ui/        <- copy this folder into your project root (res://scribble_ui/)
  x1/               art for a 1280x720 game
  x1_5/             same art, 1.5x, for a 1920x1080 game
  x2/               same art, 2x, for a 2560x1440 game
  themes/           one ready Theme per resolution
  touch/            on-screen analog stick + jump / attack / drop weapon buttons (scripts + ready scenes)
  demo/<size>/      main_menu, pause_menu, level_select, touch_demo example scenes
  fonts/            Patrick Hand + Cabin Sketch (SIL Open Font License, free for commercial use)
extras/             sprite sheets + JSON coordinates, preview image, screenshots (don't copy these into the project)
```

## Setup (2 minutes)

1. Copy the `scribble_ui` folder into your project so the path is `res://scribble_ui/`.
2. **Project Settings → Display → Window**: set Viewport Width/Height to the size you're using
   (1280×720, 1920×1080 or 2560×1440) and set **Stretch → Mode** to `canvas_items`.
3. **Project Settings → GUI → Theme → Custom**: choose `res://scribble_ui/themes/scribble_theme_<your size>.tres`.
   (Or set the `theme` property on the root Control of your menus.)
4. Open `res://scribble_ui/demo/<your size>/main_menu.tscn` and press F6 to run it.

If your viewport size isn't one of the three, use the closest one. With `canvas_items` stretch, Godot scales everything evenly.

## Which style goes on which node

Choose these in the Inspector under **Theme → Type Variation**:

| Type Variation | Put it on | Looks like |
|---|---|---|
| *(none)* | Button | White wide button with hatched shadow |
| `PrimaryButton` | Button | Yellow highlighter button (PLAY, RESUME) |
| `ButtonAlt` | Button | Same, wobble mirrored (alternate it in lists so they don't look copy-pasted) |
| `IconButton` | Button | Round button: leave text empty and set **Icon** to `x1/icons/*.png` |
| `SquareButton` | Button | Square button, stretches to any size |
| `LevelButton`, `LevelButtonCurrent` | Button | Level tile (white / yellow). Add a TextureRect child with `hud/stars_0..3.png` at the bottom (see `level_select.tscn`) |
| `TitleLabel` | Label | Big Cabin Sketch title with a highlighter stroke behind it |
| `HeaderLabel` | Label | Smaller header (PAUSED, LEVELS) |

These are styled automatically, no variation needed: **Panel / PanelContainer** (paper card with shadow),
**HSlider** (volume slider), **CheckButton** (on/off switch), **CheckBox**, **Label** (ink color, Patrick Hand).

Every button has normal, hover (lifts up, turns yellow), pressed (sinks into its shadow, the text moves with it),
disabled (dashed and grey) and keyboard/gamepad focus (dashed ring) states built in.

### Tips

- **Button height**: wide buttons are drawn for 64 px tall (96 at 1.5x, 128 at 2x). Keep the height and stretch them as wide as you like.
- **Icon + text**: set the Button's `icon` to one of `x1/icons/*.png` (use the folder for your size).
- **HUD**: use TextureRects with `hud/heart_full`, `heart_empty`, `coin`, `star_full`, `star_empty`, `stars_0..3`.
- **Notebook background**: TextureRect with `decor/paper_lined.png`, *Expand Mode = Ignore Size*, *Stretch Mode = Tile*.
  The red margin line in the demo is just a 2 px ColorRect (`#EBA6A6`).
- **Mute toggle**: swap the icon in code:

```gdscript
const SOUND_ON := preload("res://scribble_ui/x1/icons/sound_on.png")
const SOUND_OFF := preload("res://scribble_ui/x1/icons/sound_off.png")

@onready var sound_button: Button = $Corner/Sound

func _ready() -> void:
	sound_button.pressed.connect(_on_sound_pressed)

func _on_sound_pressed() -> void:
	var bus := AudioServer.get_bus_index("Master")
	var muted := not AudioServer.is_bus_mute(bus)
	AudioServer.set_bus_mute(bus, muted)
	sound_button.icon = SOUND_OFF if muted else SOUND_ON
```

## Touch controls (analog stick, jump, attack, drop weapon)

![touch controls](extras/screenshots/touch_controls_held.png)

**Add them to your game:** instance `res://scribble_ui/touch/touch_controls_<your size>.tscn` in your level scene
(or add it as an Autoload so it's on top of every level). It's a CanvasLayer, so it stays fixed to the screen while the camera moves.
The stick sits bottom-left. Jump, attack and drop weapon sit bottom-right, within reach of your right thumb.

**Input actions:** the controls press these actions, the same way a gamepad would:

| Control | Action |
|---|---|
| Stick | `move_left`, `move_right`, `move_up`, `move_down` (analog strength 0–1) |
| Yellow button | `jump` |
| Pink sword button | `attack` |
| Blue button | `drop_weapon` |

Any actions missing from your Input Map are created automatically when the game starts. If your game already uses other names
(for example `ui_left` or `shoot`), select the Joystick or a button in the scene and change its action names in the Inspector.

Your player code reads them like keyboard or gamepad input. Nothing touch-specific is needed:

```gdscript
func _physics_process(delta: float) -> void:
	var direction := Input.get_axis("move_left", "move_right")   # -1..1, analog from the stick
	velocity.x = direction * SPEED
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	if Input.is_action_just_pressed("attack"):
		attack()
	if Input.is_action_just_pressed("drop_weapon"):
		drop_weapon()
	move_and_slide()
```

If you use `Input.get_vector(...)`, pass `0.0` as the last argument (or lower the actions' deadzone in the Input Map). The stick already applies its own 15% deadzone.

**Good to know**
- Several fingers work at once: you can hold the stick, jump and attack together.
- The controls hide themselves on computers without a touch screen. Tick **Show On Desktop** on the TouchControls node to see them while testing.
  The mouse then acts as one finger.
- On the Joystick node, **Mode = Dynamic** (default) makes the stick jump to wherever the thumb lands in the left part of the screen.
  **Fixed** keeps it in one place. You can also change Rest Offset, Deadzone and Idle Opacity (it fades when not touched).
- On each button, **Hit Scale** enlarges the touch area and **Idle Opacity** sets how see-through it is.
- To add more buttons (dash, interact…), duplicate one and use `touch/blank_normal.png` / `blank_pressed.png`, or ask for new art.
- `demo/<size>/touch_demo.tscn` shows a live readout of what the controls send, which is handy for checking on a real phone.
- For phones, set **Project Settings → Display → Window → Stretch → Aspect** to `expand` so the controls stay in the corners on wide screens.

## Using the art without the theme

Every piece is a separate PNG. For a NinePatchRect, use these patch margins (1x values; multiply by 1.5 or 2 for the bigger sets):

| Texture | Left | Top | Right | Bottom | Notes |
|---|---|---|---|---|---|
| `buttons/button_*`, `button_alt_*` | 78 | 36 | 80 | 44 | includes 8/8/10/12 px of transparent space for the shadow; set Axis Stretch Horizontal = Tile |
| `buttons/square_*` | 30 | 30 | 30 | 32 | Axis Stretch = Tile Fit |
| `panel/panel` | 40 | 40 | 46 | 48 | Axis Stretch = Tile Fit |
| `controls/slider_track`, `slider_fill` | 14 | 9 | 14 | 9 | |
| `panel/title_highlight` | 34 | 0 | 34 | 0 | |

`extras/scribble_ui_sheet_x1.png` / `_x2.png` pack everything into a single sprite sheet, like the sheet you drew.
The matching `.json` gives `x, y, w, h` for each piece, so you can make AtlasTextures from it.

## Colors

| | Hex |
|---|---|
| Ink (outlines, text) | `#1F1F1F` |
| Paper | `#FDFBF4` (panels `#FFFEF8`) |
| Notebook lines | `#CFE0F0` |
| Margin line | `#EBA6A6` |
| Highlighter | `#FFE45C` |
| Disabled fill / ink | `#F3F0E7` / `#A8A397` |
| Heart | `#FF7A7A` |
| Coin / star | `#FFD84A` |

Fonts: Patrick Hand (body, buttons) and Cabin Sketch Bold (titles, level numbers), both from Google Fonts under the SIL Open Font License.
Their license files are in `scribble_ui/fonts/`.
