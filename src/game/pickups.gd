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
# Rendering is split so that almost nothing is redrawn per frame:
#  - this node: base plates + jump pads (static; redrawn only when an item changes state)
#  - _progress: respawn rings of inactive items (redrawn while any item is respawning)
#  - one icon node per item and one halo node per item (under _glow): drawn once, the bob
#    and spin are just node transforms (no redraw); redrawn only if the weapon changes
#  - _glow itself: jump pad chevrons (animated)
#  - weapon icons (pixel sprites from the GunSprites atlas) sit together under _gun_icons so
#    they form one batch instead of breaking the DrawUtil batch between items
var _progress: Node2D
var _gun_icons: Node2D
var _icons: Array[Node2D] = []
var _halos: Array[Node2D] = []
var _state := PackedInt32Array()       # per item: active | dormant << 1 | (wid + 1) << 2 (last drawn)


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
	DrawUtil.setup(self)
	_progress = Node2D.new()
	_progress.draw.connect(_draw_progress)
	add_child(_progress)
	_glow = Node2D.new()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = add
	_glow.draw.connect(_draw_glow)
	_state.resize(items.size())
	_state.fill(-1)
	_gun_icons = Node2D.new()
	for i in items.size():
		var icon := Node2D.new()
		icon.draw.connect(_draw_icon.bind(i, icon))
		icon.visible = false
		(_gun_icons if items[i].type == "w" else self).add_child(icon)
		_icons.append(icon)
		var halo := Node2D.new()
		halo.use_parent_material = true
		halo.draw.connect(_draw_halo.bind(i, halo))
		halo.visible = false
		_glow.add_child(halo)
		_halos.append(halo)
	add_child(_gun_icons)
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
	var respawning := false
	var changed := false
	for i in items.size():
		var it := items[i]
		var st := int(it.active) | (int(it.dormant) << 1) | ((int(it.wid) + 1) << 2)
		if st != _state[i]:
			_state[i] = st
			changed = true
			var show: bool = it.active and not it.dormant
			_icons[i].visible = show
			_halos[i].visible = show
			_icons[i].queue_redraw()
			_halos[i].queue_redraw()
		if it.active:
			var p: Vector2 = it.pos + Vector2(0, _bob(i) - 4)
			_icons[i].position = p
			_halos[i].position = p
			match it.type:
				"D": _icons[i].queue_redraw()       # morphing spin: cheap, rare
				"w": _icons[i].rotation = sin(_t * 1.5 + i) * 0.15
		elif not it.dormant:
			respawning = true
	if changed:
		queue_redraw()
	if respawning or changed:
		_progress.queue_redraw()
	if not pads.is_empty():
		_glow.queue_redraw()


func _bob(i: int) -> float:
	return sin(_t * 2.4 + i * 1.7) * 3.0


## Base plates (static) and jump pads.
func _draw() -> void:
	for i in items.size():
		var it := items[i]
		if it.dormant:
			continue
		draw_set_transform(it.pos + Vector2(0, 13), 0.0, Vector2(1.0, 0.3))
		DrawUtil.circle(self, Vector2.ZERO, 15.0, Color(0, 0, 0, 0.35))
		DrawUtil.ring(self, Vector2.ZERO, 15.0, 2.0, Color(color_of(it), 0.45), 24)
	draw_set_transform(Vector2.ZERO)
	# Jump pads: glowing plate with rising chevrons.
	for pad in pads:
		DrawUtil.rect(self, Rect2(pad + Vector2(-15, -5), Vector2(30, 5)), Color(0.15, 0.17, 0.22))
		DrawUtil.rect(self, Rect2(pad + Vector2(-15, -5), Vector2(30, 2)), Color(0.9, 0.95, 1.0))


## Respawn progress ring around the plate of every inactive item.
func _draw_progress() -> void:
	var now: float = world.clock
	for it in items:
		if it.active or it.dormant:
			continue
		var k := clampf(1.0 - (it.respawn_at - now) / float(it.wait), 0.0, 1.0)
		if k <= 0.0:
			continue
		_progress.draw_set_transform(it.pos + Vector2(0, 13), 0.0, Vector2(1.0, 0.3))
		DrawUtil.arc(_progress, Vector2.ZERO, 15.0, -PI * 0.5, -PI * 0.5 + TAU * k, 3.0, color_of(it), maxi(2, int(24 * k)))
	_progress.draw_set_transform(Vector2.ZERO)


## One item's icon at its node origin (the node bobs / spins).
func _draw_icon(i: int, ci: Node2D) -> void:
	var it := items[i]
	var c := color_of(it)
	match it.type:
		"h", "H":
			var s := 9.0 if it.type == "h" else 13.0
			DrawUtil.rect(ci, Rect2(-s, -s, s * 2, s * 2).grow(2), CharPainter.OUTLINE)
			DrawUtil.rect(ci, Rect2(-s, -s, s * 2, s * 2), Color(0.95, 0.97, 1.0))
			DrawUtil.rect(ci, Rect2(-s * 0.25, -s * 0.75, s * 0.5, s * 1.5), c)
			DrawUtil.rect(ci, Rect2(-s * 0.75, -s * 0.25, s * 1.5, s * 0.5), c)
		"a":
			var shield := PackedVector2Array([Vector2(-11, -11), Vector2(11, -11), Vector2(10, 2), Vector2(0, 13), Vector2(-10, 2)])
			DrawUtil.outlined(ci, shield, c, CharPainter.OUTLINE, 4.0)
			DrawUtil.line(ci, Vector2(0, -9), Vector2(0, 10), c.lightened(0.4), 2.0)
		"D":
			var r := _t * 2.0
			var q := Vector2(12, 15)
			DrawUtil.quad(ci, Vector2.from_angle(r) * q, Vector2.from_angle(r + PI * 0.5) * q,
					Vector2.from_angle(r + PI) * q, Vector2.from_angle(r + PI * 1.5) * q, c)
			DrawUtil.circle(ci, Vector2.ZERO, 4.0, Color.WHITE)
		"w":
			# Pixel-art sprite, centred; small guns scaled up more so every pickup reads.
			var sz := GunSprites.size(it.wid)
			var k := clampf(40.0 / sz.x, 1.3, 2.0)
			GunSprites.draw_icon(ci, it.wid, Rect2(-sz * k * 0.5, sz * k))


## One item's additive halo (static; follows the icon's bob via its node position).
func _draw_halo(i: int, ci: Node2D) -> void:
	var c := color_of(items[i])
	DrawUtil.circle(ci, Vector2.ZERO, 26.0, Color(c, 0.10))
	DrawUtil.circle(ci, Vector2.ZERO, 16.0, Color(c, 0.12))


## Jump pad chevrons rising off each pad (animated).
func _draw_glow() -> void:
	for pad in pads:
		DrawUtil.circle(_glow, pad + Vector2(0, -4), 18.0, Color(0.4, 0.8, 1.0, 0.15))
		for k in 3:
			var f := fposmod(_t * 1.6 + k / 3.0, 1.0)
			var y := pad.y - 8.0 - f * 46.0
			var col := Color(0.5, 0.9, 1.0, (1.0 - f) * 0.6)
			var tip := Vector2(pad.x, y)
			DrawUtil.line(_glow, Vector2(pad.x - 11, y + 6), tip, col, 3.0)
			DrawUtil.line(_glow, tip, Vector2(pad.x + 11, y + 6), col, 3.0)
