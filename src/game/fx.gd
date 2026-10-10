class_name Fx
extends Node2D
## Pooled particles, all drawn in one batch per layer (normal + additive glow).
## Fixed-size pool: when full, the oldest particle is recycled — never allocates mid-match.

const MAX := 400

class Part:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var life := 0.0
	var max_life := 1.0
	var size := 4.0
	var size_end := 0.0
	var color := Color.WHITE
	var grav := 0.0
	var drag := 0.0
	var additive := false

## Lines (tracers, beams) and expanding rings (shockwaves) live in their own small lists.
class Line:
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var color := Color.WHITE
	var width := 2.0
	var life := 0.0
	var max_life := 1.0
	var wave := false

class Ring:
	var pos := Vector2.ZERO
	var radius := 10.0
	var color := Color.WHITE
	var life := 0.0
	var max_life := 1.0

class Text:
	var pos := Vector2.ZERO
	var text := ""
	var color := Color.WHITE
	var life := 0.0

const FONT := UiTheme.TITLE

var _parts: Array[Part] = []
var _lines: Array[Line] = []
var _rings: Array[Ring] = []
var _texts: Array[Text] = []
var _next := 0
var _busy := 0.0     # time until every particle is dead; lets idle frames skip all work
var _glow: Node2D


func _ready() -> void:
	for i in MAX:
		_parts.append(Part.new())
	_glow = Node2D.new()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = add
	_glow.draw.connect(_draw_glow)
	add_child(_glow)


func emit(pos: Vector2, vel: Vector2, life: float, size: float, size_end: float, color: Color,
		grav := 0.0, drag := 0.0, additive := false) -> void:
	var p := _parts[_next]
	_next = (_next + 1) % MAX
	p.pos = pos
	p.vel = vel
	p.life = life
	p.max_life = life
	p.size = size
	p.size_end = size_end
	p.color = color
	p.grav = grav
	p.drag = drag
	p.additive = additive
	_busy = maxf(_busy, life)


## Low quality halves particle counts.
func scaled(count: int) -> int:
	return count if Settings.quality > 0 else maxi(1, int(count * 0.5))


## Puff of dust at the feet (jump, land, dodge).
func dust(pos: Vector2, count: int, push := Vector2.ZERO) -> void:
	for i in scaled(count):
		var v := Vector2(randf_range(-90, 90), randf_range(-60, -10)) + push
		emit(pos + Vector2(randf_range(-8, 8), 0), v, randf_range(0.3, 0.55), randf_range(3, 5), randf_range(7, 11),
				Color(0.85, 0.9, 1.0, 0.35), -40.0, 3.0)


func line(a: Vector2, b: Vector2, color: Color, width: float, life: float, wave := false) -> void:
	var l := Line.new()
	l.wave = wave
	l.a = a
	l.b = b
	l.color = color
	l.width = width
	l.life = life
	l.max_life = life
	_lines.append(l)
	_busy = maxf(_busy, life)


func ring(pos: Vector2, radius: float, color: Color, life: float) -> void:
	var r := Ring.new()
	r.pos = pos
	r.radius = radius
	r.color = color
	r.life = life
	r.max_life = life
	_rings.append(r)
	_busy = maxf(_busy, life)


## Floating number (damage dealt by you).
func text(pos: Vector2, s: String, color: Color) -> void:
	var t := Text.new()
	t.pos = pos + Vector2(randf_range(-10, 10), 0)
	t.text = s
	t.color = color
	t.life = 0.8
	_texts.append(t)
	_busy = maxf(_busy, 0.8)


func sparks(pos: Vector2, dir: Vector2, color: Color, count: int, speed := 320.0) -> void:
	for i in scaled(count):
		var v := dir.rotated(randf_range(-0.9, 0.9)) * speed * randf_range(0.3, 1.0)
		emit(pos, v, randf_range(0.15, 0.35), 2.2, 0.5, color, 500.0, 3.0, true)


func muzzle(pos: Vector2, color: Color) -> void:
	emit(pos, Vector2.ZERO, 0.07, 16.0, 6.0, Color(color.lerp(Color.WHITE, 0.5), 0.8), 0.0, 0.0, true)


func explosion(pos: Vector2, radius: float, color: Color) -> void:
	var big := radius > 200.0
	emit(pos, Vector2.ZERO, 0.16 if not big else 0.5, radius * 0.45, radius * 0.9, Color(1.0, 0.8, 0.55, 0.5), 0.0, 0.0, true)
	ring(pos, radius, color.lerp(Color.WHITE, 0.4), 0.35 if not big else 0.8)
	for i in scaled(14 if not big else 40):
		var a := randf() * TAU
		emit(pos, Vector2.from_angle(a) * randf_range(150, 520) * (2.0 if big else 1.0), randf_range(0.25, 0.6), 3.0, 0.5,
				color.lerp(Color(1, 0.8, 0.3), 0.5), 400.0, 2.0, true)
	for i in scaled(8 if not big else 24):
		var a := randf() * TAU
		emit(pos + Vector2.from_angle(a) * randf_range(0, radius * 0.3), Vector2.from_angle(a) * randf_range(20, 90),
				randf_range(0.6, 1.1), radius * 0.15, radius * 0.4, Color(0.18, 0.18, 0.2, 0.55), -60.0, 2.0)


