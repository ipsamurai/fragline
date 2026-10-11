class_name World
extends Node2D
## One match. Runs the authoritative rules (firing, damage, deaths, pickups, scoring)
## and turns every outcome into an event handled by apply_event(). Offline and on the host
## the rules run here and events are applied directly (the host also broadcasts them).
## On a network client the rules don't run: events and snapshots from the host drive it.

signal restart_requested               # results / pause screen: play the same setup again
signal menu_requested                  # results / pause screen: back to the main menu
signal died(victim_eid: int, killer_eid: int, wid: int)   # every death, as it's applied
signal event_applied(kind: int, args: Array)   # every event, everywhere (MatchStats listens)

enum Ev { SPAWN, DIED, HIT, SHOT, PROJ_END, PICKUP, STATUS, END, JOIN, LEAVE }

const RESPAWN_TIME := 2.5
## Field of view: the most world any player can see, whatever their window shape.
## Keeps ultrawide screens from seeing (and sniping) further than everyone else.
const VIEW_WORLD := Vector2(960, 540)
const HAZARD := -1                     # "weapon" ids for environmental deaths: lava / void,
const LASER := -2                      # laser gates,
const VENT := -3                       # floor vents,
const PURGE := -4                      # and the spawn-room loitering purge
# Spawn rooms (anti spawn-camping): no combat inside, limited time inside.
const SPAWN_GRACE := 8.0               # room time after (re)spawning
const RETURN_GRACE := 3.0              # room time once you've left (returning / invading)
const ZONE_DRAIN := 0.5                # loiter meter drains at this rate outside
const EXIT_SHIELD := 1.5               # protection granted the first time you leave after spawning
const PURGE_BASE := 10                 # purge tick damage: BASE + STEP * n, every Status.TICK
const PURGE_STEP := 6
const LOCAL_EID := 1
const COUNTDOWN := 3.0                 # pre-match 3-2-1: everyone frozen, spawn timers paused
const NET_RATE := 1.0 / 30.0           # snapshots (host) and state updates (client) per second
const SNAP_STRIDE := 10                # floats per entity in a snapshot

var map_def: Dictionary
var training := false                  # training room: no frag limit, configurable dummies
var level: Level
var background: Background
var camera: Camera2D
var fx: Fx
var projectiles: Projectiles
var pickups: Pickups
var traps: Traps
var _nav: NavGraph                     # built on first use (only bots need it)
static var _nav_cache := {}            # map id -> NavGraph (levels are deterministic, so reuse them)
var _alive: Array[Player] = []
var _alive_dirty := true
var hud: Hud
var players_root: Node2D
var gravity_scale := 1.0
var friction := 1.0

var entities := {}                     # eid -> Player
var roster := {}                       # eid -> {name, kills, deaths, bot}
var local_player: Player
var clock := 0.0                       # match time; pauses with the game
var paused := false
var frag_limit := 15
var ended := false
var _winner_eid := 0
var _killer_eid := 0                   # who fragged you last (the death cam follows them)
var _last_death_pos := Vector2.ZERO
var _hitstop_until := 0                # msec (real time) when a kill's hit-pause ends
const FINALE := 2.4                    # real seconds of slow-mo on the match-winning frag
var _finale_t := 0.0
var _finale_pos := Vector2.ZERO
var _base_zoom := 1.0
var xray: XRay
var touch: TouchControls               # phones / tablets: on-screen twin sticks (null on desktop)

var nuke_released := false
# Training-room options (changed from the training panel).
var infinite_ammo := true
var god_mode := false
var dummy_behaviour := DummyBrain.Behaviour.IDLE
var dummy_random_weapon := true
var bot_skill := BotBrain.Skill.REGULAR     # arena bots and the training "Opponent"
var input_blocked := false             # a UI panel is open: ignore gameplay input
var panel_open := false                # training panel showing

var demo := false                      # main-menu background: everyone is a bot, no HUD
var time_limit := 0.0                  # seconds, 0 = no limit (set before setup())
var game_mode := 0                     # GameMode.DEATHMATCH / GUN_GAME / ... (set before setup())
var low_gravity := false               # Low Gravity mutator (set before setup())
var countdown := 0.0
# Networking (set before setup()).
var net_role := 0                      # Net.Role: OFFLINE, HOST or CLIENT
var my_eid := LOCAL_EID                # your entity: 1 offline / host, your peer id on a client
var lobby := {}                        # peer id -> {"name", "look"} of remote humans
var _net_t := 0.0
var _next_fire := {}                   # host: peer id -> earliest time its next shot is allowed
var _decay_acc := 0.0
var _cam_pos := Vector2.ZERO
var _shake := 0.0


func setup(def: Dictionary, dummies: int) -> void:
	_build_scene(def)
	_deal_weapons()
	GameMode.configure(self)
	local_player = _add_player(my_eid, Player.Mode.LOCAL, Settings.look(), Settings.player_name)
	if demo:
		local_player.mode = Player.Mode.BOT
		local_player.brain = BotBrain.new(BotBrain.Skill.VETERAN)
		local_player.display_name = Characters.LIST[Settings.character].name
		roster[my_eid].name = local_player.display_name
	for id in lobby:
		if id != my_eid:
			_add_player(id, Player.Mode.PUPPET, lobby[id].look, lobby[id].name)
	var chars := range(Characters.LIST.size())
	chars.erase(Settings.character)
	chars.shuffle()
	for i in dummies:
		var c: int = chars[i % chars.size()]
		var bot := _add_player(-(i + 1), Player.Mode.BOT, Characters.resolve(c), Characters.LIST[c].name)
		bot.brain = BotBrain.new(bot_skill)
	if training or demo:
		frag_limit = 0
		time_limit = 0.0
	else:
		countdown = COUNTDOWN
	var delay := 0.0
	for e: Player in entities.values():
		e.respawn_at = delay
		delay += 0.15
	_finish_setup()
	if dummies > 0 or demo:
		get_nav()                                    # build now, not on the first bot tick at "FIGHT!"


