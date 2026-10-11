extends Node
## Dev tool (excluded from exports): match stats, awards and the results screen.
## Run: godot --headless --path . -- --test=stats

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


func _real(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _shot(eid: int, wid: int, alt := false) -> void:
	world.apply_event(World.Ev.SHOT, [eid, wid, alt, Vector2(400, 300), PackedVector2Array(), []])


func _hit(victim: int, attacker: int, dmg: int, head := false, dot := -1) -> void:
	world.apply_event(World.Ev.HIT, [victim, dmg, Vector2(500, 300), attacker, false, head, dot])


func _fresh(p: Player, pos: Vector2) -> void:
	p.teleport(pos)
	p.protect_time = 0.0
	p.health = 100
	p.armor = 0
	p.amp_time = 0.0
	p._clear_status()
	p.left_spawn = true
	p.zone_time = 0.0


func _run() -> void:
	var main := get_parent()
	main._load_map(0)
	world = main.world
	world.local_player.mode = Player.Mode.BOT
	for e: Player in world.entities.values():
		e.brain = null
	await _frames(30)
	for it in world.pickups.items:
		it.active = false
		it.respawn_at = 1e9
	var st: MatchStats = world.get_node_or_null(^"MatchStats")
	_check("world creates a MatchStats node", st != null)
	_check("world has the event_applied signal", world.has_signal("event_applied"))
	if st == null:
		_finish()
		return
	st.stats.clear()                                # start from zero (spawns etc. don't count anyway)
	var me := world.my_eid

	# Accuracy: 10 enforcer shots, 4 hits (one a headshot), one burn tick that isn't a hit.
	for i in 10:
		_shot(me, Weapons.ENFORCER)
	for i in 4:
		_hit(-1, me, 15, i == 0)
	_hit(-1, me, 5, false, Status.BURN)
	_check("accuracy = hits / shots", is_equal_approx(st.accuracy(me), 0.4), "got %f" % st.accuracy(me))
	_check("headshots counted", st.of(me).heads == 1)
	_check("damage dealt includes DoT ticks", st.of(me).dmg == 65, "got %d" % st.of(me).dmg)
	_check("damage taken", st.of(-1).taken == 65)
	_check("DoT tick isn't a hit", st.of(me).hits == 4)
	_shot(me, Weapons.FLAK)
	_check("flak counts 8 pellets per shot", st.of(me).pellets == 18 and st.of(me).wshots[Weapons.FLAK] == 1)
	_shot(-1, Weapons.ROCKET, true)
	_check("rocket volley (alt) counts 3 pellets", st.of(-1).pellets == 3 and st.of(-1).shots == 1)
	# Splash: one rocket hitting three players caps at 100%.
	_shot(-2, Weapons.ROCKET)
	for v in [me, -1, -3]:
		_hit(v, -2, 40)
	_check("accuracy capped at 100%", is_equal_approx(st.accuracy(-2), 1.0))
	_check("self-damage isn't a hit", (func() -> bool:
		_hit(-3, -3, 20)
		return st.of(-3).hits == 0).call())
	_check("no shots -> no accuracy", st.accuracy_text(-3) == "—")
	world.apply_event(World.Ev.PICKUP, [0, false, me, -1])
	_check("pickups counted", st.of(me).pickups == 1)

	# Real damage: a sniper headshot through World.damage() frags dummy -1.
	var dummy: Player = world.entities[-1]
	var y := 13 * Level.T - Player.HALF.y - 1
	_fresh(world.local_player, Vector2(800, y))
	_fresh(dummy, Vector2(1300, y))
	world.damage(dummy, 500.0, me, Weapons.SNIPER, Vector2.ZERO, dummy.global_position, true)
	_check("real damage -> frag recorded", st.of(me).frags == 1 and world.roster[me].kills == 1,
			"frags %d kills %d" % [st.of(me).frags, world.roster[me].kills])
	_check("longest frag distance", absf(st.of(me).longest - 500.0) < 2.0, "got %f" % st.of(me).longest)
	_check("real headshot counted", st.of(me).heads == 2)
	# Two rocket frags right after: multi kill + spree + splash.
	world._kill(world.entities[-2], me, Weapons.ROCKET, Vector2.ZERO)
	world._kill(world.entities[-3], me, Weapons.ROCKET, Vector2.ZERO)
	var s := st.of(me)
	_check("spree tracked", s.spree == 3 and s.best_spree == 3)
	_check("multi kill tracked", s.best_multi == 3 and s.multis == 1)
	_check("splash frags", s.splash == 2)
	_check("favourite weapon = most frags", st.favourite(me) == Weapons.ROCKET)
	world._kill(world.local_player, -1, Weapons.ENFORCER, Vector2.ZERO)
	_check("death resets the spree, keeps the best", st.of(me).spree == 0 and st.of(me).best_spree == 3)
	_check("victim frag credited", st.of(-1).frags == 1 and st.of(me).deaths == 1)
	world.apply_event(World.Ev.DIED, [-2, -2, World.HAZARD, Vector2(100, 100), Vector2.ZERO])
	_check("environment death is a suicide", st.of(-2).suicides == 1 and st.of(-2).spree == 0)

	# Awards.
	var aw := st.awards(4)
	var ids := aw.map(func(a: Dictionary) -> int: return a.id)
	_check("4 awards", aw.size() == 4, str(ids))
	_check("MVP is the top fragger", aw.size() > 0 and aw[0].id == MatchStats.Award.MVP and aw[0].eid == me)
	_check("Sharpshooter goes to the accurate player", ids.has(MatchStats.Award.SHARPSHOOTER)
			and aw[ids.find(MatchStats.Award.SHARPSHOOTER)].eid == me)
	_check("Rampage = best spree", ids.has(MatchStats.Award.RAMPAGE) and aw[ids.find(MatchStats.Award.RAMPAGE)].value.begins_with("3"))
	_check("Headhunter", ids.has(MatchStats.Award.HEADHUNTER))
	_check("standings put you first", st.standings()[0] == me and st.rank_of(me) == 1)

	# Tab scoreboard cache.
	world.hud._sb_sig = -1
	world.hud._sb_refresh()
	var rows: Array = world.hud._sb_rows
	_check("scoreboard rows cached", rows.size() == world.roster.size() and rows[0][0] == me and rows[0][8])
	_check("scoreboard shows accuracy + K/D", rows[0][7] == st.accuracy_text(me) and rows[0][6] == "3.00", str(rows[0]))
	_check("scoreboard tags bots with their skill", rows[1][3] in ["BOT", "DUMMY", "REGULAR", "ROOKIE", "VETERAN", "ELITE", "GODLIKE"],
			str(rows[1][3]))

	# Results screen.
	world._end_match(me)
	await _frames(3)
	var hud := world.hud
	_check("results visible after the match", hud._results.visible and hud._res_root != null)
	_check("buttons exist", hud._res_again is Button and hud._res_menu is Button and hud._res_recap is Button)
	_check("panel waits for the headline", not hud._res_root.visible)
	await _real(3.6)
	_check("panel revealed", hud._res_root.visible and hud._res_shown and hud._res_root.modulate.a > 0.99)
	var frags_ok := false
	for c: Array in hud._res_counters:
		if is_equal_approx(c[1], 3.0) and c[0].text == "3":
			frags_ok = true
	_check("counters reach their values", frags_ok)
	_check("award cards built", _count_cards(hud._res_root) == aw.size(), "got %d" % _count_cards(hud._res_root))
	_check("play again focusable", hud._res_again.is_visible_in_tree() and not hud._res_again.disabled)

	# Recap render (headless can't read pixels back: it must still finish and report).
	hud._on_save_recap()
	var t := 0
	while hud._res_recap.disabled and t < 300:
		await _frames(1)
		t += 1
	_check("recap finishes", not hud._res_recap.disabled and hud._res_note.text != "", hud._res_note.text)
	print("recap: ", hud._res_note.text)
	_check("recap viewport freed", _count_viewports(st) == 0)
	_finish()


func _count_cards(n: Node) -> int:
	var k := 0
	for c in n.get_children():
		if c is PanelContainer and c.get_parent() is Control and not (c.get_parent() is Container) \
				and c.get_parent().custom_minimum_size.y == 92:
			k += 1
		k += _count_cards(c)
	return k


func _count_viewports(n: Node) -> int:
	var k := 0
	for c in n.get_children():
		if c is SubViewport and not c.is_queued_for_deletion():
			k += 1
	return k


func _finish() -> void:
	print("DONE fails=%d" % fails)
	get_tree().quit(1 if fails else 0)
