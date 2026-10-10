class_name CharPreview
extends Control
## Large animated fighter for the Customize screen: idles, jogs on the spot, aims at the mouse.

var look: Dictionary
var scale_factor := 4.0
var _pose := CharPainter.Pose.new()
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	var running := fmod(_t, 6.0) > 3.5          # alternate idle / jog
	_pose.time = _t
	_pose.speed01 = 0.8 if running else 0.0
	_pose.phase += delta * (7.0 if running else 0.0)
	_pose.lean = 0.1 if running else 0.0
	var center := size * Vector2(0.5, 0.58)
	var to_mouse := get_local_mouse_position() - (center + Vector2(0, -11) * scale_factor)
	_pose.aim = to_mouse.angle()
	_pose.facing = 1.0 if to_mouse.x >= 0.0 else -1.0
	_pose.wid = int(_t / 3.0) % Weapons.COUNT
	queue_redraw()


func _draw() -> void:
	if look.is_empty():
		return
	var center := size * Vector2(0.5, 0.58)
	var feet := center + Vector2(0, CharPainter.FEET * scale_factor)
	draw_set_transform(feet, 0.0, Vector2(1.0, 0.22))
	draw_circle(Vector2.ZERO, 26.0 * scale_factor * 0.5, Color(0, 0, 0, 0.35))
	draw_circle(Vector2.ZERO, 30.0 * scale_factor * 0.5, Color(look.visor, 0.12))
	draw_set_transform(Vector2.ZERO)
	CharPainter.draw(self, look, _pose, Transform2D(0.0, Vector2(scale_factor, scale_factor), 0.0, center))
