class_name MapPreview
extends Button
## Selectable arena card: a mini-map drawn straight from the map's ASCII, plus its name.
## The mini-map is baked once per map into a tiny texture (one pixel per cell) and drawn
## as a single nearest-filtered rect, instead of thousands of draw_rect calls per redraw.

static var _cache := {}                # map id -> ImageTexture (shared by every card instance)

var def: Dictionary
var _tex: Texture2D
var selected := false:
	set(v):
		selected = v
		queue_redraw()


func _init(p_def: Dictionary) -> void:
	def = p_def
	custom_minimum_size = Vector2(232, 128)
	focus_mode = Control.FOCUS_ALL
	tooltip_text = def.desc
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tex = _minimap(def)


static func _minimap(d: Dictionary) -> Texture2D:
	var key: String = d.get("id", d.name)
	if _cache.has(key):
		return _cache[key]
	var th: Dictionary = d.theme
	var rows: Array = d.rows
	var w: int = rows[0].length()
	var h := rows.size()
	var bg: Color = th.sky_bottom.darkened(0.2)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(bg)
	for y in h:
		var row: String = rows[y]
		for x in mini(w, row.length()):
			var col := Color(0, 0, 0, 0)
			match row[x]:
				"#": col = th.tile
				"-", "+": col = th.edge
				"~": col = th.hazard
				"B": col = Color(th.edge, 0.5)
				"|": col = th.oneway
			if col.a > 0.0:
				img.set_pixel(x, y, bg.blend(col))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


func _draw() -> void:
	var rows: Array = def.rows
	var w: int = rows[0].length()
	var h := rows.size()
	var cell := minf((size.x - 16) / w, (size.y - 40) / h)
	var origin := Vector2((size.x - w * cell) * 0.5, 8)
	draw_texture_rect(_tex, Rect2(origin, Vector2(w, h) * cell), false)
	var border := UiTheme.ACCENT if selected else (Color(1, 1, 1, 0.5) if has_focus() or is_hovered() else Color(1, 1, 1, 0.12))
	draw_rect(Rect2(Vector2.ZERO, size), border, false, 3.0 if selected else 1.5)
	draw_string(UiTheme.TITLE, Vector2(10, size.y - 10), String(def.name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT,
			size.x - 20, 16, UiTheme.ACCENT if selected else UiTheme.TEXT)
