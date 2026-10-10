class_name Menu
extends CanvasLayer
## Start menu over a live bot match. Screens: main, play setup (bots / host LAN / join LAN),
## LAN lobby, customize, settings, credits.
## Emits requests; Main decides what to load.

signal play_requested(config: Dictionary)
signal training_requested
signal host_requested(config: Dictionary)
signal join_requested(code: String)
signal lobby_start_requested
signal lobby_leave_requested

const SWATCHES := ["2f80ed", "39e1ff", "2ec4b6", "3ddc84", "a3e635", "fde047", "ffc93c", "ff9f1c",
		"e8553e", "ff3d81", "ff5fa2", "c084fc", "8e5cff", "8d99ae", "e6e6e6", "3b3f4a", "1b2a41", "121212"]
const BOT_SKILL_NAMES := ["Rookie", "Regular", "Veteran", "Elite", "Godlike"]
const FRAG_OPTIONS := [5, 10, 15, 20, 25, 30, 50]
const TIME_OPTIONS := [0, 5, 10, 15, 20]     # minutes, 0 = no limit

var _root: Control
var _screen: Control
var _dim: ColorRect                     # darkens the live match behind sub-screens
var _cards: Array[MapPreview] = []
var _preview: CharPreview
var _play_mode := "bots"                # play screen tab: "bots" | "host" | "join"


func _ready() -> void:
	layer = 50
	_root = Control.new()
	_root.theme = UiTheme.get_theme()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	# Darken the left side so text stays readable over the live match.
	var shade := Control.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.draw.connect(func() -> void:
		var s := shade.size
		var dark := Color(0.02, 0.03, 0.06, 0.88)
		var clear := Color(0.02, 0.03, 0.06, 0.25)
		shade.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]),
				PackedColorArray([dark, clear, clear, dark])))
	_root.add_child(shade)
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.03, 0.06, 0.82)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dim)
	show_main()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _screen and _screen.name != "Main":
		Sfx.play("ui_back", -6.0)
		if _screen.name == "Lobby":
			lobby_leave_requested.emit()          # leaving the lobby also leaves the room
		else:
			show_main()
		get_viewport().set_input_as_handled()


func _swap(screen: Control) -> void:
	if _screen:
		_screen.queue_free()
	_screen = screen
	_root.add_child(screen)
	_dim.visible = screen.name != "Main"
	screen.modulate.a = 0.0
	create_tween().tween_property(screen, "modulate:a", 1.0, 0.18)


## A screen = margin container with a vertical stack; returns the stack.
func _new_screen(screen_name: String, margin := 56) -> VBoxContainer:
	var m := MarginContainer.new()
	m.name = screen_name
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, margin)
	var box := VBoxContainer.new()
	m.add_child(box)
	_swap(m)
	return box


func _back_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	var back := UiTheme.button("Back", func() -> void:
		Sfx.play("ui_back", -6.0)
		show_main())
	row.add_child(back)
	return row


# --- main ----------------------------------------------------------------------------

func show_main() -> void:
	var box := _new_screen("Main", 64)
	box.add_theme_constant_override("separation", 4)
	var logo := UiTheme.label("FRAGLINE", "Title")
	logo.add_theme_font_size_override("font_size", 84)
	logo.add_theme_color_override("font_color", Color.WHITE)
	logo.add_theme_color_override("font_shadow_color", Color(UiTheme.ACCENT, 0.55))
	logo.add_theme_constant_override("shadow_offset_x", 0)
	logo.add_theme_constant_override("shadow_offset_y", 0)
	logo.add_theme_constant_override("shadow_outline_size", 18)
	box.add_child(logo)
	box.add_child(UiTheme.label("2D arena combat  ·  a tribute to Unreal Flash", "Muted"))
	box.add_child(_spacer(28))
	var play := UiTheme.button("Play", show_play, "BigButton")
	var buttons: Array[Button] = [
		play,
		UiTheme.button("Training", func() -> void: training_requested.emit(), "BigButton"),
		UiTheme.button("Customize", show_customize, "BigButton"),
		UiTheme.button("Settings", show_settings, "BigButton"),
		UiTheme.button("Credits", show_credits, "BigButton"),
	]
	var campaign := UiTheme.button("Campaign  ·  coming soon", func() -> void: pass, "BigButton")
	campaign.disabled = true
	buttons.insert(1, campaign)
	if not OS.has_feature("web"):
		buttons.append(UiTheme.button("Quit", func() -> void: get_tree().quit(), "BigButton"))
	for b in buttons:
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.x = 340
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		box.add_child(b)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(fill)
	box.add_child(UiTheme.label("Playing as %s  ·  Esc goes back" % Settings.player_name, "Muted"))
	play.grab_focus.call_deferred()


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c


