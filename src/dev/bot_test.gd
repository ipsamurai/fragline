extends Node
## Dev tool (excluded from exports): bots play each arena and we measure their behaviour.
## Run fast: godot --headless --fixed-fps 60 --path . -- --test=bot

const SECONDS := 45
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


func _all_bots(world: World, skill: BotBrain.Skill) -> void:
	world.local_player.mode = Player.Mode.BOT
	for e: Player in world.entities.values():
		e.brain = BotBrain.new(skill)


func _run() -> void:
	var main := get_parent()
	for m in Maps.LIST.size():
		main._load_map(m)
		var world: World = main.world
		world.frag_limit = 0                       # don't end the match mid-test
		_all_bots(world, BotBrain.Skill.VETERAN)
		var deaths := {"total": 0, "purge": 0, "env": 0, "self_env": 0}
		var trail := {}                           # eid -> [cell, action] of the last grounded moment
		world.died.connect(func(v: int, k: int, wid: int) -> void:
			if wid < 0 and wid != World.PURGE and k == v:
				print("   self-fall: %s from %s while %s" % [world.entities[v].display_name, trail.get(v, ["?", "?"])[0], trail.get(v, ["?", "?"])[1]])
			deaths.total += 1
			if wid == World.PURGE:
				deaths.purge += 1
			elif wid < 0:
				deaths.env += 1
				if k == v:
					deaths.self_env += 1             # walked/jumped in on its own (not knocked)
			)
		var left := {}
		var armed := {}
		var stuck := 0
		var last_pos := {}
		var still := {}
		var t0 := Time.get_ticks_usec()
		for sec in SECONDS:
			for f in 60:
				await get_tree().physics_frame
				for e: Player in world.entities.values():
					if e.alive and e.is_on_floor() and e.brain:
						trail[e.eid] = [world.level.cell_of(e.global_position), e.brain.action]
			for e: Player in world.entities.values():
				if not e.alive:
					still[e.eid] = 0
					continue
				if e.left_spawn:
					left[e.eid] = true
				if e.owned != 1 << Weapons.ENFORCER:
					armed[e.eid] = true
				var moved: float = e.global_position.distance_to(last_pos.get(e.eid, Vector2.INF))
				still[e.eid] = still.get(e.eid, 0) + 1 if moved < 24.0 else 0
				if still[e.eid] == 6:
					stuck += 1
					print("   stuck: %s at cell %s while %s" % [e.display_name, world.level.cell_of(e.global_position), e.brain.action])
				last_pos[e.eid] = e.global_position
		var ms_per_frame := (Time.get_ticks_usec() - t0) / 1000.0 / (SECONDS * 60)
		var kills := 0
		for eid in world.roster:
			kills += maxi(0, world.roster[eid].kills)
		var name: String = Maps.LIST[m].name
		print("%s: %d frags, %d deaths (%d env of which %d self-inflicted, %d purge), %.2f ms/frame" % [name, kills, deaths.total, deaths.env, deaths.self_env, deaths.purge, ms_per_frame])
		_check("%s: bots fight (frags scored)" % name, kills >= 3, str(kills))
		_check("%s: every bot leaves spawn" % name, left.size() == world.entities.size(), "%d/%d" % [left.size(), world.entities.size()])
		_check("%s: bots pick up weapons" % name, armed.size() >= 2, str(armed.size()))
		_check("%s: no bot stuck for 6 s" % name, stuck == 0, str(stuck))
		_check("%s: no spawn purges" % name, deaths.purge == 0, str(deaths.purge))
		_check("%s: bots rarely kill themselves on hazards" % name, deaths.self_env * 5 <= maxi(deaths.total, 1), "%d/%d" % [deaths.self_env, deaths.total])
		_check("%s: cheap enough (< 4 ms/frame headless)" % name, ms_per_frame < 4.0, "%.2f" % ms_per_frame)

	# Skill matters: an Elite should outscore a Rookie in a duel.
	main._load_map(5)
	var w: World = main.world
	w.frag_limit = 0
	w.clear_dummies()
	w.local_player.mode = Player.Mode.BOT
	w.local_player.brain = BotBrain.new(BotBrain.Skill.ELITE)
	var rookie := w._add_player(-1, Player.Mode.BOT, Characters.resolve(3), "Rookie")
	rookie.brain = BotBrain.new(BotBrain.Skill.ROOKIE)
	rookie.respawn_at = w.clock
	await _frames(60 * 90)
	var ek: int = w.roster[World.LOCAL_EID].kills
	var rk: int = w.roster[-1].kills
	print("duel: elite %d vs rookie %d" % [ek, rk])
	_check("skill tiers matter (elite beats rookie)", ek > rk, "%d vs %d" % [ek, rk])
	print("DONE fails=%d" % fails)
	get_tree().quit(1 if fails else 0)
