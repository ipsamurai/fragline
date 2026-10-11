class_name Traps
extends Node2D
## Timed environmental traps: laser gates and floor vents. Their cycles are a pure function
## of the match clock, so they're predictable (learnable) and need no network traffic.

enum { OFF, WARN, ON }

const LASER_PERIOD := 5.0
const LASER_WARN := 0.8             # flicker before firing
const LASER_ON := 1.6
const LASER_DMG := 30               # per zap, every LASER_TICK while touching (~120 dps)
const LASER_TICK := 0.25
const LASER_HALF_W := 5.0
const VENT_PERIOD := 4.0
const VENT_WARN := 0.7
const VENT_ON := 0.5
const VENT_DMG := 20
const VENT_PUSH := 900.0
const VENT_SIZE := Vector2(30, 112)   # eruption column above the vent
const LASER_COLOR := Color("ff2e4d")

var world: Node
var level: Level
var _zap_at := {}                   # eid -> next time a laser may hurt them
var _vent_hit := {}                 # eid * 1024 + vent index -> burst id already applied
var _laser_state := PackedInt32Array()   # last seen state per laser / vent (one-shot fx/sfx)
var _vent_state := PackedInt32Array()
var _glow: Node2D


func setup(p_world: Node, p_level: Level) -> void:
	world = p_world
	level = p_level
	_glow = Node2D.new()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = add
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	DrawUtil.setup(self)
	_laser_state.resize(level.lasers.size())
	_laser_state.fill(OFF)
	_vent_state.resize(level.vents.size())
	_vent_state.fill(OFF)
	# Most maps have no traps: then there is nothing to animate or redraw, ever.
	set_process(not level.lasers.is_empty() or not level.vents.is_empty())


static func cycle_state(t: float, period: float, warn: float, on: float) -> int:
	var k := fposmod(t, period)
	if k >= period - on:
		return ON
	if k >= period - on - warn:
		return WARN
	return OFF


func laser_state(d: Dictionary) -> int:
	return cycle_state(world.clock + d.phase * LASER_PERIOD, LASER_PERIOD, LASER_WARN, LASER_ON)


func vent_state(d: Dictionary) -> int:
	return cycle_state(world.clock + d.phase * VENT_PERIOD, VENT_PERIOD, VENT_WARN, VENT_ON)


func laser_rect(d: Dictionary) -> Rect2:
	return Rect2(d.x - LASER_HALF_W, d.top, LASER_HALF_W * 2.0, d.bottom - d.top)


func vent_rect(d: Dictionary) -> Rect2:
	return Rect2(d.pos - Vector2(VENT_SIZE.x * 0.5, VENT_SIZE.y), VENT_SIZE)


## Server rules: called from World each physics step.
func server_tick() -> void:
	var now: float = world.clock
	for d in level.lasers:
		if laser_state(d) != ON:
			continue
		var r := laser_rect(d)
		for e: Player in world.alive_players():
			if now >= _zap_at.get(e.eid, 0.0) and r.intersects(e.hit_rect()):
				_zap_at[e.eid] = now + LASER_TICK
				world.trap_damage(e, LASER_DMG, World.LASER, Vector2(signf(e.global_position.x - d.x) * 160.0, 0),
						Vector2(d.x, e.global_position.y), [Status.BURN, 1.5])
	for i in level.vents.size():
		var d: Dictionary = level.vents[i]
		if vent_state(d) != ON:
			continue
		var burst := floori((now + d.phase * VENT_PERIOD) / VENT_PERIOD)
		var r := vent_rect(d)
		for e: Player in world.alive_players():
			var key: int = e.eid * 1024 + i
			if _vent_hit.get(key, -1) != burst and r.intersects(e.hit_rect()):
				_vent_hit[key] = burst
				world.trap_damage(e, VENT_DMG, World.VENT, Vector2(0, -VENT_PUSH), d.pos,
						Status.VENT_STATUS.get(level.def.style, []))


func _vent_color() -> Color:
	match level.def.style:
		"foundry": return Color(1.0, 0.55, 0.15)
		"ice": return Color(0.75, 0.95, 1.0)
		"jungle": return Color(0.55, 1.0, 0.35)
	return Color(0.85, 0.9, 1.0)


