class_name MenuFocus

## Keyboard/gamepad focus for the menus without a permanent focus ring: nothing
## is focused until the first navigation press, which focuses `target`. Mouse and
## touch players therefore never see the dashed focus outline on open.

const NAV_ACTIONS: Array[StringName] = [
	&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_focus_next", &"ui_focus_prev",
]

## Call from `_unhandled_input`. Focuses `target` (and consumes the event) when
## `event` is a navigation press and nothing in the viewport has focus yet.
static func focus_on_nav(event: InputEvent, target: Control) -> void:
	if target == null or not target.is_visible_in_tree():
		return
	var viewport := target.get_viewport()
	if viewport.gui_get_focus_owner() != null:
		return
	for action in NAV_ACTIONS:
		if event.is_action_pressed(action):
			target.grab_focus()
			viewport.set_input_as_handled()
			return
