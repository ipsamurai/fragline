class_name StaticDraw
extends RefCounted
## Records flat-coloured 2D shapes once and bakes them into one ArrayMesh, so a whole static
## layer costs a single draw call with no per-frame CPU work. (In the GL Compatibility
## renderer every draw_circle / draw_polygon / draw_polyline is its own unbatched draw call,
## and a static CanvasItem replays all of them every frame.) Unlike baking to a texture this
## stays sharp at any camera zoom.
##
## Small circles are textured quads sampling a shared anti-aliased disc; every other shape
## samples the disc's opaque centre (= white), so one texture serves the whole mesh.
## Draw with:  node.draw_mesh(sd.mesh(), StaticDraw.disc())  on a node whose texture_filter is
## TEXTURE_FILTER_LINEAR_WITH_MIPMAPS (see `setup_item`).

const DISC_SIZE := 128
const FAN_RADIUS := 24.0              # circles bigger than this become real triangle fans
const SOLID_UV := Vector2(0.5, 0.5)   # centre of the disc texture: opaque white

static var _disc: ImageTexture        # shared by every StaticDraw mesh, created once

var _v := PackedVector2Array()
var _c := PackedColorArray()
var _uv := PackedVector2Array()
var _mesh: ArrayMesh


## Anti-aliased white disc (alpha edge) with mipmaps, filling the texture minus a 1px border.
static func disc() -> Texture2D:
	if _disc == null:
		var img := Image.create(DISC_SIZE, DISC_SIZE, false, Image.FORMAT_RGBA8)
		var c := DISC_SIZE * 0.5
		var r := c - 1.0
		for y in DISC_SIZE:
			for x in DISC_SIZE:
				var d := Vector2(x + 0.5 - c, y + 0.5 - c).length()
				img.set_pixel(x, y, Color(1, 1, 1, clampf(r - d + 0.5, 0.0, 1.0)))
		img.generate_mipmaps()
		_disc = ImageTexture.create_from_image(img)
	return _disc


## Filtering the disc needs (smooth small circles); solid shapes are unaffected.
static func setup_item(item: CanvasItem) -> void:
	item.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	item.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED


func tri(a: Vector2, b: Vector2, c: Vector2, ca: Color, cb := ca, cc := ca,
		ua := SOLID_UV, ub := SOLID_UV, uc := SOLID_UV) -> void:
	_v.append(a); _v.append(b); _v.append(c)
	_c.append(ca); _c.append(cb); _c.append(cc)
	_uv.append(ua); _uv.append(ub); _uv.append(uc)
	_mesh = null


## Convex quad a-b-c-d (in order), per-vertex colours.
func quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, ca: Color, cb := ca, cc := ca, cd := ca) -> void:
	tri(a, b, c, ca, cb, cc)
	tri(a, c, d, ca, cc, cd)


func rect(r: Rect2, col: Color) -> void:
	quad(r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), col)


## Same as CanvasItem.draw_rect(r, col, false, width): a border centred on the rect's edges.
func rect_outline(r: Rect2, col: Color, width: float) -> void:
	var hw := width * 0.5
	rect(Rect2(r.position.x - hw, r.position.y - hw, r.size.x + width, width), col)
	rect(Rect2(r.position.x - hw, r.end.y - hw, r.size.x + width, width), col)
	rect(Rect2(r.position.x - hw, r.position.y + hw, width, r.size.y - width), col)
	rect(Rect2(r.end.x - hw, r.position.y + hw, width, r.size.y - width), col)


## Rect with explicit texture coordinates (e.g. a tiled texture: uv in texture-size units,
## with texture_repeat enabled on the drawing item).
func rect_uv(r: Rect2, col: Color, uv: Rect2) -> void:
	var p := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var t := [uv.position, Vector2(uv.end.x, uv.position.y), uv.end, Vector2(uv.position.x, uv.end.y)]
	tri(p[0], p[1], p[2], col, col, col, t[0], t[1], t[2])
	tri(p[0], p[2], p[3], col, col, col, t[0], t[2], t[3])


## Vertical gradient, top colour -> bottom colour.
func grad(r: Rect2, top: Color, bottom: Color) -> void:
	quad(r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), top, top, bottom, bottom)


## Same footprint as CanvasItem.draw_line(a, b, col, width) for width > 0 (no caps).
func line(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	var t := (b - a).orthogonal().normalized() * width * 0.5
	quad(a + t, b + t, b - t, a - t, col)


## Thick polyline as one strip with mitred joints (no gaps between segments).
func polyline(pts: PackedVector2Array, col: Color, width: float) -> void:
	var n := pts.size()
	if n < 2:
		return
	var hw := width * 0.5
	var offs := PackedVector2Array()
	offs.resize(n)
	for i in n:
		var d_in := (pts[i] - pts[maxi(i - 1, 0)]).normalized()
		var d_out := (pts[mini(i + 1, n - 1)] - pts[i]).normalized()
		var dir := (d_in + d_out).normalized()
		if dir == Vector2.ZERO:
			dir = d_out if d_out != Vector2.ZERO else d_in
		var nrm := dir.orthogonal()
		var seg_n := (d_out if d_out != Vector2.ZERO else d_in).orthogonal()
		var k := clampf(nrm.dot(seg_n), 0.5, 1.0)     # mitre length, capped for sharp turns
		offs[i] = nrm * hw / k
	for i in n - 1:
		quad(pts[i] + offs[i], pts[i + 1] + offs[i + 1], pts[i + 1] - offs[i + 1], pts[i] - offs[i], col)


## Filled polygon (any simple polygon, triangulated like draw_colored_polygon).
func polygon(pts: PackedVector2Array, col: Color) -> void:
	if pts.size() == 3:
		tri(pts[0], pts[1], pts[2], col)
		return
	var idx := Geometry2D.triangulate_polygon(pts)
	if idx.is_empty():
		for i in range(1, pts.size() - 1):
			tri(pts[0], pts[i], pts[i + 1], col)
		return
	for i in range(0, idx.size(), 3):
		tri(pts[idx[i]], pts[idx[i + 1]], pts[idx[i + 2]], col)


func circle(center: Vector2, radius: float, col: Color) -> void:
	if radius > FAN_RADIUS:
		var segs := 64
		var prev := center + Vector2(radius, 0)
		for i in range(1, segs + 1):
			var p := center + Vector2.from_angle(TAU * i / segs) * radius
			tri(center, prev, p, col)
			prev = p
		return
	# Quad covering the disc texture; its disc fills all but a 1px border.
	var h := radius * (DISC_SIZE * 0.5) / (DISC_SIZE * 0.5 - 1.0)
	var a := center + Vector2(-h, -h)
	var b := center + Vector2(h, -h)
	var c := center + Vector2(h, h)
	var d := center + Vector2(-h, h)
	tri(a, b, c, col, col, col, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1))
	tri(a, c, d, col, col, col, Vector2(0, 0), Vector2(1, 1), Vector2(0, 1))


## The baked mesh (null if nothing was recorded). Cached until more shapes are added.
func mesh() -> ArrayMesh:
	if _mesh == null and not _v.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _v
		arrays[Mesh.ARRAY_COLOR] = _c
		arrays[Mesh.ARRAY_TEX_UV] = _uv
		_mesh = ArrayMesh.new()
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _mesh


## Convenience: draw the baked mesh on `item` (no-op if empty).
func draw_on(item: CanvasItem, texture: Texture2D = null) -> void:
	var m := mesh()
	if m != null:
		item.draw_mesh(m, texture if texture != null else disc())
