class_name DrawUtil
## Batch-friendly drawing for the GL Compatibility (WebGL2) 2D renderer.
##
## On that renderer every draw_circle / draw_colored_polygon / draw_polygon / draw_polyline /
## draw_arc is a "polygon" command: one draw call each, plus fresh GL buffers every redraw.
## Here every shape is a 4-point draw_primitive() textured from ONE shared atlas, so any run
## of DrawUtil shapes (discs, glows, quads, rects, lines, rings, polygons) - even across
## canvas items - collapses into a single instanced draw call.
##
## Atlas (256x64, mipmapped), one 64px cell per shape; content sits inside a transparent
## margin so mip blur produces a ~1px anti-aliased edge at any on-screen size:
##   cell 0  disc   - solid circle, radius 28 of 32
##   cell 1  glow   - soft radial blob for additive halos
##   cell 2  stripe - opaque middle half (rows 16..47, cols 8..55); lines/rings map their quad to 2x the
##                    stroke width across it. Its centre texel is also the solid-fill source.
##   cell 3  ring   - thin annulus (radius 28, ~3 texels thick) for small fixed rings
## Canvas items using these should set texture_filter = DrawUtil.FILTER (see setup()).

const FILTER := CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
const DISC_K := 32.0 / 28.0          # quad half-size per unit radius (disc / ring cells)
const GLOW_K := 32.0 / 30.0
const AA := 0.75                     # strokes get this much extra width for their soft edge

static var _tex: ImageTexture
static var _pts := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
static var _col1 := PackedColorArray([Color.WHITE])
static var _col4 := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
static var _uv_solid := PackedVector2Array([Vector2(0.625, 0.5), Vector2(0.625, 0.5), Vector2(0.625, 0.5), Vector2(0.625, 0.5)])
static var _uv_stripe := PackedVector2Array([Vector2(0.625, 0.0), Vector2(0.625, 0.0), Vector2(0.625, 1.0), Vector2(0.625, 1.0)])
static var _uv_disc := _cell_uvs(0)
static var _uv_glow := _cell_uvs(1)
static var _uv_ring := _cell_uvs(3)


static func _cell_uvs(i: int) -> PackedVector2Array:
	var u0 := i * 0.25
	var u1 := u0 + 0.25
	return PackedVector2Array([Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 1), Vector2(u0, 1)])


## The shared atlas (built once, on first use).
static func texture() -> Texture2D:
	if _tex == null:
		_build()
	return _tex


## Make a canvas item sample the atlas with mipmaps (smooth edges on small shapes).
static func setup(ci: CanvasItem) -> void:
	ci.texture_filter = FILTER
	if _tex == null:
		_build()


static func _build() -> void:
	var img := Image.create_empty(256, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		var cy := y + 0.5 - 32.0
		var stripe := 1.0 if y >= 16 and y < 48 else 0.0
		for x in 64:
			var cx := x + 0.5 - 32.0
			var d := sqrt(cx * cx + cy * cy)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(28.5 - d, 0.0, 1.0)))
			var g := clampf(1.0 - d / 30.0, 0.0, 1.0)
			img.set_pixel(64 + x, y, Color(1, 1, 1, g * g * (3.0 - 2.0 * g) * g))
			# Only the centre column (u = 0.625) is ever sampled; keeping the band 8px clear of the
			# cell's sides stops it bleeding into the glow / ring cells (seam on big glows).
			img.set_pixel(128 + x, y, Color(1, 1, 1, stripe if x >= 8 and x < 56 else 0.0))
			img.set_pixel(192 + x, y, Color(1, 1, 1, clampf(1.6 - absf(d - 26.5), 0.0, 1.0)))
	img.generate_mipmaps()
	_tex = ImageTexture.create_from_image(img)


