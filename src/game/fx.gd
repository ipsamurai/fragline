class_name Fx
extends Node2D
## Pooled combat effects. Everything is drawn from the DrawUtil atlas, so each layer is one
## batched draw call, and every pool is a set of fixed-size packed arrays with swap-remove
## compaction (passes only touch live entries; nothing allocates mid-match except the rare
## floating damage text). When a pool is full a live slot is recycled round-robin.
##   particles  normal pool [0, _cn) + additive pool [MAX, MAX + _ca); additive ones can be
##              stretched along their velocity (spark streaks)
##   lines      tracers, beams, tapered muzzle-flash spikes, travelling tracer streaks, arcs
##   rings      shockwaves (optionally delayed, for staged blasts)
##   chunks     shell casings and explosion debris: tumble, bounce once on level tiles, fade
##   decals     bullet holes / scorch marks that glow hot, cool, then fade
## Chunks and decals draw on a layer parented under the level, so they sit behind fighters.
## Also owns the camera recoil kick (Camera2D.offset), see kick().

const MAX := 400                     # per particle pool
const MAX_LINES := 160
const MAX_RINGS := 32
const MAX_CHUNKS := 80
const MAX_DECALS := 48

enum { FIRE, ENERGY, NUKE }          # explosion styles
enum { HIT_BULLET, HIT_SNIPER, HIT_SHOCK, HIT_PLASMA }   # hitscan wall-impact styles
enum { L_PLAIN, L_WAVE, L_FLASH, L_TRACER, L_ARC }

const SMOKE := Color(0.25, 0.24, 0.28)
const BRASS := Color(1.0, 0.78, 0.33)
const CHUNK_GRAV := 980.0
const KICK_MAX := 16.0
const NO_GLOW := Color(0, 0, 0, 0)

class Text:
	var pos := Vector2.ZERO
	var text := ""
	var color := Color.WHITE
	var life := 0.0

const FONT := UiTheme.TITLE

var _texts: Array[Text] = []
var _busy := 0.0     # time until every particle / line / ring is dead; lets idle frames skip all work
var _glow: Node2D
var _under: Node2D   # chunks + decals, behind the fighters
var _level: Level
var _world: World

# Particle pools (index i < MAX: normal, i >= MAX: additive).
var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _life := PackedFloat32Array()
var _max_life := PackedFloat32Array()
var _size := PackedFloat32Array()
var _size_end := PackedFloat32Array()
var _grav := PackedFloat32Array()
var _drag := PackedFloat32Array()
var _streak := PackedFloat32Array()
var _color := PackedColorArray()
var _cn := 0         # live normal particles
var _ca := 0         # live additive particles
var _rr_n := 0       # recycle cursors for full pools
var _rr_a := 0

# Lines.
var _la := PackedVector2Array()
var _lb := PackedVector2Array()
var _lcol := PackedColorArray()
var _lw := PackedFloat32Array()
var _ll := PackedFloat32Array()
var _lm := PackedFloat32Array()
var _lk := PackedByteArray()
var _ln := 0
var _rr_l := 0

# Rings (life includes the start delay; drawn once life <= max).
var _rp := PackedVector2Array()
var _rrad := PackedFloat32Array()
var _rw := PackedFloat32Array()
var _rl := PackedFloat32Array()
var _rm := PackedFloat32Array()
var _rc := PackedColorArray()
var _rn := 0
var _rr_r := 0

# Chunks (casings / debris). State: 0 flying, 1 bounced once, 2 resting.
var _cp := PackedVector2Array()
var _cv := PackedVector2Array()
var _cang := PackedFloat32Array()
var _cspin := PackedFloat32Array()
var _cl := PackedFloat32Array()
var _cm := PackedFloat32Array()
var _clen := PackedFloat32Array()
var _cwid := PackedFloat32Array()
var _ccol := PackedColorArray()
var _cglow := PackedColorArray()
var _cst := PackedByteArray()
var _chn := 0
var _rr_c := 0

# Decals.
var _dp := PackedVector2Array()
var _drad := PackedFloat32Array()
var _dl := PackedFloat32Array()
var _dm := PackedFloat32Array()
var _dhot := PackedColorArray()
var _dax := PackedVector2Array()     # ellipse half-extents per unit radius (flat along its surface)
var _dn := 0
var _rr_d := 0

var _under_live := false
var _under_dirty := false
var _under_t := 0.0
var _kick := Vector2.ZERO
var _kicking := false
var _mini_flip := false

# Scratch arrays for draw_primitive (reused, never reallocated).
var _quad := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _qcol := PackedColorArray([Color.WHITE])
var _disc_uv := PackedVector2Array([Vector2(0, 0), Vector2(0.25, 0), Vector2(0.25, 1), Vector2(0, 1)])
var _glow_uv := PackedVector2Array([Vector2(0.25, 0), Vector2(0.5, 0), Vector2(0.5, 1), Vector2(0.25, 1)])
var _tex: Texture2D


func _ready() -> void:
	_pos.resize(MAX * 2)
	_vel.resize(MAX * 2)
	_life.resize(MAX * 2)
	_max_life.resize(MAX * 2)
	_size.resize(MAX * 2)
	_size_end.resize(MAX * 2)
	_grav.resize(MAX * 2)
	_drag.resize(MAX * 2)
	_streak.resize(MAX * 2)
	_color.resize(MAX * 2)
	_la.resize(MAX_LINES)
	_lb.resize(MAX_LINES)
	_lcol.resize(MAX_LINES)
	_lw.resize(MAX_LINES)
	_ll.resize(MAX_LINES)
	_lm.resize(MAX_LINES)
	_lk.resize(MAX_LINES)
	_rp.resize(MAX_RINGS)
	_rrad.resize(MAX_RINGS)
	_rw.resize(MAX_RINGS)
	_rl.resize(MAX_RINGS)
	_rm.resize(MAX_RINGS)
	_rc.resize(MAX_RINGS)
	_cp.resize(MAX_CHUNKS)
	_cv.resize(MAX_CHUNKS)
	_cang.resize(MAX_CHUNKS)
	_cspin.resize(MAX_CHUNKS)
	_cl.resize(MAX_CHUNKS)
	_cm.resize(MAX_CHUNKS)
	_clen.resize(MAX_CHUNKS)
	_cwid.resize(MAX_CHUNKS)
	_ccol.resize(MAX_CHUNKS)
	_cglow.resize(MAX_CHUNKS)
	_cst.resize(MAX_CHUNKS)
	_dp.resize(MAX_DECALS)
	_drad.resize(MAX_DECALS)
	_dl.resize(MAX_DECALS)
	_dm.resize(MAX_DECALS)
	_dhot.resize(MAX_DECALS)
	_dax.resize(MAX_DECALS)
	_tex = DrawUtil.texture()
	DrawUtil.setup(self)
	_glow = Node2D.new()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = add
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	DrawUtil.setup(_glow)
	_world = get_parent() as World
	if _world:
		_level = _world.level
	_under = Node2D.new()
	_under.draw.connect(_draw_under)
	DrawUtil.setup(_under)
	if _level:
		_level.add_child(_under)       # after the tiles, before the fighters
	else:
		add_child(_under)


