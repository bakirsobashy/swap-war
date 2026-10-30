extends SceneTree

## Headless probe for the Menu UI 2.0 screens (menu_theme + Stepper).
## Verifies:
##   1. MainMenu opens on the main panel with nothing focused (no focus ring
##      for mouse/touch); the first ui_down press focuses PLAY
##   2. Stepper: next/prev emit item_selected with OptionButton's signature,
##      wrap around, and drive MainMenu's match state (AI count, arena, mode)
##   3. win mode greys out the limit that doesn't apply (score target in
##      TIMED_SCORE, time limit in SCORE_TARGET) and the time limit reads m:ss
##   4. mute state swaps the sound icon and disables that volume slider
##   5. PauseMenu: the corner close button resumes and unpauses
##   6. PostRoundMenu: DRAW title, reworded reason, rows sorted by kills with
##      the winner starred
##   7. app lifecycle: focus loss / backgrounding opens the pause menu (never
##      closes it, never over the post-round screen)
##   8. Android Back: toggles pause, leaves the end screen for the main menu,
##      and steps the main menu back one level (layout editor -> Settings ->
##      main); Quit shows on desktop (hidden on web/iOS)
##
## Probe discipline: runtime load() only, untyped vars, no autoload identifiers.
## Never presses START / mute buttons / the touch stepper — those reach
## SettingsManager setters, which persist to the user's settings file.

const SOUND_OFF_PATH := "res://Assets/ui/ui-2.0/scribble_ui/x1/icons/sound_off.png"
const MAIN_MENU_PATH := "res://Scenes/UI/MainMenu.tscn"

var _fails: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _main_menu_checks()
	await _pause_checks()
	await _post_round_checks()

	var verdict := "ALL PASS"
	if _fails > 0:
		verdict = "%d FAILURES" % _fails
	print(verdict)
	quit(1 if _fails > 0 else 0)

