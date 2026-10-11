class_name FpsCounter
extends CanvasLayer
## Discreet top-right FPS / frame time / draw-call readout, shown when Settings.show_fps is on.
## Also the auto-quality guard: if a match keeps missing frames (e.g. a laptop on battery
## saver), it drops to Low quality once and says so.

const SLOW_MS := 24.0                   # a frame this long missed at least one 60 Hz vsync
const WINDOW := 3.0                     # seconds per measurement window
const SLOW_SHARE := 0.15                # step down when this share of frames is slow

var _label: Label
var _t := 0.0
var _win_t := 0.0
var _frames := 0
var _slow := 0
var _last_usec := 0
## Headless test runs have meaningless frame times: never let them rewrite the user's settings.
var _headless := DisplayServer.get_name() == "headless"


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
		_label.text = "%d FPS · %.1f ms · %d draws" % [fps, 1000.0 / maxf(fps, 1.0),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)]
	_guard()


func _guard() -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last_usec) / 1000.0
	_last_usec = now
	var w: Node = get_parent().get("world") if get_parent() else null
	# Only judge real, running matches (not menus, loading hitches, pauses or tabbed-out time).
	if _headless or not Settings.auto_quality or Settings.quality == 0 or w == null or w.demo or w.paused \
			or w.ended or w.in_countdown() or ms > 250.0:
		_win_t = 0.0
		_frames = 0
		_slow = 0
		return
	_win_t += ms / 1000.0
	_frames += 1
	if ms > SLOW_MS:
		_slow += 1
	if _win_t < WINDOW:
		return
	if _frames > 30 and float(_slow) / _frames > SLOW_SHARE:
		Settings.quality = 0
		Settings.save_settings()
		if w.hud:
			w.hud.message("Low quality on", "auto-adjusted to keep the frame rate up", Color(1, 1, 1, 0.8), 2.0)
	_win_t = 0.0
	_frames = 0
	_slow = 0