func emit(pos: Vector2, vel: Vector2, life: float, size: float, size_end: float, color: Color,
		grav := 0.0, drag := 0.0, additive := false, streak := 0.0) -> void:
	var i: int
	if additive:
		if _ca < MAX:
			i = MAX + _ca
			_ca += 1
		else:
			i = MAX + _rr_a
			_rr_a = (_rr_a + 1) % MAX
	else:
		if _cn < MAX:
			i = _cn
			_cn += 1
		else:
			i = _rr_n
			_rr_n = (_rr_n + 1) % MAX
	_pos[i] = pos
	_vel[i] = vel
	_life[i] = life
	_max_life[i] = life
	_size[i] = size
	_size_end[i] = size_end
	_color[i] = color
	_grav[i] = grav
	_drag[i] = drag
	_streak[i] = streak
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


func _add_line(a: Vector2, b: Vector2, color: Color, width: float, life: float, kind: int) -> void:
	var i: int
	if _ln < MAX_LINES:
		i = _ln
		_ln += 1
	else:
		i = _rr_l
		_rr_l = (_rr_l + 1) % MAX_LINES
	_la[i] = a
	_lb[i] = b
	_lcol[i] = color
	_lw[i] = width
	_ll[i] = life
	_lm[i] = life
	_lk[i] = kind
	_busy = maxf(_busy, life)


func line(a: Vector2, b: Vector2, color: Color, width: float, life: float, wave := false) -> void:
	_add_line(a, b, color, width, life, L_WAVE if wave else L_PLAIN)


## A short bright streak that races from a to b (bullet in flight).
func tracer(a: Vector2, b: Vector2, color: Color, width: float, life: float) -> void:
	_add_line(a, b, color, width, life, L_TRACER)


## Flickering electric arc between two points.
func arc(a: Vector2, b: Vector2, color: Color, life := 0.06) -> void:
	_add_line(a, b, color, 2.0, life, L_ARC)


## Tapered muzzle-flash spike from `pos` along `dir`.
func _spike(pos: Vector2, dir: Vector2, length: float, width: float, color: Color, life: float) -> void:
	_add_line(pos, pos + dir * length, color, width, life, L_FLASH)


func ring(pos: Vector2, radius: float, color: Color, life: float, delay := 0.0, width := 6.0) -> void:
	var i: int
	if _rn < MAX_RINGS:
		i = _rn
		_rn += 1
	else:
		i = _rr_r
		_rr_r = (_rr_r + 1) % MAX_RINGS
	_rp[i] = pos
	_rrad[i] = radius
	_rw[i] = width
	_rl[i] = life + delay
	_rm[i] = life
	_rc[i] = color
	_busy = maxf(_busy, life + delay)


## Floating number (damage dealt by you).
func text(pos: Vector2, s: String, color: Color) -> void:
	var t := Text.new()
	t.pos = pos + Vector2(randf_range(-10, 10), 0)
	t.text = s
	t.color = color
	t.life = 0.8
	_texts.append(t)
	_busy = maxf(_busy, 0.8)


## Tumbling chunk (casing / debris) that bounces once on the level and fades.
func chunk(pos: Vector2, vel: Vector2, spin: float, length: float, width: float, color: Color,
		glow := NO_GLOW, life := 1.8) -> void:
	if _cell_kind(pos) != Level.EMPTY:
		return
	var i: int
	if _chn < MAX_CHUNKS:
		i = _chn
		_chn += 1
	else:
		i = _rr_c
		_rr_c = (_rr_c + 1) % MAX_CHUNKS
	_cp[i] = pos
	_cv[i] = vel
	_cang[i] = randf() * TAU
	_cspin[i] = spin
	_cl[i] = life
	_cm[i] = life
	_clen[i] = length
	_cwid[i] = width
	_ccol[i] = color
	_cglow[i] = glow
	_cst[i] = 0
	_under_dirty = true
	_under_live = true
	if glow.a > 0.0:
		_busy = maxf(_busy, 0.6)


## Scorch / bullet-hole mark on the surface with normal `nrm` (flattened along it).
## `hot` (alpha > 0) glows briefly on top while it cools.
func decal(pos: Vector2, radius: float, life: float, hot := NO_GLOW, nrm := Vector2.ZERO) -> void:
	var i: int
	if _dn < MAX_DECALS:
		i = _dn
		_dn += 1
	else:
		i = _rr_d
		_rr_d = (_rr_d + 1) % MAX_DECALS
	_dp[i] = pos
	_drad[i] = radius
	_dl[i] = life
	_dm[i] = life
	_dhot[i] = hot
	if absf(nrm.y) > 0.5:
		_dax[i] = Vector2(2.2, 1.0)
	elif absf(nrm.x) > 0.5:
		_dax[i] = Vector2(1.0, 2.2)
	else:
		_dax[i] = Vector2(1.8, 1.8)
	_under_dirty = true
	_under_live = true
	if hot.a > 0.0:
		_busy = maxf(_busy, 0.7)


## Camera recoil / blast push: offsets the camera by up to KICK_MAX px, decays fast.
func kick(dir: Vector2, amount: float) -> void:
	if dir.length_squared() < 0.0001 or amount <= 0.0:
		return
	_kick = (_kick + dir.normalized() * amount).limit_length(KICK_MAX)
	_kicking = true


func sparks(pos: Vector2, dir: Vector2, color: Color, count: int, speed := 320.0) -> void:
	for i in scaled(count):
		var v := dir.rotated(randf_range(-0.9, 0.9)) * speed * randf_range(0.3, 1.0)
		emit(pos, v, randf_range(0.15, 0.35), 2.2, 0.5, color, 500.0, 3.0, true, 0.018)