# --- play (versus bots) --------------------------------------------------------------

## Play: versus bots offline, host a LAN room, or join one by code.
func show_play(mode := "") -> void:
	if mode != "":
		_play_mode = mode
	var box := _new_screen("Play")
	box.add_child(UiTheme.label("PLAY", "Title"))
	var modes := HBoxContainer.new()
	var lan_ok := Net.webrtc_available()
	for m in [["bots", "Versus bots"], ["host", "Host LAN"], ["join", "Join LAN"]]:
		var b := UiTheme.button(m[1], func() -> void: show_play(m[0]))
		b.toggle_mode = true
		b.set_pressed_no_signal(m[0] == _play_mode)
		b.disabled = m[0] != "bots" and not lan_ok
		modes.add_child(b)
	var online := UiTheme.button("Internet  ·  coming soon", func() -> void: pass)
	online.disabled = true
	modes.add_child(online)
	box.add_child(modes)
	if not lan_ok:
		box.add_child(UiTheme.label("LAN play runs in the browser build (desktop builds need the webrtc-native extension).", "Muted"))
	if _play_mode == "join" and lan_ok:
		_join_form(box)
		return

	box.add_child(UiTheme.label("ARENA", "Heading"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_cards.clear()
	var prefs: Dictionary = Settings.match_prefs
	for i in Maps.LIST.size():
		var card := MapPreview.new(Maps.LIST[i])
		card.selected = i == int(prefs.map)
		card.pressed.connect(func() -> void:
			Sfx.play("ui_click", -6.0)
			prefs.map = i
			for k in _cards.size():
				_cards[k].selected = k == i)
		_cards.append(card)
		grid.add_child(card)
	box.add_child(grid)
	var desc := UiTheme.label(Maps.LIST[int(prefs.map)].desc, "Muted")
	box.add_child(desc)
	for i in _cards.size():
		_cards[i].pressed.connect(func() -> void: desc.text = Maps.LIST[i].desc)

	var opts := HBoxContainer.new()
	opts.add_theme_constant_override("separation", 24)
	opts.add_child(_option("Bots", ["None", "1", "2", "3", "4", "5", "6", "7"], int(prefs.bots),
			func(i: int) -> void: prefs.bots = i))
	opts.add_child(_option("Bot skill", BOT_SKILL_NAMES, int(prefs.skill), func(i: int) -> void: prefs.skill = i))
	opts.add_child(_option("Frag limit", FRAG_OPTIONS.map(func(f: int) -> String: return str(f)),
			maxi(0, FRAG_OPTIONS.find(int(prefs.frags))), func(i: int) -> void: prefs.frags = FRAG_OPTIONS[i]))
	opts.add_child(_option("Time limit", TIME_OPTIONS.map(func(m: int) -> String: return "None" if m == 0 else "%d min" % m),
			maxi(0, TIME_OPTIONS.find(int(prefs.minutes))), func(i: int) -> void: prefs.minutes = TIME_OPTIONS[i]))
	box.add_child(opts)

	var row := _back_row()
	var hosting := _play_mode == "host" and lan_ok
	var start := UiTheme.button("Host match" if hosting else "Start match", func() -> void:
		Settings.save_settings()
		if hosting:
			host_requested.emit(prefs.duplicate())
		else:
			play_requested.emit(prefs.duplicate()))
	start.custom_minimum_size.x = 220
	row.add_child(start)
	box.add_child(_spacer(6))
	box.add_child(row)
	start.grab_focus.call_deferred()


func _join_form(box: VBoxContainer) -> void:
	box.add_child(_spacer(12))
	box.add_child(UiTheme.label("ROOM CODE", "Heading"))
	var code := LineEdit.new()
	code.placeholder_text = "e.g. K7QX2M"
	code.max_length = 6
	code.custom_minimum_size = Vector2(260, 52)
	code.add_theme_font_override("font", UiTheme.TITLE)
	code.add_theme_font_size_override("font_size", 28)
	code.text_changed.connect(func(t: String) -> void:
		var caret := code.caret_column
		code.text = t.to_upper()
		code.caret_column = caret)
	var go := func() -> void:
		if code.text.strip_edges().length() == 6:
			join_requested.emit(code.text.strip_edges())
	code.text_submitted.connect(func(_t: String) -> void: go.call())
	box.add_child(code)
	box.add_child(UiTheme.label("Ask the host for their 6-letter code (it's shown in their lobby).", "Muted"))
	var row := _back_row()
	var join := UiTheme.button("Join", go)
	join.custom_minimum_size.x = 220
	row.add_child(join)
	box.add_child(_spacer(6))
	box.add_child(row)
	code.grab_focus.call_deferred()


## LAN lobby: room code, join link, who's here. The host starts the match.
func show_lobby() -> void:
	var box := _new_screen("Lobby")
	box.add_child(UiTheme.label("LAN LOBBY", "Title"))
	var code := UiTheme.label("…", "Title")
	code.add_theme_font_size_override("font_size", 64)
	code.add_theme_color_override("font_color", UiTheme.ACCENT)
	box.add_child(UiTheme.label("ROOM CODE", "Heading"))
	box.add_child(code)
	var link := UiTheme.label("", "Muted")
	var link_row := HBoxContainer.new()
	link_row.add_child(link)
	var copy := UiTheme.button("Copy join link", func() -> void:
		DisplayServer.clipboard_set(Net.join_link()))
	link_row.add_child(copy)
	box.add_child(link_row)
	var status := UiTheme.label("", "Muted")
	box.add_child(status)
	box.add_child(UiTheme.label("PLAYERS", "Heading"))
	var players := VBoxContainer.new()
	players.add_theme_constant_override("separation", 4)
	box.add_child(players)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(fill)
	var row := HBoxContainer.new()
	row.add_child(UiTheme.button("Leave", func() -> void: lobby_leave_requested.emit()))
	var start := UiTheme.button("Start match", func() -> void: lobby_start_requested.emit())
	start.custom_minimum_size.x = 220
	row.add_child(start)
	box.add_child(row)

	var refresh := func() -> void:
		var hosting := Net.role == Net.Role.HOST
		code.text = Net.code if Net.code != "" else "…"
		link.text = Net.join_link() if hosting else ""
		copy.visible = hosting and Net.join_link() != ""
		start.visible = hosting
		var cfg: Dictionary = Net.config
		if not cfg.is_empty():
			status.text = "%s · %d bots (%s) · %d frags%s" % [Maps.LIST[clampi(int(cfg.map), 0, Maps.LIST.size() - 1)].name,
					int(cfg.bots), BOT_SKILL_NAMES[clampi(int(cfg.skill), 0, 4)], int(cfg.frags),
					" · %d min" % int(cfg.minutes) if int(cfg.minutes) > 0 else ""]
		for c in players.get_children():
			c.queue_free()
		var ids := Net.lobby.keys()
		ids.sort()
		for id in ids:
			var p: Dictionary = Net.lobby[id]
			var tag := "  (host)" if id == 1 else ""
			var you := "  — you" if id == Net.my_id else ""
			var l := UiTheme.label("●  %s%s%s" % [p.name, tag, you])
			l.add_theme_color_override("font_color", p.look.primary.lightened(0.3))
			players.add_child(l)
		if ids.is_empty():
			players.add_child(UiTheme.label("Connecting…", "Muted"))
	Net.lobby_changed.connect(refresh)
	Net.status_changed.connect(func(t: String) -> void: status.text = t)
	box.tree_exiting.connect(func() -> void:
		Net.lobby_changed.disconnect(refresh))
	refresh.call()
	start.grab_focus.call_deferred()


## A short message across the top of the menu (connection errors, "host left"...).
func show_notice(text: String) -> void:
	var n := PanelContainer.new()
	n.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 18)
	n.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var l := UiTheme.label(text)
	l.add_theme_color_override("font_color", Color("ffc93c"))
	n.add_child(l)
	_root.add_child(n)
	var tw := create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(n, "modulate:a", 0.0, 0.6)
	tw.tween_callback(n.queue_free)


func _option(title: String, items: Array, selected: int, apply: Callable) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.add_child(UiTheme.label(title.to_upper(), "Heading"))
	var o := OptionButton.new()
	for t in items:
		o.add_item(t)
	o.selected = clampi(selected, 0, items.size() - 1)
	o.custom_minimum_size.x = 150
	o.item_selected.connect(func(i: int) -> void:
		Sfx.play("ui_click", -6.0)
		apply.call(i))
	col.add_child(o)
	return col


# --- customize -----------------------------------------------------------------------

func show_customize() -> void:
	var box := _new_screen("Customize")
	box.add_child(UiTheme.label("CUSTOMIZE", "Title"))
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 28)
	box.add_child(cols)

	# Fighter list.
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.add_child(UiTheme.label("FIGHTER", "Heading"))
	var grid := GridContainer.new()
	grid.columns = 2
	for i in Characters.LIST.size():
		var c: Dictionary = Characters.LIST[i]
		var b := UiTheme.button(c.name, func() -> void:
			Settings.character = i
			Settings.look_overrides.clear()
			_refresh_look(), "")
		b.tooltip_text = c.tag
		b.custom_minimum_size = Vector2(130, 34)
		b.icon = _swatch_icon(c.primary)
		grid.add_child(b)
	list.add_child(grid)
	cols.add_child(list)

	# Live preview.
	_preview = CharPreview.new()
	_preview.custom_minimum_size = Vector2(320, 360)
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(_preview)

	# Colours, helmet, name.
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 330
	for part in [["primary", "Armour colour"], ["secondary", "Undersuit colour"], ["visor", "Visor glow"]]:
		side.add_child(UiTheme.label(String(part[1]).to_upper(), "Heading"))
		side.add_child(_swatches(part[0]))
	side.add_child(UiTheme.label("HELMET", "Heading"))
	var helmets := HBoxContainer.new()
	helmets.add_theme_constant_override("separation", 4)
	for h in Characters.HELMET_NAMES.size():
		var hb := UiTheme.button(Characters.HELMET_NAMES[h], func() -> void:
			Settings.look_overrides.helmet = h
			_refresh_look())
		hb.add_theme_font_size_override("font_size", 13)
		helmets.add_child(hb)
	side.add_child(helmets)
	side.add_child(UiTheme.label("NAME", "Heading"))
	var name_edit := LineEdit.new()
	name_edit.text = Settings.player_name
	name_edit.max_length = 16
	name_edit.text_changed.connect(func(t: String) -> void:
		var clean := t.strip_edges()
		if clean != "":
			Settings.player_name = clean)
	side.add_child(name_edit)
	var reset := UiTheme.button("Reset colours", func() -> void:
		Settings.look_overrides.clear()
		_refresh_look())
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	side.add_child(reset)
	cols.add_child(side)

	var row := _back_row()
	(row.get_child(0) as Button).pressed.connect(Settings.save_settings)
	box.add_child(row)
	_refresh_look()