## Network client: rebuild the host's match from its description (see describe()).
func setup_client(info: Dictionary) -> void:
	net_role = Net.Role.CLIENT
	var def: Dictionary = Maps.LIST[0]
	for d in Maps.LIST:
		if d.id == info.get("map", ""):
			def = d
	frag_limit = int(info.get("frag_limit", 15))
	time_limit = float(info.get("time_limit", 0.0))
	game_mode = GameMode.sanitize(info.get("mode", 0))
	low_gravity = bool(info.get("lowgrav", false))
	_build_scene(def)
	clock = float(info.get("clock", 0.0))
	countdown = float(info.get("countdown", 0.0))
	nuke_released = bool(info.get("nuke", false))
	for row: Array in info.get("players", []):
		var eid: int = row[0]
		var mode := Player.Mode.LOCAL if eid == my_eid else Player.Mode.PUPPET
		var look: Dictionary = Settings.look() if eid == my_eid else Characters.sanitize(row[2])
		var e := _add_player(eid, mode, look, Characters.clean_name(row[1]))
		roster[eid].kills = int(row[5])
		roster[eid].deaths = int(row[6])
		roster[eid].bot = bool(row[7])
		if row[3]:
			e.spawn_at(row[4])
			_alive_dirty = true
			e.protect_time = 0.0
	local_player = entities.get(my_eid)
	var states: Array = info.get("pickups", [])
	for i in mini(states.size(), pickups.items.size()):
		var it: Dictionary = pickups.items[i]
		var st: Array = states[i]
		it.active = st[0]
		it.wid = int(st[1])
		it.respawn_at = clock + float(st[2])
		it.dormant = bool(st[3])
	GameMode.configure(self)
	_finish_setup()
	if info.get("ended", false):                     # joined on the results screen
		apply_event(Ev.END, [int(info.get("winner", 0))])


## Everything needed to join a running match (sent by the host to new clients).
func describe() -> Dictionary:
	var players := []
	for e: Player in entities.values():
		var r: Dictionary = roster[e.eid]
		players.append([e.eid, e.display_name, e.look, e.alive, e.global_position, r.kills, r.deaths, r.bot])
	var states := []
	for it in pickups.items:
		states.append([it.active, it.wid, maxf(0.0, it.respawn_at - clock), it.dormant])
	return {"map": map_def.id, "frag_limit": frag_limit, "time_limit": time_limit, "clock": clock,
			"countdown": countdown, "nuke": nuke_released, "players": players, "pickups": states,
			"ended": ended, "winner": _winner_eid, "mode": game_mode, "lowgrav": low_gravity}


func _build_scene(def: Dictionary) -> void:
	map_def = def
	training = def.get("training", false)
	level = Level.new()
	level.build(def)
	gravity_scale = level.def.gravity
	friction = level.def.friction
	add_child(level)

	background = Background.new()
	add_child(background)
	background.setup(level)

	pickups = Pickups.new()
	pickups.world = self
	pickups.fast = training
	add_child(pickups)
	pickups.setup(level)

	traps = Traps.new()
	add_child(traps)
	traps.setup(self, level)

	players_root = Node2D.new()
	add_child(players_root)

	projectiles = Projectiles.new()
	projectiles.world = self
	projectiles.z_index = 1
	add_child(projectiles)

	fx = Fx.new()
	fx.z_index = 2
	add_child(fx)

	camera = Camera2D.new()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(level.size_px.x)
	camera.limit_bottom = int(level.size_px.y)
	add_child(camera)
	camera.make_current()
	get_viewport().size_changed.connect(_fit_zoom)
	_fit_zoom()


func _finish_setup() -> void:
	_cam_pos = level.spawns[0]
	hud = Hud.new()
	hud.world = self
	add_child(hud)
	hud.visible = not demo
	if not demo:
		add_child(MatchStats.new(self))           # per-player stats for the results screen
	if net_role == Net.Role.OFFLINE:
		xray = XRay.new()
		xray.world = self
		add_child(xray)
	if training:
		var panel := TrainingPanel.new()
		panel.world = self
		add_child(panel)
	if not demo and TouchControls.wanted():
		touch = TouchControls.new()
		touch.world = self
		add_child(touch)
	if not demo:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


## Seconds left in a timed match (0 when untimed).
func time_left() -> float:
	return clampf(time_limit - (clock - COUNTDOWN), 0.0, time_limit) if time_limit > 0.0 else 0.0


func in_countdown() -> bool:
	return countdown > 0.0


## True where the rules run (offline, or the host). Clients only mirror the host.
func is_authority() -> bool:
	return net_role != Net.Role.CLIENT


func is_net_client() -> bool:
	return net_role == Net.Role.CLIENT


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false


func _add_player(eid: int, mode: Player.Mode, look: Dictionary, pname: String) -> Player:
	var p := Player.new()
	p.setup(self, eid, mode, look, pname)
	players_root.add_child(p)
	entities[eid] = p
	_alive_dirty = true
	roster[eid] = {"name": pname, "kills": 0, "deaths": 0, "bot": mode == Player.Mode.BOT}
	return p


## Random weapon slots: every match deals all standard weapons (Flak..Sniper) across the
## slots in random order, so each weapon appears somewhere but never in the same place twice.
func _deal_weapons() -> void:
	var deck: Array[int] = []
	for it in pickups.items:
		if it.get("random", false):
			if deck.is_empty():
				deck = _standard_weapons()
				deck.shuffle()
			it.wid = deck.pop_back()
			it.wait = pickups.respawn_time(it)


func _standard_weapons() -> Array[int]:
	var out: Array[int] = []
	for w in range(Weapons.FLAK, Weapons.REDEEMER):
		out.append(w)
	return out


## When a random slot respawns it re-rolls, preferring a weapon not already lying around.
func _reroll(it: Dictionary) -> int:
	var lying := {}
	for other in pickups.items:
		if other.active and other.type == "w":
			lying[other.wid] = true
	var choices := _standard_weapons().filter(func(w: int) -> bool: return not lying.has(w))
	if choices.is_empty():
		choices = _standard_weapons()
	return choices.pick_random()


## 0..1 — how far the round is: the leader's frags against the limit, or time elapsed.
func round_progress() -> float:
	var p := 0.0
	if frag_limit > 0:
		p = float(roster[_leader()].kills) / frag_limit
	if time_limit > 0.0:
		p = maxf(p, 1.0 - time_left() / time_limit)
	return p


## Outright leader by frags, or 0 when the top score is shared (a draw).
func _winner() -> int:
	var best := -1000000
	var who := 0
	var shared := false
	for eid in roster:
		var k: int = roster[eid].kills
		if k > best:
			best = k
			who = eid
			shared = false
		elif k == best:
			shared = true
	return 0 if shared else who


func _leader() -> int:
	var best := my_eid
	for eid in roster:
		if roster[eid].kills > roster[best].kills:
			best = eid
	return best


