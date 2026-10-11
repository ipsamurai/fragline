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
const QrCode := preload("res://addons/qr_code/qr_code.gd")
const QR_SIZE := 210.0
const CREDIT_CARDS := [
	["ENGINE & CODE", "[b]Godot Engine 4.7[/b]\n[color=#39e1ff]MIT License[/color]\n\n[b]QR Code addon[/b] by Kenyoni Software\n[color=#39e1ff]MIT License[/color]"],
	["WEAPON ART", "[b]Guns[/b] pixel-art sprites by [b]SnoopethDuckDuck[/b]\n[color=#39e1ff]CC0[/color]\n\nFighters, arenas, effects and UI are drawn procedurally in code."],
	["FONTS", "[b]Chakra Petch[/b] by Cadson Demak\n[color=#39e1ff]SIL Open Font License 1.1[/color]"],
	["SOUND EFFECTS", "[b]FREE FPS SFX Pack[/b] by LMGLolo\n[color=#39e1ff]CC BY-ND 4.0[/color]\n[b]Snake's Authentic Gun Sounds And More[/b] by SnakeF8 (F8 Studios)\n[color=#39e1ff]Free to use[/color]\n[b]Kenney[/b]: Sci-fi, Impact and Interface sounds\n[color=#39e1ff]CC0[/color]"],
	["MUSIC", "[b]The Cynic Project[/b] / cynicmusic.com (OpenGameArt)\nCalm Relax 1 · Hyper Ultra-Racing · Hyperflight Racing · Awake!\n[color=#39e1ff]CC0[/color]"],
	["INSPIRED BY", "[b]Unreal Flash[/b] (2006, Newgrounds) by Erik S, itself a tribute to [b]Unreal Tournament[/b].\nFRAGLINE shares no code or assets with either."],
]

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
		if _screen.name == "Customize":
			Settings.save_settings()            # leaving customize by any route (Back or Esc) keeps the changes
		_screen.queue_free()
	_screen = screen
	_root.add_child(screen)
	_dim.visible = screen.name != "Main"
	# Sub-screens cover the live match with an 82% dim: freeze it there to save the frame budget.
	var w: Node = get_parent().get("world") if get_parent() else null
	if w:
		w.process_mode = Node.PROCESS_MODE_INHERIT if screen.name == "Main" else Node.PROCESS_MODE_DISABLED
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
	var box := _new_screen("Main", 56)
	box.add_theme_constant_override("separation", 2)
	box.add_child(UiTheme.label("NEON ARENA SHOOTER  ·  BOTS  ·  LAN", "Kicker"))
	box.add_child(MenuLogo.new())
	box.add_child(UiTheme.label("2D arena combat  ·  a tribute to Unreal Flash", "Muted"))
	box.add_child(_spacer(22))
	var entries := [
		["Play", show_play, "Versus bots  ·  host or join LAN"],
		["Training", func() -> void: training_requested.emit(), "Range, dummies, agility course"],
		["Armory", func() -> void: show_armory(), "All 9 weapons  ·  stats  ·  test fire"],
		["Customize", show_customize, "Fighter, colours and helmet"],
		["Settings", show_settings, "Audio, graphics, controls"],
		["Credits", show_credits, "The people behind the assets"],
	]
	if not OS.has_feature("web"):
		entries.append(["Quit", func() -> void: get_tree().quit(), "Back to the desktop"])
	var first: Button
	for i in entries.size():
		var b := NeonButton.new(entries[i][0], i + 1, entries[i][2])
		b.name = String(entries[i][0])
		b.pressed.connect(entries[i][1])
		b.custom_minimum_size.x = 430
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		box.add_child(b)
		if first == null:
			first = b
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(fill)
	var hint := UiTheme.label("Press  X  for X-Ray vision: see what the bots see", "Muted")
	hint.add_theme_color_override("font_color", Color(UiTheme.ACCENT, 0.85))
	box.add_child(hint)
	box.add_child(UiTheme.label("Playing as %s  ·  Esc goes back  ·  runs in any browser, ~6.5 MB, peer-to-peer LAN"
			% Settings.player_name, "Muted"))
	# Featured weapon, right side (the screen's MarginContainer overlays it on the column).
	var featured := WeaponShowcase.new()
	featured.custom_minimum_size.x = 420
	featured.size_flags_horizontal = Control.SIZE_SHRINK_END
	featured.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	featured.open_requested.connect(func(wid: int) -> void: show_armory(wid))
	box.get_parent().add_child(featured)
	first.grab_focus.call_deferred()


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c


