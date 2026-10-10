extends Node
## Dev tool (excluded from exports): headless checks of the combat rules and map mechanics.
## Run: godot --headless --path . -- --test=combat

var world: World
var fails := 0


func _ready() -> void:
	Sfx.muted = true
	_run.call_deferred()


func _check(name: String, ok: bool, detail := "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("" if ok else "   " + detail))
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _load(map: int) -> void:
	get_parent()._load_map(map)
	world = get_parent().world
	world.local_player.mode = Player.Mode.BOT        # no mouse/keyboard input in tests
	for e: Player in world.entities.values():
		e.brain = null                               # rule tests need passive targets, not bots
	await _frames(30)
	for it in world.pickups.items:                   # no stray pickups (amp!) during duels
		it.active = false
		it.respawn_at = 1e9
	for e: Player in world.entities.values():        # park extra dummies out of the way
		if e.eid < -2:
			e.teleport(Vector2(2000, 60))


## Load a map without the test tweaks (pickups left as dealt).
func _load_untouched(map: int) -> void:
	get_parent()._load_map(map)
	world = get_parent().world
	world.local_player.mode = Player.Mode.BOT
	for e: Player in world.entities.values():
		e.brain = null
	await _frames(5)


func _arm(p: Player) -> void:
	for w in Weapons.COUNT:
		p.owned |= 1 << w
		p.ammo[w] = maxi(Weapons.max_ammo(w), 1)


func _fresh(p: Player, pos: Vector2) -> void:
	p.teleport(pos)
	p.protect_time = 0.0
	p.health = 100
	p.armor = 0
	p.amp_time = 0.0
	p.in_jump_held = false
	p.in_down_held = false
	p._clear_status()
	p.left_spawn = true          # test teleports shouldn't trigger the spawn exit shield
	p.zone_time = 0.0


## Shooter and dummy on Deck-17's high bridge (stand row 12), `dist` apart.
func _duel(dist: float) -> Array[Player]:
	var me := world.local_player
	var dummy: Player = world.entities[-1]
	var y := 13 * Level.T - Player.HALF.y - 1
	_fresh(me, Vector2(800, y))
	_fresh(dummy, Vector2(800 + dist, y))
	_arm(me)
	return [me, dummy]


func _fire(p: Player, wid: int, alt: bool, dir: Vector2) -> void:
	world.request_fire(p, wid, alt, p.muzzle(), dir.normalized())


func _run() -> void:
	await _load(0)
	_check("all players spawned", world.alive_players().size() == 4, str(world.alive_players().size()))

	var pair := _duel(200)
	var me := pair[0]
	var dummy := pair[1]
	await _frames(2)
	_fire(me, Weapons.ENFORCER, false, Vector2.RIGHT)
	_check("enforcer damages", dummy.health == 100 - 15, "health=%d" % dummy.health)

	dummy.health = 100
	dummy.armor = 100
	_fire(me, Weapons.SNIPER, false, Vector2.RIGHT)
	_check("armor absorbs", dummy.armor < 100 and dummy.health > 100 - 65, "h=%d a=%d" % [dummy.health, dummy.armor])

	pair = _duel(300)
	var deaths_before: int = world.roster[-1].deaths
	_fire(me, Weapons.SNIPER, false, dummy.global_position + Vector2(0, -26) - me.muzzle())
	_check("sniper headshot kills", not dummy.alive and world.roster[-1].deaths == deaths_before + 1,
			"alive=%s h=%d" % [dummy.alive, dummy.health])
	_check("kill credited", world.roster[World.LOCAL_EID].kills == 1, str(world.roster[World.LOCAL_EID].kills))
	await _frames(int(World.RESPAWN_TIME * 60) + 10)
	_check("dummy respawns", dummy.alive)

	pair = _duel(250)
	var rockets := me.ammo[Weapons.ROCKET]
	_fire(me, Weapons.ROCKET, false, Vector2.RIGHT)
	_check("rocket ammo used", me.ammo[Weapons.ROCKET] == rockets - 1)
	await _frames(30)
	_check("rocket splash damages", dummy.health < 100 or not dummy.alive, "h=%d" % dummy.health)

	pair = _duel(600)
	await _frames(5)
	world.request_fire(me, Weapons.ROCKET, false, me.global_position + Vector2(0, 10), Vector2.DOWN)
	await _frames(3)
	_check("rocket jump pushes up", me.velocity.y < -300.0, "vy=%.0f" % me.velocity.y)
	_check("self damage halved", me.health >= 50 and me.health < 100, "h=%d" % me.health)

	for w in [Weapons.FLAK, Weapons.PULSE, Weapons.GRENADE]:
		pair = _duel(220)
		dummy.health = 1000                  # survive so one weapon's kill can't skew the next test
		await _frames(2)
		_fire(me, w, false, Vector2.RIGHT)
		_check("%s spawns projectiles" % Weapons.LIST[w].name, world.projectiles.list.size() > 0)
		await _frames(150)
		_check("%s hits" % Weapons.LIST[w].name, dummy.health < 1000, "h=%d" % dummy.health)
	_check("projectiles cleaned up", world.projectiles.list.is_empty(), str(world.projectiles.list.size()))

	pair = _duel(400)
	_fire(me, Weapons.SHOCK, true, Vector2.RIGHT)
	await _frames(20)
	var ball: Projectiles.Proj = world.projectiles.list.back() if world.projectiles.list.size() else null
	_check("shock ball exists", ball != null)
	if ball:
		_fire(me, Weapons.SHOCK, false, ball.pos - me.muzzle())
		_check("shock combo consumes ball", not world.projectiles.list.has(ball))
		_check("shock combo damages", dummy.health < 100 or not dummy.alive, "h=%d" % dummy.health)
	await _frames(int(World.RESPAWN_TIME * 60) + 10)

	# --- new alt fires ---
	pair = _duel(250)
	var cells := me.ammo[Weapons.PULSE]
	for i in 10:
		_fire(me, Weapons.PULSE, true, Vector2.RIGHT)
	_check("plasma wave damages", dummy.health == 100 - 10 * 5, "h=%d" % dummy.health)
	_check("plasma wave uses ammo", me.ammo[Weapons.PULSE] == cells - 10)
	pair = _duel(650)
	_fire(me, Weapons.PULSE, true, Vector2.RIGHT)
	_check("plasma wave is short range", dummy.health == 100, "h=%d" % dummy.health)

	pair = _duel(160)
	await _frames(2)
	_fire(me, Weapons.GRENADE, true, Vector2(1, -0.25))
	var stuck := false
	for i in 60:
		await _frames(1)
		for p in world.projectiles.list:
			if p.stuck and p.stuck_to == dummy.eid:
				stuck = true
		if stuck:
			break
	_check("sticky grenade sticks to player", stuck)
	await _frames(90)
	_check("sticky grenade explodes", world.projectiles.list.is_empty() and (dummy.health < 100 or not dummy.alive),
			"left=%d h=%d" % [world.projectiles.list.size(), dummy.health])
	await _frames(int(World.RESPAWN_TIME * 60) + 10)

	pair = _duel(200)
	var second: Player = world.entities[-2]
	_fresh(second, dummy.global_position + Vector2(150, 0))
	_fire(me, Weapons.SNIPER, true, Vector2.RIGHT)
	_check("ghost bullet pierces both", dummy.health == 70 and second.health == 70,
			"h1=%d h2=%d" % [dummy.health, second.health])

	# --- map mechanics ---
	# Shooting up through the bridge is blocked; it's a solid slab for bullets.
	pair = _duel(0)
	_fresh(me, dummy.global_position + Vector2(-40, 150))     # mid-air just under the bridge
	_fire(me, Weapons.SNIPER, false, dummy.global_position - me.muzzle())
	_check("platform blocks bullets", dummy.health == 100, "h=%d" % dummy.health)

	# Deck-17 sniper tower (cols 28-30, rows 18-26) between shooter and target, mid-air.
	_fresh(me, Vector2(25.5 * Level.T, 22.5 * Level.T))
	_fresh(dummy, Vector2(32.5 * Level.T, 22.5 * Level.T))
	_fire(me, Weapons.SNIPER, false, Vector2.RIGHT)
	_check("walls block normal shots", dummy.health == 100, "h=%d" % dummy.health)
	_fire(me, Weapons.SNIPER, true, dummy.global_position - me.muzzle())
	_check("ghost bullet passes walls", dummy.health == 70, "h=%d" % dummy.health)

	# Spawn barrier: can't shoot into a spawn room, not even with the ghost bullet.
	var room := Vector2(6.5 * Level.T, 29 * Level.T - Player.HALF.y - 1)
	_fresh(dummy, room)
	_fresh(me, Vector2(13.5 * Level.T, room.y))
	await _frames(2)
	_fire(me, Weapons.SNIPER, false, dummy.global_position - me.muzzle())
	_check("barrier blocks shots", dummy.health == 100, "h=%d" % dummy.health)
	_fire(me, Weapons.SNIPER, true, dummy.global_position - me.muzzle())
	_check("barrier blocks ghost bullet", dummy.health == 100, "h=%d" % dummy.health)

	# Field of view is capped to VIEW_WORLD regardless of window shape.
	var visible := world.get_viewport().get_visible_rect().size / world.camera.zoom
	_check("FOV capped", visible.x <= World.VIEW_WORLD.x + 1.0 and visible.y <= World.VIEW_WORLD.y + 1.0, str(visible))

	# Walk through the barrier (players pass).
	me.in_move = -1.0
	await _frames(60)
	me.in_move = 0.0
	_check("players pass barrier", me.global_position.x < 9 * Level.T, "x=%.0f" % me.global_position.x)
	_fresh(dummy, Vector2(20.5 * Level.T, room.y))     # out of the spawn room before its purge kicks in

	# Ladder: Deck-17 tower ladder at column 27 (rows 18..28).
	_fresh(me, Vector2(27.5 * Level.T, 29 * Level.T - Player.HALF.y - 1))
	await _frames(5)
	var start_y := me.global_position.y
	me.in_jump_held = true
	await _frames(110)
	me.in_jump_held = false
	await _frames(20)
	_check("ladder climbs to the top", me.global_position.y < start_y - 9 * Level.T and me.is_on_floor(),
			"dy=%.0f floor=%s" % [start_y - me.global_position.y, me.is_on_floor()])
	me.in_down_held = true
	await _frames(110)
	me.in_down_held = false
	await _frames(10)
	_check("ladder climbs back down", absf(me.global_position.y - start_y) < 8.0, "dy=%.0f" % (me.global_position.y - start_y))

	# Ladder grabbed mid-air while moving sideways with W held (Deck-17 ladder, column 15).
	_fresh(me, Vector2(14.3 * Level.T, 26.0 * Level.T))
	me.in_move = 1.0
	me.in_jump_held = true
	var grabbed := false
	for i in 20:
		await _frames(1)
		grabbed = grabbed or me._climbing
	_check("ladder grabbed mid-air", grabbed, "x=%.0f" % me.global_position.x)
	me.in_move = 0.0
	me.in_jump_held = false
	await _frames(30)

	# Laser gate (under the Deck-17 tower): hurts only while on.
	var laser: Dictionary = world.level.lasers[0]
	var on_t: float = Traps.LASER_PERIOD - Traps.LASER_ON * 0.5 - laser.phase * Traps.LASER_PERIOD
	var off_t: float = on_t - Traps.LASER_ON - Traps.LASER_WARN - 0.5
	var beam_pos := Vector2(laser.x, laser.bottom - Player.HALF.y - 1)
	_fresh(dummy, beam_pos)
	world.clock = off_t
	await _frames(3)
	_check("laser off is harmless", dummy.health == 100, "h=%d" % dummy.health)
	world.clock = on_t
	_fresh(dummy, beam_pos)
	await _frames(3)
	_check("laser on hurts", dummy.health < 100, "h=%d state=%d" % [dummy.health, world.traps.laser_state(laser)])

	# Vent: erupts with damage and an upward launch.
	var vent: Dictionary = world.level.vents[0]
	world.clock = Traps.VENT_PERIOD - Traps.VENT_ON * 0.5 - vent.phase * Traps.VENT_PERIOD
	_fresh(dummy, vent.pos - Vector2(0, Player.HALF.y + 1))
	await _frames(2)
	_check("vent hurts and launches", dummy.health == 100 - Traps.VENT_DMG and dummy.velocity.y < -400.0,
			"h=%d vy=%.0f" % [dummy.health, dummy.velocity.y])
	await _frames(int(World.RESPAWN_TIME * 60) + 10)

	# --- status effects ---
	pair = _duel(250)
	dummy.health = 1000                      # a direct rocket would otherwise kill it outright
	await _frames(2)
	_fire(me, Weapons.ROCKET, false, Vector2.RIGHT)
	await _frames(25)
	_check("rocket blast sets target burning", dummy.has_status(Status.BURN))
	var h_before := dummy.health
	await _frames(70)
	_check("burn deals damage over time", dummy.health < h_before or not dummy.alive, "h=%d->%d" % [h_before, dummy.health])
	await _frames(int(World.RESPAWN_TIME * 60) + 10)

	pair = _duel(300)
	dummy.health = 4
	var kills_before: int = world.roster[World.LOCAL_EID].kills
	world.apply_status(dummy, Status.BURN, 3.0, me.eid, Weapons.ROCKET)
	await _frames(40)
	_check("burn kill credited to the attacker", not dummy.alive and world.roster[World.LOCAL_EID].kills == kills_before + 1)
	await _frames(int(World.RESPAWN_TIME * 60) + 10)

	pair = _duel(600)
	world.apply_status(me, Status.CHILL, 3.0, dummy.eid, World.VENT)
	me.in_move = 1.0
	await _frames(40)
	_check("chill slows movement", absf(me.velocity.x) < Player.RUN_SPEED * 0.6 and absf(me.velocity.x) > 50.0, "vx=%.0f" % me.velocity.x)
	me.in_move = 0.0
	await _frames(200)
	_check("chill wears off", not me.has_status(Status.CHILL))

	pair = _duel(300)
	world.apply_status(me, Status.SHOCK, 1.5, dummy.eid, World.VENT)
	me.weapon = Weapons.ROCKET
	var ammo_before := me.ammo[Weapons.ROCKET]
	me.in_fire = true
	await _frames(20)
	me.in_fire = false
	_check("jammed weapons can't fire", me.ammo[Weapons.ROCKET] == ammo_before and world.projectiles.list.is_empty())

	_fresh(me, me.global_position)
	me.protect_time = 2.0
	world.apply_status(me, Status.BURN, 2.0, dummy.eid, World.VENT)
	_check("status ignored during spawn protection", not me.has_status(Status.BURN))

	# Pickups.
	for i in world.pickups.items.size():
		world.pickups.items[i].respawn_at = 0.0
	await _frames(3)
	var hp_index := -1
	var wpn_index := -1
	for i in world.pickups.items.size():
		var it: Dictionary = world.pickups.items[i]
		if it.type == "h" and hp_index < 0:
			hp_index = i
		if it.type == "w" and wpn_index < 0:
			wpn_index = i
	var hp: Dictionary = world.pickups.items[hp_index]
	_fresh(me, hp.pos)
	await _frames(3)
	_check("full health ignores health pack", hp.active)
	me.health = 50
	await _frames(3)
	_check("health pack heals", me.health == 75 and not hp.active, "h=%d active=%s" % [me.health, hp.active])
	var wp: Dictionary = world.pickups.items[wpn_index]
	me.owned = 1
	_fresh(me, wp.pos)
	await _frames(3)
	_check("weapon pickup grants weapon", me.owns(wp.wid) and me.ammo[wp.wid] > 0)

	# --- spawn rooms (anti spawn-camping) ---
	var room_pos := Vector2(5.5 * Level.T, 29 * Level.T - Player.HALF.y - 1)     # Deck-17 lower-left room
	var out_pos := Vector2(13.5 * Level.T, room_pos.y)                          # its porch, outside
	_check("spawn room detected", world.level.zone_at(room_pos) >= 0 and world.level.zone_at(out_pos) < 0)
	pair = _duel(300)
	_fresh(dummy, room_pos)
	world.damage(dummy, 50, me.eid, Weapons.ROCKET, Vector2.ZERO, dummy.global_position)
	world.apply_status(dummy, Status.BURN, 3.0, me.eid, Weapons.ROCKET)
	_check("invulnerable inside spawn room", dummy.health == 100 and not dummy.has_status(Status.BURN))
	_fresh(me, room_pos + Vector2(40, 0))
	me.weapon = Weapons.ROCKET
	var rockets_in_room := me.ammo[Weapons.ROCKET]
	me.in_fire = true
	await _frames(10)
	me.in_fire = false
	_check("weapons offline inside spawn room", me.ammo[Weapons.ROCKET] == rockets_in_room)
	_fresh(me, Vector2(9.5 * Level.T + 14, room_pos.y))                          # straddling the barrier door
	world.request_fire(me, Weapons.ROCKET, false, me.muzzle(), Vector2.LEFT)
	_check("weapons offline in the doorway", me.ammo[Weapons.ROCKET] == rockets_in_room and world.projectiles.list.is_empty())

	me.spawn_at(room_pos)
	me.protect_time = 0.0
	await _frames(2)
	me.teleport(out_pos)
	await _frames(2)
	_check("exit shield on first leaving spawn", me.protect_time > 1.0, "protect=%.2f" % me.protect_time)

	dummy.spawn_at(room_pos)
	await _frames(int((World.SPAWN_GRACE - 0.5) * 60))
	_check("comfortable time to leave spawn", dummy.alive and dummy.health == 100, "h=%d" % dummy.health)
	await _frames(int(4.0 * 60))
	_check("loitering in spawn gets purged", not dummy.alive)
	await _frames(int(World.RESPAWN_TIME * 60) + 10)

	dummy.spawn_at(out_pos)
	dummy.protect_time = 0.0
	await _frames(2)
	_check("left_spawn set outside", dummy.left_spawn)
	dummy.teleport(room_pos)
	await _frames(int((World.RETURN_GRACE - 0.5) * 60))
	_check("short grace when returning", dummy.alive and dummy.health == 100)
	await _frames(int(4.0 * 60))
	_check("hiding back in spawn gets purged", not dummy.alive)
	await _frames(int(World.RESPAWN_TIME * 60) + 10)

	dummy.spawn_at(room_pos)
	dummy.zone_time = 6.0
	dummy.teleport(out_pos)
	await _frames(60)
	_check("loiter meter drains slowly outside", dummy.zone_time > 5.0 and dummy.zone_time < 6.0, "t=%.2f" % dummy.zone_time)

	# Redeemer flight sound stops when it detonates.
	Sfx.muted = false
	pair = _duel(400)
	me.health = 5000                     # survive our own nuke so later tests aren't disturbed by a respawn
	_fire(me, Weapons.REDEEMER, false, Vector2.RIGHT)
	var nuke: Projectiles.Proj = world.projectiles.list.back() if world.projectiles.list.size() else null
	var engine: AudioStreamPlayer2D = nuke.sound if nuke else null
	_check("redeemer has a flight sound", engine != null and engine.playing)
	await _frames(90)
	_check("redeemer flight sound stops on detonation", world.projectiles.list.is_empty() and not is_instance_valid(engine))
	Sfx.muted = true
	await _frames(int(World.RESPAWN_TIME * 60) + 10)

	# Poison is cured by a health pickup.
	me = world.local_player
	_fresh(me, Vector2(800, 13 * Level.T - Player.HALF.y - 1))
	world.apply_status(me, Status.POISON, 6.0, -1, World.VENT)
	await _frames(40)
	_check("poison hurts", me.health < 100, "h=%d" % me.health)
	var cure: Dictionary = world.pickups.items[hp_index]
	cure.active = true
	me.teleport(cure.pos)
	await _frames(3)
	_check("health pickup cures poison", not me.has_status(Status.POISON) and not cure.active)

	# Map vents inflict their map's status (Foundry flames burn).
	await _load(2)
	vent = world.level.vents[0]
	var target: Player = world.entities[-1]
	world.clock = Traps.VENT_PERIOD - Traps.VENT_ON * 0.5 - vent.phase * Traps.VENT_PERIOD
	_fresh(target, vent.pos - Vector2(0, Player.HALF.y + 1))
	await _frames(2)
	_check("foundry vent sets burning", target.has_status(Status.BURN))
	await _load(4)
	vent = world.level.vents[0]
	target = world.entities[-1]
	world.clock = Traps.VENT_PERIOD - Traps.VENT_ON * 0.5 - vent.phase * Traps.VENT_PERIOD
	_fresh(target, vent.pos - Vector2(0, Player.HALF.y + 1))
	await _frames(2)
	_check("cryo vent chills", target.has_status(Status.CHILL))

	# Lava (Foundry channel).
	await _load(2)
	_fresh(world.local_player, Vector2(30.5 * Level.T, 27 * Level.T))
	await _frames(40)
	_check("lava kills", not world.local_player.alive)
	# --- random weapon slots + mid-round Redeemer ---
	for m in Maps.LIST.size():
		await _load_untouched(m)
		var dealt := {}
		for it in world.pickups.items:
			if it.get("random", false):
				dealt[it.wid] = true
		_check("%s deals every standard weapon" % Maps.LIST[m].name, dealt.size() == Weapons.REDEEMER - Weapons.FLAK, str(dealt.keys()))
	await _load_untouched(0)
	var slot: Dictionary = {}
	var nuke_spot: Dictionary = {}
	for it in world.pickups.items:
		if it.get("random", false) and slot.is_empty():
			slot = it
		if it.get("nuke", false):
			nuke_spot = it
	_check("redeemer dormant at round start", not nuke_spot.active and nuke_spot.dormant)
	slot.active = false
	slot.respawn_at = 0.0
	await _frames(2)
	_check("random slot re-rolls a standard weapon on respawn", slot.active and slot.wid >= Weapons.FLAK and slot.wid < Weapons.REDEEMER)
	world.roster[World.LOCAL_EID].kills = ceili(world.frag_limit / 2.0)
	await _frames(2)
	_check("redeemer spawns at half-round", nuke_spot.active and not nuke_spot.dormant and nuke_spot.wid == Weapons.REDEEMER)
	await _load_untouched(3)
	_check("overgrowth tunnel mouth has no jump pad", not world.level.is_pad(Vector2i(22, 28)) and not world.level.is_pad(Vector2i(49, 28)))

	# --- training room ---
	get_parent()._load_training()
	world = get_parent().world
	await _frames(20)
	me = world.local_player
	_check("training: no dummies at start, no frag limit", world.dummy_count() == 0 and world.frag_limit == 0)
	var tight := false
	for i in world.pickups.items.size():
		for j in range(i + 1, world.pickups.items.size()):
			if world.pickups.items[i].pos.distance_to(world.pickups.items[j].pos) < 2.5 * Level.T:
				tight = true
	_check("training: pickups spaced out", not tight)
	world.spawn_dummy()
	await _frames(5)
	var d: Player = null
	for e: Player in world.entities.values():
		if e.mode == Player.Mode.BOT:
			d = e
	_check("training: spawn dummy", d != null and d.alive and world.dummy_count() == 1)
	d.protect_time = 0.0
	var x0 := d.global_position.x
	world.set_dummy_behaviour(DummyBrain.Behaviour.IDLE)
	await _frames(60)
	_check("training: idle dummy stays put", absf(d.global_position.x - x0) < 4.0)
	world.set_dummy_behaviour(DummyBrain.Behaviour.MOVE)
	await _frames(90)
	_check("training: move-only dummy moves", absf(d.global_position.x - x0) > 40.0, "dx=%.0f" % (d.global_position.x - x0))
	# Put the player in clear view of the dummy for the attack tests.
	world.set_dummy_behaviour(DummyBrain.Behaviour.IDLE)
	d.owned = 1 << Weapons.ENFORCER                 # deterministic: hitscan pistol, no knockback
	d.weapon = Weapons.ENFORCER
	d.teleport(Vector2(59.5 * Level.T, 26 * Level.T - Player.HALF.y - 1))     # open range floor
	_fresh(me, Vector2(64.5 * Level.T, 26 * Level.T - Player.HALF.y - 1))
	world.god_mode = true
	world.set_dummy_behaviour(DummyBrain.Behaviour.ATTACK)
	await _frames(90)
	_check("training: god mode blocks damage", me.health == 100, "h=%d" % me.health)
	world.god_mode = false
	await _frames(90)
	_check("training: attack-only dummy shoots you", me.health < 100, "h=%d" % me.health)
	world.give_all_weapons(me)
	var shells := me.ammo[Weapons.ROCKET]
	_fire(me, Weapons.ROCKET, false, Vector2.UP)
	_check("training: infinite ammo", me.ammo[Weapons.ROCKET] == shells)
	world.clear_dummies()
	_check("training: remove dummies", world.dummy_count() == 0)

	print("DONE fails=%d" % fails)
	get_tree().quit(1 if fails else 0)