func muzzle(pos: Vector2, color: Color) -> void:
	emit(pos, Vector2.ZERO, 0.07, 16.0, 6.0, Color(color.lerp(Color.WHITE, 0.5), 0.8), 0.0, 0.0, true)


## Per-weapon muzzle flash: tapered spikes (2-3 frames), white-hot core, coloured glow, sparks.
func muzzle_flash(pos: Vector2, dir: Vector2, color: Color, wid: int, alt: bool) -> void:
	var hot := color.lerp(Color.WHITE, 0.45)
	var n := Vector2(-dir.y, dir.x)
	match wid:
		Weapons.ENFORCER:
			_spike(pos, dir, 20.0, 7.0, hot, 0.05)
			_spike(pos, dir.rotated(0.9), 7.0, 3.0, hot, 0.04)
			_spike(pos, dir.rotated(-0.9), 7.0, 3.0, hot, 0.04)
			_core(pos, 8.0, 22.0, color, 0.09)
			_fwd_sparks(pos, dir, color, 2, 260.0, 0.35)
		Weapons.MINIGUN:
			_mini_flip = not _mini_flip
			if _mini_flip:
				_spike(pos + n * 1.5, dir, 24.0, 5.0, hot, 0.04)
			else:
				_spike(pos - n * 1.5, dir, 13.0, 8.0, hot, 0.04)
				_spike(pos, dir.rotated(1.1), 8.0, 3.0, hot, 0.035)
				_spike(pos, dir.rotated(-1.1), 8.0, 3.0, hot, 0.035)
			_core(pos, 6.0, 16.0, color, 0.06)
			if randf() < 0.5:
				_fwd_sparks(pos, dir, color, 1, 300.0, 0.3)
		Weapons.SNIPER:
			if alt:
				_spike(pos, dir, 34.0, 10.0, Color(0.75, 0.95, 1.0), 0.08)
				_core(pos, 12.0, 30.0, Color(0.75, 0.95, 1.0), 0.14)
			else:
				_spike(pos, dir, 52.0, 9.0, hot, 0.07)
				_spike(pos, dir.rotated(1.35), 14.0, 4.0, hot, 0.06)     # muzzle brake
				_spike(pos, dir.rotated(-1.35), 14.0, 4.0, hot, 0.06)
				_core(pos, 14.0, 38.0, color, 0.15)
				_fwd_sparks(pos, dir, color, 4, 380.0, 0.25)
			_smoke_puff(pos, dir, 4, 1.0)
		Weapons.FLAK:
			_spike(pos, dir, 32.0, 14.0, hot, 0.06)
			_spike(pos, dir.rotated(0.4), 20.0, 6.0, hot, 0.05)
			_spike(pos, dir.rotated(-0.4), 20.0, 6.0, hot, 0.05)
			_core(pos, 12.0, 34.0, color, 0.1)
			for i in scaled(6):
				emit(pos, dir.rotated(randf_range(-0.5, 0.5)) * randf_range(200, 480), randf_range(0.2, 0.4), 2.2, 0.4,
						Color(1.0, 0.7, 0.3), 700.0, 2.0, true, 0.02)
			_smoke_puff(pos, dir, 3, 0.8)
		Weapons.ROCKET, Weapons.REDEEMER:
			var big := wid == Weapons.REDEEMER
			_spike(pos, dir, 30.0 if big else 22.0, 12.0 if big else 9.0, hot, 0.06)
			_core(pos, 12.0, 32.0 if big else 24.0, Color(1.0, 0.6, 0.25), 0.1)
			# Back-blast out of the rear of the tube.
			var rear := pos - dir * float(Weapons.LIST[wid].gun_len + 4)
			for i in scaled(5 if big else 3):
				emit(rear, -dir.rotated(randf_range(-0.5, 0.5)) * randf_range(60, 160) + Vector2(0, -20),
						randf_range(0.5, 0.8), 4.0, 13.0, Color(SMOKE.lightened(0.3), 0.45), -30.0, 3.0)
			emit(rear, -dir * 60.0, 0.1, 8.0, 3.0, Color(1.0, 0.65, 0.3, 0.7), 0.0, 4.0, true)
		Weapons.GRENADE:
			_spike(pos, dir, 14.0, 9.0, hot, 0.05)
			_core(pos, 9.0, 20.0, color, 0.08)
			_smoke_puff(pos, dir, 2, 0.7)
		Weapons.SHOCK:
			if alt:
				ring(pos, 16.0, color, 0.18, 0.0, 3.0)
				_core(pos, 10.0, 28.0, color, 0.12)
			else:
				_spike(pos, dir, 22.0, 7.0, hot, 0.05)
				_core(pos, 10.0, 26.0, color, 0.1)
				for i in 2:
					arc(pos, pos + Vector2.from_angle(randf() * TAU) * randf_range(10.0, 18.0), color, 0.05)
		Weapons.PULSE:
			if alt:      # plasma wave fires 20x/s: keep it to a soft glow
				emit(pos, Vector2.ZERO, 0.05, 9.0, 6.0, Color(color, 0.45), 0.0, 0.0, true)
			else:
				_spike(pos, dir, 14.0, 6.0, hot, 0.04)
				_core(pos, 6.0, 16.0, color, 0.07)
		_:
			muzzle(pos, color)


func _core(pos: Vector2, core: float, glow: float, color: Color, life: float) -> void:
	emit(pos, Vector2.ZERO, life * 0.6, core, core * 0.4, Color(1, 1, 0.95, 0.95), 0.0, 0.0, true)
	emit(pos, Vector2.ZERO, life, glow * 1.4, glow * 0.7, Color(color, 0.5), 0.0, 0.0, true, -1.0)


func _fwd_sparks(pos: Vector2, dir: Vector2, color: Color, count: int, speed: float, spread: float) -> void:
	for i in scaled(count):
		emit(pos, dir.rotated(randf_range(-spread, spread)) * speed * randf_range(0.6, 1.0), randf_range(0.08, 0.16),
				1.8, 0.4, color.lerp(Color.WHITE, 0.4), 300.0, 2.0, true, 0.02)


