class_name LevelDecor
extends Node2D
## Static set dressing generated from the tile grid: back walls, platform supports,
## shadows, lamps and per-style details. Recorded once into a StaticDraw mesh, so the whole
## layer is one draw call. Sits behind the tiles; `lights` is an additive layer drawn over the
## scene (another single mesh), hidden on low quality.

const T := Maps.TILE

var level: Level
var lights: Node2D
var _rng := RandomNumberGenerator.new()
var _g: StaticDraw                     # decor mesh (must outlive _draw(): commands hold its RID)
var _lg: StaticDraw                    # lights mesh


func setup(p_level: Level) -> void:
	level = p_level
	show_behind_parent = true
	lights = Node2D.new()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	lights.material = add
	lights.z_index = 1
	lights.draw.connect(_draw_lights)
	level.add_child(lights)
	StaticDraw.setup_item(self)
	StaticDraw.setup_item(lights)
	# Lamp glow is built regardless of quality; the setting just shows/hides the layer.
	lights.visible = Settings.quality > 0
	Settings.changed.connect(_on_settings_changed)


func _on_settings_changed() -> void:
	lights.visible = Settings.quality > 0


func _style() -> String:
	return level.def.style


func _c(x: int, y: int) -> int:
	return level.cell(x, y)


## Horizontal runs of `kind` cells whose neighbour at row+dy is not solid.
func _runs(kind: int, dy: int) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for y in level.h:
		var x := 0
		while x < level.w:
			if _c(x, y) == kind and _c(x, y + dy) != Level.SOLID and y + dy >= 0 and y + dy < level.h:
				var x0 := x
				while x < level.w and _c(x, y) == kind and _c(x, y + dy) != Level.SOLID:
					x += 1
				out.append(Rect2i(x0, y, x - x0, 1))
			else:
				x += 1
	return out


## First non-empty row below (dir 1) or above (dir -1) a cell, or -1.
func _scan(x: int, y: int, dir: int, limit: int) -> int:
	for i in range(1, limit + 1):
		var k := _c(x, y + i * dir)
		if k == Level.SOLID or k == Level.ONEWAY or k == Level.HAZARD:
			return y + i * dir
	return -1


func _draw() -> void:
	if _g == null:
		_bake()
	_g.draw_on(self)


func _bake() -> void:
	_g = StaticDraw.new()
	_rng.seed = hash(level.def.id)
	var th: Dictionary = level.theme
	var back: Color = th.mid.lerp(th.tile, 0.25).darkened(0.35)
	match _style():
		"industrial", "foundry", "cryo":
			_back_wall(back)
	_supports(th.oneway.darkened(0.45))
	_shadows()
	match _style():
		"jungle": _jungle()
		"ice": _snow()
		"city": _city(th)
		"industrial": _stripes()


## Interior back wall: pillars, cross-bracing and pipes; windows on cryo.
func _back_wall(c: Color) -> void:
	var size := level.size_px
	var pillar_w := 56.0
	var x := 96.0
	while x < size.x - 96.0:
		_g.rect(Rect2(x, 0, pillar_w, size.y), c)
		_g.rect(Rect2(x + 6, 0, 4, size.y), c.lightened(0.08))
		_g.rect(Rect2(x + pillar_w - 10, 0, 4, size.y), c.darkened(0.2))
		x += 320.0
	var beam_y := 160.0
	while beam_y < size.y:
		_g.rect(Rect2(0, beam_y, size.x, 18), c)
		_g.rect(Rect2(0, beam_y, size.x, 3), c.lightened(0.1))
		beam_y += 288.0
	# Diagonal bracing between pillars on the upper beam.
	x = 96.0 + pillar_w
	while x < size.x - 320.0:
		_g.line(Vector2(x, 178), Vector2(x + 264, 440), c, 8.0)
		_g.line(Vector2(x + 264, 178), Vector2(x, 440), c, 8.0)
		x += 320.0
	if _style() == "cryo":
		x = 220.0
		while x < size.x - 200.0:
			var r := Rect2(x, 230, 120, 70)
			_g.rect(r.grow(6), c.darkened(0.3))
			_g.rect(r, level.theme.sky_bottom.lightened(0.1))
			_g.line(r.position + Vector2(20, 60), r.position + Vector2(70, 10), Color(1, 1, 1, 0.18), 6.0)
			x += 640.0
	if _style() == "foundry":
		# Hanging chains from the ceiling.
		for i in 7:
			var cx := _rng.randf_range(200, size.x - 200)
			var len := _rng.randf_range(120, 300)
			var y := 32.0
			while y < len:
				_g.rect(Rect2(cx - 3, y, 6, 10), c.lightened(0.1))
				y += 14.0
			_g.line(Vector2(cx - 10, len), Vector2(cx + 10, len + 14), c.lightened(0.15), 5.0)


