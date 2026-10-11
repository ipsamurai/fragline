class_name GunIcon
extends Control
## A weapon's pixel-art sprite fitted into this control (nearest filtering), with an optional
## soft glow in the weapon's colour behind it (a child drawing one shared radial-gradient
## texture). Redraws only when `wid` changes.

var wid := -1:
	set(v):
		if v == wid:
			return
		wid = v
		queue_redraw()
		if _glow:
			_glow.queue_redraw()
var pad := 6.0
var glow_strength := 0.0
var _glow: Control
static var _glow_tex: GradientTexture2D       # soft radial blob, shared by every icon


func _init(p_glow := 0.0) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	glow_strength = p_glow
	if p_glow > 0.0:
		_glow = Control.new()
		_glow.show_behind_parent = true
		_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
		_glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		if _glow_tex == null:
			var g := Gradient.new()
			g.set_color(0, Color(1, 1, 1, 1))
			g.set_color(1, Color(1, 1, 1, 0))
			g.add_point(0.45, Color(1, 1, 1, 0.35))
			_glow_tex = GradientTexture2D.new()
			_glow_tex.gradient = g
			_glow_tex.fill = GradientTexture2D.FILL_RADIAL
			_glow_tex.fill_from = Vector2(0.5, 0.5)
			_glow_tex.fill_to = Vector2(1.0, 0.5)
			_glow_tex.width = 64
			_glow_tex.height = 64
		_glow.draw.connect(_draw_glow)
		add_child(_glow)


func _draw_glow() -> void:
	if wid < 0:
		return
	var col: Color = Weapons.LIST[wid].color
	var c := size * 0.5
	var r := Vector2(minf(size.x * 0.5, size.y * 1.4), size.y * 0.62)
	_glow.draw_texture_rect(_glow_tex, Rect2(c - r, r * 2.0), false, Color(col, 0.3 * glow_strength))


func _draw() -> void:
	if wid < 0:
		return
	GunSprites.draw_icon(self, wid, Rect2(Vector2(pad, pad), size - Vector2(pad, pad) * 2.0))