# --- training room ------------------------------------------------------------------

const MAX_DUMMIES := 6


func dummy_count() -> int:
	var n := 0
	for e: Player in entities.values():
		if e.mode == Player.Mode.BOT:
			n += 1
	return n


func spawn_dummy() -> void:
	if dummy_count() >= MAX_DUMMIES:
		return
	var eid := -1
	while entities.has(eid):
		eid -= 1
	var p := _add_player(eid, Player.Mode.BOT, Characters.resolve(randi() % Characters.LIST.size()), "Dummy %d" % -eid)
	p.brain = _dummy_brain()
	p.respawn_at = clock


## "Opponent" dummies get the real bot AI; the other behaviours use the simple DummyBrain.
func _dummy_brain() -> RefCounted:
	if dummy_behaviour == DummyBrain.Behaviour.OPPONENT:
		return BotBrain.new(bot_skill)
	var b := DummyBrain.new()
	b.behaviour = dummy_behaviour
	return b


func clear_dummies() -> void:
	for eid in entities.keys():
		if entities[eid].mode == Player.Mode.BOT:
			entities[eid].queue_free()
			entities.erase(eid)
			_alive_dirty = true
			roster.erase(eid)


func set_dummy_behaviour(b: DummyBrain.Behaviour) -> void:
	dummy_behaviour = b
	for e: Player in entities.values():
		if e.mode == Player.Mode.BOT:
			e.brain = _dummy_brain()


func set_bot_skill(s: BotBrain.Skill) -> void:
	bot_skill = s
	if training:
		set_dummy_behaviour(dummy_behaviour)


func give_all_weapons(p: Player) -> void:
	for w in Weapons.COUNT:
		p.owned |= 1 << w
		p.ammo[w] = maxi(Weapons.max_ammo(w), p.ammo[w])


## Training dummies spawn holding a random weapon (or just the Enforcer).
func _equip_dummy(e: Player) -> void:
	if not dummy_random_weapon:
		return
	var wid := randi_range(Weapons.FLAK, Weapons.SNIPER)
	e.owned |= 1 << wid
	e.ammo[wid] = Weapons.max_ammo(wid)
	e.weapon = wid


## Living fighters. Cached: rebuilt only after someone spawns, dies, joins or leaves
## (called many times per tick by projectiles, traps, bots and the rules).
## Callers must not modify the returned array.
func alive_players() -> Array[Player]:
	if _alive_dirty:
		_alive_dirty = false
		_alive = []                    # fresh array: loops over the old one stay valid
		for e: Player in entities.values():
			if e.alive:
				_alive.append(e)
	return _alive


func set_paused(on: bool) -> void:
	paused = on
	if net_role == Net.Role.OFFLINE:                  # a networked match keeps running
		get_tree().paused = on
	refresh_input_state()


## Gameplay input and the cursor follow every overlay at once (pause, training panel, results).
func refresh_input_state() -> void:
	input_blocked = paused or panel_open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused or panel_open or ended else Input.MOUSE_MODE_HIDDEN


# --- events ----------------------------------------------------------------------

func _emit(kind: Ev, args: Array) -> void:
	apply_event(kind, args)
	if net_role == Net.Role.HOST:
		Net.s_event.rpc(kind, args)


