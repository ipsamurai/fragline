extends Node
## Dev tool (excluded from exports): headless checks of the gameplay sound hooks
## (equip, flak pump, low-ammo latch, falling wind loop, rocket engine loop cap, headshot/kill).
## Run: godot --headless --path . -- --test=sfx_hooks
## Sounds that aren't on disk yet are skipped by Sfx, so checks on loop nodes adapt to that.

var world: World
var fails := 0


func _ready() -> void:
	_run.call_deferred()


func _check(name: String, ok: bool, detail := "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("" if ok else "   " + detail))
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _arm(p: Player) -> void:
	for w in Weapons.COUNT:
		p.owned |= 1 << w
		p.ammo[w] = maxi(Weapons.max_ammo(w), 1)


static func _exists(n: String) -> bool:
	return ResourceLoader.exists("res://assets/audio/%s.ogg" % n) \
			or ResourceLoader.exists("res://assets/audio/%s.wav" % n)


func _run() -> void:
	get_parent()._load_map(0)
	world = get_parent().world
	world.local_player.mode = Player.Mode.BOT        # no keyboard/mouse in tests
	for e: Player in world.entities.values():
		e.brain = null
	await _frames(30)
	Sfx.muted = false                                # loop nodes are only created when unmuted
	Sfx.world_muted = false
	var me := world.local_player
	var bot: Player = world.entities[-1]
	_arm(me)
	_arm(bot)
	me.protect_time = 0.0

	# --- equip sounds ---------------------------------------------------------------------
	me.mode = Player.Mode.LOCAL
	me.select_weapon(Weapons.FLAK)
	_check("local select_weapon switches", me.weapon == Weapons.FLAK, "weapon=%d" % me.weapon)
	_check("equip names cached per weapon", Player._equip_names.size() == Weapons.COUNT,
			str(Player._equip_names))
	var names_ok := true
	for w in Weapons.COUNT:
		var want := ("equip_%d" % w) if _exists("equip_%d" % w) else "weapon_switch"
		names_ok = names_ok and Player._equip_names[w] == want
	_check("equip_N used when present, weapon_switch fallback", names_ok, str(Player._equip_names))
	bot.select_weapon(Weapons.ROCKET)
	bot.select_weapon(Weapons.SHOCK)                 # second switch inside the rate limit: no error
	_check("bot select_weapon switches", bot.weapon == Weapons.SHOCK, "weapon=%d" % bot.weapon)

	# --- low-ammo latch (local only, once per crossing) -----------------------------------
	me.select_weapon(Weapons.ROCKET)                 # max 30 -> warn at <= 6
	me.ammo[Weapons.ROCKET] = 10
	me._after_fire_audio(false)
	_check("no low-ammo above 20%", not me._low_ammo_latched)
	me.ammo[Weapons.ROCKET] = 6
	me._after_fire_audio(false)
	_check("low-ammo latches on crossing", me._low_ammo_latched)
	me.ammo[Weapons.ROCKET] = 5
	me._after_fire_audio(false)
	_check("low-ammo stays latched (no spam)", me._low_ammo_latched)
	me.ammo[Weapons.ROCKET] = 30
	me._after_fire_audio(false)
	_check("low-ammo re-arms after refill", not me._low_ammo_latched)
	me.ammo[Weapons.GRENADE] = 1
	me.select_weapon(Weapons.GRENADE)
	_check("switching to a low weapon latches silently", me._low_ammo_latched)
	bot._low_ammo_latched = false
	bot.select_weapon(Weapons.ROCKET)
	bot.ammo[Weapons.ROCKET] = 3
	bot._after_fire_audio(false)
	_check("bots never warn about low ammo", not bot._low_ammo_latched)

	# --- flak pump --------------------------------------------------------------------------
	bot.select_weapon(Weapons.FLAK)
	bot._pump_t = 0.0
	bot._after_fire_audio(true)
	_check("flak alt fire: no pump", bot._pump_t == 0.0)
	bot._after_fire_audio(false)
	_check("flak primary schedules pump", is_equal_approx(bot._pump_t, Player.PUMP_DELAY), str(bot._pump_t))
	bot._audio_tick(0.4)
	_check("flak pump fires after delay", bot._pump_t <= 0.0, str(bot._pump_t))

	# --- falling wind loop (local only) -------------------------------------------------------
	me.mode = Player.Mode.BOT
	me.teleport(Vector2(800, 13 * Level.T - Player.HALF.y - 220))   # in the air above Deck-17's bridge
	await _frames(2)
	me.mode = Player.Mode.LOCAL
	var airborne := not me.is_on_floor()
	_check("test setup: airborne", airborne)
	var has_loop := _exists("fall_loop")
	me.velocity.y = 1100.0
	me._audio_tick(0.2)
	_check("fall wind fades in while falling fast", me._fall_k > 0.0, str(me._fall_k))
	if has_loop:
		_check("fall wind loop node created", is_instance_valid(me._fall_snd) and me._fall_snd.playing)
	else:
		print("SKIP  fall_loop file not present yet (loop node check)")
	var snd := me._fall_snd
	me.alive = false                                 # dying cuts it at once
	me._audio_tick(0.016)
	me.alive = true
	_check("fall wind freed on death", me._fall_snd == null and me._fall_k == 0.0)
	if snd:
		_check("fall wind node queued for free", snd.is_queued_for_deletion())
	me.velocity.y = 1100.0
	me._audio_tick(0.2)
	me.velocity.y = 100.0                            # slowed (e.g. jump pad / landing): fades out
	me._audio_tick(0.5)
	_check("fall wind fades out when slow", me._fall_snd == null and me._fall_k == 0.0, str(me._fall_k))
	me.velocity.y = 1100.0
	bot._audio_tick(0.2)
	_check("bots never get a fall wind loop", bot._fall_snd == null and bot._fall_k == 0.0)
	me.mode = Player.Mode.BOT

	# --- rocket engine loops: capped ----------------------------------------------------------
	var projs: Projectiles = world.projectiles
	var spawned: Array = []
	for i in 7:
		spawned.append(projs.spawn("rocket", Vector2(2000, 60), Vector2(1, 0), me.eid, Weapons.ROCKET))
	var with_sound := 0
	for p in spawned:
		if p.sound:
			with_sound += 1
	_check("rocket loops capped", with_sound <= Projectiles.MAX_ROCKET_LOOPS and with_sound == projs._rocket_loops,
			"with_sound=%d count=%d" % [with_sound, projs._rocket_loops])
	if _exists("rocket_loop"):
		_check("rocket loops created up to the cap", with_sound == Projectiles.MAX_ROCKET_LOOPS, str(with_sound))
	for p in spawned:
		projs.remove(p)
	_check("rocket loop count returns to zero", projs._rocket_loops == 0, str(projs._rocket_loops))

	# --- headshot + kill confirm event paths run cleanly ------------------------------------
	bot.protect_time = 0.0
	bot.health = 100
	bot.armor = 0
	bot.teleport(Vector2(900, 13 * Level.T - Player.HALF.y - 1))   # out of the spawn room
	world.damage(bot, 300.0, me.eid, Weapons.SNIPER, Vector2.ZERO, bot.global_position + Vector2(0, -20), true, true)
	_check("headshot frag event path ran", not bot.alive)

	Sfx.muted = true
	print("DONE fails=%d" % fails)
	get_tree().quit(1 if fails else 0)