func _smoke_puff(pos: Vector2, dir: Vector2, count: int, scale: float) -> void:
	for i in scaled(count):
		emit(pos + dir * randf_range(0.0, 10.0), dir * randf_range(20, 70) * scale + Vector2(randf_range(-12, 12), randf_range(-35, -10)),
				randf_range(0.6, 1.0) * scale, 3.0, randf_range(9.0, 13.0) * scale, Color(0.7, 0.72, 0.78, 0.22), -25.0, 2.5)


## Spent casing kicked out of the breech (ballistic guns only).
func casing(muzzle_pos: Vector2, dir: Vector2, wid: int, alt: bool) -> void:
	var length := 4.0
	var width := 2.0
	var col := BRASS
	var glint := NO_GLOW
	match wid:
		Weapons.ENFORCER:
			pass
		Weapons.MINIGUN:
			length = 4.5
			if Settings.quality <= 0 and _mini_flip:
				return
		Weapons.SNIPER:
			length = 7.0
			width = 2.6
			col = Color(1.0, 0.85, 0.45)
			glint = Color(0.55, 0.9, 1.0, 0.8) if alt else Color(1.0, 0.8, 0.4, 0.6)
		Weapons.FLAK:
			length = 7.5 if alt else 6.0
			width = 4.0 if alt else 3.4
			col = Color(0.95, 0.3, 0.2) if alt else Color(0.9, 0.42, 0.18)
		_:
			return
	var breech := muzzle_pos - dir * float(Weapons.LIST[wid].gun_len) * 0.55
	var side := -1.0 if dir.x >= 0.0 else 1.0           # out of the gun's side, backwards
	var v := Vector2(side * randf_range(50.0, 120.0), randf_range(-270.0, -170.0)) - dir * 30.0
	chunk(breech, v, randf_range(14.0, 26.0) * (1.0 if randf() < 0.5 else -1.0), length, width, col, glint,
			1.9 if Settings.quality > 0 else 1.2)


## Hitscan end point: if it's on a wall, sparks off the surface, dust puff, scorch mark.
func impact(pos: Vector2, dir: Vector2, color: Color, style: int) -> void:
	var k := _cell_kind(pos + dir * 2.0)
	if k == Level.EMPTY or k == Level.HAZARD:
		return
	var nrm := _surface_normal(pos, dir)
	var refl := dir.bounce(nrm)
	var hot := color.lerp(Color(1.0, 0.9, 0.6), 0.5)
	var big := style == HIT_SNIPER
	var count := 9 if big else (6 if style == HIT_SHOCK else (2 if style == HIT_PLASMA else 4))
	for i in scaled(count):
		var v := (refl.rotated(randf_range(-0.7, 0.7)) + nrm * 0.3) * randf_range(180.0, 460.0) * (1.3 if big else 1.0)
		emit(pos, v, randf_range(0.12, 0.3), 2.0, 0.4, hot, 650.0, 2.5, true, 0.022)
	emit(pos, Vector2.ZERO, 0.05, 9.0 if big else 6.0, 2.0, Color(1, 1, 0.9, 0.9), 0.0, 0.0, true)
	if style == HIT_PLASMA:
		return
	# Dust kicked off the surface.
	for i in scaled(3 if big else 2):
		emit(pos + nrm * 2.0, (nrm.rotated(randf_range(-0.8, 0.8))) * randf_range(25.0, 70.0), randf_range(0.4, 0.7),
				2.0, randf_range(6.0, 9.0) * (1.4 if big else 1.0), Color(0.8, 0.8, 0.86, 0.28), -15.0, 3.0)
	if style == HIT_SHOCK:
		ring(pos, 24.0, color, 0.2, 0.0, 3.0)
	if k != Level.BARRIER:
		decal(pos + dir * 1.5, 5.5 if big else (4.5 if style == HIT_SHOCK else 3.2), 5.0,
				Color(color, 0.8) if style == HIT_SHOCK else Color(1.0, 0.55, 0.2, 0.75), nrm)


## Small non-explosive projectile end (flak shard, pulse bolt).
func pop(pos: Vector2, color: Color, energy: bool) -> void:
	for i in scaled(5 if energy else 3):
		emit(pos, Vector2.from_angle(randf() * TAU) * randf_range(90.0, 240.0), randf_range(0.12, 0.25), 2.0, 0.4,
				color.lerp(Color.WHITE, 0.3), 400.0, 2.5, true, 0.02)
	emit(pos, Vector2.ZERO, 0.08, 10.0 if energy else 5.0, 3.0, Color(color, 0.7), 0.0, 0.0, true)
	var into := _near_surface(pos, 6.0)
	if into != Vector2.INF and (energy or randf() < 0.5):
		decal(_snap(pos, into, 8.0), 2.6, 3.5, Color(color, 0.7) if energy else Color(1.0, 0.55, 0.2, 0.6), -into)


## Hit on a fighter: energy sparks + oil spray in the victim's colour, or metallic sparks on armour.
func body_hit(pos: Vector2, dir: Vector2, color: Color, armored: bool, dmg: int, head: bool) -> void:
	var n := clampi(3 + int(dmg / 8.0), 3, 12)
	if armored:
		for i in scaled(n):
			emit(pos, dir.rotated(randf_range(-0.8, 0.8)) * randf_range(200.0, 520.0), randf_range(0.12, 0.3), 2.0, 0.4,
					Color(1.0, 0.92, 0.65), 700.0, 2.0, true, 0.025)
		emit(pos, Vector2.ZERO, 0.06, 10.0, 3.0, Color(0.9, 0.95, 1.0, 0.9), 0.0, 0.0, true)
		ring(pos, 14.0, Color(0.8, 0.9, 1.0), 0.14, 0.0, 2.0)
	else:
		for i in scaled(n):
			emit(pos, dir.rotated(randf_range(-0.85, 0.85)) * randf_range(140.0, 400.0), randf_range(0.15, 0.35), 2.4, 0.5,
					color.lerp(Color.WHITE, randf() * 0.4), 500.0, 2.5, true, 0.02)
		# Oil / coolant droplets (robots: no gore).
		for i in scaled(maxi(2, int(n * 0.5))):
			emit(pos, dir.rotated(randf_range(-0.6, 0.6)) * randf_range(80.0, 240.0) + Vector2(0, -60), randf_range(0.35, 0.6),
					2.6, 1.4, Color(color.darkened(0.55), 0.9), 900.0, 1.0)
		emit(pos, Vector2.ZERO, 0.08, 12.0, 4.0, Color(color, 0.65), 0.0, 0.0, true)
	if head:
		burst(pos, Color(1.0, 0.85, 0.3), 10, 260.0)
		ring(pos, 22.0, Color(1.0, 0.85, 0.3), 0.22, 0.0, 3.0)