func apply_event(kind: Ev, a: Array) -> void:
	event_applied.emit(kind, a)               # first: some branches below return early (DoT hits)
	match kind:
		Ev.SPAWN:
			var e: Player = entities.get(a[0])
			if e:
				e.spawn_at(a[1])
				_alive_dirty = true
				GameMode.on_spawn(self, e)
				if training and e.mode == Player.Mode.BOT:
					_equip_dummy(e)
				fx.burst(a[1], e.look.visor, 18, 220.0)
				fx.ring(a[1], 44.0, e.look.visor, 0.4)
				Sfx.play_at("spawn", a[1], -8.0)
		Ev.DIED:
			var victim: Player = entities.get(a[0])
			var pos: Vector2 = a[3]
			if is_net_client() and a.size() > 7:
				if roster.has(a[1]):
					roster[a[1]].kills = a[5]
				if roster.has(a[0]):
					roster[a[0]].kills = a[6]
					roster[a[0]].deaths = a[7]
			if victim:
				victim.die()
				_alive_dirty = true
				fx.gibs(pos, victim.look, a[4])
			_last_death_pos = pos
			if a[0] == my_eid and a[1] != my_eid:
				_killer_eid = a[1]
			elif a[1] == my_eid and a[0] != my_eid and _juice_allowed():
				Engine.time_scale = 0.05                 # hitstop: a 70 ms freeze sells the frag
				_hitstop_until = Time.get_ticks_msec() + 70
			Sfx.play_at("death", pos)
			if a[1] == my_eid and a[0] != my_eid and not demo:   # sfx: you fragged someone
				Sfx.play("kill_confirm", -4.0)                   # sfx
			add_shake(6.0, pos)
			hud.on_death(a[0], a[1], a[2])
			hud.feed_kill(a[1], a[0], a[2], hud._head_by.get(a[0], 0) == a[1] and clock - float(hud._head_at.get(a[0], -1e9)) <= hud.HEAD_WINDOW)
			died.emit(a[0], a[1], a[2])
		Ev.HIT:
			var victim: Player = entities.get(a[0])
			var at: Vector2 = a[2]
			var armored: bool = a[4]
			var dot: int = a[6]                       # status kind for damage-over-time ticks, else -1
			if a[5]:
				hud.note_headshot(a[0], a[3])
			if dot >= 0:
				if a[3] == my_eid and a[0] != my_eid:
					fx.text(at - Vector2(0, 26), str(a[1]), Status.INFO[dot].color)
				if a[0] == my_eid:
					hud.hurt(a[1])
				return
			if victim:
				victim.hurt_flash = 0.12
			var src: Player = entities.get(a[3])
			var away := (at - src.global_position).normalized() if src else Vector2.UP
			fx.body_hit(at, away, victim.look.visor if victim else Color(1, 0.25, 0.35), armored, a[1], a[5])
			Sfx.play_at("hit_armor" if armored else "hit", at, -4.0)
			if a[5]:                                                  # sfx: headshot crack at the victim
				Sfx.play_at("headshot", at, -2.0)                     # sfx
				if a[3] == my_eid and a[0] != my_eid and not demo:    # sfx: and a ping for the shooter
					Sfx.play("headshot", -9.0, 1.15)                  # sfx
			if a[3] == my_eid and a[0] != my_eid:
				hud.hit_marker(a[5])
				fx.text(at - Vector2(0, 26), str(a[1]), Color(1, 0.8, 0.2) if a[5] else Color.WHITE)
			if a[0] == my_eid:
				hud.hurt(a[1])
				add_shake(minf(a[1] * 0.12, 8.0))
		Ev.SHOT:
			var e: Player = entities.get(a[0])
			var wid: int = a[1]
			var st := Weapons.stats(wid, a[2])
			var origin: Vector2 = a[3]
			var color: Color = Weapons.LIST[wid].color
			if e:
				e.pose.flash = 0.06
			var beam: String = st.get("beam", "")
			var aim := Vector2.from_angle(e.aim) if e else Vector2.RIGHT
			if not a[4].is_empty() and origin.distance_squared_to(a[4][0]) > 1.0:
				aim = origin.direction_to(a[4][0])
			elif a.size() > 5 and not a[5].is_empty():
				aim = (a[5][0][3] as Vector2).normalized()
			fx.muzzle_flash(origin, aim, color, wid, a[2])
			fx.casing(origin, aim, wid, a[2])
			# The plasma wave fires 20x/s; only voice some of those shots.
			if beam != "plasma" or randf() < 0.3:
				Sfx.play_at(st.sound, origin, -3.0 if beam != "plasma" else -9.0, 1.0 if beam != "ghost" else 0.7)
			for end: Vector2 in a[4]:
				var back := (origin - end).normalized()
				match beam:
					"shock":
						fx.line(origin, end, color, 9.0, 0.35)
						fx.sparks(end, back, color, 10)
						fx.impact(end, -back, color, Fx.HIT_SHOCK)
					"plasma":
						fx.line(origin, end, color, 7.0, 0.07, true)
						if randf() < 0.4:
							fx.sparks(end, back, color, 2, 160.0)
							fx.impact(end, -back, color, Fx.HIT_PLASMA)
					"ghost":
						fx.line(origin, end, Color(0.75, 0.95, 1.0), 14.0, 0.45)
						fx.tracer(origin, end, Color(0.75, 0.95, 1.0), 6.0, 0.25)
					_:
						var sniper := wid == Weapons.SNIPER
						fx.line(origin, end, color, 5.0 if sniper else 2.5, 0.3 if sniper else 0.09)
						fx.tracer(origin, end, color, 4.0 if sniper else 2.5, 0.16 if sniper else 0.08)
						if sniper:
							fx.vapor(origin, end)
						fx.impact(end, -back, color, Fx.HIT_SNIPER if sniper else Fx.HIT_BULLET)
			if a[0] == my_eid:
				add_shake(st.shake * 0.6)
				add_kick(-aim.rotated(randf_range(-0.3, 0.3)), st.shake * (2.6 if wid == Weapons.SNIPER else 1.5))
			if is_net_client() and a.size() > 5:
				for sp: Array in a[5]:
					projectiles.spawn_visual(sp[0], sp[1], sp[2], sp[3], a[0], wid)
		Ev.PROJ_END:
			var pos: Vector2 = a[0]
			var key: String = a[1]
			if is_net_client() and a.size() > 2:
				projectiles.remove_id(a[2])
			var def: Dictionary = Weapons.PROJ.get(key, {})
			match key:
				"combo":
					fx.explosion(pos, 190.0, Color("b388ff"), Fx.ENERGY)
					Sfx.play_at("combo", pos)
					add_shake(12.0, pos)
					add_kick(_cam_pos - pos, 7.0, pos)
				"redeemer":
					fx.explosion(pos, 420.0, Color.WHITE, Fx.NUKE)
					Sfx.play_at("nuke", pos, 4.0)
					add_shake(28.0, pos)
					add_kick(_cam_pos - pos, 16.0, pos)
					hud.flash(0.8)
				_:
					if def.has("splash") and def.splash >= 100.0:
						fx.explosion(pos, def.splash, def.color)
						Sfx.play_at("explode", pos)
						add_shake(9.0, pos)
						add_kick(_cam_pos - pos, 6.0, pos)
					elif def.has("splash"):
						fx.explosion(pos, def.splash * 1.5, def.color, Fx.ENERGY)
						Sfx.play_at("shock_alt", pos, -2.0, 0.7)
					else:
						fx.pop(pos, def.get("color", Color.WHITE), key == "pulse")
		Ev.STATUS:
			var e: Player = entities.get(a[0])
			if e == null or not e.alive:
				return
			var effect: int = a[1]
			if a[2] <= 0.0:
				e.status.erase(effect)
				return
			var fresh := not e.status.has(effect)
			e.status[effect] = maxf(e.status.get(effect, 0.0), a[2])
			e.status_src[effect] = [a[3], a[4]]
			if fresh:
				fx.burst(e.global_position, Status.INFO[effect].color, 10, 160.0)
				if effect == Status.SHOCK:
					Sfx.play_at("spawn", e.global_position, -6.0, 1.3)
		Ev.PICKUP:
			var it: Dictionary = pickups.items[a[0]]
			it.active = a[1]
			if a.size() > 3 and a[3] >= 0:
				it.wid = a[3]
			if it.active and it.dormant:
				it.dormant = false
				hud.message("THE REDEEMER IS ONLINE", "Find it before someone else does", Color.WHITE, 3.0, 3, 3)
				if not demo:
					Sfx.play("pickup_power", 0.0, 0.6)
				hud._announce("The Redeemer is online!", Announcer.HIGH)
			if not it.active:
				it.wait = pickups.respawn_time(it)
				it.respawn_at = clock + it.wait
				var sound: String = {"h": "pickup_health", "H": "pickup_health", "a": "pickup_armor", "D": "pickup_power"}.get(it.type, "pickup_weapon")
				Sfx.play_at(sound, it.pos, -2.0)
				if a[2] == my_eid:
					hud.pickup_message(it)
			else:
				fx.burst(it.pos, pickups.color_of(it), 8, 120.0)
		Ev.END:
			ended = true
			if _juice_allowed():
				_finale_t = FINALE
				_finale_pos = _last_death_pos
				_hitstop_until = 0
				Engine.time_scale = 0.25
			hud.show_end(a[0])
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Ev.JOIN:
			if not entities.has(a[0]):
				_add_player(a[0], Player.Mode.PUPPET, Characters.sanitize(a[2]), Characters.clean_name(a[1]))
			hud.message("%s joined" % Characters.clean_name(a[1]), "", UiTheme.ACCENT, 1.6)
		Ev.LEAVE:
			var gone: Player = entities.get(a[0])
			if gone:
				hud.message("%s left" % gone.display_name, "", Color(1, 1, 1, 0.8), 1.6)
				gone.queue_free()
				entities.erase(a[0])
				_alive_dirty = true
				roster.erase(a[0])


