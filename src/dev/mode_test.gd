extends Node
## Dev tool (excluded from exports): headless checks of the game modes (GameMode).
## Run: godot --headless --fixed-fps 60 --path . -- --test=mode

const BOT_SECONDS := 35
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


## A match in `mode` with passive dummies (no AI), everyone spawned.
func _load(mode: int, map := 0, lowgrav := false) -> void:
	get_parent().start_match({"map": map, "bots": 3, "frags": 15, "minutes": 0, "mode": mode, "lowgrav": lowgrav})
	world = get_parent().world
	world.countdown = 0.0
	world.local_player.mode = Player.Mode.BOT        # no mouse/keyboard input in tests
	for e: Player in world.entities.values():
		e.brain = null
	await _frames(40)


## Shooter and dummy on Deck-17's high bridge (as in combat_test), unprotected.
func _place(p: Player, x: float) -> void:
	p.teleport(Vector2(x, 13 * Level.T - Player.HALF.y - 1))
	p.protect_time = 0.0
	p.left_spawn = true
	p.zone_time = 0.0
	p._clear_status()


## Wait (capped) until `p` is alive again: kill hitstop slows the match clock in fast-forward.
func _until_alive(p: Player) -> void:
	for i in 600:
		if p.alive:
			return
		await get_tree().physics_frame


func _kill(victim: Player, killer_eid: int, wid: int) -> void:
	world.damage(victim, 5000.0, killer_eid, wid, Vector2.ZERO, victim.global_position, false, true)


func _items(type: String, active: bool) -> int:
	var n := 0
	for it in world.pickups.items:
		if (it.type == type or (type == "*" and it.type != "w")) and it.active == active:
			n += 1
	return n


func _everyone_holds(wid: int) -> bool:
	for e in world.alive_players():
		if e.owned != 1 << wid or e.weapon != wid:
			return false
		if not Weapons.infinite(wid) and e.ammo[wid] < 100:
			return false
	return true


