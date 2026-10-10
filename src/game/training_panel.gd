class_name TrainingPanel
extends CanvasLayer
## Training-room options, toggled with T: spawn/remove dummies, pick their behaviour and
## weapon, infinite ammo, god mode, give all weapons, refill.

const FONT_N := UiTheme.FONT
const FONT := UiTheme.TITLE
const ACCENT := UiTheme.GOLD             # training uses gold to stand apart from match UI
const BEHAVIOURS := [
	["Idle", "Stands still — free target practice"],
	["Move only", "Runs, jumps and dodges; never shoots"],
	["Attack only", "Stands its ground and shoots at you"],
	["Opponent", "Full bot AI: navigates, grabs pickups, fights back"],
]

var world: World
var _panel: PanelContainer
var _behaviour_buttons: Array[Button] = []
var _skill_buttons: Array[Button] = []
var _count_label: Label


func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	_panel.theme = _theme()
	_panel.custom_minimum_size = Vector2(340, 0)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN   # stays on-screen at any width
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.visible = false
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)

	var title := Label.new()
	title.text = "TRAINING"
	title.add_theme_font_override("font", FONT)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", ACCENT)
	box.add_child(title)

	_count_label = Label.new()
	box.add_child(_count_label)
	box.add_child(_row([["Spawn dummy", world.spawn_dummy], ["Remove all", world.clear_dummies]]))

	box.add_child(_heading("Dummy behaviour"))
	for i in BEHAVIOURS.size():
		var b := Button.new()
		b.text = BEHAVIOURS[i][0]
		b.tooltip_text = BEHAVIOURS[i][1]
		b.toggle_mode = true
		b.pressed.connect(_on_behaviour.bind(i))
		_behaviour_buttons.append(b)
		box.add_child(b)

	box.add_child(_heading("Opponent skill"))
	var skills := HBoxContainer.new()
	for i in BotBrain.SKILLS.size():
		var b := Button.new()
		b.text = BotBrain.SKILLS[i].name
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(func() -> void:
			world.set_bot_skill(i as BotBrain.Skill)
			_sync())
		_skill_buttons.append(b)
		skills.add_child(b)
	box.add_child(skills)

	box.add_child(_heading("Options"))
	box.add_child(_toggle("Dummies carry random weapons", world.dummy_random_weapon,
			func(on: bool) -> void: world.dummy_random_weapon = on))
	box.add_child(_toggle("Infinite ammo", world.infinite_ammo, func(on: bool) -> void: world.infinite_ammo = on))
	box.add_child(_toggle("God mode (you take no damage)", world.god_mode, func(on: bool) -> void: world.god_mode = on))
	box.add_child(_row([["Give all weapons", func() -> void: world.give_all_weapons(world.local_player)],
			["Refill health", _refill]]))
	var hint := Label.new()
	hint.text = "T — close"
	hint.modulate = Color(1, 1, 1, 0.55)
	box.add_child(hint)
	_sync()
	_panel.set_anchors_and_offsets_preset.call_deferred(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, 20)


func _theme() -> Theme:
	var t := Theme.new()
	t.default_font = FONT_N
	t.default_font_size = 15
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.04, 0.06, 0.1, 0.92)
	panel.border_color = Color(ACCENT, 0.6)
	panel.border_width_top = 2
	panel.set_content_margin_all(16)
	panel.set_corner_radius_all(6)
	t.set_stylebox("panel", "PanelContainer", panel)
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.06) if state == "normal" else (Color(ACCENT, 0.25) if state == "pressed" else Color(1, 1, 1, 0.12))
		sb.border_color = Color(ACCENT, 0.9) if state == "pressed" else Color(1, 1, 1, 0.15)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(4)
		sb.set_content_margin_all(6)
		t.set_stylebox(state, "Button", sb)
	return t


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	l.add_theme_font_size_override("font_size", 12)
	return l


func _row(buttons: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	for spec in buttons:
		var b := Button.new()
		b.text = spec[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(spec[1])
		b.pressed.connect(_sync)
		row.add_child(b)
	return row


func _toggle(text: String, on: bool, apply: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = on
	c.toggled.connect(apply)
	return c


func _on_behaviour(i: int) -> void:
	world.set_dummy_behaviour(i as DummyBrain.Behaviour)
	_sync()


func _refill() -> void:
	var p := world.local_player
	if p.alive:
		p.health = 100
		p.armor = 100


func _sync() -> void:
	for i in _behaviour_buttons.size():
		_behaviour_buttons[i].set_pressed_no_signal(i == world.dummy_behaviour)
	for i in _skill_buttons.size():
		_skill_buttons[i].set_pressed_no_signal(i == world.bot_skill)
	_count_label.text = "Dummies: %d / %d" % [world.dummy_count(), World.MAX_DUMMIES]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("training"):
		_panel.visible = not _panel.visible
		world.input_blocked = _panel.visible
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _panel.visible else Input.MOUSE_MODE_HIDDEN
		_sync()
		get_viewport().set_input_as_handled()
