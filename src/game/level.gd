class_name Level
extends Node2D
## Turns an ASCII map into merged collision rectangles and a static, drawn-once
## tile layer. Merging keeps the physics shape count (and draw calls) small.

enum { EMPTY, SOLID, ONEWAY, HAZARD, BARRIER }

const T := Maps.TILE
const LAYER_SOLID := 1        # physics layer 1: walls/floors (players + shots)
const LAYER_ONEWAY := 3       # physics layer 3: platforms for players (drop through by unmasking it)
const LAYER_SHOT := 4         # physics layer 4: platform slabs, shots only
const LAYER_BARRIER := 5      # physics layer 5: spawn-door barriers, shots only
const BARRIER_MASK := 1 << (LAYER_BARRIER - 1)
const SHOT_MASK := (1 << (LAYER_SOLID - 1)) | (1 << (LAYER_SHOT - 1)) | BARRIER_MASK
const PICKUP_CHARS := "hHaD"

var def: Dictionary
var theme: Dictionary
var w := 0
var h := 0
var cells := PackedByteArray()
var pads := {}                         # Vector2i -> true
var ladders := {}                      # Vector2i -> true
var lasers: Array[Dictionary] = []     # {x, top, bottom, phase} — timed laser gates
var vents: Array[Dictionary] = []      # {pos, phase} — timed floor vents (pos = floor point)
var zones := PackedInt32Array()        # per cell: spawn-room id, or -1 outside any spawn room
var zone_count := 0
var spawns: Array[Vector2] = []
var dummy_spawns: Array[Vector2] = []    # training-room dummy spots ("T")
var pickups: Array[Dictionary] = []    # {type: "h"/"H"/"a"/"D"/"w", wid, pos}
var size_px := Vector2.ZERO
var _panel: Texture2D                  # must outlive _draw(): canvas commands only hold its RID



## Build from a map definition (an entry of Maps.LIST, or Maps.TRAINING).
func build(p_def: Dictionary) -> void:
	def = p_def
	theme = def.theme
	var rows: Array = def.rows
	h = rows.size()
	w = 0
	for r in rows:
		w = maxi(w, r.length())
	cells.resize(w * h)
	cells.fill(EMPTY)
	var laser_cells: Array[Vector2i] = []
	for y in h:
		var row: String = rows[y]
		for x in w:
			var c := row[x] if x < row.length() else "#"
			var pos := Vector2(x * T + T * 0.5, y * T + T * 0.5)
			match c:
				"#": cells[y * w + x] = SOLID
				"-": cells[y * w + x] = ONEWAY
				"~": cells[y * w + x] = HAZARD
				"B": cells[y * w + x] = BARRIER
				"|": ladders[Vector2i(x, y)] = true
				"+":
					cells[y * w + x] = ONEWAY
					ladders[Vector2i(x, y)] = true
				"^": pads[Vector2i(x, y)] = true
				"L": laser_cells.append(Vector2i(x, y))
				"V": vents.append({"pos": Vector2(pos.x, (y + 1) * T), "phase": _phase(x, y)})
				"S": spawns.append(Vector2(pos.x, (y + 1) * T - Player.HALF.y - 1))
				"T": dummy_spawns.append(Vector2(pos.x, (y + 1) * T - Player.HALF.y - 1))
				"w": pickups.append({"type": "w", "wid": -1, "pos": pos, "random": true})
				"N": pickups.append({"type": "w", "wid": Weapons.REDEEMER, "pos": pos, "nuke": true})
				_:
					if c in PICKUP_CHARS:
						pickups.append({"type": c, "wid": -1, "pos": pos})
					elif c >= "2" and c <= "9":
						pickups.append({"type": "w", "wid": c.to_int() - 1, "pos": pos})
	size_px = Vector2(w * T, h * T)
	# A laser fires down from its emitter cell until the first floor below it.
	for c in laser_cells:
		var bottom := c.y
		while bottom + 1 < h and cell(c.x, bottom + 1) in [EMPTY, BARRIER, HAZARD]:
			bottom += 1
		lasers.append({"x": (c.x + 0.5) * T, "top": c.y * T, "bottom": (bottom + 1) * T, "phase": _phase(c.x, c.y)})
	_find_spawn_zones()
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED   # tiled panel draws (required on WebGL)
	_build_collision()
	_build_hazards()
	var decor := LevelDecor.new()
	add_child(decor)
	decor.setup(self)
	queue_redraw()


