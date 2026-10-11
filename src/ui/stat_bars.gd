class_name StatBars
extends Control
## Segmented neon stat bars (label · bar · value), drawn with batched draw_rect only.
## set_stats() animates the bars from their old values to the new ones; it only redraws
## while that short tween runs.

const SEGMENTS := 12
const ROW_H := 26.0
const LABEL_W := 92.0
const VALUE_W := 64.0

var color := UiTheme.ACCENT
var names: Array = WeaponInfo.STAT_NAMES
var _from: Array = [0.0, 0.0, 0.0, 0.0]
var _to: Array = [0.0, 0.0, 0.0, 0.0]
var _values: Array = ["", "", "", ""]
var _t := 1.0:
	set(v):
		_t = v
		queue_redraw()
var _tween: Tween


func _init(rows := 4) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	names = WeaponInfo.STAT_NAMES.slice(0, rows).map(func(n: String) -> String: return n.to_upper())
	custom_minimum_size.y = ROW_H * rows


func set_stats(bars: Array, values: Array, col: Color, animate := true) -> void:
	for i in names.size():
		_from[i] = lerpf(_from[i], _to[i], _t)
		_to[i] = bars[i]
		_values[i] = values[i]
	color = col
	if _tween:
		_tween.kill()
	if animate and is_inside_tree():
		_t = 0.0
		_tween = create_tween()
		_tween.tween_property(self, "_t", 1.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_t = 1.0


func _draw() -> void:
	var font := UiTheme.TITLE
	var bar_x := LABEL_W
	var bar_w := maxf(40.0, size.x - LABEL_W - VALUE_W)
	var seg_w := bar_w / SEGMENTS
	for i in names.size():
		var y := i * ROW_H
		draw_string(font, Vector2(0, y + 17), names[i], HORIZONTAL_ALIGNMENT_LEFT, LABEL_W - 8, 12, UiTheme.MUTED)
		var v: float = lerpf(_from[i], _to[i], _t)
		var lit := v * SEGMENTS
		for s in SEGMENTS:
			var r := Rect2(bar_x + s * seg_w, y + 7, seg_w - 3.0, 12)
			var a := clampf(lit - s, 0.0, 1.0)
			draw_rect(r, Color(1, 1, 1, 0.07))
			if a > 0.0:
				draw_rect(r, Color(color, a))
				draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), Color(1, 1, 1, 0.35 * a))
		draw_string(font, Vector2(bar_x + bar_w + 8, y + 18), String(_values[i]), HORIZONTAL_ALIGNMENT_RIGHT, VALUE_W - 8, 14, UiTheme.TEXT)
