extends Node
## Dev tool (excluded from exports): headless checks of the announcer's line logic: countdown,
## kill callouts, lead changes, frags remaining and time warnings each fire exactly once.
## Lines are read back from Announcer.log (recorded on every platform; speech is web only).
## Run: godot --headless --path . -- --test=announcer

var world: World
var hud: Hud
var fails := 0


func _ready() -> void:
	Sfx.muted = true
	_run.call_deferred()


func _check(name: String, ok: bool, detail := "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("" if ok else "   " + detail))
	if not ok:
		fails += 1


func _said(line: String, times: int, name: String) -> void:
	var n := Announcer.count(line)
	_check(name, n == times, "\"%s\" said %d times, expected %d; log=%s" % [line, n, times, str(Announcer.log)])


## Mimics World._kill's roster bookkeeping, then hands the frag to the HUD like Ev.DIED does.
func _frag(victim: int, killer: int, wid := Weapons.SHOCK) -> void:
	world.roster[victim].deaths += 1
	if killer == victim:
		world.roster[victim].kills -= 1
	else:
		world.roster[killer].kills += 1
	hud.on_death(victim, killer, wid)


func _run() -> void:
	get_parent()._load_map(0)
	world = get_parent().world
	hud = world.hud
	world.local_player.mode = Player.Mode.BOT
	for e: Player in world.entities.values():
		e.brain = null
	await get_tree().physics_frame
	var me := world.my_eid
	var others: Array = []
	for eid in world.roster:
		if eid != me:
			others.append(eid)
	_check("roster has 2+ opponents", others.size() >= 2)
	var a: int = others[0]
	var b: int = others[1]

	# --- pre-match countdown ---
	Announcer.log.clear()
	world.countdown = World.COUNTDOWN
	var guard := 0
	while world.countdown > 0.0 and guard < 600:
		guard += 1
		await get_tree().physics_frame
	await get_tree().physics_frame
	_said("Three", 1, "countdown: Three")
	_said("Two", 1, "countdown: Two")
	_said("One", 1, "countdown: One")
	_said("Fight!", 1, "countdown: Fight!")
	_check("countdown: order", Announcer.log.slice(0, 4) == ["Three", "Two", "One", "Fight!"], str(Announcer.log))
	_check("countdown: FIGHT drawn big", hud._msg == "FIGHT!" and hud._msg_size == Hud.MSG_SIZE[3])

	# --- callouts + lead changes ---
	for eid in world.roster:
		world.roster[eid].kills = 0
		world.roster[eid].deaths = 0
	world.frag_limit = 10
	Announcer.log.clear()
	_frag(a, me)                                         # 1-0-0
	_said("First blood!", 1, "first blood")
	_said("You have taken the lead!", 1, "lead: taken on first frag")
	_check("first blood headline", hud._msg == "FIRST BLOOD", hud._msg)
	_frag(b, a)                                          # me 1, a 1
	_said("Tied for the lead!", 1, "lead: tied")
	_frag(me, a)                                         # a 2
	_said("You have lost the lead!", 1, "lead: lost")
	_frag(a, b)
	_frag(a, b)                                          # b 2, still behind: nothing new
	_said("You have taken the lead!", 1, "lead: no repeat while behind")
	_said("Tied for the lead!", 1, "lead: no tie call while behind")
	_said("You have lost the lead!", 1, "lead: no repeat lost")
	_frag(a, me)
	_frag(b, me)                                         # me 3 vs 2: back in front, double kill
	_said("You have taken the lead!", 2, "lead: retaken")
	_said("Double kill!", 1, "multi: double kill")
	_check("double kill headline shakes", hud._msg == "DOUBLE KILL" and hud._msg_shake > 0.0, hud._msg)
	_check("lead change on the sub-line", "LEAD" in hud._msg_sub, hud._msg_sub)
	_check("bots' frags don't announce kills", Announcer.count("Killing spree!") == 0)

	# --- headshot / humiliation ---
	hud._multi = 0
	hud._last_kill = -100.0
	hud.note_headshot(a, me)
	_frag(a, me, Weapons.SNIPER)
	_said("Headshot!", 1, "headshot (noted by Ev.HIT)")
	hud._head_at[a] = -100.0
	hud._hit_t = 0.0
	hud._last_kill = -100.0
	_frag(a, me, Weapons.SNIPER)
	_said("Headshot!", 1, "no headshot without the head flag")
	world.roster[b].kills = 5
	hud._last_kill = -100.0
	_frag(b, me, Weapons.ENFORCER)
	_said("Humiliation!", 1, "humiliation: enforcer on a 5+ fragger")

	# --- frags remaining (frag limit 10) ---
	for eid in world.roster:
		world.roster[eid].kills = 0
	world.roster[b].kills = 4
	hud._frag_called.clear()
	Announcer.log.clear()
	_frag(a, b)                                          # b 5
	_said("Five frags remain.", 1, "frags: five remain")
	_frag(a, b)                                          # b 6
	_frag(a, b)                                          # b 7
	_said("Three frags remain.", 1, "frags: three remain")
	_frag(b, b)                                          # suicide: b 6
	_frag(a, b)                                          # b 7 again: no repeat
	_said("Three frags remain.", 1, "frags: three called once")
	_said("Five frags remain.", 1, "frags: five called once")
	_frag(a, b)
	_frag(a, b)                                          # b 9
	_said("One frag remains.", 1, "frags: one remains")

	# --- time warnings (driven directly; World calls time_warnings each physics frame) ---
	world.time_limit = 400.0
	hud._time_prev = -1.0
	Announcer.log.clear()
	var t := 301.0
	while t >= 0.0:
		hud.time_warnings(t)
		t -= 0.25
	_said("Five minutes remain.", 1, "time: five minutes")
	_said("One minute remains.", 1, "time: one minute")
	_said("Thirty seconds remain.", 1, "time: thirty seconds")
	for n in range(1, 11):
		_said(Hud.COUNT_SAY[n], 1, "time: final count %d" % n)
	world.time_limit = 120.0                             # too short for a "five minutes" call
	hud._time_prev = -1.0
	Announcer.log.clear()
	t = 120.0
	while t >= 50.0:
		hud.time_warnings(t)
		t -= 0.25
	_said("Five minutes remain.", 0, "time: no five-minute call in a 2-minute match")
	_said("One minute remains.", 1, "time: one minute (short match)")
	world.time_limit = 0.0

	# --- message priority + demo silence ---
	hud.message("BIG", "", Color.WHITE, 2.0, 3, 3)
	hud.message("small", "", Color.WHITE, 2.0, 1, 0)
	_check("message: lower priority can't replace a callout", hud._msg == "BIG", hud._msg)
	world.demo = true
	Announcer.log.clear()
	hud._last_kill = -100.0
	_frag(a, me)
	_check("demo match: silent", Announcer.log.is_empty(), str(Announcer.log))
	world.demo = false

	print("DONE fails=%d" % fails)
	get_tree().quit(1 if fails else 0)
