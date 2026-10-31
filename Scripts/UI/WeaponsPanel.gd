class_name WeaponsPanel
extends PanelContainer

## CHOOSE WEAPONS: a scrolling grid with one WeaponCard per WeaponDatabase
## entry, an in-game switch on each, and INCLUDE ALL. Holds the working
## selection only — MainMenu saves it with START MATCH, like its other options.
## At least one weapon always stays on.

signal back_requested
## The disabled list changed (MainMenu re-reads get_disabled()).
signal selection_changed

const CardScene := preload("res://Scenes/UI/WeaponCard.tscn")

@onready var _grid: GridContainer = %CardGrid
@onready var _count_label: Label = %CountLabel
@onready var _include_all_btn: Button = %IncludeAllBtn
@onready var _back_btn: Button = %WeaponsBackBtn

var _cards: Dictionary = {}           # weapon name -> WeaponCard
var _disabled := PackedStringArray()

func _ready() -> void:
	var registry := get_node_or_null("/root/WeaponDatabase")
	if registry == null:
		return
	for weapon_name: String in registry.get_names():
		var card: WeaponCard = CardScene.instantiate()
		_grid.add_child(card)
		card.setup(registry, weapon_name)
		card.toggled.connect(_on_card_toggled)
		_cards[weapon_name] = card
	_refresh()

## Load a selection (names switched off) without emitting selection_changed.
func set_disabled(names: PackedStringArray) -> void:
	_disabled = PackedStringArray()
	for weapon_name in names:
		if _cards.has(weapon_name):
			_disabled.append(weapon_name)
	# Never let a saved list switch everything off.
	if _disabled.size() >= _cards.size():
		_disabled = PackedStringArray()
	_refresh()

func get_disabled() -> PackedStringArray:
	return _disabled.duplicate()

func get_enabled_count() -> int:
	return _cards.size() - _disabled.size()

func get_total_count() -> int:
	return _cards.size()

func get_card(weapon_name: String) -> WeaponCard:
	return _cards.get(weapon_name, null)

## First control for keyboard/gamepad focus (MenuFocus).
func get_default_focus() -> Control:
	return _back_btn

func include_all() -> void:
	_disabled = PackedStringArray()
	_refresh()
	selection_changed.emit()

func _on_card_toggled(weapon_name: String, enabled: bool) -> void:
	if enabled:
		var i := _disabled.find(weapon_name)
		if i >= 0:
			_disabled.remove_at(i)
	elif not _disabled.has(weapon_name):
		_disabled.append(weapon_name)
	_refresh()
	selection_changed.emit()

func _refresh() -> void:
	var on := get_enabled_count()
	for weapon_name in _cards:
		var card: WeaponCard = _cards[weapon_name]
		var enabled := not _disabled.has(weapon_name)
		card.set_enabled(enabled)
		card.set_locked(enabled and on <= 1)
	_count_label.text = "%d of %d weapons in game" % [on, _cards.size()]
	_include_all_btn.disabled = _disabled.is_empty()

func _on_back_pressed() -> void:
	back_requested.emit()

func _on_include_all_pressed() -> void:
	include_all()

func _play_click() -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_ui_click()
