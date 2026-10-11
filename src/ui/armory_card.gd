class_name ArmoryCard
extends Button
## Armory grid tile: number key, fire type, the weapon's sprite and name. Selected tiles take
## the weapon's colour. Drawn with draw_rect / draw_string / one texture rect (batched).

var wid := 0
var selected := false:
	set(v):
		selected = v
		queue_redraw()
var _name := ""
var _kind := ""
var _key := ""
var _tint := UiTheme.ACCENT


func _init(p_wid: int) -> void:
	wid = p_wid
	var w: Dictionary = Weapons.LIST[wid]
	_name = String(w.name).to_upper()
	_kind = "HITSCAN" if w.kind == Weapons.Kind.HITSCAN else "PROJECTILE"
	_key = str(wid + 1)
	var col: Color = w.color
	_tint = col if col.get_luminance() < 0.92 else UiTheme.ACCENT
	custom_minimum_size = Vector2(212, 150)
	focus_mode = Control.FOCUS_ALL
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(st, empty)
	mouse_entered.connect(func() -> void:
		Sfx.play("ui_hover", -16.0)
		queue_redraw())
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var hot := is_hovered() or has_focus()
	var bg := Color(0.03, 0.045, 0.08, 0.86)
	draw_rect(r, bg)
	if selected:
		draw_rect(r, Color(_tint, 0.13))
		draw_rect(Rect2(0, size.y - 4, size.x, 4), _tint)
	elif hot:
		draw_rect(r, Color(1, 1, 1, 0.05))
	var border := _tint if selected else (Color(UiTheme.ACCENT, 0.75) if hot else Color(1, 1, 1, 0.1))
	draw_rect(r, border, false, 2.0 if selected or hot else 1.0)
	if has_focus() and not selected:
		draw_rect(r.grow(3), Color(UiTheme.ACCENT, 0.35), false, 1.0)
	# Key badge + type.
	var font := UiTheme.TITLE
	draw_rect(Rect2(10, 10, 22, 20), Color(_tint, 0.9) if selected else Color(1, 1, 1, 0.1))
	draw_string(font, Vector2(10, 25), _key, HORIZONTAL_ALIGNMENT_CENTER, 22, 14,
			Color(0.02, 0.03, 0.06) if selected else UiTheme.TEXT)
	draw_string(font, Vector2(0, 25), _kind, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 12, 11,
			Color(_tint, 0.9) if selected else UiTheme.MUTED)
	# Sprite.
	var icon := Rect2(24, 34, size.x - 48, size.y - 74)
	GunSprites.draw_icon(self, wid, icon, Color.WHITE if selected or hot else Color(0.82, 0.86, 0.95))
	draw_string(font, Vector2(12, size.y - 14), _name, HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, 16,
			Color.WHITE if selected else UiTheme.TEXT)