## Spawn rooms = the open cells reachable from each spawn point without crossing a wall or a
## barrier door. Flood fill caps out on maps without enclosed rooms (then no zone is made).
func _find_spawn_zones() -> void:
	zones.resize(w * h)
	zones.fill(-1)
	if def.get("training", false):        # open practice map: no spawn rooms
		return
	const MAX_ROOM_CELLS := 600
	for sp in spawns:
		var start := cell_of(sp)
		if zones[start.y * w + start.x] >= 0:
			continue
		var seen := {start: true}
		var stack: Array[Vector2i] = [start]
		var ok := true
		while not stack.is_empty() and ok:
			var c: Vector2i = stack.pop_back()
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n: Vector2i = c + d
				if seen.has(n) or cell(n.x, n.y) in [SOLID, BARRIER, HAZARD]:
					continue
				seen[n] = true
				stack.append(n)
				ok = seen.size() <= MAX_ROOM_CELLS
		if not ok:
			push_warning("Spawn at %s is not inside an enclosed spawn room" % start)
			continue
		for c: Vector2i in seen:
			zones[c.y * w + c.x] = zone_count
		zone_count += 1


## Spawn-room id at a world position (-1 = not in a spawn room).
func zone_at(p: Vector2) -> int:
	var c := cell_of(p)
	if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h:
		return -1
	return zones[c.y * w + c.x]


## True if a rectangle overlaps a spawn room or a barrier door (no-fire area).
func touches_zone(r: Rect2) -> bool:
	var a := cell_of(r.position)
	var b := cell_of(r.end)
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			if x >= 0 and y >= 0 and x < w and y < h and (zones[y * w + x] >= 0 or cells[y * w + x] == BARRIER):
				return true
	return false


## Cycle offset for a trap. Mirrored traps get the same phase so both sides stay fair.
func _phase(x: int, y: int) -> float:
	return fposmod(absf(x + 0.5 - w * 0.5) * 0.37 + y * 0.21, 1.0)


func cell(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= w or y >= h:
		return SOLID
	return cells[y * w + x]


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / T), floori(p.y / T))


func is_pad(c: Vector2i) -> bool:
	return pads.has(c)


func is_ladder(c: Vector2i) -> bool:
	return ladders.has(c)


func hazard_at(p: Vector2) -> bool:
	var c := cell_of(p)
	return cell(c.x, c.y) == HAZARD


# --- collision -----------------------------------------------------------------

## Greedy merge: horizontal runs, then stack identical runs vertically.
func _merged_rects(kind: int) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var open := {}   # Vector2i(x0, x1) -> index into out (run continuing from previous row)
	for y in h:
		var next_open := {}
		var x := 0
		while x < w:
			if cell(x, y) != kind:
				x += 1
				continue
			var x0 := x
			while x < w and cell(x, y) == kind:
				x += 1
			var key := Vector2i(x0, x - 1)
			if kind != ONEWAY and open.has(key):
				var i: int = open[key]
				out[i].size.y += 1
				next_open[key] = i
			else:
				out.append(Rect2i(x0, y, x - x0, 1))
				next_open[key] = out.size() - 1
		open = next_open
	return out


func _build_collision() -> void:
	var solid := StaticBody2D.new()
	solid.collision_layer = 0
	solid.set_collision_layer_value(LAYER_SOLID, true)
	solid.collision_mask = 0
	for r in _merged_rects(SOLID):
		_add_rect_shape(solid, Rect2(r.position * T, r.size * T), false)
	add_child(solid)

	var oneway := StaticBody2D.new()
	oneway.collision_layer = 0
	oneway.set_collision_layer_value(LAYER_ONEWAY, true)
	oneway.collision_mask = 0
	for r in _merged_rects(ONEWAY):
		_add_rect_shape(oneway, Rect2(r.position.x * T, r.position.y * T, r.size.x * T, 10), true)
	add_child(oneway)

	# Bullets can't pass platforms (from either side) or spawn barriers; players can.
	var shot := StaticBody2D.new()
	shot.collision_layer = 0
	shot.set_collision_layer_value(LAYER_SHOT, true)
	shot.collision_mask = 0
	for r in _merged_rects(ONEWAY):
		_add_rect_shape(shot, Rect2(r.position.x * T, r.position.y * T, r.size.x * T, 10), false)
	add_child(shot)
	# Barriers get their own layer so wall-piercing shots can still be stopped by them.
	var barrier := StaticBody2D.new()
	barrier.collision_layer = 0
	barrier.set_collision_layer_value(LAYER_BARRIER, true)
	barrier.collision_mask = 0
	for r in _merged_rects(BARRIER):
		_add_rect_shape(barrier, Rect2(r.position * T, r.size * T), false)
	add_child(barrier)


func _add_rect_shape(body: StaticBody2D, r: Rect2, one_way: bool) -> void:
	var shape := RectangleShape2D.new()
	shape.size = r.size
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = r.get_center()
	cs.one_way_collision = one_way
	cs.one_way_collision_margin = 12.0
	body.add_child(cs)


# --- rendering -----------------------------------------------------------------