func _swatches(part: String) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 9
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	for hex in SWATCHES:
		var col := Color(hex)
		var b := Button.new()
		b.custom_minimum_size = Vector2(30, 24)
		b.tooltip_text = "#" + hex
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(4)
		b.add_theme_stylebox_override("normal", sb)
		var hover := sb.duplicate()
		hover.set_border_width_all(2)
		hover.border_color = Color.WHITE
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("focus", hover)
		b.add_theme_stylebox_override("pressed", hover)
		b.pressed.connect(func() -> void:
			Sfx.play("ui_click", -8.0)
			Settings.look_overrides[part] = col
			_refresh_look())
		g.add_child(b)
	return g


func _swatch_icon(col: Color) -> Texture2D:
	var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	img.fill(col)
	return ImageTexture.create_from_image(img)


func _refresh_look() -> void:
	if _preview:
		_preview.look = Settings.look()


# --- settings / credits --------------------------------------------------------------

func show_settings() -> void:
	var box := _new_screen("Settings")
	box.add_child(UiTheme.label("SETTINGS", "Title"))
	var panel := SettingsPanel.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.custom_minimum_size.x = 680
	box.add_child(panel)
	box.add_child(_back_row())


func show_credits() -> void:
	var box := _new_screen("Credits")
	box.add_child(UiTheme.label("CREDITS", "Title"))
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.custom_minimum_size.x = 640
	text.add_theme_font_override("normal_font", UiTheme.FONT)
	text.add_theme_font_override("bold_font", UiTheme.TITLE)
	text.add_theme_font_size_override("normal_font_size", 17)
	text.text = """[b]FRAGLINE[/b] — built with Godot Engine 4.7 (MIT license).

[b]Music[/b] — The Cynic Project / cynicmusic.com (OpenGameArt). CC0.
[b]Sound effects[/b] — Kenney (kenney.nl): Sci-fi, Impact and Interface sounds. CC0.
[b]Fonts[/b] — Chakra Petch by Cadson Demak. SIL Open Font License 1.1.

[b]Inspired by[/b] Unreal Flash (2006, Newgrounds) and Unreal Tournament.
Characters, levels, effects and UI are drawn procedurally for this game."""
	box.add_child(text)
	box.add_child(_back_row())
