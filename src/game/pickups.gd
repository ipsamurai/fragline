class_name Pickups
extends Node2D
## Item state (active / respawn timer) and drawing for every pickup and jump pad.
## World decides who grabs what; this node only stores state and renders it.

const RESPAWN := {"h": 20.0, "H": 45.0, "a": 25.0, "D": 60.0, "w": 20.0}
const POWER_WEAPON_RESPAWN := 30.0     # rocket launcher, shock rifle
const REDEEMER_RESPAWN := 90.0
const TRAINING_RESPAWN := 3.0

## Each item: {type, wid, pos, active, respawn_at, wait}
var world: Node
var fast := false                      # training room: everything respawns quickly
var items: Array[Dictionary] = []
var pads: Array[Vector2] = []
var _t := 0.0
var _glow: Node2D


func setup(level: Level) -> void:
	for it in level.pickups:
		var d: Dictionary = it.duplicate()
		d.active = true
		d.respawn_at = 0.0
		d.dormant = false
		if d.get("nuke", false):           # Redeemer spot: hidden until World releases it
			d.active = false
			d.dormant = true
			d.respawn_at = INF
		d.wait = respawn_time(d)
		items.append(d)
	for c: Vector2i in level.pads:
		pads.append(Vector2((c.x + 0.5) * Level.T, (c.y + 1) * Level.T))
	_glow = Node2D.new()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = add
	_glow.draw.connect(_draw_glow)
	add_child(_glow)


func respawn_time(it: Dictionary) -> float:
	if fast:
		return TRAINING_RESPAWN
	if it.type == "w" and it.wid == Weapons.REDEEMER:
		return REDEEMER_RESPAWN
	if it.type == "w" and it.wid in [Weapons.ROCKET, Weapons.SHOCK]:
		return POWER_WEAPON_RESPAWN
	return RESPAWN[it.type]


func color_of(it: Dictionary) -> Color:
	match it.type:
		"h": return Color("4ade80")
		"H": return Color("38bdf8")
		"a": return Color("fbbf24")
		"D": return Color("c084fc")
	return Weapons.LIST[it.wid].color if it.wid >= 0 else Color.WHITE


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	_glow.queue_redraw()


func _bob(i: int) -> float:
	return sin(_t * 2.4 + i * 1.7) * 3.0


func _draw() -> void:
	var now: float = world.clock
	for i in items.size():
		var it := items[i]
		if it.dormant:
			continue
		var base: Vector2 = it.pos + Vector2(0, 13)
		# Base plate, with a respawn progress ring while inactive.
		draw_set_transform(base, 0.0, Vector2(1.0, 0.3))
		draw_circle(Vector2.ZERO, 15.0, Color(0, 0, 0, 0.35))
		draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 24, Color(color_of(it), 0.45), 2.0, true)
		if not it.active:
			var k := clampf(1.0 - (it.respawn_at - now) / float(it.wait), 0.0, 1.0)
			draw_arc(Vector2.ZERO, 15.0, -PI * 0.5, -PI * 0.5 + TAU * k, 24, color_of(it), 3.0, true)
		draw_set_transform(Vector2.ZERO)
		if not it.active:
			continue
		var p: Vector2 = it.pos + Vector2(0, _bob(i) - 4)
		var c := color_of(it)
		match it.type:
			"h", "H":
				var s := 9.0 if it.type == "h" else 13.0
				draw_rect(Rect2(p - Vector2(s, s), Vector2(s, s) * 2).grow(2), CharPainter.OUTLINE)
				draw_rect(Rect2(p - Vector2(s, s), Vector2(s, s) * 2), Color(0.95, 0.97, 1.0))
				draw_rect(Rect2(p - Vector2(s * 0.25, s * 0.75), Vector2(s * 0.5, s * 1.5)), c)
				draw_rect(Rect2(p - Vector2(s * 0.75, s * 0.25), Vector2(s * 1.5, s * 0.5)), c)
			"a":
				var shield := PackedVector2Array([p + Vector2(-11, -11), p + Vector2(11, -11), p + Vector2(10, 2), p + Vector2(0, 13), p + Vector2(-10, 2)])
				var outline := shield.duplicate()
				outline.append(shield[0])
				draw_polyline(outline, CharPainter.OUTLINE, 4.0, true)
				draw_colored_polygon(shield, c)
				draw_line(p + Vector2(0, -9), p + Vector2(0, 10), c.lightened(0.4), 2.0)
			"D":
				var r := _t * 2.0
				var pts := PackedVector2Array()
				for k in 4:
					pts.append(p + Vector2.from_angle(r + k * PI * 0.5) * Vector2(12, 15))
				draw_colored_polygon(pts, c)
				draw_circle(p, 4.0, Color.WHITE)
			"w":
				var xf := Transform2D(sin(_t * 1.5 + i) * 0.15, Vector2(1.5, 1.5), 0.0,
						p - Vector2(Weapons.LIST[it.wid].gun_len * 0.6, 0))
				CharPainter.draw_gun(self, it.wid, xf)
	# Jump pads: glowing plate with rising chevrons.
	for pad in pads:
		draw_rect(Rect2(pad + Vector2(-15, -5), Vector2(30, 5)), Color(0.15, 0.17, 0.22))
		draw_rect(Rect2(pad + Vector2(-15, -5), Vector2(30, 2)), Color(0.9, 0.95, 1.0))


func _draw_glow() -> void:
	for i in items.size():
		var it := items[i]
		if not it.active:
			continue
		var p: Vector2 = it.pos + Vector2(0, _bob(i) - 4)
		var c := color_of(it)
		_glow.draw_circle(p, 26.0, Color(c, 0.10))
		_glow.draw_circle(p, 16.0, Color(c, 0.12))
	for pad in pads:
		for k in 3:
			var f := fposmod(_t * 1.6 + k / 3.0, 1.0)
			var y := pad.y - 8.0 - f * 46.0
			var a := (1.0 - f) * 0.6
			_glow.draw_polyline(PackedVector2Array([Vector2(pad.x - 11, y + 6), Vector2(pad.x, y), Vector2(pad.x + 11, y + 6)]),
					Color(0.5, 0.9, 1.0, a), 3.0, true)
		_glow.draw_circle(pad + Vector2(0, -4), 18.0, Color(0.4, 0.8, 1.0, 0.15))
