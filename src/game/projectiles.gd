class_name Projectiles
extends Node2D
## All projectiles as plain data, simulated at the physics rate with swept ray tests
## (no tunnelling through thin walls) and drawn in one pass, interpolated for smoothness.

class Proj:
	var id := 0
	var key := ""
	var def: Dictionary
	var pos := Vector2.ZERO
	var prev := Vector2.ZERO
	var vel := Vector2.ZERO
	var owner_eid := 0
	var wid := 0
	var life := 0.0
	var age := 0.0
	var bounces := 0
	var sound: AudioStreamPlayer2D # looping engine sound (Redeemer), freed with the projectile
	var stuck := false             # sticky grenade attached to a wall or a player
	var stuck_to := 0              # eid it rides on (0 = wall)
	var offset := Vector2.ZERO

var world: Node
var list: Array[Proj] = []
var _next_id := 1
var _glow: Node2D
var _trail_t := 0.0


func _ready() -> void:
	_glow = Node2D.new()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = add
	_glow.draw.connect(_draw_glow)
	add_child(_glow)


func spawn(key: String, pos: Vector2, vel: Vector2, owner_eid: int, wid: int) -> Proj:
	var p := Proj.new()
	p.id = _next_id
	_next_id += 1
	p.key = key
	p.def = Weapons.PROJ[key]
	p.pos = pos
	p.prev = pos
	p.vel = vel
	p.owner_eid = owner_eid
	p.wid = wid
	p.life = p.def.life
	p.bounces = p.def.get("bounces", 0)
	if p.def.has("loop_sound"):
		p.sound = Sfx.loop_at(p.def.loop_sound, self, pos, -2.0)
	list.append(p)
	return p


## Network client: draw a projectile the host spawned (same id, so the host can end it).
func spawn_visual(id: int, key: String, pos: Vector2, vel: Vector2, owner_eid: int, wid: int) -> void:
	if not Weapons.PROJ.has(key):
		return
	var p := spawn(key, pos, vel, owner_eid, wid)
	p.id = id
	p.life += 1.0                       # grace: the host's "ended" event normally removes it first


func remove_id(id: int) -> void:
	for p in list:
		if p.id == id:
			remove(p)
			return


## First shock ball within `radius` of segment a->b (for the shock combo).
func ball_on_segment(a: Vector2, b: Vector2, radius: float) -> Proj:
	var best: Proj = null
	var best_d := INF
	for p in list:
		if p.key != "shock_ball":
			continue
		var c := Geometry2D.get_closest_point_to_segment(p.pos, a, b)
		if c.distance_to(p.pos) <= radius and a.distance_to(c) < best_d:
			best_d = a.distance_to(c)
			best = p
	return best


func remove(p: Proj) -> void:
	_drop(p)
	list.erase(p)


## Release anything a projectile owns (its looping sound) when it leaves the list.
func _drop(p: Proj) -> void:
	if p.sound:
		p.sound.queue_free()
		p.sound = null


func _exit_tree() -> void:
	for p in list:
		_drop(p)


func _physics_process(delta: float) -> void:
	var space := get_world_2d().direct_space_state
	var i := 0
	var visual_only: bool = not world.is_authority()
	while i < list.size():
		var p := list[i]
		p.prev = p.pos
		p.age += delta
		p.life -= delta
		if visual_only:
			if p.life <= 0.0:
				_drop(p)
				list.remove_at(i)
			else:
				_visual_step(p, delta, space)
				i += 1
			continue
		if p.stuck:
			_ride(p)
			if p.life <= 0.0:
				world.projectile_expired(p)
				_drop(p)
				list.remove_at(i)
			else:
				i += 1
			continue
		p.vel.y += p.def.get("grav", 0.0) * delta
		var next := p.pos + p.vel * delta
		var done := false
		# Players first (closest hit along the step wins).
		var victim: Player = null
		var best_t := 2.0
		for e: Player in world.alive_players():
			if e.eid == p.owner_eid and p.age < 0.25:
				continue
			var t := World.seg_rect(p.pos, next, e.hit_rect().grow(p.def.radius))
			if t >= 0.0 and t < best_t:
				best_t = t
				victim = e
		var q := PhysicsRayQueryParameters2D.create(p.pos, next, Level.SHOT_MASK)
		var hit := space.intersect_ray(q)
		var wall_t := 2.0
		if hit:
			wall_t = p.pos.distance_to(hit.position) / maxf(p.pos.distance_to(next), 0.001)
		if victim and best_t <= wall_t:
			p.pos = p.pos.lerp(next, best_t)
			if p.def.get("sticky", false):
				_stick(p, victim.eid, p.pos - victim.global_position)
			else:
				world.projectile_hit(p, victim)
				done = true
		elif hit:
			if p.def.get("sticky", false):
				_stick(p, 0, Vector2.ZERO)
				p.pos = hit.position + hit.normal * 4.0
			elif p.bounces > 0:
				p.bounces -= 1
				var n: Vector2 = hit.normal
				p.vel = p.vel.bounce(n) * p.def.get("restitution", 0.5)
				p.pos = hit.position + n * 2.0
				if p.key == "grenade" and p.vel.length() > 120.0:
					Sfx.play_at("bounce", p.pos, -10.0)
			else:
				p.pos = hit.position - p.vel.normalized() * 2.0
				world.projectile_hit(p, null)
				done = true
		else:
			p.pos = next
		if not done and p.life <= 0.0:
			world.projectile_expired(p)
			done = true
		if done:
			_drop(p)
			list.remove_at(i)
		else:
			if p.sound:
				p.sound.global_position = p.pos
			i += 1
	_trails(delta)


