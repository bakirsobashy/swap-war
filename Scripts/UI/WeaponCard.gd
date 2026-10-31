class_name WeaponCard
extends PanelContainer

## One CHOOSE WEAPONS card: art, name, melee/ranged tag, every card stat as a
## value + highlighter bar (scaled to the best weapon), and an "in game"
## switch. Built at runtime by WeaponsPanel from WeaponDatabase.

signal toggled(weapon_name: String, enabled: bool)

const STAT_LABELS := {
	&"damage": "Damage",
	&"attack_speed": "Attack speed",
	&"critical_chance": "Crit chance",
	&"durability": "Durability",
	&"knockback": "Knockback",
	&"range": "Range",
}
## Switched-off cards fade their content (never the switch row).
const OFF_TINT := Color(1, 1, 1, 0.4)

@onready var _content: Control = %Content
@onready var _icon: TextureRect = %Icon
@onready var _name_label: Label = %NameLabel
@onready var _category_label: Label = %CategoryLabel
@onready var _stats: GridContainer = %Stats
@onready var _switch: CheckButton = %InGameSwitch
@onready var _switch_hint: Label = %SwitchHint

var weapon_name: String = ""

func _ready() -> void:
	_switch.toggled.connect(_on_switch_toggled)

## Fill the card from the registry (call once, after it enters the tree).
func setup(registry: Node, name: String) -> void:
	weapon_name = name
	var data = registry.get_data(name)
	_icon.texture = registry.get_icon(name)
	_name_label.text = name
	_category_label.text = data.category if data else ""
	for child in _stats.get_children():
		child.queue_free()
	for stat in registry.CARD_STATS:
		var value: float = registry.get_stat(name, stat)
		# Range compares within the category: melee reach (~40 px) next to
		# gun range (~900 px) would leave every melee bar empty.
		var best: float = registry.get_stat_max(stat, data.category if stat == &"range" and data else "")
		var label := Label.new()
		label.theme_type_variation = &"KeyLabel"
		label.add_theme_font_size_override("font_size", 19)
		label.text = STAT_LABELS.get(stat, String(stat))
		_stats.add_child(label)
		var value_label := Label.new()
		value_label.theme_type_variation = &"HintLabel"
		value_label.add_theme_font_size_override("font_size", 19)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.custom_minimum_size = Vector2(64, 0)
		value_label.text = format_stat(stat, value)
		_stats.add_child(value_label)
		var bar := ProgressBar.new()
		bar.theme_type_variation = &"StatBar"
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(70, 12)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.max_value = 1.0
		bar.step = 0.0
		bar.value = value / best if best > 0.0 else 0.0
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stats.add_child(bar)

static func format_stat(stat: StringName, value: float) -> String:
	match stat:
		&"attack_speed": return "%.1f/s" % value
		&"critical_chance": return "%d%%" % roundi(value * 100.0)
		&"durability": return "%d hits" % roundi(value)
		&"range": return "%d px" % roundi(value)
	return str(roundi(value))

## Show the in-game state without emitting toggled.
func set_enabled(enabled: bool) -> void:
	_switch.set_pressed_no_signal(enabled)
	_content.modulate = Color.WHITE if enabled else OFF_TINT

## The last weapon still on can't be switched off.
func set_locked(locked: bool) -> void:
	_switch.disabled = locked
	_switch_hint.text = "keep at least one" if locked else "in game"

func is_enabled() -> bool:
	return _switch.button_pressed

func get_switch() -> CheckButton:
	return _switch

func _on_switch_toggled(enabled: bool) -> void:
	_content.modulate = Color.WHITE if enabled else OFF_TINT
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_ui_click()
	toggled.emit(weapon_name, enabled)
