class_name CharPainter
## Draws a fighter procedurally (no sprite sheets), so any colour scheme is free.
## Origin is the body centre; feet sit at +23. Shared by players and menu previews.

const OUTLINE := Color(0.035, 0.04, 0.07)
const GUN_DARK := Color(0.17, 0.19, 0.24)
const FEET := 23.0
const HIP := Vector2(0, 4)


## Everything the painter needs to know about the current frame.
class Pose:
	var facing := 1.0      # +1 right, -1 left
	var aim := 0.0         # world angle (radians)
	var phase := 0.0       # run cycle
	var speed01 := 0.0     # 0..1 run intensity
	var air := false
	var vy := 0.0
	var roll := 0.0        # world-space body rotation (dodge)
	var wid := 0           # weapon to draw
	var flash := 0.0       # muzzle flash timer
	var time := 0.0        # drives idle breathing
	var squash := 0.0      # >0 stretch (jump), <0 squash (landing)
	var lean := 0.0        # forward lean when running


## `origin` places/scales the fighter (e.g. menu previews); identity for in-game use.
static func draw(ci: CanvasItem, look: Dictionary, pose: Pose, origin := Transform2D.IDENTITY) -> void:
	var p: Color = look.primary
	var s: Color = look.secondary
	var v: Color = look.visor
	var bulk: float = look.bulk
	var sx := 1.0 - pose.squash * 0.10
	var sy := 1.0 + pose.squash * 0.14
	var base := origin * Transform2D(pose.roll, Vector2.ZERO) \
			* Transform2D(0.0, Vector2(pose.facing, 1.0), 0.0, Vector2.ZERO) \
			* Transform2D(0.0, Vector2(sx, sy), 0.0, Vector2(0, FEET * (1.0 - sy)))
	var breath := sin(pose.time * 2.6) * 0.8 * (1.0 - pose.speed01) * (0.0 if pose.air else 1.0)
	# Upper body leans around the hip and breathes.
	var upper := base * Transform2D(pose.lean, HIP) * Transform2D(0.0, Vector2(0, -HIP.y + breath))

	# Aim in the upper body's local space ("facing right", lean removed).
	var a := pose.aim if pose.facing > 0 else PI - pose.aim
	a = wrapf(a - pose.lean, -PI, PI)
	var dir := Vector2.from_angle(a)
	var shoulder := Vector2(-1, -11)
	var hand := shoulder + dir * 12.0

	# Legs.
	var front: Vector2
	var back: Vector2
	if pose.air:
		if pose.vy < 0.0:
			front = Vector2(0.9, 1.6)
			back = Vector2(-0.15, 0.9)
		else:
			front = Vector2(0.35, 0.35)
			back = Vector2(-0.35, 0.5)
	else:
		var swing := sin(pose.phase) * 0.85 * pose.speed01
		front = Vector2(swing, maxf(0.0, -cos(pose.phase)) * 1.2 * pose.speed01 + 0.1)
		back = Vector2(-swing, maxf(0.0, cos(pose.phase)) * 1.2 * pose.speed01 + 0.1)
	ci.draw_set_transform_matrix(base)
	var leg := s.lerp(p, 0.4)
	_leg(ci, HIP + Vector2(-2, 0), back.x, back.y, leg.darkened(0.35), p.darkened(0.35))

	ci.draw_set_transform_matrix(upper)
	# Back arm reaches for the foregrip.
	_limb(ci, shoulder + Vector2(-3, 1), hand + dir * 8.0, 4.5, s.darkened(0.25))
	# Jetpack.
	var bw := 8.0 * bulk
	_rect(ci, Rect2(-bw - 6, -14, 6, 14), s.lightened(0.08))
	ci.draw_rect(Rect2(-bw - 5, -10, 4, 1.5), s.darkened(0.3))
	ci.draw_rect(Rect2(-bw - 5, -6, 4, 1.5), s.darkened(0.3))
	# Torso: armoured chest in the main colour, dark abdomen, belt with a small glowing buckle.
	var torso := PackedVector2Array([Vector2(-bw, -16), Vector2(bw, -16), Vector2(bw - 2, 6), Vector2(-bw + 2, 6)])
	_poly(ci, torso, p)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-bw + 1, -15), Vector2(bw - 1, -15), Vector2(bw - 1.3, -12.5), Vector2(-bw + 1.3, -12.5)]), p.lightened(0.3))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(bw - 4, -12), Vector2(bw - 1.3, -12), Vector2(bw - 2, 0), Vector2(bw - 5, 0)]), p.darkened(0.15))
	ci.draw_rect(Rect2(-bw + 2.2, -1, bw * 2 - 4.4, 7), s)
	ci.draw_rect(Rect2(-bw + 2.2, 2, bw * 2 - 4.4, 2.5), s.darkened(0.35))
	ci.draw_rect(Rect2(1, 2, 3, 2.5), v)

	ci.draw_set_transform_matrix(base)
	_leg(ci, HIP + Vector2(2, 0), front.x, front.y, leg, p)

	ci.draw_set_transform_matrix(upper)
	_head(ci, look, p, s, v)
	# Gun + front arm follow the aim.
	ci.draw_set_transform_matrix(upper * Transform2D(a, hand))
	_gun(ci, pose.wid, pose.flash)
	ci.draw_set_transform_matrix(upper)
	_limb(ci, shoulder, hand, 5.5, s)
	ci.draw_circle(hand, 3.4, OUTLINE)
	ci.draw_circle(hand, 2.6, p.darkened(0.2))
	# Pauldron caps the arm root.
	var pad := PackedVector2Array([shoulder + Vector2(-5, -5), shoulder + Vector2(3, -5.5),
			shoulder + Vector2(5.5, -1), shoulder + Vector2(3, 3), shoulder + Vector2(-5, 2)])
	_poly(ci, pad, p.lightened(0.08))
	ci.draw_line(shoulder + Vector2(-4, -4), shoulder + Vector2(3, -4.5), p.lightened(0.45), 1.5)
	ci.draw_set_transform_matrix(origin)