## Struts under one-way platforms down to the floor, or cables up to a ceiling.
func _supports(c: Color) -> void:
	if _style() == "space":
		return
	for r in _runs(Level.ONEWAY, 1):
		var xs: Array[int] = [r.position.x + 1, r.end.x - 2]
		var mid := r.position.x + 4
		while mid < r.end.x - 4:
			xs.append(mid)
			mid += 6
		for cx in xs:
			if cx < r.position.x or cx >= r.end.x:
				continue
			var px := cx * T + T * 0.5
			var py := r.position.y * T + 10.0
			var below := _scan(cx, r.position.y, 1, 14)
			if below > 0 and _c(cx, below) != Level.HAZARD:
				if _style() == "jungle":
					_vine(Vector2(px, py), minf((below - r.position.y) * T - 10.0, 90.0))
				else:
					_truss(Vector2(px, py), below * T - py, c)
			else:
				var above := _scan(cx, r.position.y, -1, 14)
				if above > 0:
					var top := (above + 1) * T
					_g.line(Vector2(px - 8, top), Vector2(px - 4, py), c.lightened(0.2), 2.0)
					_g.line(Vector2(px + 8, top), Vector2(px + 4, py), c.lightened(0.2), 2.0)


func _truss(top: Vector2, length: float, c: Color) -> void:
	var w := 10.0
	_g.rect(Rect2(top.x - w, top.y, 3, length), c)
	_g.rect(Rect2(top.x + w - 3, top.y, 3, length), c)
	var y := top.y
	var flip := false
	while y + 20.0 <= top.y + length:
		var a := Vector2(top.x - w + 1, y)
		var b := Vector2(top.x + w - 1, y + 20.0)
		_g.line(a if not flip else Vector2(b.x, a.y), b if not flip else Vector2(a.x, b.y), c, 2.0)
		y += 20.0
		flip = not flip


## Soft contact shadows under one-way platforms and solid overhangs.
func _shadows() -> void:
	var dark := Color(0, 0, 0, 0.35)
	var clear := Color(0, 0, 0, 0)
	for r in _runs(Level.ONEWAY, 1):
		_grad(Rect2(r.position.x * T, r.position.y * T + 10, r.size.x * T, 26), dark, clear)
	for r in _runs(Level.SOLID, 1):
		if _c(r.position.x, r.position.y + 1) != Level.HAZARD:
			_grad(Rect2(r.position.x * T, (r.position.y + 1) * T, r.size.x * T, 34), dark, clear)


func _grad(r: Rect2, top: Color, bottom: Color) -> void:
	_g.grad(r, top, bottom)


func _vine(start: Vector2, length: float) -> void:
	var green := Color("2f7a3a")
	var pts := PackedVector2Array()
	var y := 0.0
	while y <= length:
		pts.append(start + Vector2(sin(y * 0.08 + start.x) * 4.0, y))
		y += 8.0
	_g.polyline(pts, green, 2.5)
	for i in range(1, pts.size(), 2):
		var side := -1.0 if i % 4 == 1 else 1.0
		_g.polygon(PackedVector2Array([pts[i], pts[i] + Vector2(7 * side, -3), pts[i] + Vector2(5 * side, 4)]), green.lightened(0.15))


func _jungle() -> void:
	# Grass tufts on every exposed top surface.
	var grass := Color("4caf50")
	for kind in [Level.SOLID, Level.ONEWAY]:
		for r in _runs(kind, -1):
			for x in range(r.position.x * T, r.end.x * T, 6):
				var hgt := _rng.randf_range(3, 9)
				_g.line(Vector2(x, r.position.y * T), Vector2(x + _rng.randf_range(-3, 3), r.position.y * T - hgt),
						grass.darkened(_rng.randf_range(0, 0.3)), 2.0)
	# Vines from solid undersides.
	for r in _runs(Level.SOLID, 1):
		for x in range(r.position.x, r.end.x, 3):
			if _rng.randf() < 0.5:
				_vine(Vector2(x * T + 16, (r.position.y + 1) * T), _rng.randf_range(30, 80))


