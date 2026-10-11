class_name WeaponShowcase
extends PanelContainer
## Main-menu "featured" card: cycles through the 9 weapons every few seconds with a slide,
## showing the sprite, name, a one-liner and damage / fire-rate bars. Hover pauses it,
## click opens the Armory on the weapon shown. Only tweens run; nothing redraws per frame.

signal open_requested(wid: int)

const PERIOD := 3.2

var _wid := 0
var _content: VBoxContainer
var _icon: GunIcon
var _name: Label
var _kind: Label
var _tag: Label
var _bars: StatBars
var _counter: Label
var _progress: ColorRect
var _dots: Control
var _timer: Timer
var _hover := false
var _prog_tween: Tween


func _init() -> void:
	theme_type_variation = "Card"
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(UiTheme.label("FEATURED ARSENAL", "Kicker"))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(fill)
	_counter = UiTheme.label("", "Muted")
	head.add_child(_counter)
	col.add_child(head)
	var rail := ColorRect.new()
	rail.color = Color(1, 1, 1, 0.08)
	rail.custom_minimum_size.y = 2
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rail)
	_progress = ColorRect.new()
	_progress.color = Color(UiTheme.ACCENT, 0.9)
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress.set_anchors_preset(Control.PRESET_FULL_RECT)
	rail.add_child(_progress)

	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.custom_minimum_size.y = 318
	col.add_child(clip)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 2)
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(_content)
	_icon = GunIcon.new(1.0)
	_icon.custom_minimum_size = Vector2(0, 150)
	_icon.pad = 14.0
	_content.add_child(_icon)
	_name = UiTheme.label("", "Title")
	_name.add_theme_font_size_override("font_size", 32)
	_content.add_child(_name)
	_kind = UiTheme.label("", "Kicker")
	_content.add_child(_kind)
	_tag = UiTheme.label("", "Muted")
	_tag.add_theme_font_size_override("font_size", 15)
	_tag.add_theme_color_override("font_color", Color(UiTheme.TEXT, 0.82))
	_content.add_child(_tag)
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	_content.add_child(gap)
	_bars = StatBars.new(2)
	_content.add_child(_bars)

	var foot := HBoxContainer.new()
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dots = Control.new()
	_dots.custom_minimum_size = Vector2(9 * 16, 14)
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dots.draw.connect(_draw_dots)
	foot.add_child(_dots)
	var fill2 := Control.new()
	fill2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(fill2)
	var open := UiTheme.label("OPEN ARMORY  ›", "Kicker")
	open.add_theme_font_size_override("font_size", 12)
	foot.add_child(open)
	col.add_child(foot)

	_timer = Timer.new()
	_timer.wait_time = PERIOD
	_timer.timeout.connect(func() -> void:
		if not _hover:
			show_weapon((_wid + 1) % Weapons.COUNT))
	add_child(_timer)
	mouse_entered.connect(func() -> void:
		_hover = true
		Sfx.play("ui_hover", -16.0)
		if _prog_tween:
			_prog_tween.pause())
	mouse_exited.connect(func() -> void:
		_hover = false
		if _prog_tween:
			_prog_tween.play())


func _ready() -> void:
	_wid = randi() % Weapons.COUNT
	_fill(_wid)
	_restart_progress()
	_timer.start()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Sfx.play("ui_click", -6.0)
		open_requested.emit(_wid)
		accept_event()


func show_weapon(wid: int) -> void:
	_wid = wid
	_timer.start()
	var tw := create_tween()
	tw.tween_property(_content, "position:x", -36.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_content, "modulate:a", 0.0, 0.16)
	tw.tween_callback(func() -> void:
		_fill(wid)
		_content.position.x = 36.0)
	tw.tween_property(_content, "position:x", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_content, "modulate:a", 1.0, 0.22)
	_restart_progress()


func _restart_progress() -> void:
	if _prog_tween:
		_prog_tween.kill()
	_progress.scale.x = 0.0
	_prog_tween = create_tween()
	_prog_tween.tween_property(_progress, "scale:x", 1.0, PERIOD)
	if _hover:
		_prog_tween.pause()


func _fill(wid: int) -> void:
	var w: Dictionary = Weapons.LIST[wid]
	var col: Color = w.color
	var tint := col if col.get_luminance() < 0.92 else UiTheme.ACCENT
	_icon.wid = wid
	_name.text = String(w.name).to_upper()
	_name.add_theme_color_override("font_color", Color.WHITE)
	_name.add_theme_color_override("font_shadow_color", Color(tint, 0.45))
	_name.add_theme_constant_override("shadow_outline_size", 10)
	_name.add_theme_constant_override("shadow_offset_x", 0)
	_name.add_theme_constant_override("shadow_offset_y", 0)
	_kind.text = "KEY %d  ·  %s" % [wid + 1, "HITSCAN" if w.kind == Weapons.Kind.HITSCAN else "PROJECTILE"]
	_kind.add_theme_color_override("font_color", tint)
	_tag.text = WeaponInfo.TAGLINES[wid]
	var st := WeaponInfo.stats(wid)
	_bars.set_stats(st.bars, st.values, tint, is_inside_tree())
	_counter.text = "%02d / %02d" % [wid + 1, Weapons.COUNT]
	_progress.color = Color(tint, 0.9)
	_dots.queue_redraw()


func _draw_dots() -> void:
	for i in Weapons.COUNT:
		var on := i == _wid
		var r := Rect2(i * 16, 5, 12 if on else 8, 4)
		_dots.draw_rect(r, Color(UiTheme.ACCENT, 0.95) if on else Color(1, 1, 1, 0.2))