## Sniper vapour trail along a shot.
func vapor(a: Vector2, b: Vector2) -> void:
	var len := a.distance_to(b)
	var steps := scaled(mini(14, int(len / 55.0)))
	for i in steps:
		var p := a.lerp(b, (i + randf()) / maxf(steps, 1))
		emit(p, Vector2(randf_range(-8, 8), randf_range(-14, -4)), randf_range(0.5, 0.9), 1.5, randf_range(5.0, 8.0),
				Color(0.75, 0.88, 1.0, 0.24), -10.0, 2.0)


## Layered blast: white flash, shockwave rings, fireball, sparks, rising smoke, bouncing debris,
## scorch mark. ENERGY = plasma (no smoke/debris), NUKE = Redeemer multi-stage.
func explosion(pos: Vector2, radius: float, color: Color, style := FIRE) -> void:
	var nuke := style == NUKE
	var energy := style == ENERGY
	var hot := color.lerp(Color.WHITE, 0.35) if energy else color.lerp(Color(1.0, 0.8, 0.42), 0.65)
	if nuke:
		hot = Color(1.0, 0.82, 0.5)
	# Flash: a white-hot frame or two (small hard core + soft bloom), then a coloured bloom.
	emit(pos, Vector2.ZERO, 0.12 if nuke else 0.05, radius * 1.1, radius * 1.2, Color(1, 1, 1, 0.85), 0.0, 0.0, true, -1.0)
	emit(pos, Vector2.ZERO, 0.08 if nuke else 0.04, radius * 0.22, radius * 0.3, Color(1, 1, 1, 0.9), 0.0, 0.0, true)
	emit(pos, Vector2.ZERO, 0.7 if nuke else 0.25, radius * 0.8, radius * 1.3, Color(hot, 0.5), 0.0, 0.0, true, -1.0)
	# Shockwaves: a fast bright front, a slower coloured one behind it.
	ring(pos, radius * 1.15, Color.WHITE.lerp(color, 0.3), 0.6 if nuke else 0.28, 0.0, 10.0 if nuke else 6.0)
	ring(pos, radius * 0.8, hot, 0.9 if nuke else 0.42, 0.05, 4.0)
	if nuke:
		ring(pos, radius * 1.7, Color(1.0, 0.55, 0.25), 1.4, 0.18, 12.0)
		ring(pos, radius * 0.55, Color.WHITE, 0.5, 0.45, 5.0)
		emit(pos, Vector2.ZERO, 1.6, radius * 0.6, radius * 1.1, Color(1.0, 0.5, 0.2, 0.35), 0.0, 0.0, true, -1.0)
	# Fireball (energy: plasma) blobs that billow outward and up.
	var spread := 2.2 if nuke else 1.0
	for i in scaled(30 if nuke else 9):
		var d := Vector2.from_angle(randf() * TAU)
		var c := color.lerp(Color.WHITE, randf() * 0.5) if energy else hot.lerp(Color(1.0, 0.35, 0.1), randf() * 0.7)
		emit(pos + d * randf_range(0.0, radius * 0.22), d * randf_range(40.0, 200.0) * spread + Vector2(0, -40),
				randf_range(0.25, 0.5) * (2.2 if nuke else 1.0), radius * randf_range(0.13, 0.2), radius * 0.04,
				Color(c, 0.8), 0.0 if energy else -160.0, 3.5, true)
	if nuke:   # mushroom column
		for i in scaled(14):
			emit(pos + Vector2(randf_range(-30, 30), randf_range(-10, 10)), Vector2(randf_range(-30, 30), randf_range(-420, -160)),
					randf_range(0.7, 1.2), radius * 0.12, radius * 0.22, Color(hot.lerp(Color(1, 0.4, 0.1), randf()), 0.7), 0.0, 1.5, true)
	# Hot shrapnel streaks.
	for i in scaled(34 if nuke else 12):
		var d := Vector2.from_angle(randf() * TAU)
		emit(pos, d * randf_range(200.0, 560.0) * (1.9 if nuke else 1.0), randf_range(0.25, 0.6), 2.4, 0.4,
				color.lerp(Color.WHITE, 0.4) if energy else color.lerp(Color(1, 0.85, 0.35), 0.5), 520.0, 1.8, true, 0.025)
	if energy:
		ring(pos, radius * 0.5, Color.WHITE, 0.18, 0.0, 3.0)
		for i in scaled(4):
			arc(pos, pos + Vector2.from_angle(randf() * TAU) * radius * randf_range(0.3, 0.6), color, 0.12)
	else:
		# Smoke that rises and lingers after the fire is gone.
		for i in scaled(26 if nuke else 7):
			var d := Vector2.from_angle(randf() * TAU)
			emit(pos + d * randf_range(0.0, radius * 0.3), d * randf_range(15.0, 70.0) * spread + Vector2(0, -25),
					randf_range(1.0, 1.7) * (1.9 if nuke else 1.0), radius * 0.13, radius * randf_range(0.32, 0.48),
					Color(SMOKE, 0.5), -45.0, 1.4)
		# Debris chunks, glowing hot, that tumble and bounce.
		for i in scaled(12 if nuke else 5):
			var d := Vector2.from_angle(randf_range(PI * 1.08, PI * 1.92))
			chunk(pos, d * randf_range(220.0, 520.0) * (1.6 if nuke else 1.0), randf_range(-18.0, 18.0),
					randf_range(3.0, 6.0), randf_range(2.0, 3.5), Color(0.22, 0.2, 0.24), Color(1.0, 0.5, 0.18, 0.9), 1.6)
	# Scorch where the blast touched a floor or wall (pushed into the surface).
	var into := _near_surface(pos, radius * 0.3)
	if into != Vector2.INF:
		decal(_snap(pos, into, radius * 0.3), radius * 0.15, 8.0 if nuke else 5.5, Color(hot, 0.7), -into)


