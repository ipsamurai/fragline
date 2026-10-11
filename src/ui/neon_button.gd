class_name NeonButton
extends Button
## Main-menu entry: index number, big label that slides right on hover/focus, a lit accent bar,
## a hint line that fades in on the right and a chevron. Drawn with draw_rect/draw_string only
## and redrawn only while its 0.16 s hover tween runs.

const H := 44.0

var index := 0
var hint := ""
var accent := UiTheme.ACCENT
var _label := ""
var _index_text := ""
var _hot := 0.0:
	set(v):
		_hot = v
		queue_redraw()
var _tween: Tween
var _born := 0


func _init(p_text: String, p_index: int, p_hint := "") -> void:
	_label = p_text.to_upper()
	text = p_text                              # kept for accessibility / lookups; drawn by us
	index = p_index
	_index_text = "%02d" % p_index
	hint = p_hint
	custom_minimum_size = Vector2(0, H)
	focus_mode = Control.FOCUS_ALL
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(st, empty)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color", "font_disabled_color"]:
		add_theme_color_override(c, Color(0, 0, 0, 0))
	add_theme_font_override("font", UiTheme.TITLE)
	add_theme_font_size_override("font_size", 22)
	mouse_entered.connect(func() -> void:
		Sfx.play("ui_hover", -16.0)
		_heat(true))
	mouse_exited.connect(func() -> void: _heat(has_focus()))
	focus_entered.connect(func() -> void:
		if not is_hovered() and Time.get_ticks_msec() - _born > 250:
			Sfx.play("ui_hover", -16.0)          # keyboard / controller navigation
		_heat(true))
	focus_exited.connect(func() -> void: _heat(is_hovered()))
	pressed.connect(func() -> void: Sfx.play("ui_click", -6.0))


func _ready() -> void:
	_born = Time.get_ticks_msec()


func _heat(on: bool) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "_hot", 1.0 if on else 0.0, 0.16 if on else 0.22) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	var h := _hot
	var w := size.x
	var dim := 0.45 if disabled else 1.0
	# Sweep: the highlight band grows from the left edge.
	if h > 0.0:
		draw_rect(Rect2(0, 2, w * (0.35 + 0.65 * h), size.y - 4), Color(accent, 0.09 * h))
		draw_rect(Rect2(0, size.y - 3, w * h, 1), Color(accent, 0.35 * h))
	# Accent bar.
	draw_rect(Rect2(0, 6 - 4 * h, 3 + 2 * h, size.y - 12 + 8 * h), Color(accent, (0.18 + 0.82 * h) * dim))
	var font := UiTheme.TITLE
	var base := size.y * 0.5 + 8
	draw_string(font, Vector2(16, base - 1), _index_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(accent, (0.45 + 0.55 * h) * dim))
	var x := 44.0 + 14.0 * h
	draw_string(font, Vector2(x, base), _label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22,
			Color(UiTheme.TEXT.lerp(Color.WHITE, h), dim))
	if h > 0.01:
		var cx := w - 20 - 6 * (1.0 - h)
		draw_string(font, Vector2(cx, base), "›", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(accent, h))
		if hint != "":
			draw_string(UiTheme.FONT, Vector2(0, base - 2), hint, HORIZONTAL_ALIGNMENT_RIGHT, w - 34, 13,
					Color(UiTheme.MUTED, UiTheme.MUTED.a * h))
