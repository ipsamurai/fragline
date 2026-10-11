class_name GameMode
extends RefCounted
## Match rule sets layered over Deathmatch. Everything here is data plus small hooks that
## World calls at fixed points (setup, spawn, damage, kill, pickup, death event); with the
## default DEATHMATCH every hook is a no-op, so the classic rules are untouched.
##
## Hooks (all static, all cheap; none run per frame):
##   configure(world)        World.setup() / setup_client(): frag limit, pickups, gravity, death listener
##   on_spawn(world, e)      World.apply_event(SPAWN) on every peer: the mode's loadout
##   scale_damage(...)       World.damage(): instagib one-shots, rocket-arena self damage
##   on_kill(world, v, k)    World._kill() (authority): gun-game demotion floor, respawn delay
##   item_allowed(world, it) World._give(): disabled pickups can never be taken
##   _on_died(...)           World.died signal on every peer: gun-game tier change + HUD message
## HUD helper: status_text(world, player) -> "" in Deathmatch, else a short status line.

enum { DEATHMATCH, GUN_GAME, INSTAGIB, ROCKET_ARENA }

const NAMES: Array[String] = ["Deathmatch", "Gun Game", "Instagib", "Rocket Arena"]
const DESCS: Array[String] = [
	"Classic free-for-all. Grab weapons around the arena; first to the frag limit wins.",
	"Every frag moves you to the next gun. Finish the 8-weapon ladder to win. Suicide sends you back a tier.",
	"Shock Rifles only, infinite ammo, every hit kills. No pickups, fast respawns.",
	"Rocket Launchers only, infinite ammo. Your own rockets barely hurt you, so rocket-jump everywhere.",
]
## Gun Game ladder: every standard weapon once, strongest crowd-pleasers first, ending on the
## Enforcer: the last frag is a pistol duel, so the leader can still be caught.
const LADDER: Array[int] = [Weapons.MINIGUN, Weapons.FLAK, Weapons.PULSE, Weapons.SHOCK,
		Weapons.ROCKET, Weapons.GRENADE, Weapons.SNIPER, Weapons.ENFORCER]
const AMMO := 999                      # "infinite": refilled on every spawn and every frag
const INSTAGIB_RESPAWN := 1.2
const INSTAGIB_DAMAGE := 1000.0        # beyond any health + armor
const ROCKET_SELF_SCALE := 0.5         # on top of the usual self-damage halving (so 25% in all)
const LOW_GRAVITY := 0.55              # Low Gravity mutator: Orbital's gravity, on any map

static var _status_cache := {}         # (mode, tier) -> status line, so the HUD can call every frame


static func sanitize(m: Variant) -> int:
	return clampi(int(m), 0, NAMES.size() - 1)


static func name_of(m: int) -> String:
	return NAMES[sanitize(m)]


static func desc_of(m: int) -> String:
	return DESCS[sanitize(m)]


## Weapon this player holds under the current mode (-1 = normal Deathmatch inventory).
static func weapon_for(world: World, eid: int) -> int:
	match world.game_mode:
		GUN_GAME:
			return LADDER[tier(world, eid)]
		INSTAGIB:
			return Weapons.SHOCK
		ROCKET_ARENA:
			return Weapons.ROCKET
	return -1


## Gun Game tier (0-based): your frag count, clamped to the ladder.
static func tier(world: World, eid: int) -> int:
	var k: int = world.roster[eid].kills if world.roster.has(eid) else 0
	return clampi(k, 0, LADDER.size() - 1)


## Pickups the mode keeps. Disabled ones are made dormant at setup (hidden, never respawn,
## ignored by bots because they're inactive) and refused by World._give() regardless.
static func item_allowed(world: World, it: Dictionary) -> bool:
	match world.game_mode:
		GUN_GAME, ROCKET_ARENA:
			return it.type != "w"
		INSTAGIB:
			return false
	return true


# --- hooks -------------------------------------------------------------------------------

## World.setup() (after the scene and weapon slots are built) and World.setup_client().
## Training and the menu's background match always play Deathmatch.
static func configure(world: World) -> void:
	if world.training or world.demo:
		world.game_mode = DEATHMATCH
		world.low_gravity = false
		return
	world.game_mode = sanitize(world.game_mode)
	if world.low_gravity:
		world.gravity_scale = minf(world.gravity_scale, LOW_GRAVITY)
	if world.game_mode == DEATHMATCH:
		return
	if world.game_mode == GUN_GAME:
		world.frag_limit = LADDER.size()
	world.nuke_released = true           # the Redeemer spot stays dormant (no weapon pickups)
	for it in world.pickups.items:
		if not item_allowed(world, it):
			it.active = false
			it.dormant = true
			it.respawn_at = INF
	world.died.connect(_on_died.bind(world))
	for e: Player in world.entities.values():   # a client joining mid-match: fighters already alive
		if e.alive:
			on_spawn(world, e)


