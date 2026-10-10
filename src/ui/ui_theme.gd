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
	var states := {
		"normal": _box(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.12)),
		"hover": _box(Color(ACCENT, 0.14), Color(ACCENT, 0.7)),
		"pressed": _box(Color(ACCENT, 0.3), ACCENT),
		"focus": _box(Color(0, 0, 0, 0), Color(ACCENT, 0.9), 6, Vector2(14, 8), 2),
		"disabled": _box(Color(1, 1, 1, 0.02), Color(1, 1, 1, 0.06)),
	}
	for type in ["Button", "OptionButton"]:
		for st in states:
			t.set_stylebox(st, type, states[st])
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, Color(1, 1, 1, 0.3))
	t.set_stylebox("pressed", "Button", _box(Color(ACCENT, 0.3), ACCENT))
	for st in ["normal", "hover", "pressed", "focus"]:
		t.set_stylebox(st, "CheckButton", _box(Color(0, 0, 0, 0), Color(ACCENT, 0.6) if st == "focus" else Color(0, 0, 0, 0)))

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

	# Sliders, text fields, tabs, scroll.
	var rail := _box(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 3, Vector2(0, 3))
	var fill := _box(Color(ACCENT, 0.8), Color(0, 0, 0, 0), 3, Vector2(0, 3))
	t.set_stylebox("slider", "HSlider", rail)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_stylebox("normal", "LineEdit", _box(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.15)))
	t.set_stylebox("focus", "LineEdit", _box(Color(1, 1, 1, 0.08), ACCENT))
	t.set_color("font_color", "LineEdit", TEXT)
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