## Animated quads: lava/void surfaces and spawn-door energy barriers.
func _build_hazards() -> void:
	var lava := ShaderMaterial.new()
	lava.shader = preload("res://src/game/hazard.gdshader")
	lava.set_shader_parameter("color", theme.hazard)
	for r in _merged_rects(HAZARD):
		_shader_rect(Rect2(Vector2(r.position * T) - Vector2(0, 6), Vector2(r.size * T) + Vector2(0, 6)), lava, r.size.x)
	var field := ShaderMaterial.new()
	field.shader = preload("res://src/game/barrier.gdshader")
	field.set_shader_parameter("color", theme.edge)
	for r in _merged_rects(BARRIER):
		var quad := _shader_rect(Rect2(r.position * T, r.size * T), field, r.size.y)
		quad.z_index = 2


func _shader_rect(r: Rect2, mat: ShaderMaterial, tiles: int) -> ColorRect:
	var rect := ColorRect.new()
	rect.position = r.position
	rect.size = r.size
	rect.material = mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_instance_shader_parameter("tiles", float(tiles))
	add_child(rect)
	return rect


## 32x32 bevelled metal panel, generated (no image asset needed) and tinted per theme.
func _panel_texture() -> Texture2D:
	var img := Image.create(T, T, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in T:
		for x in T:
			var v := 0.78 + rng.randf_range(-0.025, 0.025)
			if x == 0 or y == 0:
				v = 0.98
			elif x == T - 1 or y == T - 1:
				v = 0.52
			elif (x == 4 or x == T - 5) and y > 3 and y < T - 4:
				v -= 0.08
			elif (y == 4 or y == T - 5) and x > 3 and x < T - 4:
				v -= 0.08
			if (x == 7 or x == T - 8) and (y == 7 or y == T - 8):
				v = 0.95
			img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)


func _draw() -> void:
	var tile: Color = theme.tile
	var edge: Color = theme.edge
	if _panel == null:
		_panel = _panel_texture()
	var tex := _panel
	# Solid blocks: one tiled draw per merged rect.
	for r in _merged_rects(SOLID):
		draw_texture_rect(tex, Rect2(r.position * T, r.size * T), true, tile)
	# Lit top edges + soft neon lip, darker undersides.
	var glow_a := Color(edge, 0.28)
	var glow_b := Color(edge, 0.0)
	for y in h:
		var x := 0
		while x < w:
			if cell(x, y) == SOLID and cell(x, y - 1) != SOLID:
				var x0 := x
				while x < w and cell(x, y) == SOLID and cell(x, y - 1) != SOLID:
					x += 1
				var rx := x0 * T
				var rw := (x - x0) * T
				_gradient_rect(Rect2(rx, y * T - 10, rw, 10), glow_b, glow_a)
				draw_rect(Rect2(rx, y * T, rw, 3), edge)
				draw_rect(Rect2(rx, y * T + 3, rw, 3), tile.lightened(0.15))
			else:
				x += 1
	for y in h:
		for x in w:
			if cell(x, y) == SOLID and cell(x, y + 1) != SOLID and y + 1 < h:
				draw_rect(Rect2(x * T, (y + 1) * T - 3, T, 3), tile.darkened(0.45))
	# One-way platforms: slim slabs with struts.
	var ow: Color = theme.oneway
	for r in _merged_rects(ONEWAY):
		var rx := r.position.x * T
		var ry := r.position.y * T
		var rw := r.size.x * T
		_gradient_rect(Rect2(rx, ry - 8, rw, 8), glow_b, Color(edge, 0.18))
		draw_rect(Rect2(rx, ry, rw, 10), ow)
		draw_rect(Rect2(rx, ry, rw, 2), edge.lerp(Color.WHITE, 0.2))
		draw_rect(Rect2(rx, ry + 8, rw, 2), ow.darkened(0.4))
		for i in range(1, r.size.x * 2, 2):
			var sx := rx + i * T * 0.5
			draw_line(Vector2(sx - 6, ry + 10), Vector2(sx, ry + 18), ow.darkened(0.3), 2.0)
			draw_line(Vector2(sx + 6, ry + 10), Vector2(sx, ry + 18), ow.darkened(0.3), 2.0)
	# Ladders: two rails and rungs.
	var rail: Color = theme.oneway.lightened(0.15)
	for c: Vector2i in ladders:
		var x := c.x * T
		var y := c.y * T
		draw_rect(Rect2(x + 6, y, 3, T), rail)
		draw_rect(Rect2(x + T - 9, y, 3, T), rail)
		for k in 3:
			draw_rect(Rect2(x + 6, y + 5 + k * 11, T - 12, 3), rail.darkened(0.15))
	# Heat haze above hazards.
	var hz: Color = theme.hazard
	for r in _merged_rects(HAZARD):
		_gradient_rect(Rect2(r.position.x * T, r.position.y * T - 70, r.size.x * T, 64),
				Color(hz, 0.0), Color(hz, 0.22))


## Vertical gradient (top colour -> bottom colour) via per-vertex colours.
func _gradient_rect(r: Rect2, top: Color, bottom: Color) -> void:
	draw_polygon(
		PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))
