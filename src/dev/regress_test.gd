extends Node
## Dev tool (excluded from exports): regression checks for recently added rules and polish
## (alive cache, draws, kill credit, overheal, fire validation, hitstop/finale, X-Ray, nav cache,
## bot brain safety, training panel vs pause, settings keys, auto-quality guard).
## Restores your settings file after.
## Run: godot --headless --path . -- --test=regress

var world: World
var fails := 0
var _backup := ""
var _had_file := false
var _saved := {}
var _mouse_ok := false             # headless display servers may ignore mouse_mode


func _ready() -> void:
	Sfx.muted = true
	_had_file = FileAccess.file_exists(Settings.PATH)
	if _had_file:
		_backup = FileAccess.get_file_as_string(Settings.PATH)
	for k in ["auto_quality", "announcer", "quality"]:
		_saved[k] = Settings.get(k)
	Settings.auto_quality = false          # the real FpsCounter must not react to slow headless frames
	_run.call_deferred()


func _check(name: String, ok: bool, detail := "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("" if ok else "   " + detail))
	if not ok:
		fails += 1


func _skip(name: String, why: String) -> void:
	print("SKIP  " + name + "   " + why)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _real(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout     # ignores Engine.time_scale


func _load(map: int) -> void:
	get_parent()._load_map(map)
	world = get_parent().world
	world.frag_limit = 0                             # never end by frags unless a test wants it
	world.local_player.mode = Player.Mode.BOT        # no mouse/keyboard input in tests
	for e: Player in world.entities.values():
		e.brain = null
	await _frames(30)
	for it in world.pickups.items:
		it.active = false
		it.respawn_at = 1e9


func _arm(p: Player) -> void:
	for w in Weapons.COUNT:
		p.owned |= 1 << w
		p.ammo[w] = maxi(Weapons.max_ammo(w), 1)


func _fresh(p: Player, pos: Vector2) -> void:
	if not p.alive:
		p.spawn_at(pos)
		world._alive_dirty = true
	p.teleport(pos)
	p.protect_time = 0.0
	p.health = 100
	p.armor = 0
	p.amp_time = 0.0
	p.in_move = 0.0
	p.in_fire = false
	p.in_alt = false
	p.in_jump_held = false
	p.in_down_held = false
	p._clear_status()
	p.left_spawn = true
	p.zone_time = 0.0


func _bridge(x: float) -> Vector2:
	return Vector2(x, 13 * Level.T - Player.HALF.y - 1)       # Deck-17 high bridge


func _action(name: String) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	return ev


func _run() -> void:
	_settings_checks()
	await _load(0)
	_main_checks()
	await _world_checks()
	await _nav_cache_and_exit_checks()
	await _demo_checks()
	await _host_checks()
	await _training_checks()
	_done()


# --- 17. settings keys ----------------------------------------------------------------

func _settings_checks() -> void:
	Settings.auto_quality = false
	Settings.announcer = false
	Settings.save_settings()
	var cfg := ConfigFile.new()
	var err := cfg.load(Settings.PATH)
	_check("settings: auto_quality + announcer saved", err == OK
			and cfg.get_value("prefs", "auto_quality", true) == false and cfg.get_value("prefs", "announcer", true) == false,
			"err=%d aq=%s an=%s" % [err, cfg.get_value("prefs", "auto_quality", "?"), cfg.get_value("prefs", "announcer", "?")])
	Settings.auto_quality = true
	Settings.announcer = true
	Settings.load_settings()
	_check("settings: auto_quality + announcer load back", Settings.auto_quality == false and Settings.announcer == false,
			"aq=%s an=%s" % [Settings.auto_quality, Settings.announcer])
	Settings.announcer = bool(_saved.announcer)
	Settings.auto_quality = false


# --- 16. main ignores match starts that don't include us -----------------------------------

func _main_checks() -> void:
	var main := get_parent()
	var before: World = main.world
	var fake_id := Net.my_id + 424242
	main._on_net_match_started({"map": "deck17", "players": [[fake_id, "Ghost", {}, true, Vector2.ZERO, 0, 0, false]]})
	_check("main: net match start without our id is ignored", main.world == before and is_instance_valid(before))
	main._on_net_match_started({"map": "deck17", "players": ["junk", [], null]})
	_check("main: malformed player rows are ignored", main.world == before)


# --- world rules ---------------------------------------------------------------------

func _world_checks() -> void:
	var me := world.local_player
	var d1: Player = world.entities[-1]
	var d2: Player = world.entities[-2]
	var d3: Player = world.entities[-3]

	# 1. alive_players() cache.
	var a0 := world.alive_players()
	_check("alive: all 4 spawned", a0.size() == 4, str(a0.size()))
	_check("alive: cached between changes", is_same(a0, world.alive_players()))
	_fresh(d3, _bridge(1400))
	world.damage(d3, 1000.0, d3.eid, World.HAZARD, Vector2.ZERO, d3.global_position, false, true)
	var a1 := world.alive_players()
	_check("alive: death removes from cache", a1.size() == 3 and not a1.has(d3), str(a1.size()))
	_check("alive: fresh array after change (old loop stays valid)", not is_same(a0, a1) and a0.size() == 4)
	await _frames(int(World.RESPAWN_TIME * 60) + 10)
	_check("alive: respawn re-adds", world.alive_players().size() == 4 and world.alive_players().has(d3))
	var jid := 4242
	world.apply_event(World.Ev.JOIN, [jid, "Joiner", Settings.look()])
	_check("alive: joined peer not alive until spawned", world.entities.has(jid) and world.alive_players().size() == 4)
	world.apply_event(World.Ev.SPAWN, [jid, _bridge(600)])
	var a2 := world.alive_players()
	_check("alive: spawned peer counted", a2.size() == 5 and a2.has(world.entities[jid]), str(a2.size()))
	var joiner: Player = world.entities[jid]
	world.apply_event(World.Ev.LEAVE, [jid])
	var a3 := world.alive_players()
	_check("alive: leaving peer dropped", a3.size() == 4 and not a3.has(joiner) and not world.roster.has(jid), str(a3.size()))
	_check("alive: old array untouched by leave", a2.size() == 5)
	await _frames(2)

	# 2. _winner(): ties are draws, outright leader wins.
	var saved_kills := {}
	for eid in world.roster:
		saved_kills[eid] = world.roster[eid].kills
		world.roster[eid].kills = 0
	world.roster[World.LOCAL_EID].kills = 3
	world.roster[-1].kills = 3
	_check("winner: tied top score is a draw (0)", world._winner() == 0, str(world._winner()))
	world.roster[-1].kills = 4
	_check("winner: outright leader wins", world._winner() == -1, str(world._winner()))
	world.roster[World.LOCAL_EID].kills = -2
	world.roster[-1].kills = -2
	world.roster[-2].kills = -5
	world.roster[-3].kills = -5
	_check("winner: negative tie is still a draw", world._winner() == 0, str(world._winner()))
	for eid in saved_kills:
		world.roster[eid].kills = saved_kills[eid]

	# 3. _kill credit.
	_fresh(me, _bridge(800))
	var k0: int = world.roster[World.LOCAL_EID].kills
	var dth0: int = world.roster[World.LOCAL_EID].deaths
	world.damage(me, 1000.0, me.eid, Weapons.ROCKET, Vector2.ZERO, me.global_position)
	_check("kill: suicide costs a frag", not me.alive and world.roster[World.LOCAL_EID].kills == k0 - 1
			and world.roster[World.LOCAL_EID].deaths == dth0 + 1,
			"k=%d->%d alive=%s" % [k0, world.roster[World.LOCAL_EID].kills, me.alive])
	_fresh(d1, _bridge(1000))
	var vk: int = world.roster[-1].kills
	var vd: int = world.roster[-1].deaths
	world.damage(d1, 1000.0, 987654, Weapons.ROCKET, Vector2.ZERO, d1.global_position)
	_check("kill: killer gone from roster -> victim keeps frags", not d1.alive and world.roster[-1].kills == vk
			and world.roster[-1].deaths == vd + 1 and not world.roster.has(987654),
			"k=%d->%d d=%d->%d" % [vk, world.roster[-1].kills, vd, world.roster[-1].deaths])
	await _frames(int(World.RESPAWN_TIME * 60) + 10)

	# 4. _give: small health never lowers overheal; still cures poison.
	_fresh(me, _bridge(800))
	me.health = 199
	world.apply_status(me, Status.POISON, 6.0, -1, World.VENT)
	var took := world._give(me, {"type": "h"})
	_check("give: +25 health keeps 199 overheal and cures poison", took and me.health == 199 and not me.has_status(Status.POISON),
			"took=%s h=%d poison=%s" % [took, me.health, me.has_status(Status.POISON)])
	me.health = 150
	took = world._give(me, {"type": "h"})
	_check("give: +25 health refused above 100 when not poisoned", not took and me.health == 150, "took=%s h=%d" % [took, me.health])
	me.health = 90
	world._give(me, {"type": "h"})
	_check("give: +25 health caps at 100", me.health == 100, "h=%d" % me.health)

	# 5. _server_fire refusals.
	_fresh(me, _bridge(800))
	_fresh(d1, _bridge(1300))
	_arm(me)
	me.aim = 0.0
	var r0 := me.ammo[Weapons.ROCKET]
	var refusals := {
		"ended": func() -> void: world.ended = true,
		"countdown": func() -> void: world.countdown = 1.0,
		"jammed": func() -> void: me.status[Status.SHOCK] = 1.0,
		"dead": func() -> void: me.alive = false,
		"not owned": func() -> void: me.owned &= ~(1 << Weapons.ROCKET),
	}
	for why: String in refusals:
		refusals[why].call()
		me.protect_time = 1.0
		world._server_fire(me, Weapons.ROCKET, false, me.muzzle(), Vector2.RIGHT)
		_check("server_fire refuses when %s" % why, me.ammo[Weapons.ROCKET] == r0 and world.projectiles.list.is_empty()
				and me.protect_time == 1.0, "ammo=%d projs=%d" % [me.ammo[Weapons.ROCKET], world.projectiles.list.size()])
		world.ended = false
		world.countdown = 0.0
		me.status.erase(Status.SHOCK)
		me.alive = true
		me.owned |= 1 << Weapons.ROCKET
	me.protect_time = 1.0
	world._server_fire(me, Weapons.ENFORCER, false, me.muzzle(), Vector2.UP)
	_check("server_fire: firing clears spawn protection", me.protect_time == 0.0, "protect=%.2f" % me.protect_time)

	# 6. host_client_fire: rejects when ended; small same-frame backlog after idle.
	_fresh(d1, _bridge(1300))
	_arm(d1)
	var m0 := d1.ammo[Weapons.MINIGUN]
	world.ended = true
	world.host_client_fire(d1.eid, Weapons.MINIGUN, false, d1.muzzle(), Vector2.UP)
	world.ended = false
	_check("client_fire: rejected after the match ended", d1.ammo[Weapons.MINIGUN] == m0, "ammo=%d" % d1.ammo[Weapons.MINIGUN])
	world.host_client_fire(d1.eid, Weapons.MINIGUN, false, d1.muzzle(), Vector2.UP)
	world.host_client_fire(d1.eid, Weapons.MINIGUN, false, d1.muzzle(), Vector2.UP)
	_check("client_fire: two same-frame shots after idle both fire", d1.ammo[Weapons.MINIGUN] == m0 - 2,
			"used=%d" % (m0 - d1.ammo[Weapons.MINIGUN]))
	for i in 10:
		world.host_client_fire(d1.eid, Weapons.MINIGUN, false, d1.muzzle(), Vector2.UP)
	var burst := m0 - d1.ammo[Weapons.MINIGUN]
	_check("client_fire: same-frame burst is rate limited", burst <= 3, "fired %d in one frame" % burst)
	world.host_client_fire(d1.eid, Weapons.MINIGUN, false, d1.muzzle(), Vector2(NAN, 0))
	_check("client_fire: NaN direction rejected", m0 - d1.ammo[Weapons.MINIGUN] == burst)
	await _frames(3)

	# 7. headshot flag only for weapons with a headshot multiplier.
	_fresh(me, _bridge(800))
	_fresh(d1, _bridge(1100))
	_arm(me)
	var head := d1.global_position + Vector2(0, -26)
	world.hud._hit_head = true
	world._server_fire(me, Weapons.ENFORCER, false, me.muzzle(), head - me.muzzle())
	_check("headshot: enforcer head hit is not a headshot", d1.health == 100 - 15 and not world.hud._hit_head,
			"h=%d head=%s" % [d1.health, world.hud._hit_head])
	_fresh(d1, _bridge(1100))
	world.hud._hit_head = true
	world._server_fire(me, Weapons.SNIPER, true, me.muzzle(), head - me.muzzle())
	_check("headshot: ghost bullet (x1.0) never headshots", d1.health == 70 and not world.hud._hit_head,
			"h=%d head=%s" % [d1.health, world.hud._hit_head])
	_fresh(d1, _bridge(1100))
	d1.health = 1000
	world.hud._hit_head = false
	world._server_fire(me, Weapons.SNIPER, false, me.muzzle(), head - me.muzzle())
	_check("headshot: sniper head hit flags + multiplies", world.hud._hit_head and d1.health == 1000 - roundi(65 * 2.2),
			"h=%d head=%s" % [d1.health, world.hud._hit_head])
	await _real(0.15)                       # let any hitstop settle

	# 9. Auto-switch after the last Redeemer shot.
	_fresh(me, _bridge(800))
	_fresh(d1, _bridge(1300))
	_arm(me)
	me.health = 5000
	me.ammo[Weapons.REDEEMER] = 1
	me.weapon = Weapons.REDEEMER
	me.aim = 0.0
	me._fire_cd = 0.0
	me.in_fire = true
	await _frames(2)
	me.in_fire = false
	_check("auto-switch: last redeemer shot switches to best weapon", me.ammo[Weapons.REDEEMER] == 0
			and me.weapon == me.best_weapon() and me.weapon != Weapons.REDEEMER,
			"ammo=%d weapon=%d best=%d" % [me.ammo[Weapons.REDEEMER], me.weapon, me.best_weapon()])
	await _frames(120)                      # nuke flies, detonates; victims respawn
	await _frames(int(World.RESPAWN_TIME * 60) + 10)

	# 13. bot brain: freed target cleared; in_jump_held reset each tick.
	var b := BotBrain.new(BotBrain.Skill.VETERAN)
	_fresh(d1, _bridge(900))
	d1.brain = null                          # we tick it by hand
	b.update(d1, 1.0 / 60.0)
	b.target = d2
	b.target_visible = true
	b._was_engaged = true
	world.apply_event(World.Ev.LEAVE, [d2.eid])
	await _frames(2)
	_check("brain: target freed by leave (setup)", not is_instance_valid(b.target))
	var intent: Variant = b.intent()
	_check("brain: intent() survives a freed target", typeof(intent) == TYPE_STRING, "got %s" % type_string(typeof(intent)))
	var rp: Variant = b.reaction_progress()
	_check("brain: reaction_progress() survives a freed target", typeof(rp) == TYPE_FLOAT and rp >= 0.0 and rp <= 1.0, str(rp))
	b._think_t = 999.0                       # no re-perceive this tick: it could legitimately pick a new target
	b.update(d1, 1.0 / 60.0)
	_check("brain: freed target cleared on next tick", b.target == null and not b.target_visible,
			"target=%s visible=%s" % [b.target, b.target_visible])
	b._think_t = 0.0
	b.update(d1, 1.0 / 60.0)
	_check("brain: re-perceive after a leave picks a live target or none", b.target == null or is_instance_valid(b.target))
	b._think_t = 999.0
	b._path = PackedInt64Array()
	b._path_i = 0
	b._goal = -1
	b._was_engaged = false
	b.target = null
	b._jump_hold = -1.0
	d1.in_jump_held = true
	b.update(d1, 1.0 / 60.0)
	_check("brain: in_jump_held resets each tick", not d1.in_jump_held)
	b._jump_hold = 0.2
	b.update(d1, 1.0 / 60.0)
	_check("brain: in_jump_held held while jump_hold runs", d1.in_jump_held)

	# 14. hitstop on a local kill offline.
	await _real(0.1)
	_fresh(me, _bridge(800))
	_fresh(d1, _bridge(1100))
	Engine.time_scale = 1.0
	world.damage(d1, 1000.0, me.eid, Weapons.ENFORCER, Vector2.ZERO, d1.global_position)
	var ts := Engine.time_scale
	_check("hitstop: local kill offline slows time", not d1.alive and ts < 1.0, "ts=%.2f" % ts)
	await _real(0.25)
	_check("hitstop: time returns to normal", is_equal_approx(Engine.time_scale, 1.0), "ts=%.2f" % Engine.time_scale)
	await _frames(int(World.RESPAWN_TIME * 60) + 10)

	# 10. HUD: first blood counts towards the spree; sounds play in a real match.
	var hud := world.hud
	Announcer.log.clear()
	hud._first_blood = false
	hud._spree = 0
	hud._multi = 0
	hud._msg_t = 0.0
	hud.on_death(-1, world.my_eid, Weapons.ENFORCER)
	_check("hud: first blood message", hud._msg == "FIRST BLOOD" and hud._spree == 1, "msg=%s spree=%d" % [hud._msg, hud._spree])
	for i in 3:
		hud.on_death(-1, world.my_eid, Weapons.ENFORCER)
	hud._msg_t = 0.0
	Sfx.muted = false
	var ui0 := Sfx._next_ui
	hud.on_death(-1, world.my_eid, Weapons.ENFORCER)
	var played := Sfx._next_ui != ui0
	Sfx.muted = true
	_check("hud: first blood counts towards the spree (5th frag = KILLING SPREE)", hud._msg == "KILLING SPREE" and hud._spree == 5,
			"msg=%s spree=%d" % [hud._msg, hud._spree])
	_check("hud: frag sound plays in a real match (control)", played)
	_check("hud: announcer lines requested in a real match (control)", not Announcer.log.is_empty(), str(Announcer.log))
	hud.on_death(-1, 987654, Weapons.ENFORCER)
	_check("hud: unknown killer in feed doesn't crash", hud._feed.size() > 0)

	# 18. FpsCounter auto-quality guard.
	await _fps_guard_checks()

	# 11. X-Ray exists offline and toggles with the action.
	_check("xray: exists offline", world.xray != null and is_instance_valid(world.xray))
	if world.xray:
		XRay.enabled = false
		world.xray._apply()
		_check("xray: hidden by default", not world.xray.visible)
		world.xray._unhandled_input(_action("xray"))
		_check("xray: action shows it", XRay.enabled and world.xray.visible and not world.xray._segments.is_empty())
		await _frames(3)
		world.xray._unhandled_input(_action("xray"))
		_check("xray: action hides it", not XRay.enabled and not world.xray.visible)
	var segs := world.get_nav().segments_by_type()
	var even := segs.size() == NavGraph.Link.size()
	var total := 0
	for s in segs:
		even = even and s.size() % 2 == 0
		total += s.size()
	_check("xray: segments_by_type gives 6 even-length arrays", even and segs.size() == 6 and total > 0,
			"n=%d sizes=%s" % [segs.size(), str(segs.map(func(s: PackedVector2Array) -> int: return s.size()))])

	# 2 + 8 + 10 + 14. Time limit with a tie: DRAW, freeze, finale slow-mo, delayed focus.
	for eid in world.roster:
		world.roster[eid].kills = 0
	world.roster[World.LOCAL_EID].kills = 2
	world.roster[-1].kills = 2
	_fresh(me, _bridge(800) + Vector2(0, -160))           # mid-air: gravity must still apply after END
	_fresh(d3, _bridge(1400))
	d3.brain = BotBrain.new(BotBrain.Skill.VETERAN)
	_arm(me)
	me.weapon = Weapons.MINIGUN
	await _frames(1)
	world.time_limit = 60.0
	world.clock = World.COUNTDOWN + world.time_limit + 1.0
	me.in_move = 1.0
	me.in_fire = true
	var y0 := me.global_position.y
	var ammo0 := me.ammo[Weapons.MINIGUN]
	await _frames(1)
	var again: Button = _again_button(hud)
	_check("end: tie at the time limit ends with winner 0", world.ended and world._winner_eid == 0, "ended=%s w=%d" % [world.ended, world._winner_eid])
	_check("end: show_end(0) says DRAW", hud._msg == "DRAW" and hud._results.visible, "msg=%s" % hud._msg)
	_check("end: Play again not focused immediately", not again.has_focus())
	_check("finale: END offline starts slow-mo", Engine.time_scale < 1.0, "ts=%.2f" % Engine.time_scale)
	await _frames(20)
	_check("freeze: local inputs cleared after END", me.in_move == 0.0 and not me.in_fire and me.ammo[Weapons.MINIGUN] == ammo0,
			"move=%.1f fire=%s ammo=%d->%d" % [me.in_move, me.in_fire, ammo0, me.ammo[Weapons.MINIGUN]])
	_check("freeze: gravity still applies after END", me.global_position.y > y0 + 4.0, "dy=%.1f" % (me.global_position.y - y0))
	_check("freeze: bot inputs cleared after END", d3.in_move == 0.0 and not d3.in_fire and not d3.in_jump_held)
	await _real(2.8)
	_check("finale: slow-mo returns to 1.0", is_equal_approx(Engine.time_scale, 1.0), "ts=%.2f" % Engine.time_scale)
	if again.is_visible_in_tree():
		_check("end: Play again focused after the delay", again.has_focus())
	else:
		_skip("end: Play again focused after the delay", "button not visible in tree (headless)")


## "Play again" on the results screen (survives the HUD's results-panel refactor).
func _again_button(hud: Hud) -> Button:
	var b: Variant = hud.get("_res_again")
	if b is Button:
		return b
	return hud._results.get_child(0).get_child(0)


func _fps_guard_checks() -> void:
	var fc := FpsCounter.new()
	fc._headless = false                    # the guard skips headless runs; drive it directly here
	get_parent().add_child(fc)
	await _frames(1)
	Settings.auto_quality = true
	Settings.quality = 1
	world.hud._msg = ""
	world.hud._msg_t = 0.0
	for i in 150:                            # 1.5 s of smooth 10 ms frames
		fc._last_usec = Time.get_ticks_usec() - 10000
		fc._guard()
	_check("fps guard: smooth frames keep quality", Settings.quality == 1, "q=%d" % Settings.quality)
	for i in 150:                            # 4.5 s of 30 ms frames (all slow)
		fc._last_usec = Time.get_ticks_usec() - 30000
		fc._guard()
	_check("fps guard: slow frames drop quality to 0", Settings.quality == 0, "q=%d" % Settings.quality)
	_check("fps guard: says so on the HUD", world.hud._msg == "Low quality on", "msg=%s" % world.hud._msg)
	world.hud._msg = ""
	world.hud._msg_t = 0.0
	for i in 150:
		fc._last_usec = Time.get_ticks_usec() - 30000
		fc._guard()
	_check("fps guard: only once", Settings.quality == 0 and world.hud._msg == "", "msg=%s" % world.hud._msg)
	Settings.quality = 1
	Settings.auto_quality = false
	for i in 150:
		fc._last_usec = Time.get_ticks_usec() - 30000
		fc._guard()
	_check("fps guard: off when auto_quality is off", Settings.quality == 1)
	Settings.quality = int(_saved.quality)
	fc.queue_free()


# --- 12 + 14. nav cache across worlds; leaving a world resets time_scale ----------------------

func _nav_cache_and_exit_checks() -> void:
	var nav_a := world.get_nav()
	var old := world
	Engine.time_scale = 0.3
	await _load(0)
	_check("exit: leaving a world resets time_scale", is_equal_approx(Engine.time_scale, 1.0), "ts=%.2f" % Engine.time_scale)
	var nav_b := world.get_nav()
	_check("nav cache: same map reuses the NavGraph", world != old and is_same(nav_a, nav_b))
	_check("nav cache: graph points at the new level", nav_b.level == world.level and is_instance_valid(nav_b.level))


# --- 10 + 11 + 14. menu background (demo) match ---------------------------------------------

func _demo_checks() -> void:
	var main := get_parent()
	main.show_menu()
	world = main.world
	await _frames(150)
	_check("demo: menu world is a demo", world.demo)
	_check("demo: xray exists offline (menu)", world.xray != null)
	var fresh := BotBrain.new()
	_check("brain: fresh intent() is empty", fresh.intent() == "")
	_check("brain: fresh path_ahead() is empty", fresh.path_ahead().is_empty())
	_check("brain: fresh reaction_progress() is 0", fresh.reaction_progress() == 0.0)
	var bounds := Rect2(Vector2.ZERO, world.level.size_px).grow(Level.T)
	var sane := true
	var with_intent := 0
	var detail := ""
	for e: Player in world.entities.values():
		if not (e.brain is BotBrain):
			continue
		var bb: BotBrain = e.brain
		var it: Variant = bb.intent()
		var pa: PackedVector2Array = bb.path_ahead()
		var rp: float = bb.reaction_progress()
		if typeof(it) != TYPE_STRING or rp < 0.0 or rp > 1.0:
			sane = false
			detail += "%s: intent=%s rp=%.2f; " % [e.display_name, str(it), rp]
		for p in pa:
			if not p.is_finite() or not bounds.has_point(p):
				sane = false
				detail += "%s: path point %s; " % [e.display_name, p]
				break
		if typeof(it) == TYPE_STRING and it != "":
			with_intent += 1
	_check("brain: intent/path_ahead/reaction_progress sane after play", sane, detail)
	_check("brain: bots report an intent after play", with_intent > 0, str(with_intent))
	XRay.enabled = true
	world.xray._apply()
	await _frames(10)
	_check("xray: overlay runs on a live bot match", world.xray.visible)
	XRay.enabled = false
	world.xray._apply()

	Sfx.muted = false
	Announcer.log.clear()
	var ui0 := Sfx._next_ui
	world.hud._first_blood = false
	world.hud.on_death(-1, world.my_eid, Weapons.ENFORCER)
	world.hud.hit_marker(true)
	var played := Sfx._next_ui != ui0
	Sfx.muted = true
	_check("demo: no HUD sounds in the menu match", not played)

	var victim: Player = null
	for e: Player in world.alive_players():
		if e.eid != world.my_eid:
			victim = e
	if victim:
		Engine.time_scale = 1.0
		world.damage(victim, 1000.0, world.my_eid, Weapons.ENFORCER, Vector2.ZERO, victim.global_position, false, true)
		_check("demo: no hitstop in the menu match", is_equal_approx(Engine.time_scale, 1.0), "ts=%.2f" % Engine.time_scale)
	world.apply_event(World.Ev.END, [0])
	_check("demo: no finale slow-mo in the menu match", is_equal_approx(Engine.time_scale, 1.0), "ts=%.2f" % Engine.time_scale)
	_check("demo: no announcer lines in the menu match", Announcer.log.is_empty(), str(Announcer.log))
	await _frames(2)


# --- 1 + 11 + 14. LAN host world (no peers actually connected) ----------------------------

func _host_checks() -> void:
	var main := get_parent()
	main._clear()
	var w: World = main._new_world()
	w.net_role = Net.Role.HOST
	w.my_eid = World.LOCAL_EID
	w.setup(Maps.LIST[0], 1)
	w.countdown = 0.0
	w.frag_limit = 0
	main.world = w
	world = w
	w.local_player.mode = Player.Mode.BOT
	for e: Player in w.entities.values():
		e.brain = null
	await _frames(30)
	_check("host: no xray in LAN", w.xray == null)
	var n0 := w.alive_players().size()
	var pid := 77
	w.host_add_peer(pid, {"name": "Peer", "look": Settings.look()})
	_check("host: added peer is in entities, not yet alive", w.entities.has(pid) and w.roster.has(pid)
			and w.alive_players().size() == n0)
	await _frames(80)
	_check("host: peer spawns into the alive cache", w.alive_players().size() == n0 + 1 and w.alive_players().has(w.entities.get(pid)),
			"%d vs %d" % [w.alive_players().size(), n0 + 1])
	var peer: Player = w.entities.get(pid)
	var held := w.alive_players()
	w.host_remove_peer(pid)
	_check("host: removed peer leaves the alive cache", not w.entities.has(pid) and w.alive_players().size() == n0
			and not w.alive_players().has(peer), str(w.alive_players().size()))
	_check("host: old alive array still valid after leave", held.size() == n0 + 1)
	var victim: Player = w.entities[-1]
	_fresh(victim, _bridge(1100))
	Engine.time_scale = 1.0
	w.damage(victim, 1000.0, w.my_eid, Weapons.ENFORCER, Vector2.ZERO, victim.global_position)
	_check("host: no hitstop in LAN", not victim.alive and is_equal_approx(Engine.time_scale, 1.0), "ts=%.2f" % Engine.time_scale)
	w._end_match(w.my_eid)
	_check("host: no finale slow-mo in LAN", w.ended and is_equal_approx(Engine.time_scale, 1.0), "ts=%.2f" % Engine.time_scale)
	await _frames(2)


# --- 1 + 15. training room ---------------------------------------------------------------------

func _training_checks() -> void:
	var main := get_parent()
	main.start_training()
	world = main.world
	await _frames(20)
	var n0 := world.alive_players().size()
	world.spawn_dummy()
	await _frames(3)
	_check("training: spawned dummy joins the alive cache", world.alive_players().size() == n0 + 1, "%d vs %d" % [world.alive_players().size(), n0 + 1])
	var held := world.alive_players()
	world.clear_dummies()
	_check("training: removed dummies leave the alive cache", world.alive_players().size() == n0 and held.size() == n0 + 1)
	await _frames(2)

	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_mouse_ok = Input.mouse_mode == Input.MOUSE_MODE_HIDDEN
	if not _mouse_ok:
		_skip("training: mouse mode checks", "display server ignores mouse_mode (headless)")
	var panel: TrainingPanel = null
	for c in world.get_children():
		if c is TrainingPanel:
			panel = c
	_check("training: panel exists", panel != null)
	if panel == null:
		return
	var hud := world.hud
	var hidden := Input.MOUSE_MODE_HIDDEN
	var shown := Input.MOUSE_MODE_VISIBLE
	panel._unhandled_input(_action("training"))
	_state("panel open", true, true, shown)
	hud._toggle_pause()
	_state("panel open + paused", true, true, shown)
	panel._unhandled_input(_action("training"))
	_check("training: T ignored while paused", world.panel_open)
	hud._toggle_pause()
	_state("panel open + resumed", true, true, shown)
	panel._unhandled_input(_action("training"))
	_state("panel closed", false, false, hidden)
	hud._toggle_pause()
	_state("paused, no panel", false, true, shown)
	hud._toggle_pause()
	_state("resumed, no panel", false, false, hidden)
	await _frames(2)


func _state(label: String, panel_open: bool, blocked: bool, mouse: int) -> void:
	var ok := world.panel_open == panel_open and world.input_blocked == blocked
	if _mouse_ok:
		ok = ok and Input.mouse_mode == mouse
	_check("training: %s -> input %s" % [label, "blocked" if blocked else "live"], ok,
			"panel=%s blocked=%s mouse=%d paused=%s" % [world.panel_open, world.input_blocked, Input.mouse_mode, world.paused])


func _done() -> void:
	XRay.enabled = false
	Engine.time_scale = 1.0
	get_tree().paused = false
	Settings.auto_quality = bool(_saved.auto_quality)
	Settings.announcer = bool(_saved.announcer)
	Settings.quality = int(_saved.quality)
	if _had_file:
		var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.close()
	elif FileAccess.file_exists(Settings.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
	print("DONE fails=%d" % fails)
	get_tree().quit(1 if fails else 0)
