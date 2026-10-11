class_name SettingsPanel
extends TabContainer
## Audio / Graphics / Controls / Gameplay tabs. Every change applies immediately and is saved.
## Used by the main menu and the in-match pause menu.

var _rebinding := ""                    # action waiting for a key press
var _bind_buttons := {}                 # action -> Button
var _bind_msg: Label                    # feedback after a rebind (swapped / refused)


func _ready() -> void:
	custom_minimum_size = Vector2(560, 380)
	_add_tab("Audio", _audio())
	_add_tab("Graphics", _graphics())
	_add_tab("Controls", _controls())
	_add_tab("Gameplay", _gameplay())


func _add_tab(title: String, content: Control) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	add_child(scroll)


func _row(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := UiTheme.label(text)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	control.custom_minimum_size.x = maxf(control.custom_minimum_size.x, 220)
	row.add_child(control)
	return row


func _slider(value: float, apply: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(v: float) -> void:
		apply.call(v)
		Settings.save_settings())
	return s


func _toggle(on: bool, apply: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = on
	c.toggled.connect(func(v: bool) -> void:
		apply.call(v)
		Sfx.play("ui_click", -8.0)
		Settings.save_settings())
	return c


func _choice(options: Array, selected: int, apply: Callable) -> OptionButton:
	var o := OptionButton.new()
	for text in options:
		o.add_item(text)
	o.selected = selected
	o.item_selected.connect(func(i: int) -> void:
		apply.call(i)
		Settings.save_settings())
	return o


func _audio() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_child(_row("Master volume", _slider(Settings.master_volume, func(v: float) -> void: Settings.master_volume = v)))
	box.add_child(_row("Music", _slider(Settings.music_volume, func(v: float) -> void: Settings.music_volume = v)))
	box.add_child(_row("Sound effects", _slider(Settings.sfx_volume, func(v: float) -> void: Settings.sfx_volume = v)))
	box.add_child(_row("Announcer voice", _toggle(Settings.announcer, func(v: bool) -> void: Settings.announcer = v)))
	return box


func _graphics() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_child(_row("Quality", _choice(["Low — older laptops", "High"], Settings.quality,
			func(i: int) -> void: Settings.quality = i)))
	box.add_child(_row("Auto quality", _toggle(Settings.auto_quality, func(v: bool) -> void: Settings.auto_quality = v)))
	box.add_child(_row("Screen shake", _toggle(Settings.screen_shake, func(v: bool) -> void: Settings.screen_shake = v)))
	# Read the real window mode: on the web the browser can leave fullscreen on its own (Esc),
	# and a saved "fullscreen" isn't applied at startup there (browsers need a click first).
	var mode := DisplayServer.window_get_mode()
	Settings.fullscreen = mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	box.add_child(_row("Fullscreen", _toggle(Settings.fullscreen, func(v: bool) -> void:
		Settings.fullscreen = v
		Settings.apply_display())))
	box.add_child(_row("Show FPS counter", _toggle(Settings.show_fps, func(v: bool) -> void: Settings.show_fps = v)))
	box.add_child(UiTheme.label("Low quality halves particle effects and turns off lamp glow. Auto quality switches to Low if a match keeps dropping frames.", "Muted"))
	return box


func _controls() -> VBoxContainer:
	var box := VBoxContainer.new()
	for action in Settings.REBINDABLE:
		var b := Button.new()
		b.custom_minimum_size.x = 160
		b.pressed.connect(_start_rebind.bind(action))
		_bind_buttons[action] = b
		box.add_child(_row(Settings.ACTION_LABELS[action], b))
	_bind_msg = UiTheme.label("", "Muted")
	box.add_child(_bind_msg)
	box.add_child(UiTheme.label("Mouse: left = fire, right = alt fire, wheel = switch weapon. Keys 1–9 pick weapons.", "Muted"))
	var reset := UiTheme.button("Reset to defaults", func() -> void:
		Settings.reset_bindings()
		_bind_msg.text = ""
		_refresh_bindings())
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(reset)
	_refresh_bindings()
	return box


func _gameplay() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_child(_row("Auto-switch to new weapons", _toggle(Settings.auto_switch, func(v: bool) -> void: Settings.auto_switch = v)))
	return box


func _refresh_bindings() -> void:
	for action in _bind_buttons:
		_bind_buttons[action].text = "press a key…" if action == _rebinding else Settings.key_name(action)


func _start_rebind(action: String) -> void:
	_rebinding = action
	_refresh_bindings()


func _input(event: InputEvent) -> void:
	if _rebinding == "" or not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: int = (event as InputEventKey).physical_keycode
	if key != KEY_ESCAPE:                      # Esc cancels
		_bind_msg.text = Settings.rebind(_rebinding, key)
	_rebinding = ""
	_refresh_bindings()
	get_viewport().set_input_as_handled()