## Client-side flight: gravity, wall bounces and sticking only — damage is the host's job.
func _visual_step(p: Proj, delta: float, space: PhysicsDirectSpaceState2D) -> void:
	if p.stuck:
		return
	p.vel.y += p.def.get("grav", 0.0) * delta
	var next := p.pos + p.vel * delta
	var hit := space.intersect_ray(PhysicsRayQueryParameters2D.create(p.pos, next, Level.SHOT_MASK))
	if hit.is_empty():
		p.pos = next
	elif p.bounces > 0 and not p.def.get("sticky", false):
		p.bounces -= 1
		p.vel = p.vel.bounce(hit.normal) * p.def.get("restitution", 0.5)
		p.pos = hit.position + hit.normal * 2.0
	else:
		p.pos = hit.position + hit.normal * 2.0
		p.vel = Vector2.ZERO
		p.stuck = true
	if p.sound:
		p.sound.global_position = p.pos


func _stick(p: Proj, eid: int, offset: Vector2) -> void:
	p.stuck = true
	p.stuck_to = eid
	p.offset = offset
	p.vel = Vector2.ZERO
	p.life = minf(p.life, p.def.stick_fuse)
	Sfx.play_at("bounce", p.pos, -6.0, 1.5)


## Follow the player a sticky grenade is attached to; falls off if they die.
func _ride(p: Proj) -> void:
	if p.stuck_to == 0:
		return
	var e: Player = world.entities.get(p.stuck_to)
	if e and e.alive:
		p.pos = e.global_position + p.offset
	else:
		p.stuck_to = 0


func _trails(delta: float) -> void:
	_trail_t -= delta
	if _trail_t > 0.0:
		return
	_trail_t = 0.03
	var fx: Fx = world.fx
	for p in list:
		if p.def.get("trail", false):
			var back := p.pos - p.vel.normalized() * 10.0
			fx.emit(back, -p.vel * 0.05 + Vector2(randf_range(-20, 20), randf_range(-20, 20)), 0.6,
					3.0, 12.0, Color(0.6, 0.6, 0.65, 0.4), -30.0, 1.5)
			fx.emit(back, -p.vel * 0.1, 0.12, 6.0, 1.0, Color(1.0, 0.6, 0.2, 0.8), 0.0, 0.0, true)


func _process(_delta: float) -> void:
	queue_redraw()
	_glow.queue_redraw()


func _lerp_pos(p: Proj) -> Vector2:
	return p.prev.lerp(p.pos, Engine.get_physics_interpolation_fraction())


func _draw() -> void:
	for p in list:
		var at := _lerp_pos(p)
		var c: Color = p.def.color
		var dir := p.vel.normalized()
		match p.key:
			"rocket", "redeemer":
				var s: float = p.def.size
				draw_set_transform(at, dir.angle())
				draw_rect(Rect2(-s * 1.6, -s * 0.55, s * 2.6, s * 1.1), Color(0.85, 0.87, 0.9))
				draw_colored_polygon(PackedVector2Array([Vector2(s, -s * 0.55), Vector2(s * 1.8, 0), Vector2(s, s * 0.55)]), c)
				draw_rect(Rect2(-s * 1.6, -s * 0.8, s * 0.6, s * 1.6), c.darkened(0.3))
				draw_set_transform(Vector2.ZERO)
			"grenade", "sticky":
				if p.key == "sticky":
					for k in 6:
						var spike := Vector2.from_angle(k * TAU / 6.0 + p.age * 3.0) * 8.5
						draw_line(at, at + spike, CharPainter.OUTLINE, 2.5)
				draw_circle(at, 6.5, CharPainter.OUTLINE)
				draw_circle(at, 5.0, c.darkened(0.2))
				var blink := 20.0 if p.stuck else 8.0
				if int(p.age * blink) % 2 == 0:
					draw_circle(at, 2.0, Color(1, 0.3, 0.2))
			"flak_shell":
				draw_circle(at, 7.0, CharPainter.OUTLINE)
				draw_circle(at, 5.5, c)
			"flak":
				draw_line(at - dir * 7.0, at, c.lightened(0.4), 3.0)
			_:
				draw_circle(at, p.def.size * 0.5, c.lightened(0.6))


func _draw_glow() -> void:
	for p in list:
		var at := _lerp_pos(p)
		var c: Color = p.def.color
		var s: float = p.def.size
		match p.key:
			"shock_ball":
				_glow.draw_circle(at, s * 2.2, Color(c, 0.25))
				_glow.draw_circle(at, s * 1.2, Color(c, 0.6))
				_glow.draw_circle(at, s * 0.6, Color(1, 1, 1, 0.8))
			"pulse":
				var d := p.vel.normalized()
				_glow.draw_line(at - d * 14.0, at, Color(c, 0.5), s * 1.6, true)
				_glow.draw_circle(at, s * 1.4, Color(c, 0.35))
			"rocket", "redeemer":
				_glow.draw_circle(at - p.vel.normalized() * s * 2.0, s * 1.6, Color(1.0, 0.55, 0.15, 0.55))
			"flak":
				_glow.draw_circle(at, 5.0, Color(c, 0.4))
			_:
				_glow.draw_circle(at, s * 1.5, Color(c, 0.3))