## Armour fragments in the fighter's colours + an energy burst in the visor colour.
func gibs(pos: Vector2, look: Dictionary, vel: Vector2) -> void:
	var cols: Array[Color] = [look.primary, look.secondary, look.primary.lightened(0.2)]
	for i in scaled(16):
		var v := vel * 0.4 + Vector2(randf_range(-260, 260), randf_range(-420, -80))
		emit(pos + Vector2(randf_range(-10, 10), randf_range(-20, 15)), v, randf_range(0.6, 1.1), randf_range(3, 5.5), 2.0,
				cols[i % 3], 1400.0, 0.5)
	# A few plates that clatter onto the floor.
	for i in scaled(5):
		var v := vel * 0.3 + Vector2(randf_range(-220, 220), randf_range(-460, -200))
		chunk(pos + Vector2(randf_range(-8, 8), randf_range(-14, 8)), v, randf_range(-16.0, 16.0), randf_range(5.0, 8.0),
				randf_range(3.0, 4.5), cols[i % 3], Color(look.visor, 0.5), 2.2)
	burst(pos, look.visor, 18, 300.0)
	emit(pos, Vector2.ZERO, 0.25, 30.0, 60.0, Color(look.visor, 0.6), 0.0, 0.0, true)


## Glowing ring of sparks (jump pads, double jumps).
func burst(pos: Vector2, color: Color, count: int, speed: float) -> void:
	for i in scaled(count):
		var a := randf() * TAU
		emit(pos, Vector2.from_angle(a) * speed * randf_range(0.5, 1.0), randf_range(0.25, 0.45), 2.5, 0.0,
				color, 200.0, 2.0, true)


# --- level queries -----------------------------------------------------------------

func _cell_kind(p: Vector2) -> int:
	if _level == null:
		return Level.EMPTY
	return _level.cell(floori(p.x / Level.T), floori(p.y / Level.T))


## Face normal of the tile a shot hit at `pos` travelling along `dir`.
func _surface_normal(pos: Vector2, dir: Vector2) -> Vector2:
	if _level == null:
		return -dir
	var t := float(Level.T)
	var p := pos + dir * 2.0
	var cx := floorf(p.x / t) * t
	var cy := floorf(p.y / t) * t
	var l := pos.x - cx
	var r := cx + t - pos.x
	var u := pos.y - cy
	var d := cy + t - pos.y
	var m := minf(minf(l, r), minf(u, d))
	if m == u:
		return Vector2.UP
	if m == d:
		return Vector2.DOWN
	return Vector2.LEFT if m == l else Vector2.RIGHT


## Direction to a solid surface within `dist` (down first), or Vector2.INF if in open air.
func _near_surface(pos: Vector2, dist: float) -> Vector2:
	var below := _cell_kind(pos + Vector2(0, dist))
	if below == Level.SOLID or below == Level.ONEWAY:
		return Vector2.DOWN
	if _cell_kind(pos + Vector2(dist, 0)) == Level.SOLID:
		return Vector2.RIGHT
	if _cell_kind(pos - Vector2(dist, 0)) == Level.SOLID:
		return Vector2.LEFT
	if _cell_kind(pos - Vector2(0, dist)) == Level.SOLID:
		return Vector2.UP
	return Vector2.INF


## Walk from `pos` along `dir` (up to `dist`) to the first solid tile: the surface point.
func _snap(pos: Vector2, dir: Vector2, dist: float) -> Vector2:
	var step := maxf(3.0, dist / 12.0)
	var p := pos
	var moved := 0.0
	while moved < dist:
		var k := _cell_kind(p + dir * step)
		if k == Level.SOLID or k == Level.ONEWAY:
			break
		p += dir * step
		moved += step
	return p + dir * 2.0


# --- simulation --------------------------------------------------------------------

func _process(delta: float) -> void:
	if _kicking:
		_step_kick(delta)
	if _under_live:
		_step_under(delta)
	if _busy <= 0.0:
		return
	_busy -= delta
	_cn = _step(0, _cn, delta)
	_ca = _step(MAX, _ca, delta)
	# Lines / rings / texts: age + compact in place (swap-remove; order doesn't matter).
	var i := 0
	while i < _ln:
		var life := _ll[i] - delta
		if life > 0.0:
			_ll[i] = life
			i += 1
		else:
			_ln -= 1
			if i != _ln:
				_la[i] = _la[_ln]
				_lb[i] = _lb[_ln]
				_lcol[i] = _lcol[_ln]
				_lw[i] = _lw[_ln]
				_ll[i] = _ll[_ln]
				_lm[i] = _lm[_ln]
				_lk[i] = _lk[_ln]
	i = 0
	while i < _rn:
		var life := _rl[i] - delta
		if life > 0.0:
			_rl[i] = life
			i += 1
		else:
			_rn -= 1
			if i != _rn:
				_rp[i] = _rp[_rn]
				_rrad[i] = _rrad[_rn]
				_rw[i] = _rw[_rn]
				_rl[i] = _rl[_rn]
				_rm[i] = _rm[_rn]
				_rc[i] = _rc[_rn]
	var n := _texts.size()
	i = 0
	while i < n:
		var t := _texts[i]
		t.life -= delta
		t.pos.y -= 50.0 * delta
		if t.life > 0.0:
			i += 1
		else:
			n -= 1
			_texts[i] = _texts[n]
	_texts.resize(n)
	queue_redraw()
	_glow.queue_redraw()


func _step_kick(delta: float) -> void:
	_kick *= exp(-13.0 * delta)
	if _kick.length_squared() < 0.04:
		_kick = Vector2.ZERO
		_kicking = false
	if _world and _world.camera:
		_world.camera.offset = _kick


## Integrate one pool's live particles [base, base + count); returns the new live count.
func _step(base: int, count: int, delta: float) -> int:
	var i := base
	var end := base + count
	while i < end:
		var life := _life[i] - delta
		if life <= 0.0:
			end -= 1
			if i != end:
				_pos[i] = _pos[end]
				_vel[i] = _vel[end]
				_life[i] = _life[end]
				_max_life[i] = _max_life[end]
				_size[i] = _size[end]
				_size_end[i] = _size_end[end]
				_color[i] = _color[end]
				_grav[i] = _grav[end]
				_drag[i] = _drag[end]
				_streak[i] = _streak[end]
			continue
		_life[i] = life
		var v := _vel[i]
		v.y += _grav[i] * delta
		v *= maxf(0.0, 1.0 - _drag[i] * delta)
		_vel[i] = v
		_pos[i] += v * delta
		i += 1
	return end - base