static func _leg(ci: CanvasItem, hip: Vector2, thigh: float, bend: float, c: Color, pad: Color) -> void:
	var knee := hip + Vector2(sin(thigh), cos(thigh)) * 9.5
	var shin := thigh - bend
	var foot := knee + Vector2(sin(shin), cos(shin)) * 9.5
	_limb(ci, hip, knee, 6.5, c)
	_limb(ci, knee, foot, 6.0, c.darkened(0.1))
	ci.draw_circle(knee, 2.3, pad.darkened(0.15))
	# Boot.
	_limb(ci, foot + Vector2(-2, -1), foot + Vector2(5, -1), 5.5, OUTLINE.lightened(0.12))


static func _limb(ci: CanvasItem, a: Vector2, b: Vector2, width: float, c: Color) -> void:
	ci.draw_line(a, b, OUTLINE, width + 3.0, true)
	ci.draw_line(a, b, c, width, true)


static func _rect(ci: CanvasItem, r: Rect2, c: Color) -> void:
	ci.draw_rect(r.grow(1.5), OUTLINE)
	ci.draw_rect(r, c)


static func _poly(ci: CanvasItem, pts: PackedVector2Array, c: Color) -> void:
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, OUTLINE, 3.0, true)
	ci.draw_colored_polygon(pts, c)