func _process(_delta: float) -> void:
	# One-shot effects on state changes (sound + particles), purely cosmetic.
	var fx: Fx = world.fx
	var changed := false                # any device changed state -> redraw both layers
	var flicker := false                # a laser is in its warning flicker -> redraw glow
	for i in level.lasers.size():
		var d: Dictionary = level.lasers[i]
		var st := laser_state(d)
		if st != _laser_state[i]:
			changed = true
			if st == ON:
				Sfx.play_at("shock_alt", Vector2(d.x, d.top), -6.0, 1.6)
		flicker = flicker or st == WARN
		_laser_state[i] = st
	var c := _vent_color()
	for i in level.vents.size():
		var d: Dictionary = level.vents[i]
		var st := vent_state(d)
		if st == WARN and randf() < 0.25:
			fx.emit(d.pos + Vector2(randf_range(-8, 8), -4), Vector2(randf_range(-15, 15), -60), 0.5, 3.0, 8.0, Color(c, 0.35), -20.0, 1.0)
		elif st == ON:
			for k in 2:
				fx.emit(d.pos + Vector2(randf_range(-10, 10), -4), Vector2(randf_range(-40, 40), randf_range(-520, -380)),
						0.3, 6.0, 14.0, Color(c, 0.5), 0.0, 1.5, true)
			if _vent_state[i] != ON:
				Sfx.play_at("rocket", d.pos, -4.0, 0.6)
		changed = changed or st != _vent_state[i]
		_vent_state[i] = st
	if changed:
		queue_redraw()
	if changed or flicker:
		_glow.queue_redraw()


func _draw() -> void:
	var metal := Color(0.16, 0.18, 0.22)
	var vc := _vent_color()
	for d in level.lasers:
		var st := laser_state(d)
		var r := Rect2(d.x - 9, d.top, 18, 8)
		DrawUtil.rect(self, r.grow(1.5), CharPainter.OUTLINE)
		DrawUtil.rect(self, r, metal)
		DrawUtil.rect(self, Rect2(d.x - 4, d.top + 8, 8, 4), LASER_COLOR if st != OFF else LASER_COLOR.darkened(0.6))
		var base := Rect2(d.x - 9, d.bottom - 6, 18, 6)
		DrawUtil.rect(self, base.grow(1.5), CharPainter.OUTLINE)
		DrawUtil.rect(self, base, metal)
		if st == ON:
			DrawUtil.rect(self, Rect2(d.x - 1.0, d.top + 12, 2.0, d.bottom - d.top - 18), Color(1, 0.85, 0.88))
	for d in level.vents:
		var p: Vector2 = d.pos
		DrawUtil.rect(self, Rect2(p + Vector2(-15, -5), Vector2(30, 5)).grow(1.0), CharPainter.OUTLINE)
		DrawUtil.rect(self, Rect2(p + Vector2(-15, -5), Vector2(30, 5)), metal)
		var warn := vent_state(d) != OFF
		for k in 4:
			DrawUtil.rect(self, Rect2(p + Vector2(-12 + k * 7, -4), Vector2(3, 3)), vc if warn else Color(0.05, 0.05, 0.07))


func _draw_glow() -> void:
	var t: float = world.clock
	for d in level.lasers:
		var st := laser_state(d)
		var a := Vector2(d.x, d.top + 12)
		var b := Vector2(d.x, d.bottom - 6)
		if st == WARN and int(t * 16.0) % 2 == 0:
			DrawUtil.rect(_glow, Rect2(d.x - 0.75, a.y, 1.5, b.y - a.y), Color(LASER_COLOR, 0.35))
		elif st == ON:
			DrawUtil.line(_glow, a, b, Color(LASER_COLOR, 0.35), 14.0)
			DrawUtil.line(_glow, a, b, Color(LASER_COLOR, 0.8), 5.0)
			DrawUtil.circle(_glow, b, 10.0, Color(LASER_COLOR, 0.5))
	var c := _vent_color()
	for d in level.vents:
		if vent_state(d) == ON:
			var r := vent_rect(d)
			DrawUtil.quad4(_glow, r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y),
					Color(c, 0.0), Color(c, 0.0), Color(c, 0.35), Color(c, 0.35))
