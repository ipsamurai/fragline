class_name MenuLogo
extends VBoxContainer
## The FRAGLINE wordmark: "FRAG" white + "LINE" cyan over two soft outline-glow layers, with a
## lit underline and a travelling glint. Animated only with modulate / position tweens (no
## shaders, no redraws): a slow glow pulse, an occasional neon flicker on "LINE".

const SIZE := 96


func _init() -> void:
	add_theme_constant_override("separation", 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var stack := MarginContainer.new()          # children overlap: glow layers under the letters
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		stack.add_theme_constant_override("margin_" + side, 0)
	add_child(stack)
	# Stacked outline layers fake a soft falloff: wide + faint under tight + brighter.
	var glow_wide := VBoxContainer.new()
	glow_wide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wide_stack := MarginContainer.new()
	wide_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow_wide.add_child(wide_stack)
	wide_stack.add_child(_word(Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(UiTheme.ACCENT, 0.05), 46))
	wide_stack.add_child(_word(Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(UiTheme.ACCENT, 0.07), 30))
	var glow_tight := _word(Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(UiTheme.ACCENT, 0.22), 14)
	var main := _word(Color.WHITE, UiTheme.ACCENT, Color(0.02, 0.03, 0.06, 0.6), 4)
	stack.add_child(glow_wide)
	stack.add_child(glow_tight)
	stack.add_child(main)

	# Underline: dim rail + bright travelling glint.
	var rail := ColorRect.new()
	rail.color = Color(UiTheme.ACCENT, 0.28)
	rail.custom_minimum_size = Vector2(0, 2)
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail.clip_contents = true
	add_child(rail)
	var glint := ColorRect.new()
	glint.color = Color(0.8, 1.0, 1.0, 0.95)
	glint.size = Vector2(90, 2)
	glint.position.x = -120
	glint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail.add_child(glint)

	# Pulse the glow; flicker the cyan half now and then; sweep the glint.
	var pulse := glow_wide.create_tween().set_loops()
	pulse.tween_property(glow_wide, "modulate:a", 0.4, 1.6).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(glow_wide, "modulate:a", 1.0, 1.6).set_trans(Tween.TRANS_SINE)
	var line_half: Label = main.get_child(1)
	var tight_half: Label = glow_tight.get_child(1)
	var flick := line_half.create_tween().set_loops()
	flick.tween_interval(4.6)
	for step in [[0.35, 0.05], [1.0, 0.06], [0.55, 0.04], [1.0, 0.05], [0.7, 0.03], [1.0, 0.08]]:
		flick.tween_property(line_half, "modulate:a", step[0], step[1])
		flick.parallel().tween_property(tight_half, "modulate:a", step[0], step[1])
	var sweep := glint.create_tween().set_loops()
	sweep.tween_interval(1.2)
	sweep.tween_property(glint, "position:x", 640.0, 1.4).from(-120.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	sweep.tween_interval(2.4)


func _word(a: Color, b: Color, outline: Color, outline_size: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for part in [["FRAG", a], ["LINE", b]]:
		var l := Label.new()
		l.text = part[0]
		l.add_theme_font_override("font", UiTheme.TITLE)
		l.add_theme_font_size_override("font_size", SIZE)
		l.add_theme_color_override("font_color", part[1])
		l.add_theme_color_override("font_outline_color", outline)
		l.add_theme_constant_override("outline_size", outline_size)
		row.add_child(l)
	return row
