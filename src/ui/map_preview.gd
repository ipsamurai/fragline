class_name MapPreview
extends Button
## Selectable arena card: a mini-map drawn straight from the map's ASCII, plus its name.

var def: Dictionary
var selected := false:
	set(v):
		selected = v
		queue_redraw()


func _init(p_def: Dictionary) -> void:
	def = p_def
	custom_minimum_size = Vector2(232, 150)
	focus_mode = Control.FOCUS_ALL
	tooltip_text = def.desc


func _draw() -> void:
	var th: Dictionary = def.theme
	var rows: Array = def.rows
	var w: int = rows[0].length()
	var h := rows.size()
	var cell := minf((size.x - 16) / w, (size.y - 40) / h)
	var origin := Vector2((size.x - w * cell) * 0.5, 8)
	draw_rect(Rect2(origin, Vector2(w, h) * cell), th.sky_bottom.darkened(0.2))
	for y in h:
		var row: String = rows[y]
		for x in w:
			var col := Color(0, 0, 0, 0)
			match row[x]:
				"#": col = th.tile
				"-", "+": col = th.edge
				"~": col = th.hazard
				"B": col = Color(th.edge, 0.5)
				"|": col = th.oneway
			if col.a > 0.0:
				draw_rect(Rect2(origin + Vector2(x, y) * cell, Vector2(cell, cell)), col)
	var border := UiTheme.ACCENT if selected else (Color(1, 1, 1, 0.5) if has_focus() or is_hovered() else Color(1, 1, 1, 0.12))
	draw_rect(Rect2(Vector2.ZERO, size), border, false, 3.0 if selected else 1.5)
	draw_string(UiTheme.TITLE, Vector2(10, size.y - 10), String(def.name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT,
			size.x - 20, 16, UiTheme.ACCENT if selected else UiTheme.TEXT)