# --- server rules ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	clock += delta
	_net_t -= delta
	if ended:
		return
	if countdown > 0.0:                               # announcer: "Three… Two… One… FIGHT!"
		var before := ceili(countdown) if countdown < COUNTDOWN else ceili(COUNTDOWN) + 1
		countdown -= delta
		if countdown <= 0.0:
			hud.message("FIGHT!", "", UiTheme.ACCENT, 1.2, 3, 3)
			if not demo:
				Sfx.play("pickup_power", -2.0, 1.2)
			hud._announce("Fight!", Announcer.CRITICAL)
		elif ceili(countdown) < before:
			hud._announce(Hud.COUNT_SAY[ceili(countdown)], Announcer.CRITICAL)
	elif time_limit > 0.0:                            # timed match: 5 min / 1 min / 30 s / 10..1 calls
		hud.time_warnings(time_left())
	if is_net_client():
		_client_tick(delta)
		return
	if net_role == Net.Role.HOST and _net_t <= 0.0:
		_net_t = NET_RATE
		_send_snapshot()
	if countdown <= 0.0 and time_limit > 0.0 and time_left() <= 0.0:
		_end_match(_winner())
		return
	for e: Player in entities.values():
		if not e.alive and clock >= e.respawn_at:
			_emit(Ev.SPAWN, [e.eid, _pick_spawn(e)])
	_check_hazards()
	_release_nuke()
	if countdown <= 0.0:
		_spawn_rules(delta)
	_tick_statuses(delta)
	traps.server_tick()
	_check_pickups()
	# Overheal above 100 decays by 1 per second, like the classics.
	_decay_acc += delta
	if _decay_acc >= 1.0:
		_decay_acc -= 1.0
		for e: Player in entities.values():
			if e.health > 100:
				e.health -= 1


## Inflict a status (refreshes to the longer duration). No effect during spawn protection
## or inside a spawn room.
func apply_status(victim: Player, kind: int, duration: float, source_eid: int, wid: int) -> void:
	if not victim.alive or ended or victim.protect_time > 0.0 or level.zone_at(victim.global_position) >= 0:
		return
	_emit(Ev.STATUS, [victim.eid, kind, duration, source_eid, wid])


## The Redeemer spot wakes up once the round is half over.
func _release_nuke() -> void:
	if nuke_released or round_progress() < 0.5:
		return
	nuke_released = true
	for i in pickups.items.size():
		if pickups.items[i].get("nuke", false):
			_emit(Ev.PICKUP, [i, true, 0, Weapons.REDEEMER])


## Spawn rooms are safe but temporary: a loiter meter fills inside and drains slowly outside.
## Past the allowance (generous right after spawning, short when returning) an escalating
## purge kills within ~3 seconds, so nobody can hide or camp in a spawn room.
func _spawn_rules(delta: float) -> void:
	for e in alive_players():
		var inside := level.zone_at(e.global_position) >= 0
		if inside:
			e.zone_time += delta
		else:
			e.zone_time = maxf(0.0, e.zone_time - ZONE_DRAIN * delta)
			if not e.left_spawn:
				e.left_spawn = true
				e.protect_time = maxf(e.protect_time, EXIT_SHIELD)
		if inside and e.zone_time > zone_allowance(e):
			e.purge_acc += delta
			if e.purge_acc >= Status.TICK:
				e.purge_acc -= Status.TICK
				var credit := e.last_attacker if clock - e.last_hit_time < 4.0 and roster.has(e.last_attacker) else e.eid
				damage(e, PURGE_BASE + PURGE_STEP * e.purge_ticks, credit, PURGE, Vector2.ZERO,
						e.global_position + Vector2(0, -30), false, true, Status.SHOCK)
				e.purge_ticks += 1
		else:
			e.purge_ticks = 0
			e.purge_acc = 0.0


func zone_allowance(e: Player) -> float:
	return RETURN_GRACE if e.left_spawn else SPAWN_GRACE


func _tick_statuses(delta: float) -> void:
	for e in alive_players():
		for kind in [Status.BURN, Status.POISON]:
			if not e.status.has(kind):
				continue
			var acc: float = e.dot_acc.get(kind, 0.0) + delta
			if acc >= Status.TICK:
				acc -= Status.TICK
				var src: Array = e.status_src.get(kind, [e.eid, HAZARD])
				damage(e, Status.INFO[kind].tick_dmg, src[0], src[1], Vector2.ZERO,
						e.global_position + Vector2(0, -30), false, false, kind)
			e.dot_acc[kind] = acc
			if not e.alive:
				break


func request_fire(p: Player, wid: int, alt: bool, origin: Vector2, dir: Vector2) -> void:
	if is_net_client():
		Net.c_fire.rpc_id(1, wid, alt, origin, dir.normalized())
	else:
		_server_fire(p, wid, alt, origin, dir.normalized())


func _server_fire(p: Player, wid: int, alt: bool, origin: Vector2, dir: Vector2) -> void:
	if ended or countdown > 0.0 or not p.alive or not p.owns(wid) or p.in_no_fire_zone() 			or p.has_status(Status.SHOCK):
		return
	var st := Weapons.stats(wid, alt)
	var cost: int = st.get("cost", 1)
	if not Weapons.infinite(wid) and not (training and infinite_ammo):
		if p.ammo[wid] < cost:
			return
		p.ammo[wid] -= cost
	p.protect_time = 0.0
	origin = _safe_origin(p, origin)
	var ends := PackedVector2Array()
	var spawned := []                                  # [id, key, origin, velocity] for clients
	var spread: float = st.get("spread", 0.0)
	for i in int(st.get("pellets", 1)):
		var d := dir.rotated(randf_range(-spread, spread))
		if st.kind == Weapons.Kind.HITSCAN:
			ends.append(_hitscan(p, wid, st, origin, d))
		else:
			var key: String = st.proj
			var pd: Dictionary = Weapons.PROJ[key]
			var speed: float = pd.speed * (1.0 + randf_range(-1.0, 1.0) * pd.get("jitter", 0.0))
			var inherit := p.velocity * 0.2 if pd.get("grav", 0.0) > 0.0 else Vector2.ZERO
			var pr := projectiles.spawn(key, origin, d * speed + inherit, p.eid, wid)
			spawned.append([pr.id, key, origin, pr.vel])
	_emit(Ev.SHOT, [p.eid, wid, alt, origin, ends, spawned])


