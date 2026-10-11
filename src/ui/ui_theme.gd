class_name UiTheme
## The one UI theme: dark glass panels, cyan accent, Chakra Petch. Built in code once.

const FONT := preload("res://assets/fonts/ui.ttf")
const TITLE := preload("res://assets/fonts/title.ttf")
const ACCENT := Color("39e1ff")
const GOLD := Color("ffc93c")
const TEXT := Color("e8f0ff")
const MUTED := Color(0.91, 0.94, 1.0, 0.6)
const PANEL_BG := Color(0.035, 0.05, 0.09, 0.9)

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func _box(bg: Color, border: Color, radius := 6, margin := Vector2(14, 8), width := 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin.x
	sb.content_margin_right = margin.x
	sb.content_margin_top = margin.y
	sb.content_margin_bottom = margin.y
	return sb


## _box with a soft outer glow (StyleBoxFlat shadow, centred).
static func _glow_box(bg: Color, border: Color, glow: Color, glow_size := 8, radius := 6,
		margin := Vector2(14, 8), width := 1) -> StyleBoxFlat:
	var sb := _box(bg, border, radius, margin, width)
	sb.shadow_color = glow
	sb.shadow_size = glow_size
	sb.anti_aliasing = true
	return sb


## Small icons (toggle pill, check box, slider knob) baked once into textures.
static func _icon(w: int, h: int, paint: Callable) -> ImageTexture:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			img.set_pixel(x, y, paint.call(x + 0.5, y + 0.5))
	return ImageTexture.create_from_image(img)


## Signed-distance rounded rectangle (negative inside).
static func _rr(x: float, y: float, cx: float, cy: float, hw: float, hh: float, r: float) -> float:
	var qx := absf(x - cx) - (hw - r)
	var qy := absf(y - cy) - (hh - r)
	return Vector2(maxf(qx, 0.0), maxf(qy, 0.0)).length() + minf(maxf(qx, qy), 0.0) - r


static func _toggle(on: bool, dim: bool) -> ImageTexture:
	var a := 0.4 if dim else 1.0
	return _icon(44, 24, func(x: float, y: float) -> Color:
		var rail := _rr(x, y, 22, 12, 21, 11, 11)
		var kx := 32.0 if on else 12.0
		var knob := Vector2(x - kx, y - 12).length() - 8.0
		var c := Color(0, 0, 0, 0)
		var fill := Color(ACCENT, 0.85 * a) if on else Color(1, 1, 1, 0.08 * a)
		c = c.blend(Color(fill, fill.a * clampf(0.5 - rail, 0.0, 1.0)))
		var edge := clampf(1.0 - absf(rail + 0.5), 0.0, 1.0)
		c = c.blend(Color(ACCENT if on else Color(1, 1, 1), (0.9 if on else 0.25) * a * edge))
		var kc := Color(1, 1, 1, a) if on else Color(0.75, 0.8, 0.9, 0.85 * a)
		c = c.blend(Color(kc, kc.a * clampf(0.5 - knob, 0.0, 1.0)))
		return c)


static func _check(on: bool) -> ImageTexture:
	return _icon(22, 22, func(x: float, y: float) -> Color:
		var box := _rr(x, y, 11, 11, 9, 9, 3)
		var c := Color(0, 0, 0, 0)
		c = c.blend(Color(ACCENT, (0.8 if on else 0.06) * clampf(0.5 - box, 0.0, 1.0)))
		c = c.blend(Color(ACCENT if on else Color(1, 1, 1), (1.0 if on else 0.3) * clampf(1.0 - absf(box + 0.5), 0.0, 1.0)))
		if on:
			var inner := _rr(x, y, 11, 11, 4, 4, 1.5)
			c = c.blend(Color(0.02, 0.03, 0.06, clampf(0.5 - inner, 0.0, 1.0)))
		return c)


static func _knob(r: float, hot: bool) -> ImageTexture:
	var s := int(ceil(r * 2.0 + 8.0))
	var c0 := s * 0.5
	return _icon(s, s, func(x: float, y: float) -> Color:
		var d := Vector2(x - c0, y - c0).length()
		var c := Color(ACCENT, (0.35 if hot else 0.18) * clampf(1.0 - (d - r) / 4.0, 0.0, 1.0) * float(d > r - 1.0))
		c = c.blend(Color(ACCENT, clampf(r + 0.5 - d, 0.0, 1.0)))
		c = c.blend(Color(1, 1, 1, clampf(r * 0.45 + 0.5 - d, 0.0, 1.0)))
		return c)


static func _build() -> Theme:
	for f: FontFile in [FONT, TITLE]:
		if f.fallbacks.is_empty():
			f.fallbacks = [ThemeDB.fallback_font]       # symbols the font lacks (∞, arrows)
	var t := Theme.new()
	t.default_font = FONT
	t.default_font_size = 17
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", _box(PANEL_BG, Color(ACCENT, 0.3), 10, Vector2(20, 18)))
	t.set_stylebox("panel", "Panel", _box(PANEL_BG, Color(ACCENT, 0.3), 10, Vector2(20, 18)))

	# Buttons (also used by CheckButton / OptionButton).
	# Neon glass: dark fill + faint cyan rim; hover lights the rim and adds a soft glow.
	var states := {
		"normal": _box(Color(0.07, 0.1, 0.17, 0.72), Color(ACCENT, 0.22), 5),
		"hover": _glow_box(Color(ACCENT, 0.16), Color(ACCENT, 0.9), Color(ACCENT, 0.22), 7, 5),
		"pressed": _glow_box(Color(ACCENT, 0.3), ACCENT, Color(ACCENT, 0.3), 9, 5),
		"hover_pressed": _glow_box(Color(ACCENT, 0.36), ACCENT, Color(ACCENT, 0.36), 10, 5),
		"focus": _glow_box(Color(0, 0, 0, 0), Color(ACCENT, 0.95), Color(ACCENT, 0.16), 5, 5, Vector2(14, 8), 2),
		"disabled": _box(Color(1, 1, 1, 0.025), Color(1, 1, 1, 0.07), 5),
	}
	for type in ["Button", "OptionButton"]:
		for st in states:
			t.set_stylebox(st, type, states[st])
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_hover_pressed_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, Color(1, 1, 1, 0.3))
	t.set_color("font_outline_color", "Button", Color(ACCENT, 0.0))
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var cb := _box(Color(ACCENT, 0.07) if st in ["hover", "hover_pressed"] else Color(0, 0, 0, 0),
				Color(ACCENT, 0.7) if st == "focus" else Color(0, 0, 0, 0), 5)
		t.set_stylebox(st, "CheckButton", cb)
		t.set_stylebox(st, "CheckBox", cb)
	for type in ["CheckButton", "CheckBox"]:
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, TEXT)
		t.set_color("font_hover_pressed_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, Color.WHITE)
	t.set_icon("checked", "CheckButton", _toggle(true, false))
	t.set_icon("unchecked", "CheckButton", _toggle(false, false))
	t.set_icon("checked_disabled", "CheckButton", _toggle(true, true))
	t.set_icon("unchecked_disabled", "CheckButton", _toggle(false, true))
	t.set_icon("checked", "CheckBox", _check(true))
	t.set_icon("unchecked", "CheckBox", _check(false))
	t.set_icon("radio_checked", "CheckBox", _check(true))
	t.set_icon("radio_unchecked", "CheckBox", _check(false))

	# Drop-down lists (OptionButton popups) and tooltips.
	var popup := _glow_box(Color(0.03, 0.045, 0.08, 0.97), Color(ACCENT, 0.45), Color(0, 0, 0, 0.5), 10, 6, Vector2(6, 6))
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", _box(Color(ACCENT, 0.2), Color(ACCENT, 0.6), 4, Vector2(8, 4)))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_constant("v_separation", "PopupMenu", 8)
	t.set_stylebox("panel", "TooltipPanel", _box(Color(0.03, 0.045, 0.08, 0.96), Color(ACCENT, 0.5), 5, Vector2(10, 6)))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 14)

	# Cards: framed glass panels for grouped content (featured weapon, armory detail, credits).
	t.set_type_variation("Card", "PanelContainer")
	var card := _box(Color(0.025, 0.04, 0.075, 0.9), Color(ACCENT, 0.2), 8, Vector2(22, 18))
	card.border_width_top = 2
	card.shadow_color = Color(0, 0, 0, 0.35)
	card.shadow_size = 12
	t.set_stylebox("panel", "Card", card)
	t.set_type_variation("CardFlat", "PanelContainer")
	t.set_stylebox("panel", "CardFlat", _box(Color(1, 1, 1, 0.025), Color(1, 1, 1, 0.08), 6, Vector2(16, 12)))

	# Big menu buttons: left-aligned, larger, a light accent bar on hover.
	t.set_type_variation("BigButton", "Button")
	t.set_font_size("font_size", "BigButton", 24)
	t.set_font("font", "BigButton", TITLE)
	t.set_constant("h_separation", "BigButton", 12)
	var big_normal := _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 4, Vector2(18, 10))
	var big_hover := _box(Color(ACCENT, 0.12), Color(0, 0, 0, 0), 4, Vector2(18, 10))
	big_hover.border_width_left = 4
	big_hover.border_color = ACCENT
	var big_focus := big_hover.duplicate()
	t.set_stylebox("normal", "BigButton", big_normal)
	t.set_stylebox("hover", "BigButton", big_hover)
	t.set_stylebox("pressed", "BigButton", big_hover)
	t.set_stylebox("focus", "BigButton", big_focus)
	t.set_stylebox("disabled", "BigButton", big_normal)

	# Headings.
	t.set_type_variation("Title", "Label")
	t.set_font("font", "Title", TITLE)
	t.set_font_size("font_size", "Title", 34)
	t.set_type_variation("Heading", "Label")
	t.set_font("font", "Heading", TITLE)
	t.set_font_size("font_size", "Heading", 15)
	t.set_color("font_color", "Heading", Color(ACCENT, 0.9))
	t.set_type_variation("Muted", "Label")
	t.set_color("font_color", "Muted", MUTED)
	t.set_font_size("font_size", "Muted", 14)
	# Kicker: small letter-spaced caps over titles and inside cards.
	var spaced := FontVariation.new()
	spaced.base_font = TITLE
	spaced.spacing_glyph = 3
	t.set_type_variation("Kicker", "Label")
	t.set_font("font", "Kicker", spaced)
	t.set_font_size("font_size", "Kicker", 13)
	t.set_color("font_color", "Kicker", ACCENT)

	# Sliders, text fields, tabs, scroll.
	var rail := _box(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 3, Vector2(0, 3))
	var fill := _box(Color(ACCENT, 0.8), Color(0, 0, 0, 0), 3, Vector2(0, 3))
	t.set_stylebox("slider", "HSlider", rail)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(ACCENT, Color(0, 0, 0, 0), 3, Vector2(0, 3)))
	t.set_icon("grabber", "HSlider", _knob(7.0, false))
	t.set_icon("grabber_highlight", "HSlider", _knob(8.0, true))
	t.set_icon("grabber_disabled", "HSlider", _knob(6.0, false))
	t.set_stylebox("normal", "LineEdit", _box(Color(0.07, 0.1, 0.17, 0.72), Color(ACCENT, 0.22), 5))
	t.set_stylebox("focus", "LineEdit", _glow_box(Color(0, 0, 0, 0), ACCENT, Color(ACCENT, 0.2), 6, 5, Vector2(14, 8), 2))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(TEXT, 0.35))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.35))
	for sb_type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb_type, _box(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), 3, Vector2(3, 3)))
		t.set_stylebox("grabber", sb_type, _box(Color(ACCENT, 0.35), Color(0, 0, 0, 0), 3, Vector2(3, 3)))
		t.set_stylebox("grabber_highlight", sb_type, _box(Color(ACCENT, 0.6), Color(0, 0, 0, 0), 3, Vector2(3, 3)))
		t.set_stylebox("grabber_pressed", sb_type, _box(ACCENT, Color(0, 0, 0, 0), 3, Vector2(3, 3)))
	t.set_stylebox("panel", "TabContainer", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, Vector2(4, 12)))
	t.set_stylebox("tab_selected", "TabBar", _box(Color(ACCENT, 0.18), Color(ACCENT, 0.8), 6, Vector2(16, 6)))
	t.set_stylebox("tab_unselected", "TabBar", _box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.1), 6, Vector2(16, 6)))
	t.set_stylebox("tab_hovered", "TabBar", _box(Color(ACCENT, 0.1), Color(ACCENT, 0.4), 6, Vector2(16, 6)))
	t.set_stylebox("tab_selected", "TabContainer", t.get_stylebox("tab_selected", "TabBar"))
	t.set_stylebox("tab_unselected", "TabContainer", t.get_stylebox("tab_unselected", "TabBar"))
	t.set_stylebox("tab_hovered", "TabContainer", t.get_stylebox("tab_hovered", "TabBar"))
	t.set_color("font_selected_color", "TabContainer", Color.WHITE)
	t.set_color("font_unselected_color", "TabContainer", MUTED)
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	return t


## Small helpers so screens read declaratively.
static func label(text: String, variation := "") -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	return l


static func button(text: String, on_press: Callable, variation := "") -> Button:
	var b := Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	b.pressed.connect(func() -> void: Sfx.play("ui_click", -6.0))
	b.pressed.connect(on_press)
	b.mouse_entered.connect(func() -> void: Sfx.play("ui_hover", -16.0))
	return b