func _run() -> void:
	# --- Deathmatch: unchanged default -----------------------------------------------------
	await _load(GameMode.DEATHMATCH)
	var me := world.local_player
	_check("DM: default mode", world.game_mode == GameMode.DEATHMATCH)
	_check("DM: spawn with Enforcer only", me.owned == 1 << Weapons.ENFORCER and me.weapon == Weapons.ENFORCER)
	_check("DM: weapon pickups live", _items("w", true) > 0, str(_items("w", true)))
	_check("DM: frag limit from config", world.frag_limit == 15, str(world.frag_limit))
	_check("DM: no mode status line", GameMode.status_text(world, me) == "")
	_check("DM: describe carries mode", int(world.describe().get("mode", -1)) == GameMode.DEATHMATCH)

	# --- Gun Game --------------------------------------------------------------------------
	await _load(GameMode.GUN_GAME)
	me = world.local_player
	var ladder := GameMode.LADDER
	_check("GG: frag limit = ladder length", world.frag_limit == ladder.size(), str(world.frag_limit))
	_check("GG: everyone starts on tier 0 (%s)" % Weapons.LIST[ladder[0]].name, _everyone_holds(ladder[0]))
	_check("GG: weapon pickups gone", _items("w", true) == 0, str(_items("w", true)))
	_check("GG: health / armor stay", _items("*", true) > 0, str(_items("*", true)))
	var wpick: Dictionary = {}
	for it in world.pickups.items:
		if it.type == "w":
			wpick = it
			break
	_check("GG: weapon pickup refused", wpick.is_empty() or not world._give(me, wpick))
	_check("GG: status line tier 1", GameMode.status_text(world, me).contains("Tier 1/%d" % ladder.size()), GameMode.status_text(world, me))
	_kill(world.entities[-1], me.eid, me.weapon)
	_check("GG: frag promotes to tier 2", me.weapon == ladder[1] and me.owned == 1 << ladder[1],
			"%d owned=%d" % [me.weapon, me.owned])
	_check("GG: status line tier 2", GameMode.status_text(world, me).contains("Tier 2/%d" % ladder.size()), GameMode.status_text(world, me))
	_kill(world.entities[-2], me.eid, me.weapon)
	_check("GG: second frag -> tier 3", me.weapon == ladder[2], str(me.weapon))
	_kill(me, me.eid, World.HAZARD)                       # suicide: demoted one tier
	_check("GG: suicide demotes a tier", world.roster[me.eid].kills == 1, str(world.roster[me.eid].kills))
	await _until_alive(me)
	_check("GG: respawn on the demoted tier", me.alive and me.weapon == ladder[1] and me.owned == 1 << ladder[1],
			"alive=%s w=%d" % [me.alive, me.weapon])
	world.roster[me.eid].kills = 0
	_kill(me, me.eid, World.HAZARD)
	_check("GG: never below tier 1", world.roster[me.eid].kills == 0, str(world.roster[me.eid].kills))
	await _until_alive(me)
	# Fast-forward to the final tier, then win it.
	world.roster[me.eid].kills = ladder.size() - 2
	var bot3: Player = world.entities[-3]
	await _until_alive(bot3)
	_kill(bot3, me.eid, me.weapon)
	_check("GG: final tier is the %s" % Weapons.LIST[ladder[-1]].name, me.weapon == ladder[-1] and not world.ended, str(me.weapon))
	_check("GG: status line final tier", GameMode.status_text(world, me).contains("FINAL"), GameMode.status_text(world, me))
	var victim: Player = null
	for eid in [-1, -2, -3]:
		if world.entities[eid].alive:
			victim = world.entities[eid]
	if victim == null:
		victim = world.entities[-1]
		await _until_alive(victim)
	_kill(victim, me.eid, me.weapon)
	_check("GG: finishing the ladder wins", world.ended and world._winner_eid == me.eid, "ended=%s winner=%d" % [world.ended, world._winner_eid])
	var info := world.describe()
	_check("GG: describe carries mode", int(info.get("mode", -1)) == GameMode.GUN_GAME)
	# A LAN client rebuilt from the description gets the same mode, limit and hidden pickups.
	var cw := World.new()
	cw.process_mode = Node.PROCESS_MODE_DISABLED
	cw.my_eid = me.eid
	get_parent().add_child(cw)
	info.ended = false
	cw.setup_client(info)
	var dormant_w := 0
	for it in cw.pickups.items:
		if it.type == "w" and not it.active and it.dormant:
			dormant_w += 1
	var host_w := 0
	for it in world.pickups.items:
		if it.type == "w":
			host_w += 1
	_check("LAN client: mode + frag limit", cw.game_mode == GameMode.GUN_GAME and cw.frag_limit == ladder.size(),
			"%d %d" % [cw.game_mode, cw.frag_limit])
	_check("LAN client: weapon pickups hidden", dormant_w == host_w, "%d/%d" % [dormant_w, host_w])
	cw.queue_free()
	await _frames(2)

	# --- Instagib --------------------------------------------------------------------------
	await _load(GameMode.INSTAGIB)
	me = world.local_player
	_check("IG: everyone holds only the Shock Rifle", _everyone_holds(Weapons.SHOCK))
	_check("IG: every pickup disabled", _items("w", true) + _items("*", true) == 0)
	var dummy: Player = world.entities[-1]
	_place(me, 800.0)
	_place(dummy, 1100.0)
	dummy.health = 199
	dummy.armor = 150
	world.request_fire(me, Weapons.SHOCK, false, me.muzzle(), (dummy.global_position - me.muzzle()).normalized())
	_check("IG: one beam kills (even 199 hp + 150 armor)", not dummy.alive, "hp=%d" % dummy.health)
	_check("IG: fast respawn", dummy.respawn_at - world.clock <= GameMode.INSTAGIB_RESPAWN + 0.01, str(dummy.respawn_at - world.clock))
	_check("IG: kill refills the rifle", me.ammo[Weapons.SHOCK] == GameMode.AMMO, str(me.ammo[Weapons.SHOCK]))
	_place(me, 800.0)
	me.health = 100
	world.damage(me, 125.0, me.eid, Weapons.SHOCK, Vector2.ZERO, me.global_position)
	_check("IG: own combo doesn't hurt", me.alive and me.health == 100, str(me.health))

	# --- Rocket Arena ----------------------------------------------------------------------
	await _load(GameMode.ROCKET_ARENA)
	me = world.local_player
	_check("RA: everyone holds only rockets", _everyone_holds(Weapons.ROCKET))
	_check("RA: weapon pickups gone, health stays", _items("w", true) == 0 and _items("h", true) + _items("H", true) > 0)
	_place(me, 800.0)
	me.health = 100
	me.armor = 0
	world.damage(me, 100.0, me.eid, Weapons.ROCKET, Vector2.ZERO, me.global_position)
	_check("RA: self rocket damage quartered", me.health == 75, str(me.health))
	world.damage(me, 5.0, me.eid, Weapons.ROCKET, Vector2.ZERO, me.global_position, false, false, Status.BURN)
	_check("RA: no self-burn", me.health == 75, str(me.health))
	dummy = world.entities[-1]
	_place(dummy, 1100.0)
	dummy.health = 100
	dummy.armor = 0
	world.damage(dummy, 60.0, me.eid, Weapons.ROCKET, Vector2.ZERO, dummy.global_position)
	_check("RA: rockets still hurt others normally", dummy.health == 40, str(dummy.health))
	world.request_fire(me, Weapons.ROCKET, true, me.muzzle(), Vector2.RIGHT)
	_check("RA: alt volley doesn't run dry", me.ammo[Weapons.ROCKET] >= GameMode.AMMO - 3, str(me.ammo[Weapons.ROCKET]))

	# --- Low gravity mutator / training ignores modes ---------------------------------------
	await _load(GameMode.DEATHMATCH, 0, true)
	_check("Low gravity mutator", is_equal_approx(world.gravity_scale, GameMode.LOW_GRAVITY), str(world.gravity_scale))
	_check("Low gravity in describe", bool(world.describe().get("lowgrav", false)))
	var main := get_parent()
	main._clear()
	main.world = main._new_world()
	main.world.game_mode = GameMode.GUN_GAME
	main.world.setup(Maps.TRAINING, 0)
	_check("Training ignores modes", main.world.game_mode == GameMode.DEATHMATCH)
	await _frames(5)

	# --- Bots play every mode ---------------------------------------------------------------
	var maps := [1, 2, 3, 5, 4]
	var modes := [GameMode.DEATHMATCH, GameMode.GUN_GAME, GameMode.INSTAGIB, GameMode.ROCKET_ARENA, GameMode.GUN_GAME]
	for n in modes.size():
		var m: int = modes[n]
		var lowgrav := n == 4
		main.start_match({"map": maps[n], "bots": 5, "skill": BotBrain.Skill.VETERAN, "frags": 15, "minutes": 0,
				"mode": m, "lowgrav": lowgrav})
		world = main.world
		world.countdown = 0.0
		if m != GameMode.GUN_GAME:
			world.frag_limit = 0
		world.local_player.mode = Player.Mode.BOT
		world.local_player.brain = BotBrain.new(BotBrain.Skill.VETERAN)
		var bad_loadout := 0
		var took_weapon := 0
		var t0 := Time.get_ticks_usec()
		var secs := 0
		for sec in BOT_SECONDS:
			await _frames(60)
			secs += 1
			for e in world.alive_players():
				var want := GameMode.weapon_for(world, e.eid)
				if want >= 0 and (e.owned != 1 << want or e.weapon != want):
					bad_loadout += 1
			if m != GameMode.DEATHMATCH and _items("w", true) > 0:
				took_weapon += 1
			if world.ended:
				break
		var kills := 0
		var top := 0
		for eid in world.roster:
			kills += maxi(0, world.roster[eid].kills)
			top = maxi(top, world.roster[eid].kills)
		var label := GameMode.name_of(m) + (" + low grav" if lowgrav else "") + " on " + str(Maps.LIST[maps[n]].name)
		print("%s: %d frags (top %d) in %d s%s, %.2f ms/frame" % [label, kills, top, secs, " (match won)" if world.ended else "",
				(Time.get_ticks_usec() - t0) / 1000.0 / (secs * 60)])
		_check("%s: bots frag" % label, kills >= 3, str(kills))
		_check("%s: loadouts stay on the mode's weapon" % label, bad_loadout == 0, str(bad_loadout))
		_check("%s: weapon pickups stay off" % label, took_weapon == 0, str(took_weapon))
		if m == GameMode.GUN_GAME and world.ended:
			_check("%s: winner finished the ladder" % label, world.roster[world._winner_eid].kills >= GameMode.LADDER.size())

	print("DONE fails=%d" % fails)
	get_tree().quit(1 if fails else 0)