## Screen header: small kicker line over a big title.
func _header(box: VBoxContainer, title: String, kicker: String) -> void:
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 0)
	head.add_child(UiTheme.label(kicker, "Kicker"))
	head.add_child(UiTheme.label(title, "Title"))
	box.add_child(head)


# --- armory --------------------------------------------------------------------------

## Every weapon: sprite, both fire modes (from Weapons data), stat bars and a test-fire button.
## Arrow keys / d-pad move through the grid (focus selects), Enter or click test-fires.
func show_armory(focus_wid := 0) -> void:
	var box := _new_screen("Armory", 44)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 26)
	box.add_child(cols)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	_header(left, "ARMORY", "%d WEAPONS  ·  EACH WITH AN ALT FIRE" % Weapons.COUNT)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	left.add_child(grid)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(fill)
	var back_row := _back_row()
	back_row.add_child(UiTheme.label("  Arrows / d-pad to browse  ·  Enter test-fires  ·  Esc goes back", "Muted"))
	back_row.get_child(1).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.add_child(back_row)

	# Detail card.
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	card.custom_minimum_size.x = 452
	cols.add_child(card)
	var d := VBoxContainer.new()
	d.add_theme_constant_override("separation", 4)
	card.add_child(d)
	var icon := GunIcon.new(1.0)
	icon.custom_minimum_size.y = 118
	icon.pad = 10.0
	d.add_child(icon)
	var title := UiTheme.label("", "Title")
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_constant_override("shadow_outline_size", 10)
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 0)
	d.add_child(title)
	var kind := UiTheme.label("", "Kicker")
	d.add_child(kind)
	var tag := UiTheme.label("", "Muted")
	tag.add_theme_font_size_override("font_size", 15)
	tag.add_theme_color_override("font_color", Color(UiTheme.TEXT, 0.85))
	d.add_child(tag)
	d.add_child(_spacer(4))
	var modes: Array[Label] = []
	for m in ["PRIMARY FIRE", "ALT FIRE"]:
		var block := PanelContainer.new()
		block.theme_type_variation = "CardFlat"
		var bv := VBoxContainer.new()
		bv.add_theme_constant_override("separation", 0)
		block.add_child(bv)
		var hl := UiTheme.label(m, "Heading")
		hl.add_theme_font_size_override("font_size", 12)
		bv.add_child(hl)
		var what := UiTheme.label("")
		what.add_theme_font_size_override("font_size", 16)
		bv.add_child(what)
		var nums := UiTheme.label("", "Muted")
		nums.add_theme_font_size_override("font_size", 13)
		bv.add_child(nums)
		modes.append_array([what, nums])
		d.add_child(block)
	d.add_child(_spacer(4))
	var bars := StatBars.new(4)
	d.add_child(bars)
	var ammo := UiTheme.label("", "Muted")
	d.add_child(ammo)
	var dfill := Control.new()
	dfill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	d.add_child(dfill)
	var sel := [focus_wid]                    # array: lambdas capture by value
	var fire_row := HBoxContainer.new()
	var test := UiTheme.button("Test fire", func() -> void: pass)
	test.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var test_alt := UiTheme.button("Alt fire", func() -> void: pass)
	test_alt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fire_row.add_child(test)
	fire_row.add_child(test_alt)
	d.add_child(fire_row)

	var cards: Array[ArmoryCard] = []
	var shoot := func(alt: bool) -> void:
		var s := Weapons.stats(sel[0], alt)
		Sfx.play(String(s.sound), -4.0)
		var tw := icon.create_tween()                # recoil kick + flash
		icon.modulate = Color(1.8, 1.8, 1.8)
		icon.position.x = icon.position.x - 10.0
		tw.tween_property(icon, "modulate", Color.WHITE, 0.25)
		tw.parallel().tween_property(icon, "position:x", icon.position.x + 10.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var select := func(wid: int) -> void:
		sel[0] = wid
		for c in cards:
			c.selected = c.wid == wid
		var w: Dictionary = Weapons.LIST[wid]
		var col: Color = w.color
		var tint := col if col.get_luminance() < 0.92 else UiTheme.ACCENT
		icon.wid = wid
		title.text = String(w.name).to_upper()
		title.add_theme_color_override("font_shadow_color", Color(tint, 0.45))
		kind.text = "KEY %d  ·  %s" % [wid + 1, "HITSCAN" if w.kind == Weapons.Kind.HITSCAN else "PROJECTILE"]
		kind.add_theme_color_override("font_color", tint)
		tag.text = WeaponInfo.TAGLINES[wid]
		modes[0].text = WeaponInfo.PRIMARY[wid]
		modes[1].text = WeaponInfo.mode_line(wid, false)
		var has_alt: bool = w.has("alt")
		modes[2].text = WeaponInfo.ALT[wid] if has_alt else "No alt fire. Make the one shot count."
		modes[3].text = WeaponInfo.mode_line(wid, true) if has_alt else "—"
		test_alt.disabled = not has_alt
		var st := WeaponInfo.stats(wid)
		bars.set_stats(st.bars, st.values, tint)
		ammo.text = WeaponInfo.ammo_text(wid)
	test.pressed.connect(func() -> void: shoot.call(false))
	test_alt.pressed.connect(func() -> void: shoot.call(true))
	for i in Weapons.COUNT:
		var c := ArmoryCard.new(i)
		c.name = "Weapon%d" % (i + 1)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.focus_entered.connect(func() -> void: select.call(i))
		c.pressed.connect(func() -> void:
			select.call(i)
			shoot.call(false))
		cards.append(c)
		grid.add_child(c)
	select.call(clampi(focus_wid, 0, Weapons.COUNT - 1))
	cards[clampi(focus_wid, 0, Weapons.COUNT - 1)].grab_focus.call_deferred()


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
	box.add_child(modes)
	if not lan_ok:
		box.add_child(UiTheme.label("LAN play runs in the browser build (desktop builds need the webrtc-native extension).", "Muted"))
	if _play_mode == "join" and lan_ok:
		_join_form(box)
		return

	box.add_child(UiTheme.label("ARENA", "Heading"))
	var grid := GridContainer.new()
	grid.columns = 4
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
	# Game mode (GameMode.*): one-line description below; Gun Game sets its own frag limit.
	prefs.mode = GameMode.sanitize(prefs.get("mode", GameMode.DEATHMATCH))
	var mode_desc := UiTheme.label(GameMode.desc_of(prefs.mode), "Muted")
	var frag_col := _option("Frag limit", FRAG_OPTIONS.map(func(f: int) -> String: return str(f)),
			maxi(0, FRAG_OPTIONS.find(int(prefs.frags))), func(i: int) -> void: prefs.frags = FRAG_OPTIONS[i])
	(frag_col.get_child(1) as OptionButton).disabled = int(prefs.mode) == GameMode.GUN_GAME
	var mode_col := _option("Mode", GameMode.NAMES, int(prefs.mode), func(i: int) -> void:
		prefs.mode = i
		mode_desc.text = GameMode.desc_of(i)
		(frag_col.get_child(1) as OptionButton).disabled = i == GameMode.GUN_GAME)
	mode_col.name = "Mode"
	opts.add_child(mode_col)
	opts.add_child(_option("Bots", ["None", "1", "2", "3", "4", "5", "6", "7"], int(prefs.bots),
			func(i: int) -> void: prefs.bots = i))
	opts.add_child(_option("Bot skill", BOT_SKILL_NAMES, int(prefs.skill), func(i: int) -> void: prefs.skill = i))
	opts.add_child(frag_col)
	opts.add_child(_option("Time limit", TIME_OPTIONS.map(func(m: int) -> String: return "None" if m == 0 else "%d min" % m),
			maxi(0, TIME_OPTIONS.find(int(prefs.minutes))), func(i: int) -> void: prefs.minutes = TIME_OPTIONS[i]))
	var grav_col := VBoxContainer.new()
	grav_col.add_theme_constant_override("separation", 4)
	grav_col.add_child(UiTheme.label("MUTATOR", "Heading"))
	var grav := CheckBox.new()
	grav.text = "Low gravity"
	grav.button_pressed = bool(prefs.get("lowgrav", false))
	grav.toggled.connect(func(on: bool) -> void:
		Sfx.play("ui_click", -6.0)
		prefs.lowgrav = on)
	grav_col.add_child(grav)
	opts.add_child(grav_col)
	box.add_child(opts)
	box.add_child(mode_desc)

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
	if hosting:
		var phones := UiTheme.label("  Phones can join by scanning the QR code in the lobby.", "Muted")
		phones.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(phones)
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
	# Read-only but selectable, so the link can always be copied by hand.
	var link := LineEdit.new()
	link.editable = false
	link.select_all_on_focus = true
	link.custom_minimum_size.x = 440
	var link_row := HBoxContainer.new()
	link_row.add_child(link)
	var copy := UiTheme.button("Copy join link", func() -> void: pass)
	copy.pressed.connect(func() -> void:          # connected after creation so the lambda sees `copy`
		copy.text = "Copied!" if _copy_text(Net.join_link()) else "Select the link to copy it")
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
	# Host: QR code of the join link, top right (the screen's MarginContainer overlays it).
	var qr_panel := PanelContainer.new()
	qr_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	qr_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var qr_box := VBoxContainer.new()
	qr_box.add_theme_constant_override("separation", 8)
	qr_panel.add_child(qr_box)
	var qr_rect := TextureRect.new()
	qr_rect.custom_minimum_size = Vector2(QR_SIZE, QR_SIZE)
	qr_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	qr_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	qr_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	qr_box.add_child(qr_rect)
	var qr_caption := UiTheme.label("Scan to join on your phone")
	qr_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qr_caption.add_theme_color_override("font_color", UiTheme.ACCENT)
	qr_box.add_child(qr_caption)
	var qr_sub := UiTheme.label("same Wi-Fi as this computer", "Muted")
	qr_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qr_box.add_child(qr_sub)
	box.get_parent().add_child(qr_panel)
	var qr_link := [""]                           # link the QR was last made for (array: lambdas capture by value)
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
		link.visible = hosting and Net.join_link() != ""
		copy.visible = link.visible
		if link.visible and qr_link[0] != link.text:
			qr_link[0] = link.text
			qr_rect.texture = qr_texture(link.text)
		qr_panel.visible = link.visible and qr_rect.texture != null
		start.visible = hosting
		var cfg: Dictionary = Net.config
		if not cfg.is_empty():
			status.text = "%s · %s%s · %d bots (%s) · %d frags%s" % [Maps.LIST[clampi(int(cfg.map), 0, Maps.LIST.size() - 1)].name,
					GameMode.name_of(int(cfg.get("mode", 0))), " · Low gravity" if cfg.get("lowgrav", false) else "",
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
	var on_status := func(t: String) -> void: status.text = t
	Net.lobby_changed.connect(refresh)
	Net.status_changed.connect(on_status)
	box.tree_exiting.connect(func() -> void:
		Net.lobby_changed.disconnect(refresh)
		Net.status_changed.disconnect(on_status))
	refresh.call()
	start.grab_focus.call_deferred()


## QR code (byte mode, error correction M) as a texture: dark modules on white with a 4-module
## quiet zone, one pixel per module (draw it with nearest filtering). Null if the text won't fit.
static func qr_texture(text: String) -> ImageTexture:
	var qr := QrCode.new(QrCode.ErrorCorrection.MEDIUM)
	qr.put_byte(text.to_utf8_buffer())
	if text.is_empty() or qr.calc_min_version() < 1:
		return null
	var img := QrCode.generate_image(qr.encode(), 1, Color.WHITE, Color("0a0e18"), 4)
	return ImageTexture.create_from_image(img)


## Copy to the clipboard. On the web, the async clipboard API needs a secure context (HTTPS or
## localhost), which a plain-HTTP LAN address isn't, so fall back to a textarea + execCommand.
func _copy_text(text: String) -> bool:
	if not OS.has_feature("web"):
		DisplayServer.clipboard_set(text)
		return true
	var js := """(function (t) {
		if (window.isSecureContext && navigator.clipboard) {
			navigator.clipboard.writeText(t).catch(function () {});
			return true;
		}
		var a = document.createElement('textarea');
		a.value = t;
		a.setAttribute('readonly', '');
		a.style.position = 'fixed'; a.style.top = '0'; a.style.left = '0'; a.style.opacity = '0';
		document.body.appendChild(a);
		a.focus();
		a.select();
		var ok = false;
		try { ok = document.execCommand('copy'); } catch (e) {}
		document.body.removeChild(a);
		var c = document.getElementById('canvas') || document.querySelector('canvas');
		if (c) { c.focus(); }
		return ok ? '1' : '0';
	})(%s)""" % JSON.stringify(text)
	return str(JavaScriptBridge.eval(js, true)) == "1"


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
	var box := _new_screen("Customize", 44)
	_header(box, "CUSTOMIZE", "YOUR FIGHTER  ·  SAVED AUTOMATICALLY")
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 24)
	box.add_child(cols)

	# Fighter list.
	var list_card := PanelContainer.new()
	list_card.theme_type_variation = "Card"
	list_card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list_card.add_child(list)
	list.add_child(UiTheme.label("FIGHTER", "Heading"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	var fighters := ButtonGroup.new()
	for i in Characters.LIST.size():
		var c: Dictionary = Characters.LIST[i]
		var b := UiTheme.button(c.name, func() -> void:
			Settings.character = i
			Settings.look_overrides.clear()
			_refresh_look(), "")
		b.tooltip_text = c.tag
		b.toggle_mode = true
		b.button_group = fighters
		b.set_pressed_no_signal(i == Settings.character)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(136, 34)
		b.icon = _swatch_icon(c.primary)
		grid.add_child(b)
	list.add_child(grid)
	cols.add_child(list_card)

	# Live preview.
	_preview = CharPreview.new()
	_preview.custom_minimum_size = Vector2(320, 360)
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(_preview)

	# Colours, helmet, name.
	var side_card := PanelContainer.new()
	side_card.theme_type_variation = "Card"
	side_card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	side.custom_minimum_size.x = 330
	side_card.add_child(side)
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
	cols.add_child(side_card)

	box.add_child(_back_row())                  # _swap() saves the settings when this screen closes
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
	var box := _new_screen("Credits", 44)
	_header(box, "CREDITS", "MADE WITH GODOT  ·  OPEN-LICENCE ASSETS")
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	box.add_child(grid)
	for c in CREDIT_CARDS:
		grid.add_child(_credit_card(c[0], c[1]))
	box.add_child(_spacer(0))
	box.get_child(box.get_child_count() - 1).size_flags_vertical = Control.SIZE_EXPAND_FILL
	var row := _back_row()
	var thanks := UiTheme.label("  Thanks to every creator who shares their work freely.", "Muted")
	thanks.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(thanks)
	box.add_child(row)
	row.get_child(0).grab_focus.call_deferred()


func _credit_card(title: String, body: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.y = 190
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	v.add_child(UiTheme.label(title, "Kicker"))
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = 300
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_font_override("normal_font", UiTheme.FONT)
	text.add_theme_font_override("bold_font", UiTheme.TITLE)
	text.add_theme_font_size_override("normal_font_size", 15)
	text.add_theme_font_size_override("bold_font_size", 16)
	text.add_theme_color_override("default_color", Color(UiTheme.TEXT, 0.78))
	text.add_theme_constant_override("line_separation", 3)
	text.text = body
	v.add_child(text)
	return card