## Muzzle can poke through a wall when hugging it; pull it back to the near side.
func _safe_origin(p: Player, origin: Vector2) -> Vector2:
	var from := p.global_position + Player.SHOULDER
	var hit := _ray(from, origin)
	return hit.position + (from - origin).normalized() * 3.0 if hit else origin


## Line of fire: blocked by solid tiles, platforms and spawn barriers.
func get_nav() -> NavGraph:
	if _nav == null:
		_nav = _nav_cache.get(map_def.id)
		if _nav == null:
			_nav = NavGraph.new()
			_nav.build(level)
			_nav_cache[map_def.id] = _nav
		else:
			_nav.level = level
	return _nav


func is_enemy(a: Player, b: Player) -> bool:
	return a != b and (a.team == 0 or a.team != b.team)


func line_clear(a: Vector2, b: Vector2) -> bool:
	return _ray(a, b).is_empty()


func _ray(a: Vector2, b: Vector2, mask := Level.SHOT_MASK) -> Dictionary:
	var q := PhysicsRayQueryParameters2D.create(a, b, mask)
	return get_world_2d().direct_space_state.intersect_ray(q)


func _hitscan(p: Player, wid: int, st: Dictionary, origin: Vector2, d: Vector2) -> Vector2:
	var range_px: float = st.get("range", 1500.0)
	var mask := Level.BARRIER_MASK if st.get("through_walls", false) else Level.SHOT_MASK
	var hit := _ray(origin, origin + d * range_px, mask)
	var end: Vector2 = hit.position if hit else origin + d * range_px
	if st.get("beam", "") == "shock":
		var ball := projectiles.ball_on_segment(origin, end, 26.0)
		if ball:
			_combo(ball, p.eid)
			end = ball.pos
	# Everyone the line crosses, nearest first.
	var hits: Array = []
	for e in alive_players():
		if e == p:
			continue
		var t := seg_rect(origin, end, e.hit_rect())
		if t >= 0.0:
			hits.append([t, e])
	if hits.is_empty():
		return end
	hits.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	if not st.get("pierce", false):
		hits.resize(1)
		end = origin.lerp(end, hits[0][0])
	for h in hits:
		var victim: Player = h[1]
		var at := origin.lerp(end, h[0]) if st.get("pierce", false) else end
		var head: bool = float(st.get("headshot", 1.0)) > 1.0 and victim.is_head_hit(at)
		var dmg: float = st.dmg * (st.get("headshot", 1.0) if head else 1.0)
		damage(victim, dmg, p.eid, wid, d * dmg * 5.0, at, head)
	return end


func _combo(ball: Projectiles.Proj, attacker_eid: int) -> void:
	projectiles.remove(ball)
	var pd: Dictionary = Weapons.PROJ.shock_ball
	_splash(ball.pos, pd.combo_radius, pd.combo_dmg, 900.0, attacker_eid, Weapons.SHOCK, null, [Status.SHOCK, 1.5])
	_emit(Ev.PROJ_END, [ball.pos, "combo", ball.id])


## Called by Projectiles when a projectile touches a player (victim) or a wall (null).
func projectile_hit(proj: Projectiles.Proj, victim: Player) -> void:
	var d := proj.def
	if victim and d.has("dmg"):
		damage(victim, d.dmg, proj.owner_eid, proj.wid, proj.vel.normalized() * float(d.dmg) * 8.0, proj.pos)
	if d.has("splash"):
		_splash(proj.pos, d.splash, d.splash_dmg, d.get("impulse", 400.0), proj.owner_eid, proj.wid,
				victim if d.has("dmg") else null, d.get("status", []))
	_emit(Ev.PROJ_END, [proj.pos, proj.key, proj.id])


func projectile_expired(proj: Projectiles.Proj) -> void:
	if proj.def.has("splash") and proj.key != "shock_ball":
		projectile_hit(proj, null)


func _splash(center: Vector2, radius: float, max_dmg: float, impulse: float, attacker_eid: int, wid: int,
		skip: Player = null, status: Array = []) -> void:
	for e in alive_players():
		if e == skip:
			continue
		var r := e.hit_rect()
		var closest := Vector2(clampf(center.x, r.position.x, r.end.x), clampf(center.y, r.position.y, r.end.y))
		var dist := center.distance_to(closest)
		if dist > radius or _ray(center, e.global_position):
			continue
		var k := 1.0 - 0.6 * dist / radius
		var dir := (e.global_position - center).normalized()
		dir = (dir + Vector2(0, -0.4)).normalized()   # bias upward: makes rocket jumps feel right
		damage(e, max_dmg * k, attacker_eid, wid, dir * impulse * k, closest)
		if not status.is_empty():
			apply_status(e, status[0], status[1] * k, attacker_eid, wid)


## `dot` = status kind when this is a damage-over-time tick (no amp, no self-halving), else -1.
func damage(victim: Player, amount: float, attacker_eid: int, wid: int, impulse: Vector2, at: Vector2,
		head := false, force := false, dot := -1) -> void:
	if not victim.alive or ended:
		return
	if not force and (victim.protect_time > 0.0 or level.zone_at(victim.global_position) >= 0):
		return
	if training and god_mode and victim == local_player:
		return
	var attacker: Player = entities.get(attacker_eid)
	if attacker and attacker.amp_time > 0.0 and not force and dot < 0:
		amount *= 2.0
	if attacker_eid == victim.eid and dot < 0:
		amount *= 0.5
	amount = GameMode.scale_damage(self, victim, amount, attacker_eid, wid, dot)
	if amount <= 0.0:
		return
	var dmg := maxi(1, roundi(amount))
	var absorbed := mini(victim.armor, int(dmg * 0.66))
	victim.armor -= absorbed
	victim.health -= dmg - absorbed
	if impulse != Vector2.ZERO:
		if victim.mode == Player.Mode.PUPPET:
			Net.to_owner(victim.eid, "impulse", [impulse])
		else:
			victim.push(impulse)
	if attacker_eid != victim.eid:
		victim.last_attacker = attacker_eid
		victim.last_hit_time = clock
	_emit(Ev.HIT, [victim.eid, dmg, at, attacker_eid, absorbed > 0, head, dot])
	if victim.health <= 0:
		_kill(victim, attacker_eid, wid, victim.velocity + impulse * 0.5)