## Every peer, right after a (re)spawn: hand out the mode's only weapon.
static func on_spawn(world: World, e: Player) -> void:
	if world.game_mode == DEATHMATCH:
		return
	_equip(e, weapon_for(world, e.eid))


static func _equip(e: Player, wid: int) -> void:
	if wid < 0:
		return
	var ammo := PackedInt32Array()
	ammo.resize(Weapons.COUNT)
	if not Weapons.infinite(wid):
		ammo[wid] = AMMO
	e.ammo = ammo
	e.owned = 1 << wid
	if e.weapon != wid:
		e.weapon = wid
		e._fire_cd = maxf(e._fire_cd, 0.25)


## World.damage(), after the usual amp / self-halving. Returns the damage to deal; <= 0
## means "no damage at all".
static func scale_damage(world: World, victim: Player, amount: float, attacker_eid: int, wid: int, dot: int) -> float:
	match world.game_mode:
		INSTAGIB:
			if wid == Weapons.SHOCK:
				return 0.0 if attacker_eid == victim.eid else INSTAGIB_DAMAGE
		ROCKET_ARENA:
			if wid == Weapons.ROCKET and attacker_eid == victim.eid:
				return 0.0 if dot >= 0 else amount * ROCKET_SELF_SCALE   # no self-burn either
	return amount


## World._kill() on the authority, after scores change and before the death is announced.
static func on_kill(world: World, victim: Player, _killer_eid: int) -> void:
	match world.game_mode:
		GUN_GAME:
			var r: Dictionary = world.roster[victim.eid]
			r.kills = maxi(0, r.kills)       # a suicide demotes one tier, never below the first
		INSTAGIB:
			victim.respawn_at = world.clock + INSTAGIB_RESPAWN


## World.died on every peer (scores are already synced): the killer's new tier / ammo refill,
## and the tier-up / demotion callout for the local player. Runs after Hud.on_death, so the
## callout (prio 3) takes the centre over that frag's spree / multi-kill headline.
static func _on_died(victim_eid: int, killer_eid: int, _wid: int, world: World) -> void:
	if not is_instance_valid(world) or world.ended:
		return
	var killer: Player = world.entities.get(killer_eid)
	if killer and killer.alive and killer_eid != victim_eid:
		var before := killer.weapon
		_equip(killer, weapon_for(world, killer_eid))
		if world.game_mode == GUN_GAME and killer_eid == world.my_eid and killer.weapon != before:
			var t := tier(world, killer_eid)
			var wname := str(Weapons.LIST[killer.weapon].name).to_upper()
			if t == LADDER.size() - 1:
				world.hud.message("FINAL TIER: " + wname, "One more frag wins it", Color("ffd166"), 2.4, 3, 2)
			else:
				world.hud.message("TIER UP: " + wname, "Tier %d/%d  ·  next: %s" % [t + 1, LADDER.size(),
						Weapons.LIST[LADDER[t + 1]].name], Weapons.LIST[killer.weapon].color, 2.0, 3, 1)
	elif world.game_mode == GUN_GAME and killer_eid == victim_eid and victim_eid == world.my_eid:
		var t := tier(world, victim_eid)
		world.hud.message("DEMOTED", "Back to tier %d: %s" % [t + 1, Weapons.LIST[LADDER[t]].name],
				Color(1, 0.35, 0.35), 2.0, 3, 1)


# --- HUD -----------------------------------------------------------------------------------

## One-line mode status for the HUD ("" in Deathmatch). Cached per (mode, tier), so calling it
## every frame allocates nothing.
static func status_text(world: World, player: Player) -> String:
	var m := world.game_mode
	if m == DEATHMATCH:
		return ""
	var t := tier(world, player.eid) if m == GUN_GAME and player else 0
	var key := m * 100 + t
	var s: String = _status_cache.get(key, "")
	if s == "":
		match m:
			GUN_GAME:
				var wname: String = Weapons.LIST[LADDER[t]].name
				if t == LADDER.size() - 1:
					s = "GUN GAME  ·  FINAL TIER %d/%d: %s  ·  one frag wins" % [t + 1, LADDER.size(), wname]
				else:
					s = "GUN GAME  ·  Tier %d/%d: %s  →  next: %s" % [t + 1, LADDER.size(), wname,
							Weapons.LIST[LADDER[t + 1]].name]
			INSTAGIB:
				s = "INSTAGIB  ·  one hit kills"
			ROCKET_ARENA:
				s = "ROCKET ARENA  ·  rockets only, rocket-jump freely"
		_status_cache[key] = s
	return s


## True when the HUD should show "∞" instead of an ammo count.
static func infinite_ammo(world: World) -> bool:
	return world.game_mode != DEATHMATCH