## Armour fragments in the fighter's colours + an energy burst in the visor colour.
func gibs(pos: Vector2, look: Dictionary, vel: Vector2) -> void:
	var cols: Array[Color] = [look.primary, look.secondary, look.primary.lightened(0.2)]
	for i in scaled(16):
		var v := vel * 0.4 + Vector2(randf_range(-260, 260), randf_range(-420, -80))
		emit(pos + Vector2(randf_range(-10, 10), randf_range(-20, 15)), v, randf_range(0.6, 1.1), randf_range(3, 5.5), 2.0,
				cols[i % 3], 1400.0, 0.5)
	burst(pos, look.visor, 18, 300.0)
	emit(pos, Vector2.ZERO, 0.25, 30.0, 60.0, Color(look.visor, 0.6), 0.0, 0.0, true)


## Glowing ring of sparks (jump pads, double jumps).
func burst(pos: Vector2, color: Color, count: int, speed: float) -> void:
	for i in scaled(count):
		var a := randf() * TAU
		emit(pos, Vector2.from_angle(a) * speed * randf_range(0.5, 1.0), randf_range(0.25, 0.45), 2.5, 0.0,
				color, 200.0, 2.0, true)


func _process(delta: float) -> void:
	if _busy <= 0.0:
		return
	_busy -= delta
	for p in _parts:
		if p.life <= 0.0:
			continue
		p.life -= delta
		p.vel.y += p.grav * delta
		p.vel *= maxf(0.0, 1.0 - p.drag * delta)
		p.pos += p.vel * delta
	for l in _lines:
		l.life -= delta
	for r in _rings:
		r.life -= delta
	for t in _texts:
		t.life -= delta
		t.pos.y -= 50.0 * delta
	_lines = _lines.filter(func(l: Line) -> bool: return l.life > 0.0)
	_rings = _rings.filter(func(r: Ring) -> bool: return r.life > 0.0)
	_texts = _texts.filter(func(t: Text) -> bool: return t.life > 0.0)
	queue_redraw()
	_glow.queue_redraw()


func _draw() -> void:
	_draw_layer(self, false)
	for l in _lines:
		var k := l.life / l.max_life
		if l.wave:
			draw_polyline(_wave_points(l), Color(l.color.lerp(Color.WHITE, 0.7), k), 2.0, true)
		else:
			draw_line(l.a, l.b, Color(l.color.lerp(Color.WHITE, 0.6), k), maxf(1.0, l.width * 0.4))
	for t in _texts:
		var k := clampf(t.life / 0.3, 0.0, 1.0)
		draw_string_outline(FONT, t.pos, t.text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, 4, Color(0, 0, 0, 0.7 * k))
		draw_string(FONT, t.pos, t.text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color(t.color, k))


## Sine-wave polyline between a line's endpoints (plasma beam).
func _wave_points(l: Line) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var len := l.a.distance_to(l.b)
	var dir := (l.b - l.a) / maxf(len, 1.0)
	var n := Vector2(-dir.y, dir.x)
	var t := Time.get_ticks_msec() * 0.03
	var steps := maxi(2, int(len / 12.0))
	for i in steps + 1:
		var d := len * i / steps
		var amp := 6.0 * sin(PI * i / steps)
		pts.append(l.a + dir * d + n * sin(d * 0.08 - t) * amp)
	return pts


func _draw_glow() -> void:
	_draw_layer(_glow, true)
	for l in _lines:
		var k := l.life / l.max_life
		if l.wave:
			_glow.draw_polyline(_wave_points(l), Color(l.color, 0.7 * k), l.width, true)
		else:
			_glow.draw_line(l.a, l.b, Color(l.color, 0.55 * k), l.width * 1.6, true)
	for r in _rings:
		var k := 1.0 - r.life / r.max_life
		_glow.draw_arc(r.pos, r.radius * (0.2 + 0.8 * sqrt(k)), 0.0, TAU, 48, Color(r.color, (1.0 - k) * 0.7), 4.0 + 6.0 * (1.0 - k), true)


func _draw_layer(ci: CanvasItem, additive: bool) -> void:
	for p in _parts:
		if p.life <= 0.0 or p.additive != additive:
			continue
		var t := 1.0 - p.life / p.max_life
		var c := p.color
		c.a *= 1.0 - t
		ci.draw_circle(p.pos, lerpf(p.size, p.size_end, t), c)
