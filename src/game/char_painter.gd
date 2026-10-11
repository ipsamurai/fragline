class_name CharPainter
## Draws a fighter procedurally (no sprite sheets), so any colour scheme is free.
## All shapes go through DrawUtil, so a whole fighter (and every fighter after it) is one
## batched draw call on the Compatibility renderer. Guns are pixel-art sprites (GunSprites atlas).
## In-game (Node2D, identity origin) the gun goes on a child canvas item one z-level up, so every
## fighter's gun lands in ONE shared batch instead of splitting each fighter's DrawUtil batch.
## Origin is the body centre; feet sit at +23. Shared by players and menu previews.

const OUTLINE := Color(0.035, 0.04, 0.07)
const HAND_REACH := 12.0      # shoulder -> trigger hand along the aim (Player.muzzle() matches)
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
	var hand := shoulder + dir * HAND_REACH
	var gs := GunSprites.hold_scale(pose.wid)
	var gun_xf := Transform2D(a, Vector2(gs, gs), 0.0, hand)
	var fore := gun_xf * GunSprites.fore_offset(pose.wid)

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
	_limb(ci, shoulder + Vector2(-3, 1), fore, 4.5, s.darkened(0.25))
	# Jetpack.
	var bw := 8.0 * bulk
	_rect(ci, Rect2(-bw - 6, -14, 6, 14), s.lightened(0.08))
	DrawUtil.rect(ci, Rect2(-bw - 5, -10, 4, 1.5), s.darkened(0.3))
	DrawUtil.rect(ci, Rect2(-bw - 5, -6, 4, 1.5), s.darkened(0.3))
	# Torso: armoured chest in the main colour, dark abdomen, belt with a small glowing buckle.
	DrawUtil.outlined_quad(ci, Vector2(-bw, -16), Vector2(bw, -16), Vector2(bw - 2, 6), Vector2(-bw + 2, 6), p, OUTLINE, 3.0)
	DrawUtil.quad(ci, Vector2(-bw + 1, -15), Vector2(bw - 1, -15), Vector2(bw - 1.3, -12.5), Vector2(-bw + 1.3, -12.5), p.lightened(0.3))
	DrawUtil.quad(ci, Vector2(bw - 4, -12), Vector2(bw - 1.3, -12), Vector2(bw - 2, 0), Vector2(bw - 5, 0), p.darkened(0.15))
	DrawUtil.rect(ci, Rect2(-bw + 2.2, -1, bw * 2 - 4.4, 7), s)
	DrawUtil.rect(ci, Rect2(-bw + 2.2, 2, bw * 2 - 4.4, 2.5), s.darkened(0.35))
	DrawUtil.rect(ci, Rect2(1, 2, 3, 2.5), v)

	ci.draw_set_transform_matrix(base)
	_leg(ci, HIP + Vector2(2, 0), front.x, front.y, leg, p)

	ci.draw_set_transform_matrix(upper)
	_head(ci, look, p, s, v)
	# Muzzle flash sits under the sprite's barrel tip; the gun itself is drawn last.
	if pose.flash > 0.0:
		ci.draw_set_transform_matrix(upper * gun_xf)
		_flash(ci, pose.wid)
	ci.draw_set_transform_matrix(upper)
	_limb(ci, shoulder, hand, 5.5, s)
	DrawUtil.circle(ci, hand, 3.4, OUTLINE)
	DrawUtil.circle(ci, hand, 2.6, p.darkened(0.2))
	# Pauldron caps the arm root.
	var pad := PackedVector2Array([shoulder + Vector2(-5, -5), shoulder + Vector2(3, -5.5),
			shoulder + Vector2(5.5, -1), shoulder + Vector2(3, 3), shoulder + Vector2(-5, 2)])
	DrawUtil.outlined(ci, pad, p.lightened(0.08), OUTLINE, 3.0)
	DrawUtil.line(ci, shoulder + Vector2(-4, -4), shoulder + Vector2(3, -4.5), p.lightened(0.45), 1.5)
	# Gun held at the trigger hand, rotated to the aim (the facing mirror keeps it upright).
	if origin == Transform2D.IDENTITY and ci is Node2D:
		GunSprites.draw_rid(_gun_layer(ci), pose.wid, upper * gun_xf)
	else:
		GunSprites.draw_xf(ci, pose.wid, upper * gun_xf)
	ci.draw_set_transform_matrix(origin)


static func _leg(ci: CanvasItem, hip: Vector2, thigh: float, bend: float, c: Color, pad: Color) -> void:
	var knee := hip + Vector2(sin(thigh), cos(thigh)) * 9.5
	var shin := thigh - bend
	var foot := knee + Vector2(sin(shin), cos(shin)) * 9.5
	_limb(ci, hip, knee, 6.5, c)
	_limb(ci, knee, foot, 6.0, c.darkened(0.1))
	DrawUtil.circle(ci, knee, 2.3, pad.darkened(0.15))
	# Boot.
	_limb(ci, foot + Vector2(-2, -1), foot + Vector2(5, -1), 5.5, OUTLINE.lightened(0.12))