## Chunks + decals: age, move flying chunks, redraw the under-layer (every frame while
## something moves, otherwise ~15 Hz for the slow fades).
func _step_under(delta: float) -> void:
	var moving := false
	var died := false
	var i := 0
	while i < _chn:
		var life := _cl[i] - delta
		if life <= 0.0:
			died = true
			_chn -= 1
			if i != _chn:
				_cp[i] = _cp[_chn]
				_cv[i] = _cv[_chn]
				_cang[i] = _cang[_chn]
				_cspin[i] = _cspin[_chn]
				_cl[i] = _cl[_chn]
				_cm[i] = _cm[_chn]
				_clen[i] = _clen[_chn]
				_cwid[i] = _cwid[_chn]
				_ccol[i] = _ccol[_chn]
				_cglow[i] = _cglow[_chn]
				_cst[i] = _cst[_chn]
			continue
		_cl[i] = life
		if _cst[i] < 2:
			moving = true
			_move_chunk(i, delta)
		i += 1
	i = 0
	while i < _dn:
		var life := _dl[i] - delta
		if life <= 0.0:
			died = true
			_dn -= 1
			if i != _dn:
				_dp[i] = _dp[_dn]
				_drad[i] = _drad[_dn]
				_dl[i] = _dl[_dn]
				_dm[i] = _dm[_dn]
				_dhot[i] = _dhot[_dn]
				_dax[i] = _dax[_dn]
			continue
		_dl[i] = life
		i += 1
	_under_t -= delta
	if moving or died or _under_dirty or _under_t <= 0.0:
		_under_t = 0.066
		_under_dirty = false
		_under.queue_redraw()
	_under_live = _chn > 0 or _dn > 0 or died


func _move_chunk(i: int, delta: float) -> void:
	var p := _cp[i]
	var v := _cv[i]
	v.y += CHUNK_GRAV * delta
	var np := p + v * delta
	_cang[i] += _cspin[i] * delta
	if _level:
		var t := float(Level.T)
		var cx := floori(np.x / t)
		var cy := floori(np.y / t)
		var k := _level.cell(cx, cy)
		if v.y > 0.0 and cy > floori(p.y / t) and (k == Level.SOLID or k == Level.ONEWAY):
			np.y = cy * t - 0.5
			if _cst[i] == 0 and v.y > 140.0:
				v = Vector2(v.x * 0.5, -v.y * 0.35)        # one bounce
				_cspin[i] *= -0.5
				_cst[i] = 1
			else:
				v = Vector2.ZERO                          # settle, lying flat
				_cspin[i] = 0.0
				_cang[i] = roundf(_cang[i] / PI) * PI
				_cst[i] = 2
		elif k == Level.SOLID:
			if floori(p.x / t) != cx:
				v.x *= -0.35
				np.x = p.x
			else:
				v.y = absf(v.y) * 0.2
				np.y = p.y
	_cp[i] = np
	_cv[i] = v


# --- drawing -----------------------------------------------------------------------

func _draw() -> void:
	_draw_pool(self, 0, _cn)
	for i in _ln:
		var k := _ll[i] / _lm[i]
		var c := _lcol[i]
		match _lk[i]:
			L_PLAIN:
				DrawUtil.line(self, _la[i], _lb[i], Color(c.lerp(Color.WHITE, 0.6), k), maxf(1.0, _lw[i] * 0.4))
			L_WAVE:
				_draw_wave(self, _la[i], _lb[i], Color(c.lerp(Color.WHITE, 0.7), k), 2.0)
			L_FLASH:
				_kite(self, _la[i], _lb[i], _lw[i] * 0.4, 0.45 + 0.25 * k, Color(1, 1, 1, k), Color(1, 1, 0.9, k))
			L_TRACER:
				_draw_tracer(self, i, Color(1, 1, 1, minf(1.0, k * 2.0)), maxf(1.0, _lw[i] * 0.45))
			L_ARC:
				_draw_arc(self, _la[i], _lb[i], Color(1, 1, 1, k), 1.0)
	for t in _texts:
		var k := clampf(t.life / 0.3, 0.0, 1.0)
		draw_string_outline(FONT, t.pos, t.text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, 4, Color(0, 0, 0, 0.7 * k))
		draw_string(FONT, t.pos, t.text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color(t.color, k))


func _draw_glow() -> void:
	_draw_pool(_glow, MAX, _ca)
	for i in _ln:
		var k := _ll[i] / _lm[i]
		var c := _lcol[i]
		match _lk[i]:
			L_PLAIN:
				DrawUtil.line(_glow, _la[i], _lb[i], Color(c, 0.55 * k), _lw[i] * 1.6)
			L_WAVE:
				_draw_wave(_glow, _la[i], _lb[i], Color(c, 0.7 * k), _lw[i])
			L_FLASH:
				_kite(_glow, _la[i], _lb[i], _lw[i], 0.7 + 0.3 * k, Color(c.lerp(Color.WHITE, 0.5), k), Color(c, 0.85 * k))
			L_TRACER:
				_draw_tracer(_glow, i, Color(c, 0.9 * minf(1.0, k * 2.0)), _lw[i] * 1.4)
			L_ARC:
				_draw_arc(_glow, _la[i], _lb[i], Color(c, k), 2.5)
	for i in _rn:
		var mx := _rm[i]
		var life := _rl[i]
		if life > mx:
			continue                                  # still in its start delay
		var k := 1.0 - life / mx
		var r := _rrad[i] * (0.15 + 0.85 * sqrt(k))
		var c := Color(_rc[i], _rc[i].a * 0.7 * (1.0 - k))
		if r < 30.0:
			DrawUtil.thin_ring(_glow, _rp[i], r, c)
		else:
			DrawUtil.ring(_glow, _rp[i], r, 1.0 + _rw[i] * (1.0 - k), c, clampi(int(r / 4.5), 20, 72))
	# Cooling decals and hot debris / casing glints.
	for i in _dn:
		var hot := _dhot[i]
		var age := _dm[i] - _dl[i]
		if hot.a > 0.0 and age < 0.7:
			_ellipse(_glow, _dp[i], _dax[i] * _drad[i] * 1.2, Color(hot, hot.a * (1.0 - age / 0.7)), _glow_uv)
	for i in _chn:
		var g := _cglow[i]
		var age := _cm[i] - _cl[i]
		if g.a > 0.0 and age < 0.6:
			DrawUtil.glow(_glow, _cp[i], _clen[i] * 1.6, Color(g, g.a * (1.0 - age / 0.6)))