func _kill(victim: Player, killer_eid: int, wid: int, vel: Vector2) -> void:
	roster[victim.eid].deaths += 1
	if killer_eid == victim.eid:
		roster[victim.eid].kills -= 1
	elif roster.has(killer_eid):
		roster[killer_eid].kills += 1
	victim.respawn_at = clock + RESPAWN_TIME
	GameMode.on_kill(self, victim, killer_eid)
	_emit(Ev.DIED, [victim.eid, killer_eid, wid, victim.global_position, vel,
			roster[killer_eid].kills if roster.has(killer_eid) else 0, roster[victim.eid].kills, roster[victim.eid].deaths])
	if frag_limit > 0 and roster.has(killer_eid) and roster[killer_eid].kills >= frag_limit:
		_end_match(killer_eid)


func _end_match(winner: int) -> void:
	_winner_eid = winner
	_emit(Ev.END, [winner])


## Damage (and optional [status, duration]) from a trap. Kills are credited to whoever
## last hurt the victim, if that was recent.
func trap_damage(e: Player, amount: int, kind: int, impulse: Vector2, at: Vector2, status: Array = []) -> void:
	var credit := e.last_attacker if clock - e.last_hit_time < 4.0 and roster.has(e.last_attacker) else e.eid
	damage(e, amount, credit, kind, impulse, at)
	if not status.is_empty():
		apply_status(e, status[0], status[1], credit, kind)


func _check_hazards() -> void:
	for e in alive_players():
		var feet := e.global_position + Vector2(0, Player.HALF.y - 4)
		if level.hazard_at(feet) or e.global_position.y > level.size_px.y + 64.0:
			var credit := e.last_attacker if clock - e.last_hit_time < 4.0 and roster.has(e.last_attacker) else e.eid
			damage(e, 1000.0, credit, HAZARD, Vector2.ZERO, e.global_position, false, true)


func _check_pickups() -> void:
	for i in pickups.items.size():
		var it := pickups.items[i]
		if not it.active:
			if clock >= it.respawn_at:
				_emit(Ev.PICKUP, [i, true, 0, _reroll(it) if it.get("random", false) else -1])
			continue
		for e in alive_players():
			if e.hit_rect().grow(4.0).has_point(it.pos) and _give(e, it):
				_emit(Ev.PICKUP, [i, false, e.eid, -1])
				if e.mode == Player.Mode.PUPPET:
					Net.to_owner(e.eid, "inventory", [e.owned, e.ammo, e.amp_time])
				break


## Apply a pickup's effect; false if the player can't use it (full health, max ammo...).
func _give(e: Player, it: Dictionary) -> bool:
	if not GameMode.item_allowed(self, it):
		return false
	match it.type:
		"h", "H":
			var cap := 100 if it.type == "h" else 199
			var poisoned := e.has_status(Status.POISON)
			if e.health >= cap and not poisoned:
				return false
			e.health = maxi(e.health, mini(cap, e.health + (25 if it.type == "h" else 100)))
			if poisoned:
				_emit(Ev.STATUS, [e.eid, Status.POISON, 0.0, 0, 0])   # health cures poison
		"a":
			if e.armor >= 150:
				return false
			e.armor = mini(150, e.armor + 50)
		"D":
			e.amp_time = 25.0
		"w":
			var wid: int = it.wid
			var w: Dictionary = Weapons.LIST[wid]
			if not e.owns(wid):
				e.owned |= 1 << wid
				e.ammo[wid] = maxi(e.ammo[wid], w.ammo_pickup)
				e.on_new_weapon(wid)
			elif e.ammo[wid] >= w.ammo_max:
				return false
			else:
				e.ammo[wid] = mini(w.ammo_max, e.ammo[wid] + w.ammo_pickup)
	return true


func _pick_spawn(e: Player) -> Vector2:
	if training and e.mode == Player.Mode.BOT and not level.dummy_spawns.is_empty():
		return level.dummy_spawns.pick_random()
	var scored: Array = []
	for s in level.spawns:
		var nearest := INF
		for o in alive_players():
			if o != e:
				nearest = minf(nearest, s.distance_to(o.global_position))
		scored.append([nearest, s])
	scored.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
	return scored[randi() % mini(3, scored.size())][1]


## Segment a->b against a rectangle (slab method). Returns entry t in 0..1, or -1.
static func seg_rect(a: Vector2, b: Vector2, r: Rect2) -> float:
	var d := b - a
	var tmin := 0.0
	var tmax := 1.0
	for axis in 2:
		var o: float = a[axis]
		var dd: float = d[axis]
		var lo: float = r.position[axis]
		var hi: float = r.end[axis]
		if absf(dd) < 0.000001:
			if o < lo or o > hi:
				return -1.0
		else:
			var t1 := (lo - o) / dd
			var t2 := (hi - o) / dd
			if t1 > t2:
				var tmp := t1
				t1 = t2
				t2 = tmp
			tmin = maxf(tmin, t1)
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return -1.0
	return tmin


# --- network ---------------------------------------------------------------------

## Host: everyone's position, aim, weapon, health and armor, ~30 times a second.
func _send_snapshot() -> void:
	var eids := PackedInt32Array()
	var data := PackedFloat32Array()
	for e: Player in entities.values():
		eids.append(e.eid)
		var st := e.pack_state()
		data.append_array(st)
		data.append(e.health)
		data.append(e.armor)
		data.append((1 if e.alive else 0) | (2 if e.protect_time > 0.0 else 0) | (4 if e.amp_time > 0.0 else 0))
	Net.s_snapshot.rpc(clock, eids, data)


## Client: apply a host snapshot. Our own position stays ours; health/armor come from the host.
func client_snapshot(host_clock: float, eids: PackedInt32Array, data: PackedFloat32Array) -> void:
	clock = lerpf(clock, host_clock, 0.2) if absf(clock - host_clock) < 1.0 else host_clock
	for n in eids.size():
		var e: Player = entities.get(eids[n])
		if e == null:
			continue
		var i := n * SNAP_STRIDE
		e.health = int(data[i + 7])
		e.armor = int(data[i + 8])
		var flags := int(data[i + 9])
		if e == local_player:
			e.protect_time = 0.5 if flags & 2 else 0.0
			continue
		e.net_update(data, i)
		e.protect_time = 0.5 if flags & 2 else 0.0
		e.amp_time = 1.0 if flags & 4 else 0.0
		if flags & 1 and not e.alive:                 # joined mid-life: show them
			e.spawn_at(Vector2(data[i], data[i + 1]))
			_alive_dirty = true