func _main_menu_checks() -> void:
	var settings = root.get_node_or_null("/root/SettingsManager")
	var menu = (load("res://Scenes/UI/MainMenu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame

	# 1. open state + lazy keyboard focus
	_check(menu.main_panel.visible and not menu.options_panel.visible
			and not menu.settings_panel.visible and not menu.help_panel.visible,
			"main panel is the only visible panel on open")
	_check(root.gui_get_focus_owner() == null, "nothing focused on open (no focus ring)")
	_press_action(&"ui_down")
	await process_frame
	var focused = root.gui_get_focus_owner()
	_check(focused != null and focused.name == "PlayBtn", "first ui_down focuses PLAY")

	# 2. steppers
	menu._on_play_pressed()
	await process_frame
	var ai = menu.ai_stepper
	var emitted := []
	ai.item_selected.connect(func(i): emitted.append(i))
	ai.set_selected_no_signal(2)
	menu._ai_count = 3
	ai.get_node("Next").pressed.emit()
	_check(emitted == [0] and menu._ai_count == 1,
			"AI stepper wraps 3 bots -> 1 bot and updates the match AI count")
	ai.get_node("Prev").pressed.emit()
	_check(menu._ai_count == 3, "AI stepper prev wraps back to 3 bots")
	var arena_names = load("res://Scripts/Arena/ArenaDatabase.gd").get_arena_names()
	_check(arena_names.size() > 0 and Array(menu.arena_stepper.items) == arena_names,
			"arena stepper is filled from ArenaDatabase")
	var arena_before: int = menu._arena_index
	menu.arena_stepper.get_node("Next").pressed.emit()
	_check(menu._arena_index == (arena_before + 1) % menu.arena_stepper.items.size(),
			"arena stepper next advances the arena index")

	# 3. win mode -> row greying, duration format
	menu.mode_stepper.set_selected_no_signal(0)
	menu._on_mode_option_changed(0)
	_check(menu.score_slider.editable and not menu.duration_slider.editable,
			"SCORE_TARGET: score slider live, time limit greyed")
	_check(menu.duration_row.modulate.a < 0.99 and menu.score_row.modulate.a > 0.99,
			"SCORE_TARGET: time-limit row faded, score row opaque")
	menu.mode_stepper.get_node("Next").pressed.emit()
	_check(menu._win_mode == 1 and not menu.score_slider.editable and menu.duration_slider.editable,
			"TIMED_SCORE (via stepper): time limit live, score slider greyed")
	menu.duration_slider.value = 90.0
	_check(menu.duration_value.text == "1:30", "time limit reads m:ss (90 s -> 1:30)")
	menu.score_slider.value = 12.0
	_check(menu.score_value.text == "12", "score value label follows the slider")

	# 4. mute icon + slider (property set directly — never the persisting setter)
	if settings:
		var sfx_was: bool = settings.sfx_enabled
		settings.sfx_enabled = false
		menu._refresh_audio_ui()
		_check(menu.sfx_toggle.icon.resource_path == SOUND_OFF_PATH
				and menu.corner_sound.icon.resource_path == SOUND_OFF_PATH,
				"muted sound shows sound_off on both buttons")
		_check(not menu.sfx_slider.editable, "muted sound disables its volume slider")
		settings.sfx_enabled = sfx_was
		menu._refresh_audio_ui()
	else:
		_check(false, "SettingsManager autoload present")

	# 8. Back steps out one level; Quit is a desktop/Android button
	_check(menu.quit_btn.visible, "Quit shows on desktop")
	menu._on_how_to_play_pressed()
	menu.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(menu.main_panel.visible and not menu.help_panel.visible,
			"Back from How to Play returns to the main screen")
	menu._on_settings_pressed()
	menu._on_customize_touch_pressed()
	await process_frame
	menu.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	_check(menu.settings_panel.visible and not menu.touch_layout_editor.visible
			and not Input.emulate_touch_from_mouse,
			"Back from the layout editor returns to Settings and restores emulation")
	menu.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(menu.main_panel.visible and not menu.settings_panel.visible,
			"Back from Settings returns to the main screen")

	menu.queue_free()
	await process_frame

func _pause_checks() -> void:
	var pause = (load("res://Scenes/UI/PauseMenu.tscn") as PackedScene).instantiate()
	root.add_child(pause)
	await process_frame
	await process_frame
	pause._toggle_pause()
	_check(pause.visible and paused, "pause opens and pauses the tree")
	_check(pause.get_node("Root/Dim").visible, "pause dims the game behind the card")
	pause.get_node("%CloseBtn").pressed.emit()
	_check(not pause.visible and not paused, "corner close button resumes")

	# 7. focus loss / backgrounding pauses; 8. Back toggles
	pause.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(pause.visible and paused, "losing focus opens the pause menu")
	pause.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(pause.visible and paused, "a second focus loss keeps it open")
	pause.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(not pause.visible and not paused, "Back closes the pause menu")
	pause.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check(pause.visible and paused, "going to the background opens the pause menu")
	pause._on_resume_pressed()
	pause.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(pause.visible and paused, "Back opens the pause menu during play")
	pause._on_resume_pressed()
	var fake_post := CanvasLayer.new()
	root.add_child(fake_post)
	pause._post_round_menu = fake_post
	pause.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	pause.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(not pause.visible and not paused,
			"focus loss and Back leave the post-round screen alone")
	fake_post.queue_free()
	pause.queue_free()
	await process_frame

func _post_round_checks() -> void:
	var post = (load("res://Scenes/UI/PostRoundMenu.tscn") as PackedScene).instantiate()
	root.add_child(post)
	await process_frame
	var a := Node.new()
	a.name = "Alpha"
	var b := Node.new()
	b.name = "Bravo"
	var c := Node.new()
	c.name = "Charlie"
	root.add_child(a)
	root.add_child(b)
	root.add_child(c)

	post.show_post_round(null, {a: 3, b: 3}, "Time Up")
	_check(post.get_node("%Title").text == "DRAW!", "no winner -> DRAW! title")
	_check(post.get_node("%Reason").text == "time's up!", "Time Up reason is reworded")

	post.show_post_round(b, {a: 2, b: 9, c: 5}, "Score Target")
	var board = post.get_node("%Scoreboard")
	var rows := board.get_children().filter(func(n): return n is HBoxContainer)
	var names := rows.map(func(r): return r.get_child(1).text)
	_check(names == ["Bravo", "Charlie", "Alpha"], "rows sorted by kills (got %s)" % [names])
	_check(rows.size() == 3 and rows[0].get_child(0) is TextureRect
			and rows[1].get_child(0) is Label,
			"winner row starred, others ranked")
	_check(board.get_child_count() == 5, "notebook-line separators between rows (rows rebuilt, not appended)")
	_check(post.get_node("%Title").text == "BRAVO WINS!", "winner title")

	# 8. Back on the end screen goes to the main menu
	post.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	await process_frame
	_check(not paused and current_scene != null
			and current_scene.scene_file_path == MAIN_MENU_PATH,
			"Back on the end screen goes to the main menu")
	unload_current_scene()

	paused = false
	post.queue_free()
	a.queue_free()
	b.queue_free()
	c.queue_free()
	await process_frame

func _press_action(action: StringName) -> void:
	# Press AND release: a parsed press without a release stays held.
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)

func _check(ok: bool, what: String) -> void:
	var verdict := "FAIL"
	if ok:
		verdict = "PASS"
	print("%s: %s" % [verdict, what])
	if not ok:
		_fails += 1