static func _head(ci: CanvasItem, look: Dictionary, p: Color, s: Color, v: Color) -> void:
	var c := Vector2(1, -25)
	var helmet := int(look.helmet)
	match helmet:
		Characters.Helmet.CREST:
			_poly(ci, PackedVector2Array([c + Vector2(-10, -3), c + Vector2(1, -16), c + Vector2(5, -8)]), v.darkened(0.1))
		Characters.Helmet.ANTENNA:
			_limb(ci, c + Vector2(-4, -8), c + Vector2(-8, -18), 1.5, s.lightened(0.2))
			ci.draw_circle(c + Vector2(-8, -18), 3.0, v)
		Characters.Helmet.HORNS:
			_poly(ci, PackedVector2Array([c + Vector2(-6, -6), c + Vector2(-13, -17), c + Vector2(-1, -9)]), s.lightened(0.55))
			_poly(ci, PackedVector2Array([c + Vector2(3, -8), c + Vector2(7, -19), c + Vector2(7, -6)]), s.lightened(0.55))
		Characters.Helmet.HOOD:
			_poly(ci, PackedVector2Array([c + Vector2(-12, 6), c + Vector2(-11, -6), c + Vector2(-3, -15), c + Vector2(5, -9), c + Vector2(-4, 8)]), s.lightened(0.08))
	ci.draw_circle(c, 11.0, OUTLINE)
	ci.draw_circle(c, 9.5, p)
	# Two-tone helmet shading + specular highlight + jaw guard.
	ci.draw_circle(c + Vector2(1.5, 2.0), 8.0, p.darkened(0.12))
	ci.draw_circle(c + Vector2(-0.5, -0.5), 7.6, p)
	ci.draw_circle(c + Vector2(-3, -4), 2.8, p.lightened(0.4))
	ci.draw_rect(Rect2(c.x - 3, c.y + 5, 9, 4), s)
	if helmet == Characters.Helmet.CYCLOPS:
		ci.draw_circle(c + Vector2(5, 0), 7.0, Color(v, 0.22))
		ci.draw_circle(c + Vector2(5, 0), 4.6, OUTLINE)
		ci.draw_circle(c + Vector2(5, 0), 3.4, v)
		ci.draw_circle(c + Vector2(5.8, -0.8), 1.3, Color.WHITE)
	else:
		ci.draw_line(c + Vector2(0, -1), c + Vector2(9, -1), Color(v, 0.25), 11.0)
		ci.draw_line(c + Vector2(0.5, -1), c + Vector2(9.5, -1), OUTLINE, 7.5)
		ci.draw_line(c + Vector2(1, -1), c + Vector2(9, -1), v, 5.0)
		ci.draw_line(c + Vector2(3, -2.5), c + Vector2(7.5, -2.5), Color(1, 1, 1, 0.75), 1.2)


## Draw just a weapon (pickups, HUD icons).
static func draw_gun(ci: CanvasItem, wid: int, origin: Transform2D) -> void:
	ci.draw_set_transform_matrix(origin)
	_gun(ci, wid, 0.0)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## Gun drawn along +x from the hand. Shape varies a little per weapon.
static func _gun(ci: CanvasItem, wid: int, flash: float) -> void:
	var w: Dictionary = Weapons.LIST[clampi(wid, 0, Weapons.COUNT - 1)]
	var length: float = w.gun_len
	var thick: float = w.gun_w
	var accent: Color = w.color
	_rect(ci, Rect2(-4, -thick * 0.5, length + 1, thick), GUN_DARK)
	ci.draw_rect(Rect2(-4, -thick * 0.5, length + 1, 2), GUN_DARK.lightened(0.3))
	ci.draw_rect(Rect2(length * 0.3, thick * 0.5 - 3, length * 0.45, 2), accent)
	ci.draw_rect(Rect2(-1, thick * 0.5, 4, 5), GUN_DARK)   # grip
	if wid == Weapons.SNIPER:
		_rect(ci, Rect2(4, -thick * 0.5 - 5, 12, 3), accent.darkened(0.3))
	if flash > 0.0:
		var m := Vector2(length + 6, 0)
		var r := 7.0 + thick * 0.4
		ci.draw_circle(m, r * 0.9, Color(1, 0.8, 0.4, 0.35))
		ci.draw_colored_polygon(PackedVector2Array([m + Vector2(-4, -r * 0.5), m + Vector2(r, 0), m + Vector2(-4, r * 0.5), m + Vector2(-1, 0)]), Color(1, 0.9, 0.5))
		ci.draw_circle(m, r * 0.35, Color.WHITE)