static func _limb(ci: CanvasItem, a: Vector2, b: Vector2, width: float, c: Color) -> void:
	DrawUtil.stroke(ci, a, b, c, width, OUTLINE, 1.5)


static func _rect(ci: CanvasItem, r: Rect2, c: Color) -> void:
	DrawUtil.rect(ci, r.grow(1.5), OUTLINE)
	DrawUtil.rect(ci, r, c)


static func _head(ci: CanvasItem, look: Dictionary, p: Color, s: Color, v: Color) -> void:
	var c := Vector2(1, -25)
	var helmet := int(look.helmet)
	match helmet:
		Characters.Helmet.CREST:
			DrawUtil.outlined_tri(ci, c + Vector2(-10, -3), c + Vector2(1, -16), c + Vector2(5, -8), v.darkened(0.1), OUTLINE, 3.0)
		Characters.Helmet.ANTENNA:
			_limb(ci, c + Vector2(-4, -8), c + Vector2(-8, -18), 1.5, s.lightened(0.2))
			DrawUtil.circle(ci, c + Vector2(-8, -18), 3.0, v)
		Characters.Helmet.HORNS:
			DrawUtil.outlined_tri(ci, c + Vector2(-6, -6), c + Vector2(-13, -17), c + Vector2(-1, -9), s.lightened(0.55), OUTLINE, 3.0)
			DrawUtil.outlined_tri(ci, c + Vector2(3, -8), c + Vector2(7, -19), c + Vector2(7, -6), s.lightened(0.55), OUTLINE, 3.0)
		Characters.Helmet.HOOD:
			DrawUtil.outlined(ci, PackedVector2Array([c + Vector2(-12, 6), c + Vector2(-11, -6), c + Vector2(-3, -15), c + Vector2(5, -9), c + Vector2(-4, 8)]), s.lightened(0.08), OUTLINE, 3.0)
	DrawUtil.circle(ci, c, 11.0, OUTLINE)
	DrawUtil.circle(ci, c, 9.5, p)
	# Two-tone helmet shading + specular highlight + jaw guard.
	DrawUtil.circle(ci, c + Vector2(1.5, 2.0), 8.0, p.darkened(0.12))
	DrawUtil.circle(ci, c + Vector2(-0.5, -0.5), 7.6, p)
	DrawUtil.circle(ci, c + Vector2(-3, -4), 2.8, p.lightened(0.4))
	DrawUtil.rect(ci, Rect2(c.x - 3, c.y + 5, 9, 4), s)
	if helmet == Characters.Helmet.CYCLOPS:
		DrawUtil.circle(ci, c + Vector2(5, 0), 7.0, Color(v, 0.22))
		DrawUtil.circle(ci, c + Vector2(5, 0), 4.6, OUTLINE)
		DrawUtil.circle(ci, c + Vector2(5, 0), 3.4, v)
		DrawUtil.circle(ci, c + Vector2(5.8, -0.8), 1.3, Color.WHITE)
	else:
		DrawUtil.line(ci, c + Vector2(0, -1), c + Vector2(9, -1), Color(v, 0.25), 11.0)
		DrawUtil.line(ci, c + Vector2(0.5, -1), c + Vector2(9.5, -1), OUTLINE, 7.5)
		DrawUtil.line(ci, c + Vector2(1, -1), c + Vector2(9, -1), v, 5.0)
		DrawUtil.line(ci, c + Vector2(3, -2.5), c + Vector2(7.5, -2.5), Color(1, 1, 1, 0.75), 1.2)


## Muzzle flash just past the sprite's barrel tip (current transform = gun space, grip at 0).
static func _flash(ci: CanvasItem, wid: int) -> void:
	var m := GunSprites.muzzle_offset(wid) + Vector2(3, 0)
	var r := 5.5 + GunSprites.size(wid).y * 0.22
	DrawUtil.circle(ci, m, r * 0.9, Color(1, 0.8, 0.4, 0.35))
	# Concave arrowhead: fan from the notch so both triangles stay inside it.
	DrawUtil.quad(ci, m + Vector2(-1, 0), m + Vector2(-4, -r * 0.5), m + Vector2(r, 0), m + Vector2(-4, r * 0.5), Color(1, 0.9, 0.5))
	DrawUtil.circle(ci, m, r * 0.35, Color.WHITE)


## Child canvas item (z + 1) holding this fighter's gun; freed with the node (its meta).
class _GunLayer extends RefCounted:
	var rid: RID

	func _init(parent: RID) -> void:
		rid = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(rid, parent)
		RenderingServer.canvas_item_set_z_as_relative_to_parent(rid, true)
		RenderingServer.canvas_item_set_z_index(rid, 1)
		RenderingServer.canvas_item_set_default_texture_filter(rid, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and rid.is_valid():
			RenderingServer.free_rid(rid)


static func _gun_layer(ci: CanvasItem) -> RID:
	if not ci.has_meta(&"_gun_layer"):
		ci.set_meta(&"_gun_layer", _GunLayer.new(ci.get_canvas_item()))
	var l: _GunLayer = ci.get_meta(&"_gun_layer")
	return l.rid