## Filled anti-aliased circle.
static func circle(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	if _tex == null:
		_build()
	var h := r * DISC_K
	_pts[0] = Vector2(c.x - h, c.y - h)
	_pts[1] = Vector2(c.x + h, c.y - h)
	_pts[2] = Vector2(c.x + h, c.y + h)
	_pts[3] = Vector2(c.x - h, c.y + h)
	_col1[0] = col
	ci.draw_primitive(_pts, _col1, _uv_disc, _tex)


## Soft radial glow blob (best on an additive layer). `r` is where it fades to nothing.
static func glow(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	if _tex == null:
		_build()
	var h := r * GLOW_K
	_pts[0] = Vector2(c.x - h, c.y - h)
	_pts[1] = Vector2(c.x + h, c.y - h)
	_pts[2] = Vector2(c.x + h, c.y + h)
	_pts[3] = Vector2(c.x - h, c.y + h)
	_col1[0] = col
	ci.draw_primitive(_pts, _col1, _uv_glow, _tex)


## Thin anti-aliased circle outline from the ring cell (stroke ~ r / 9). Cheap: one quad.
static func thin_ring(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	if _tex == null:
		_build()
	var h := r * DISC_K * (28.0 / 26.5)
	_pts[0] = Vector2(c.x - h, c.y - h)
	_pts[1] = Vector2(c.x + h, c.y - h)
	_pts[2] = Vector2(c.x + h, c.y + h)
	_pts[3] = Vector2(c.x - h, c.y + h)
	_col1[0] = col
	ci.draw_primitive(_pts, _col1, _uv_ring, _tex)


## Solid axis-aligned rectangle (hard edges, like draw_rect) that batches with the rest.
static func rect(ci: CanvasItem, r: Rect2, col: Color) -> void:
	if _tex == null:
		_build()
	var e := r.end
	_pts[0] = r.position
	_pts[1] = Vector2(e.x, r.position.y)
	_pts[2] = e
	_pts[3] = Vector2(r.position.x, e.y)
	_col1[0] = col
	ci.draw_primitive(_pts, _col1, _uv_solid, _tex)


## Solid convex quad (pass d == c for a triangle). Triangulated as (a,b,c) + (a,c,d).
static func quad(ci: CanvasItem, a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
	if _tex == null:
		_build()
	_pts[0] = a
	_pts[1] = b
	_pts[2] = c
	_pts[3] = d
	_col1[0] = col
	ci.draw_primitive(_pts, _col1, _uv_solid, _tex)


## Quad with a colour per corner (gradients, soft feathers).
static func quad4(ci: CanvasItem, a: Vector2, b: Vector2, c: Vector2, d: Vector2,
		ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	if _tex == null:
		_build()
	_pts[0] = a
	_pts[1] = b
	_pts[2] = c
	_pts[3] = d
	_col4[0] = ca
	_col4[1] = cb
	_col4[2] = cc
	_col4[3] = cd
	ci.draw_primitive(_pts, _col4, _uv_solid, _tex)


## Solid convex polygon, split into quads fanned from the first point.
static func fan(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	var n := pts.size()
	var i := 1
	while i + 1 < n:
		var last := mini(i + 2, n - 1)
		quad(ci, pts[0], pts[i], pts[i + 1], pts[last], col)
		i += 2


## Convex polygon with an outline `w` wide (drawn as the polygon grown by w/2 underneath),
## replacing the antialiased draw_polyline + draw_colored_polygon pair.
static func outlined(ci: CanvasItem, pts: PackedVector2Array, fill: Color, line_col: Color, w: float) -> void:
	fan(ci, grow(pts, w * 0.5), line_col)
	fan(ci, pts, fill)


## Convex polygon offset outward by `d` with mitred corners (clamped on very sharp tips).
## Works for either winding.
static func grow(pts: PackedVector2Array, d: float) -> PackedVector2Array:
	var n := pts.size()
	var out := PackedVector2Array()
	out.resize(n)
	var area := 0.0
	for i in n:
		area += pts[i].cross(pts[(i + 1) % n])
	var s := d if area > 0.0 else -d
	for i in n:
		out[i] = _mitre(pts[(i + n - 1) % n], pts[i], pts[(i + 1) % n], s)
	return out


## Outlined convex quad without any array allocation (see outlined()).
static func outlined_quad(ci: CanvasItem, a: Vector2, b: Vector2, c: Vector2, d: Vector2,
		fill: Color, line_col: Color, w: float) -> void:
	var s := w * 0.5
	if (b - a).cross(c - a) + (c - a).cross(d - a) < 0.0:
		s = -s
	quad(ci, _mitre(d, a, b, s), _mitre(a, b, c, s), _mitre(b, c, d, s), _mitre(c, d, a, s), line_col)
	quad(ci, a, b, c, d, fill)


## Outlined triangle without any array allocation.
static func outlined_tri(ci: CanvasItem, a: Vector2, b: Vector2, c: Vector2,
		fill: Color, line_col: Color, w: float) -> void:
	var s := w * 0.5
	if (b - a).cross(c - a) < 0.0:
		s = -s
	var ga := _mitre(c, a, b, s)
	var gc := _mitre(b, c, a, s)
	quad(ci, ga, _mitre(a, b, c, s), gc, gc, line_col)
	quad(ci, a, b, c, c, fill)


## Corner `p` pushed out by `s` along the mitre (positive s = outward for positive-area winding).
static func _mitre(prev: Vector2, p: Vector2, next: Vector2, s: float) -> Vector2:
	var e0 := (p - prev).normalized()
	var e1 := (next - p).normalized()
	var m := Vector2(e0.y + e1.y, -e0.x - e1.x)
	var k := 1.0 + e0.dot(e1)
	return p + m * (s / maxf(k, 0.32))        # mitre length limited to ~2.5x on sharp tips


## Anti-aliased straight line (butt ends) - a textured quad, so it batches with everything.
static func line(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, width: float) -> void:
	if _tex == null:
		_build()
	var dx := b.x - a.x
	var dy := b.y - a.y
	var l := sqrt(dx * dx + dy * dy)
	if l < 0.0001:
		return
	var k := (width + AA) / l             # quad spans 2x the stroke; the stripe's opaque half is the stroke
	var n := Vector2(-dy * k, dx * k)
	_pts[0] = a + n
	_pts[1] = b + n
	_pts[2] = b - n
	_pts[3] = a - n
	_col1[0] = col
	ci.draw_primitive(_pts, _col1, _uv_stripe, _tex)


## Outlined stroke: a `width + outline * 2` line in `line_col` under a `width` line in `col`
## (one normal computation for both; used for limbs).
static func stroke(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, width: float,
		line_col: Color, outline: float) -> void:
	if _tex == null:
		_build()
	var dx := b.x - a.x
	var dy := b.y - a.y
	var l := sqrt(dx * dx + dy * dy)
	if l < 0.0001:
		return
	var u := Vector2(-dy / l, dx / l)
	var n := u * (width + outline * 2.0 + AA)
	_pts[0] = a + n
	_pts[1] = b + n
	_pts[2] = b - n
	_pts[3] = a - n
	_col1[0] = line_col
	ci.draw_primitive(_pts, _col1, _uv_stripe, _tex)
	n = u * (width + AA)
	_pts[0] = a + n
	_pts[1] = b + n
	_pts[2] = b - n
	_pts[3] = a - n
	_col1[0] = col
	ci.draw_primitive(_pts, _col1, _uv_stripe, _tex)


## Open polyline as separate anti-aliased segments.
static func polyline(ci: CanvasItem, pts: PackedVector2Array, col: Color, width: float) -> void:
	for i in pts.size() - 1:
		line(ci, pts[i], pts[i + 1], col, width)


## Closed outline of a polygon as anti-aliased segments (replaces closed draw_polyline).
static func outline(ci: CanvasItem, pts: PackedVector2Array, col: Color, width: float) -> void:
	var n := pts.size()
	for i in n:
		line(ci, pts[i], pts[(i + 1) % n], col, width)


## Anti-aliased arc / ring of any radius and stroke width, as seamless annulus segments.
static func arc(ci: CanvasItem, c: Vector2, r: float, from: float, to: float, width: float,
		col: Color, segs := 32) -> void:
	if _tex == null:
		_build()
	segs = maxi(segs, 1)
	var hw := width + AA                  # 2x the stroke (see line())
	var ro := r + hw
	var ri := maxf(0.0, r - hw)
	var step := (to - from) / segs
	var d0 := Vector2.from_angle(from)
	_col1[0] = col
	for i in segs:
		var d1 := Vector2.from_angle(from + step * (i + 1))
		_pts[0] = c + d0 * ro
		_pts[1] = c + d1 * ro
		_pts[2] = c + d1 * ri
		_pts[3] = c + d0 * ri
		ci.draw_primitive(_pts, _col1, _uv_stripe, _tex)
		d0 = d1


static func ring(ci: CanvasItem, c: Vector2, r: float, width: float, col: Color, segs := 32) -> void:
	arc(ci, c, r, 0.0, TAU, width, col, segs)
