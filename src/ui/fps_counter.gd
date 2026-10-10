class_name FpsCounter
extends CanvasLayer
## Discreet top-right FPS + frame time readout, shown when Settings.show_fps is on.

var _label: Label
var _t := 0.0


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = Label.new()
	_label.add_theme_font_override("font", ThemeDB.fallback_font)
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_label.add_theme_constant_override("outline_size", 3)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 6)
	_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


func _process(delta: float) -> void:
	_label.visible = Settings.show_fps
	_t -= delta
	if _label.visible and _t <= 0.0:
		_t = 0.25
		var fps := Engine.get_frames_per_second()
		_label.text = "%d FPS · %.1f ms" % [fps, 1000.0 / maxf(fps, 1.0)]
