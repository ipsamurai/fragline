class_name GunSprites
## Pixel-art weapon sprites (CC0 "Guns" pack by SnoopethDuckDuck, see CREDITS.md).
##
## All nine weapons live in ONE atlas (assets/sprites/guns.png, mipmapped). Each sprite was
## upscaled x4 with nearest-neighbour before packing, so linear / mipmapped canvas filtering
## still looks crisp at the game's zoom. All public coordinates are in NATIVE sprite pixels
## (the original art, 1/ATLAS_K of the atlas texels); sprites point RIGHT (+x).
##
## Per weapon: GRIP = where the trigger hand holds it, FORE = where the support hand goes,
## MUZZLE = barrel tip. Drawing is a single draw_texture_rect_region (batches with other
## draws of this texture).

const ATLAS_K := 4.0          # atlas texels per native sprite pixel
## World units per native sprite pixel when a fighter holds the gun (CharPainter / Player.muzzle);
## HOLD_SCALE tweaks it per weapon (see hold_scale()).
const WORLD_SCALE := 1.25
const HOLD_SCALE: Array[float] = [1.15, 1.0, 1.0, 1.0, 1.05, 0.95, 1.0, 1.0, 1.0]

## Sub-rects of the atlas (texels), indexed by weapon id (Weapons.ENFORCER .. Weapons.REDEEMER).
const REGIONS: Array[Rect2] = [
	Rect2(8, 8, 84, 64),        # Enforcer          Pack 2 #19
	Rect2(180, 8, 136, 80),     # Flak Cannon       Pack 1 #51
	Rect2(352, 8, 144, 84),     # Minigun           Pack 1 #48
	Rect2(8, 124, 116, 84),     # Shock Rifle       Pack 2 #33
	Rect2(180, 124, 104, 64),   # Pulse Gun         Pack 1 #32
	Rect2(352, 124, 156, 100),  # Rocket Launcher   Pack 1 #50
	Rect2(8, 240, 128, 68),     # Grenade Launcher  Pack 1 #42
	Rect2(180, 240, 144, 64),   # Sniper Rifle      Pack 1 #56
	Rect2(352, 240, 112, 88),   # Redeemer          Pack 2 #15
]
## Trigger-hand point (native px from the sprite's top-left).
const GRIP: Array[Vector2] = [
	Vector2(4.5, 10.0), Vector2(17.0, 15.5), Vector2(7.0, 14.5),
	Vector2(4.5, 12.5), Vector2(8.0, 10.0), Vector2(13.5, 19.5),
	Vector2(12.5, 11.5), Vector2(12.0, 10.0), Vector2(8.0, 13.0),
]
## Support-hand point (native px).
const FORE: Array[Vector2] = [
	Vector2(5.0, 10.0), Vector2(24.0, 14.0), Vector2(22.0, 15.0),
	Vector2(18.0, 13.0), Vector2(15.0, 9.0), Vector2(26.0, 18.0),
	Vector2(22.0, 9.0), Vector2(22.0, 8.0), Vector2(14.0, 15.0),
]
## Barrel tip (native px).
const MUZZLE: Array[Vector2] = [
	Vector2(19.0, 6.5), Vector2(32.5, 11.0), Vector2(34.5, 6.5),
	Vector2(28.5, 9.0), Vector2(25.5, 7.5), Vector2(38.5, 11.5),
	Vector2(31.0, 7.0), Vector2(34.5, 6.5), Vector2(27.5, 10.5),
]

static var _tex: Texture2D


## The shared atlas.
static func texture() -> Texture2D:
	if _tex == null:
		_tex = load("res://assets/sprites/guns.png")
	return _tex


static func _w(wid: int) -> int:
	return clampi(wid, 0, REGIONS.size() - 1)


## Atlas sub-rect (texels) for weapon id.
static func region(wid: int) -> Rect2:
	return REGIONS[_w(wid)]


## Native sprite size in px (unscaled).
static func size(wid: int) -> Vector2:
	return REGIONS[_w(wid)].size / ATLAS_K


## World units per native px when held by a fighter (WORLD_SCALE x per-weapon HOLD_SCALE).
static func hold_scale(wid: int) -> float:
	return WORLD_SCALE * HOLD_SCALE[_w(wid)]


## Grip -> muzzle vector in native px, pointing right (+y = down when not flipped).
static func muzzle_offset(wid: int) -> Vector2:
	var i := _w(wid)
	return MUZZLE[i] - GRIP[i]


## Grip -> support-hand vector in native px.
static func fore_offset(wid: int) -> Vector2:
	var i := _w(wid)
	return FORE[i] - GRIP[i]


## Draw weapon `wid` with its grip at `pos`, rotated by `angle`, scaled by `scale`;
## flip_v mirrors for left-facing aim. NOTE: sets the canvas item's draw transform and resets
## it to identity afterwards (use draw_xf to compose with an existing transform).
static func draw(ci: CanvasItem, wid: int, pos: Vector2, angle: float, scale := 1.0, flip_v := false, modulate := Color.WHITE) -> void:
	ci.draw_set_transform(pos, angle, Vector2(scale, -scale if flip_v else scale))
	_blit(ci, wid, modulate)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## Draw with the grip at the origin of `xf` (native px units, +x along the barrel).
## Leaves `xf` as the current draw transform.
static func draw_xf(ci: CanvasItem, wid: int, xf: Transform2D, modulate := Color.WHITE) -> void:
	ci.draw_set_transform_matrix(xf)
	_blit(ci, wid, modulate)


## Replace the contents of a raw RenderingServer canvas item with weapon `wid` (grip at the
## origin of `xf`, native px units). Allocation-free; used for CharPainter's per-fighter gun layer.
static func draw_rid(rid: RID, wid: int, xf: Transform2D, modulate := Color.WHITE) -> void:
	var i := _w(wid)
	var src := REGIONS[i]
	RenderingServer.canvas_item_clear(rid)
	RenderingServer.canvas_item_add_set_transform(rid, xf)
	RenderingServer.canvas_item_add_texture_rect_region(rid, Rect2(-GRIP[i], src.size / ATLAS_K), texture().get_rid(), src, modulate)


## Draw as a UI icon fitted (aspect kept, centred) inside `rect`, in the current transform.
static func draw_icon(ci: CanvasItem, wid: int, rect: Rect2, modulate := Color.WHITE) -> void:
	var src := region(wid)
	var k := minf(rect.size.x / src.size.x, rect.size.y / src.size.y)
	var sz := src.size * k
	ci.draw_texture_rect_region(texture(), Rect2(rect.position + (rect.size - sz) * 0.5, sz), src, modulate)


static func _blit(ci: CanvasItem, wid: int, modulate: Color) -> void:
	var i := _w(wid)
	var src := REGIONS[i]
	ci.draw_texture_rect_region(texture(), Rect2(-GRIP[i], src.size / ATLAS_K), src, modulate)