func _snow() -> void:
	var snow := Color(0.93, 0.97, 1.0)
	for kind in [Level.SOLID, Level.ONEWAY]:
		for r in _runs(kind, -1):
			var y := r.position.y * T
			_g.rect(Rect2(r.position.x * T, y - 3, r.size.x * T, 5), snow)
			for x in range(r.position.x * T + 8, r.end.x * T - 4, 14):
				_g.circle(Vector2(x, y - 2), _rng.randf_range(3, 6), snow)
	# Icicles under solid blocks.
	for r in _runs(Level.SOLID, 1):
		for x in range(r.position.x * T + 6, r.end.x * T - 4, 11):
			if _rng.randf() < 0.6:
				var y := (r.position.y + 1) * T
				_g.polygon(PackedVector2Array([Vector2(x - 3, y), Vector2(x + 3, y), Vector2(x, y + _rng.randf_range(8, 22))]),
						Color(0.75, 0.92, 1.0, 0.85))


func _city(th: Dictionary) -> void:
	# Rooftop clutter: AC boxes and antennas on building tops (solid tops with void below).
	for r in _runs(Level.SOLID, -1):
		if r.size.x < 4:
			continue
		var y := r.position.y * T
		var ax := (r.position.x + 1) * T
		_g.rect(Rect2(ax, y - 14, 26, 14), th.tile.darkened(0.2))
		_g.rect(Rect2(ax + 4, y - 10, 18, 3), th.tile.lightened(0.1))
		var tx := (r.end.x - 1) * T
		_g.line(Vector2(tx, y), Vector2(tx, y - 46), th.tile.lightened(0.2), 2.0)
		_g.circle(Vector2(tx, y - 47), 2.5, th.edge)


func _stripes() -> void:
	# Hazard stripes at one-way platform ends.
	var y_col := Color("ffc93c")
	for r in _runs(Level.ONEWAY, -1):
		for ex in [r.position.x * T, r.end.x * T - 18]:
			for i in 3:
				var x0: float = ex + i * 6
				_g.polygon(PackedVector2Array([Vector2(x0, r.position.y * T + 2), Vector2(x0 + 3, r.position.y * T + 2),
						Vector2(x0 + 6, r.position.y * T + 8), Vector2(x0 + 3, r.position.y * T + 8)]), y_col)


func _draw_lights() -> void:
	if _lg == null:
		_bake_lights()
	_lg.draw_on(lights)


func _bake_lights() -> void:
	_lg = StaticDraw.new()
	var th: Dictionary = level.theme
	var edge: Color = th.edge
	_rng.seed = hash(level.def.id) + 1
	# Lamps hanging under solid undersides (indoor maps only), at least 3 tiles wide.
	var indoor := _style() in ["industrial", "foundry", "ice"]
	for r in _runs(Level.SOLID, 1):
		if not indoor or r.size.x < 3 or _c(r.position.x, r.position.y + 1) == Level.HAZARD:
			continue
		var n := maxi(1, int(r.size.x / 6.0))
		for i in n:
			var cx := (r.position.x + (i + 0.5) * r.size.x / float(n)) * T
			var y := (r.position.y + 1) * T
			var lamp := Rect2(cx - 10, y, 20, 5)
			_lg.rect(lamp, Color(edge, 0.9))
			var reach := 170.0
			_lg.quad(Vector2(cx - 9, y + 5), Vector2(cx + 9, y + 5), Vector2(cx + 70, y + reach), Vector2(cx - 70, y + reach),
					Color(edge, 0.16), Color(edge, 0.16), Color(edge, 0.0), Color(edge, 0.0))
	match _style():
		"space":
			for r in _runs(Level.SOLID, 1):
				for x in range(r.position.x, r.end.x, 3):
					var p := Vector2(x * T + 16, (r.position.y + 1) * T + 4)
					_lg.circle(p, 9.0, Color(edge, 0.25))
					_lg.circle(p, 4.0, Color(edge, 0.6))
		"city":
			# Neon signs on building faces.
			for r in _runs(Level.SOLID, -1):
				if r.size.x < 4 or _rng.randf() < 0.3:
					continue
				var sign := Rect2(r.position.x * T + 30, r.position.y * T + 70, r.size.x * T - 60, 26)
				var col := edge if _rng.randf() < 0.5 else Color("39e1ff")
				_lg.rect(sign, Color(col, 0.12))
				_lg.rect_outline(sign, Color(col, 0.75), 2.0)
				_lg.rect(Rect2(sign.position + Vector2(8, 9), Vector2(sign.size.x - 16, 4)), Color(col, 0.55))
		"foundry":
			for r in _runs(Level.HAZARD, -1):
				_lg.rect(Rect2(r.position.x * T, r.position.y * T - 140, r.size.x * T, 140), Color(edge, 0.05))