func _draw_under() -> void:
	for i in _dn:
		var k := minf(1.0, _dl[i] / (_dm[i] * 0.4))       # fades over the last 40% of its life
		var r := _drad[i]
		var ext := _dax[i] * r
		_ellipse(_under, _dp[i], ext * 1.15, Color(0.02, 0.02, 0.03, 0.6 * k), _glow_uv)
		if r < 8.0:                                       # bullet hole
			_ellipse(_under, _dp[i], ext * 0.32, Color(0.01, 0.01, 0.015, 0.85 * k), _disc_uv)
	for i in _chn:
		var k := minf(1.0, _cl[i] / 0.45)
		var d := Vector2.from_angle(_cang[i])
		var n := Vector2(-d.y, d.x)
		var p := _cp[i]
		var hl := d * (_clen[i] * 0.5 + 0.8)
		var hw := n * (_cwid[i] * 0.5 + 0.8)
		DrawUtil.quad(_under, p - hl - hw, p + hl - hw, p + hl + hw, p - hl + hw, Color(0.05, 0.04, 0.06, 0.85 * k))
		hl = d * _clen[i] * 0.5
		hw = n * _cwid[i] * 0.5
		var c := _ccol[i]
		DrawUtil.quad(_under, p - hl - hw, p + hl - hw, p + hl + hw, p - hl + hw, Color(c, c.a * k))


## Axis-aligned ellipse from one atlas cell (glow = soft scorch, disc = hard hole).
func _ellipse(ci: CanvasItem, p: Vector2, ext: Vector2, c: Color, uv: PackedVector2Array) -> void:
	_quad[0] = Vector2(p.x - ext.x, p.y - ext.y)
	_quad[1] = Vector2(p.x + ext.x, p.y - ext.y)
	_quad[2] = Vector2(p.x + ext.x, p.y + ext.y)
	_quad[3] = Vector2(p.x - ext.x, p.y + ext.y)
	_qcol[0] = c
	ci.draw_primitive(_quad, _qcol, uv, _tex)


## Tapered spike from a toward b (muzzle flash): bright at the base, fading to the tip.
func _kite(ci: CanvasItem, a: Vector2, b: Vector2, w: float, scale: float, ca: Color, cb: Color) -> void:
	var d := (b - a) * scale
	var tip := a + d
	var mid := a + d * 0.3
	var n := Vector2(-d.y, d.x).normalized() * w
	DrawUtil.quad4(ci, a, mid + n, tip, mid - n, ca, cb, Color(cb, 0.0), cb)


## Travelling streak of a tracer line (head races to the end, tail catches up).
func _draw_tracer(ci: CanvasItem, i: int, color: Color, width: float) -> void:
	var a := _la[i]
	var b := _lb[i]
	var len := maxf(a.distance_to(b), 1.0)
	var prog := 1.0 - _ll[i] / _lm[i]
	var head := minf(1.0, prog * 2.2)
	var tail := clampf(prog * 2.2 - 120.0 / len, 0.0, 1.0)
	if head - tail > 0.001:
		DrawUtil.line(ci, a.lerp(b, tail), a.lerp(b, head), color, width)


## Two-segment zigzag with a fresh random kink every frame (crackle).
func _draw_arc(ci: CanvasItem, a: Vector2, b: Vector2, color: Color, width: float) -> void:
	var d := b - a
	var n := Vector2(-d.y, d.x) * randf_range(-0.35, 0.35)
	var m := a + d * randf_range(0.35, 0.65) + n
	DrawUtil.line(ci, a, m, color, width)
	DrawUtil.line(ci, m, b, color, width)


## Sine-wave beam between two points (plasma), drawn as batched segments.
func _draw_wave(ci: CanvasItem, a: Vector2, b: Vector2, color: Color, width: float) -> void:
	var len := a.distance_to(b)
	var dir := (b - a) / maxf(len, 1.0)
	var n := Vector2(-dir.y, dir.x)
	var t := Time.get_ticks_msec() * 0.03
	var steps := maxi(2, int(len / 12.0))
	var prev := a
	for i in range(1, steps + 1):
		var d := len * i / steps
		var amp := 6.0 * sin(PI * i / steps)
		var p := a + dir * d + n * sin(d * 0.08 - t) * amp
		DrawUtil.line(ci, prev, p, color, width)
		prev = p


## Every live particle of one pool as an anti-aliased disc (inlined DrawUtil.circle);
## particles with a streak factor > 0 are stretched along their velocity (motion-blurred
## sparks), streak < 0 draws a soft radial bloom instead of a hard disc.
func _draw_pool(ci: CanvasItem, base: int, count: int) -> void:
	for i in range(base, base + count):
		var t := 1.0 - _life[i] / _max_life[i]
		var c := _color[i]
		c.a *= 1.0 - t
		var h := lerpf(_size[i], _size_end[i], t) * DrawUtil.DISC_K
		var p := _pos[i]
		var s := _streak[i]
		if s < 0.0:                                   # soft bloom (glow cell)
			h *= DrawUtil.GLOW_K / DrawUtil.DISC_K
			_quad[0] = Vector2(p.x - h, p.y - h)
			_quad[1] = Vector2(p.x + h, p.y - h)
			_quad[2] = Vector2(p.x + h, p.y + h)
			_quad[3] = Vector2(p.x - h, p.y + h)
			_qcol[0] = c
			ci.draw_primitive(_quad, _qcol, _glow_uv, _tex)
			continue
		if s > 0.0:
			var v := _vel[i]
			var sp := v.length()
			if sp > 40.0:
				var u := v / sp
				var ux := u * (h + sp * s)
				var nx := Vector2(-u.y * h, u.x * h)
				_quad[0] = p - ux - nx
				_quad[1] = p + ux - nx
				_quad[2] = p + ux + nx
				_quad[3] = p - ux + nx
				_qcol[0] = c
				ci.draw_primitive(_quad, _qcol, _disc_uv, _tex)
				continue
		_quad[0] = Vector2(p.x - h, p.y - h)
		_quad[1] = Vector2(p.x + h, p.y - h)
		_quad[2] = Vector2(p.x + h, p.y + h)
		_quad[3] = Vector2(p.x - h, p.y + h)
		_qcol[0] = c
		ci.draw_primitive(_quad, _qcol, _disc_uv, _tex)
