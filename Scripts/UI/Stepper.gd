@tool
## @tool on purpose: without it the editor (and therefore the exporter,
## which loads and re-saves every scene) builds this node with a placeholder
## script that drops the scene's `items` overrides, so exported builds
## (web) showed blank Opponents / Win Mode / Touch steppers.
class_name Stepper
extends HBoxContainer

## "< value >" picker used by the menus in place of OptionButton: touch-friendly
## and drawn with the menu theme's round icon buttons. Emits item_selected with
## OptionButton's signature, so existing handlers connect unchanged.

signal item_selected(index: int)

@export var items: PackedStringArray = []:
	set(value):
		items = value
		selected = selected
@export var selected: int = 0:
	set(value):
		selected = clampi(value, 0, maxi(items.size() - 1, 0))
		_refresh()
## Stepping past either end wraps to the other; off clamps and disables the arrow.
@export var wrap_around := true

@onready var _prev: Button = $Prev
@onready var _next: Button = $Next
@onready var _value: Label = $Value

func _ready() -> void:
	_prev.pressed.connect(_step.bind(-1))
	_next.pressed.connect(_step.bind(1))
	_refresh()

func set_selected_no_signal(index: int) -> void:
	selected = index

func _step(delta: int) -> void:
	if items.is_empty() or Engine.is_editor_hint():
		return
	var target := selected + delta
	if wrap_around:
		target = posmod(target, items.size())
	else:
		target = clampi(target, 0, items.size() - 1)
	if target == selected:
		return
	selected = target
	if AudioManager:
		AudioManager.play_ui_click()
	item_selected.emit(selected)

func _refresh() -> void:
	if not is_node_ready():
		return
	_value.text = items[selected] if selected < items.size() else ""
	_prev.disabled = items.size() < 2 or (not wrap_around and selected <= 0)
	_next.disabled = items.size() < 2 or (not wrap_around and selected >= items.size() - 1)
