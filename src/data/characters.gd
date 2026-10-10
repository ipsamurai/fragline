class_name Characters
## Playable characters. Purely cosmetic — every fighter shares the same hitbox and stats.
## A "look" is the resolved dictionary that the painter draws and the network sends.

enum Helmet { DOME, CREST, ANTENNA, HORNS, HOOD, CYCLOPS }
const HELMET_NAMES := ["Dome", "Crest", "Antenna", "Horns", "Hood", "Cyclops"]

const LIST: Array[Dictionary] = [
	{"name": "Volt", "tag": "Arc trooper", "primary": Color("2f80ed"), "secondary": Color("1b2a41"), "visor": Color("5ef0ff"), "helmet": Helmet.DOME, "bulk": 1.0},
	{"name": "Ember", "tag": "Pyro specialist", "primary": Color("e8553e"), "secondary": Color("3a1f1d"), "visor": Color("ffd166"), "helmet": Helmet.CREST, "bulk": 1.0},
	{"name": "Frost", "tag": "Cryo sniper", "primary": Color("cfe8ff"), "secondary": Color("2c3e66"), "visor": Color("7fdbff"), "helmet": Helmet.HOOD, "bulk": 0.92},
	{"name": "Viper", "tag": "Toxic skirmisher", "primary": Color("3ddc84"), "secondary": Color("17321f"), "visor": Color("eaff70"), "helmet": Helmet.ANTENNA, "bulk": 0.95},
	{"name": "Onyx", "tag": "Heavy enforcer", "primary": Color("3b3f4a"), "secondary": Color("16181d"), "visor": Color("ff3d3d"), "helmet": Helmet.CYCLOPS, "bulk": 1.15},
	{"name": "Nova", "tag": "Star pilot", "primary": Color("ff5fa2"), "secondary": Color("2d1633"), "visor": Color("ffe3f1"), "helmet": Helmet.DOME, "bulk": 0.92},
	{"name": "Rook", "tag": "Siege engineer", "primary": Color("c9a227"), "secondary": Color("2e2a1a"), "visor": Color("5ef0ff"), "helmet": Helmet.HORNS, "bulk": 1.1},
	{"name": "Hex", "tag": "Rogue hacker", "primary": Color("8e5cff"), "secondary": Color("1c1433"), "visor": Color("3dff9a"), "helmet": Helmet.HOOD, "bulk": 0.95},
	{"name": "Blaze", "tag": "Demolitionist", "primary": Color("ff9f1c"), "secondary": Color("2b1a0c"), "visor": Color("fff3b0"), "helmet": Helmet.CREST, "bulk": 1.05},
	{"name": "Echo", "tag": "Recon drone-op", "primary": Color("2ec4b6"), "secondary": Color("10302d"), "visor": Color("ffffff"), "helmet": Helmet.ANTENNA, "bulk": 0.95},
	{"name": "Titan", "tag": "Juggernaut", "primary": Color("8d99ae"), "secondary": Color("2b2d42"), "visor": Color("ffb703"), "helmet": Helmet.HORNS, "bulk": 1.2},
	{"name": "Wraith", "tag": "Phantom assassin", "primary": Color("e6e6e6"), "secondary": Color("121212"), "visor": Color("ff2e63"), "helmet": Helmet.CYCLOPS, "bulk": 0.9},
]

const LOOK_KEYS := ["primary", "secondary", "visor", "helmet"]


## Merge a character's defaults with the player's custom overrides.
static func resolve(index: int, overrides: Dictionary = {}) -> Dictionary:
	var base: Dictionary = LIST[clampi(index, 0, LIST.size() - 1)]
	var look := {"char": index, "primary": base.primary, "secondary": base.secondary,
		"visor": base.visor, "helmet": base.helmet, "bulk": base.bulk}
	for k in LOOK_KEYS:
		if overrides.has(k):
			look[k] = overrides[k]
	return look



## Clean a look received over the network so bad data can't crash the painter.
static func sanitize(look: Variant) -> Dictionary:
	if typeof(look) != TYPE_DICTIONARY:
		return resolve(0)
	var out := resolve(clampi(int(look.get("char", 0)), 0, LIST.size() - 1))
	for k in ["primary", "secondary", "visor"]:
		if typeof(look.get(k)) == TYPE_COLOR:
			out[k] = look[k]
	out.helmet = clampi(int(look.get("helmet", out.helmet)), 0, HELMET_NAMES.size() - 1)
	return out


## Clean a player name received over the network.
static func clean_name(n: Variant) -> String:
	var s := str(n).strip_edges().left(16)
	return s if s != "" else "Player"
