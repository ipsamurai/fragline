class_name Weapons
## Weapon and projectile tables. Weapon N is bound to number key N (index N-1).
## Tweak numbers here to rebalance; every system reads from these tables.

enum Kind { HITSCAN, PROJECTILE }

const ENFORCER := 0
const FLAK := 1
const MINIGUN := 2
const SHOCK := 3
const PULSE := 4
const ROCKET := 5
const GRENADE := 6
const SNIPER := 7
const REDEEMER := 8

## Fields: kind, rate (s between shots), dmg (hitscan), pellets, spread (rad), range,
## proj (projectile key), ammo_pickup / ammo_max (-1 = infinite), sound, shake,
## gun_len / gun_w (visual), bot_range (ideal min/max distance), prio (bot preference).
## `alt` overrides any field for right-click fire; `cost` = ammo per shot (default 1).
## Hitscan extras: beam ("shock" combo-capable, "plasma", "ghost" visuals), pierce (all fighters
## in line), through_walls (only spawn barriers stop it), headshot multiplier.
const LIST: Array[Dictionary] = [
	{
		"name": "Enforcer", "color": Color("ffd166"), "kind": Kind.HITSCAN,
		"rate": 0.28, "dmg": 15, "pellets": 1, "spread": 0.015, "range": 1600.0,
		"ammo_pickup": -1, "ammo_max": -1, "sound": "pistol", "shake": 1.5,
		"gun_len": 16, "gun_w": 5, "bot_range": Vector2(0, 900), "prio": 1,
		"alt": {"rate": 0.16, "spread": 0.09},
	},
	{
		"name": "Flak Cannon", "color": Color("ff8c42"), "kind": Kind.PROJECTILE,
		"proj": "flak", "pellets": 8, "spread": 0.16, "rate": 0.95,
		"ammo_pickup": 12, "ammo_max": 40, "sound": "flak", "shake": 5.0,
		"gun_len": 24, "gun_w": 10, "bot_range": Vector2(0, 450), "prio": 6,
		"alt": {"proj": "flak_shell", "pellets": 1, "spread": 0.0, "rate": 1.0, "sound": "flak_alt"},
	},
	{
		"name": "Minigun", "color": Color("f6f740"), "kind": Kind.HITSCAN,
		"rate": 0.08, "dmg": 8, "pellets": 1, "spread": 0.06, "range": 1500.0,
		"ammo_pickup": 80, "ammo_max": 300, "sound": "minigun", "shake": 1.0,
		"gun_len": 26, "gun_w": 9, "bot_range": Vector2(0, 900), "prio": 4,
		"alt": {"rate": 0.055, "spread": 0.14, "dmg": 6},
	},
	{
		"name": "Shock Rifle", "color": Color("b388ff"), "kind": Kind.HITSCAN,
		"rate": 0.75, "dmg": 40, "pellets": 1, "spread": 0.0, "range": 2400.0, "beam": "shock",
		"ammo_pickup": 15, "ammo_max": 50, "sound": "shock", "shake": 3.0,
		"gun_len": 26, "gun_w": 7, "bot_range": Vector2(150, 1400), "prio": 7,
		"alt": {"kind": Kind.PROJECTILE, "proj": "shock_ball", "rate": 0.6, "sound": "shock_alt"},
	},
	{
		"name": "Pulse Gun", "color": Color("5cff9d"), "kind": Kind.PROJECTILE,
		"proj": "pulse", "pellets": 1, "spread": 0.03, "rate": 0.12,
		"ammo_pickup": 50, "ammo_max": 200, "sound": "pulse", "shake": 0.8,
		"gun_len": 22, "gun_w": 8, "bot_range": Vector2(0, 800), "prio": 5,
		# Alt: continuous short-range plasma wave — strong, but drains ammo ~3x faster.
		"alt": {"kind": Kind.HITSCAN, "rate": 0.05, "dmg": 5, "spread": 0.0, "range": 520.0, "beam": "plasma"},
	},
	{
		"name": "Rocket Launcher", "color": Color("ff4d4d"), "kind": Kind.PROJECTILE,
		"proj": "rocket", "pellets": 1, "spread": 0.0, "rate": 0.9,
		"ammo_pickup": 8, "ammo_max": 30, "sound": "rocket", "shake": 4.0,
		"gun_len": 28, "gun_w": 12, "bot_range": Vector2(160, 1100), "prio": 8,
		"alt": {"pellets": 3, "spread": 0.12, "rate": 1.6, "cost": 3},
	},
	{
		"name": "Grenade Launcher", "color": Color("8bd450"), "kind": Kind.PROJECTILE,
		"proj": "grenade", "pellets": 1, "spread": 0.02, "rate": 0.65,
		"ammo_pickup": 10, "ammo_max": 30, "sound": "grenade", "shake": 2.5,
		"gun_len": 22, "gun_w": 11, "bot_range": Vector2(120, 700), "prio": 5,
		# Alt: sticky grenade — clings to walls or players, detonates shortly after.
		"alt": {"proj": "sticky", "spread": 0.0, "rate": 0.8},
	},
	{
		"name": "Sniper Rifle", "color": Color("4dd2ff"), "kind": Kind.HITSCAN,
		"rate": 1.3, "dmg": 65, "pellets": 1, "spread": 0.0, "range": 3200.0, "headshot": 2.2,
		"ammo_pickup": 8, "ammo_max": 25, "sound": "sniper", "shake": 4.0,
		"gun_len": 34, "gun_w": 6, "bot_range": Vector2(400, 3000), "prio": 6,
		# Alt: ghost bullet — passes through fighters, walls and platforms (not spawn barriers);
		# much weaker and no headshots.
		"alt": {"dmg": 30, "headshot": 1.0, "pierce": true, "through_walls": true, "beam": "ghost"},
	},
	{
		"name": "Redeemer", "color": Color("ffffff"), "kind": Kind.PROJECTILE,
		"proj": "redeemer", "pellets": 1, "spread": 0.0, "rate": 2.0,
		"ammo_pickup": 1, "ammo_max": 1, "sound": "rocket", "shake": 6.0,
		"gun_len": 30, "gun_w": 15, "bot_range": Vector2(600, 2000), "prio": 9,
	},
]