## Client: our movement goes to the host; the spawn-room meter runs locally for the HUD.
func _client_tick(delta: float) -> void:
	if _net_t <= 0.0 and local_player and local_player.alive:
		_net_t = NET_RATE
		Net.c_state.rpc_id(1, local_player.pack_state())
	if local_player and local_player.alive and countdown <= 0.0:
		var inside := level.zone_at(local_player.global_position) >= 0
		if inside:
			local_player.zone_time += delta
		else:
			local_player.zone_time = maxf(0.0, local_player.zone_time - ZONE_DRAIN * delta)
			local_player.left_spawn = true


## Client: a message meant only for us (knockback, inventory after a pickup).
func client_owner_message(kind: String, args: Array) -> void:
	if local_player == null:
		return
	match kind:
		"impulse":
			local_player.push(args[0])
		"inventory":
			var old := local_player.owned
			local_player.owned = int(args[0])
			local_player.ammo = args[1]
			local_player.amp_time = float(args[2])
			for w in Weapons.COUNT:
				if local_player.owns(w) and not (old & (1 << w)):
					local_player.on_new_weapon(w)


## Host: a client's reported movement.
func host_client_state(peer: int, data: PackedFloat32Array) -> void:
	var e: Player = entities.get(peer)
	if e == null or not e.alive or data.size() < 7:
		return
	for i in 7:
		if not is_finite(data[i]):                  # a NaN position would poison physics
			return
	e.net_update(data, 0)


## Host: a client wants to fire. Validate rate and position, then run it like any shot.
func host_client_fire(peer: int, wid: int, alt: bool, origin: Vector2, dir: Vector2) -> void:
	var e: Player = entities.get(peer)
	if e == null or not e.alive or wid < 0 or wid >= Weapons.COUNT or countdown > 0.0 or ended:
		return
	if dir == Vector2.ZERO or not dir.is_finite() or not origin.is_finite():
		return
	var rate := float(Weapons.stats(wid, alt).rate)
	var t: float = maxf(_next_fire.get(peer, -INF), clock - 2.0 * rate)   # up to ~2 banked shots
	if t > clock:
		return
	_next_fire[peer] = t + rate * 0.9
	var shoulder := e.global_position + Player.SHOULDER
	if origin.distance_to(shoulder) > 80.0:
		origin = shoulder
	e.weapon = wid
	_server_fire(e, wid, alt, origin, dir.normalized())


## Host: someone joined mid-match — add them, tell everyone, send them the full state.
func host_add_peer(id: int, info: Dictionary) -> void:
	if entities.has(id):
		return
	var e := _add_player(id, Player.Mode.PUPPET, info.look, info.name)
	e.respawn_at = clock + 1.0
	_emit(Ev.JOIN, [id, info.name, info.look])
	Net.s_start.rpc_id(id, describe())


func host_remove_peer(id: int) -> void:
	if entities.has(id):
		_emit(Ev.LEAVE, [id])


# --- camera ----------------------------------------------------------------------

## Zoom so at most VIEW_WORLD is visible (and the map always fills the screen).
func _fit_zoom() -> void:
	var view := get_viewport().get_visible_rect().size
	var z := maxf(maxf(view.x / VIEW_WORLD.x, view.y / VIEW_WORLD.y), maxf(view.x / level.size_px.x, view.y / level.size_px.y))
	camera.zoom = Vector2(z, z)
	_base_zoom = z


## Hitstop / slow-mo only where we own the clock: offline, not the menu's background match.
func _juice_allowed() -> bool:
	return net_role == Net.Role.OFFLINE and not demo


func add_shake(amount: float, at := Vector2.INF) -> void:
	if not Settings.screen_shake:
		return
	if at != Vector2.INF:
		amount *= clampf(1.0 - _cam_pos.distance_to(at) / 900.0, 0.0, 1.0)
	_shake = maxf(_shake, amount)


## Directional camera nudge (weapon recoil, blast push); Fx applies and decays it via
## camera.offset. `at` attenuates with distance like add_shake.
func add_kick(dir: Vector2, amount: float, at := Vector2.INF) -> void:
	if not Settings.screen_shake or demo:
		return
	if at != Vector2.INF:
		amount *= clampf(1.0 - _cam_pos.distance_to(at) / 900.0, 0.0, 1.0)
	fx.kick(dir, amount)


func _process(delta: float) -> void:
	var real_delta := delta / maxf(Engine.time_scale, 0.01)
	if _hitstop_until > 0 and Time.get_ticks_msec() >= _hitstop_until:
		_hitstop_until = 0
		if _finale_t <= 0.0:
			Engine.time_scale = 1.0
	if _finale_t > 0.0:
		# Match-winning frag: slow-mo that eases back to full speed, camera pushed in on it.
		_finale_t = maxf(0.0, _finale_t - real_delta)
		var k := _finale_t / FINALE
		Engine.time_scale = lerpf(1.0, 0.25, k * k) if _finale_t > 0.0 else 1.0
		var push := minf(1.0, (1.0 - k) * 5.0) * minf(1.0, k * 3.0)   # quick push in, ease back out
		camera.zoom = Vector2.ONE * _base_zoom * (1.0 + 0.3 * smoothstep(0.0, 1.0, push))
		_cam_pos = _cam_pos.lerp(_finale_pos, 1.0 - exp(-6.0 * real_delta))
	elif local_player.alive:
		var target := local_player.visual_position()
		# Look-ahead toward the mouse so you can see where you're shooting.
		var look_pt := target + touch.aim_dir * 400.0 if touch and touch.active else get_global_mouse_position()
		var to_mouse := look_pt - target
		target += to_mouse.limit_length(600.0) * 0.25
		_cam_pos = _cam_pos.lerp(target, 1.0 - exp(-10.0 * delta))
	elif entities.has(_killer_eid) and entities[_killer_eid].alive and not ended:
		# Death cam: watch the player who fragged you until you respawn.
		_cam_pos = _cam_pos.lerp(entities[_killer_eid].visual_position(), 1.0 - exp(-4.0 * real_delta))
	_shake = lerpf(_shake, 0.0, 1.0 - exp(-9.0 * delta))
	camera.global_position = _cam_pos + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
	background.follow(camera.get_screen_center_position())