## Projectiles. splash = explosion radius (absent = direct hit only); sticky ones attach to
## whatever they touch and explode `stick_fuse` seconds later; `status` = [Status kind, seconds]
## inflicted on everyone caught in the blast (scaled by distance); `loop_sound` plays while in flight.
const PROJ := {
	"flak": {"speed": 1150.0, "grav": 500.0, "radius": 3.0, "dmg": 12, "bounces": 1,
		"restitution": 0.5, "life": 0.7, "size": 3.5, "color": Color("ffb347"), "jitter": 0.15},
	"flak_shell": {"speed": 850.0, "grav": 1200.0, "radius": 6.0, "splash": 120.0, "splash_dmg": 80,
		"impulse": 520.0, "life": 3.0, "size": 6.0, "color": Color("ff8c42"),
		"status": [Status.BURN, 2.0]},
	"shock_ball": {"speed": 520.0, "radius": 10.0, "dmg": 45, "splash": 60.0, "splash_dmg": 25,
		"impulse": 250.0, "life": 4.0, "size": 10.0, "color": Color("b388ff"),
		"combo_radius": 190.0, "combo_dmg": 125},
	"pulse": {"speed": 1250.0, "radius": 5.0, "dmg": 17, "life": 1.2, "size": 6.0,
		"color": Color("5cff9d")},
	"rocket": {"speed": 820.0, "radius": 6.0, "splash": 125.0, "splash_dmg": 100, "impulse": 720.0,
		"life": 4.0, "size": 7.0, "color": Color("ff4d4d"), "trail": true, "status": [Status.BURN, 2.0]},
	"grenade": {"speed": 820.0, "grav": 1500.0, "radius": 6.0, "splash": 115.0, "splash_dmg": 85,
		"impulse": 600.0, "bounces": 99, "restitution": 0.55, "life": 1.8, "size": 6.0,
		"color": Color("8bd450")},
	"sticky": {"speed": 760.0, "grav": 1300.0, "radius": 6.0, "splash": 110.0, "splash_dmg": 80,
		"impulse": 550.0, "sticky": true, "stick_fuse": 1.2, "life": 4.0, "size": 6.0,
		"color": Color("c6ff4d")},
	"redeemer": {"speed": 430.0, "radius": 12.0, "splash": 420.0, "splash_dmg": 350, "impulse": 1400.0,
		"life": 8.0, "size": 12.0, "color": Color("ffffff"), "trail": true, "status": [Status.BURN, 4.0],
		"loop_sound": "redeemer"},
}

const COUNT := 9


## Weapon stats with alt-fire overrides merged in.
static func stats(wid: int, alt: bool) -> Dictionary:
	var w: Dictionary = LIST[wid]
	if alt and w.has("alt"):
		var merged := w.duplicate()
		merged.merge(w["alt"], true)
		return merged
	return w


static func max_ammo(wid: int) -> int:
	return LIST[wid]["ammo_max"]


static func infinite(wid: int) -> bool:
	return LIST[wid]["ammo_max"] < 0
