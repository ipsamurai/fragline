class_name WeaponInfo
## Menu-facing weapon facts: flavour text plus numbers derived from Weapons.LIST / PROJ, and
## 0..1 stat-bar values (Damage / Fire rate / Range / Splash). Built once, cached.

const TAGLINES := [
	"Reliable sidearm. Never runs dry.",
	"Shreds anything at close range.",
	"Spin it up and hose the arena.",
	"Instant beam with a devastating combo.",
	"Plasma bolts and a short-range wave.",
	"Big splash, big knockback, rocket jumps.",
	"Bank shots around corners.",
	"Long range. Headshots hurt.",
	"One shot. One very big boom.",
]
const PRIMARY := [
	"Precise single shot",
	"Eight hot shards that ricochet once",
	"Fast, accurate bullet stream",
	"Instant hitscan beam",
	"Rapid plasma bolts",
	"Single rocket that sets targets alight",
	"Bouncing grenade on a short fuse",
	"Heavy round, headshots deal double+",
	"Slow warhead with an enormous blast",
]
const ALT := [
	"Fan the hammer: faster, wider spread",
	"Arcing shell that bursts into flame",
	"Wild spray: even faster, less accurate",
	"Slow energy orb. Hit it with the beam to combo",
	"Continuous plasma wave, short range",
	"Three-rocket volley (uses 3 ammo)",
	"Sticky grenade: clings, then detonates",
	"Ghost bullet: pierces fighters and walls",
	"",
]
const STAT_NAMES := ["Damage", "Fire rate", "Range", "Splash"]

static var _cache: Array = []


## Damage of one trigger pull (all pellets, direct hit + splash for projectiles).
static func shot_damage(s: Dictionary) -> float:
	var pellets := float(s.get("pellets", 1))
	if s.kind == Weapons.Kind.HITSCAN:
		return float(s.get("dmg", 0)) * pellets
	var p: Dictionary = Weapons.PROJ.get(s.get("proj", ""), {})
	return maxf(float(p.get("dmg", 0)), float(p.get("splash_dmg", 0))) * pellets


static func reach(s: Dictionary) -> float:
	if s.kind == Weapons.Kind.HITSCAN:
		return float(s.get("range", 0.0))
	var p: Dictionary = Weapons.PROJ.get(s.get("proj", ""), {})
	var r := float(p.get("speed", 0.0)) * float(p.get("life", 0.0))
	if p.has("grav"):
		r *= 0.45                                 # lobbed: the useful reach is far shorter
	return minf(r, 3200.0)


static func splash(s: Dictionary) -> float:
	if s.kind == Weapons.Kind.HITSCAN:
		return 0.0
	var p: Dictionary = Weapons.PROJ.get(s.get("proj", ""), {})
	return float(p.get("splash", 0.0))


## One line of numbers for a fire mode, e.g. "Hitscan · 15 dmg · 3.6/s".
static func mode_line(wid: int, alt: bool) -> String:
	var s := Weapons.stats(wid, alt)
	var parts: PackedStringArray = []
	parts.append("Hitscan" if s.kind == Weapons.Kind.HITSCAN else "Projectile")
	var pellets := int(s.get("pellets", 1))
	var per := shot_damage(s) / maxf(1.0, pellets)
	parts.append(("%d×%d dmg" % [pellets, int(per)]) if pellets > 1 else ("%d dmg" % int(per)))
	parts.append("%.1f/s" % (1.0 / float(s.rate)))
	var sp := splash(s)
	if sp > 0.0:
		parts.append("%d splash" % int(sp))
	if s.get("headshot", 1.0) > 1.0:
		parts.append("headshot ×%.1f" % float(s.headshot))
	if s.get("through_walls", false):
		parts.append("through walls")
	return "  ·  ".join(parts)


## {bars: [4 floats 0..1], values: [4 short strings]} for the primary fire.
static func stats(wid: int) -> Dictionary:
	if _cache.is_empty():
		for i in Weapons.COUNT:
			var s := Weapons.stats(i, false)
			var dmg := shot_damage(s)
			var rps := 1.0 / float(s.rate)
			var rng := reach(s)
			var sp := splash(s)
			_cache.append({
				"bars": [clampf(sqrt(dmg / 130.0), 0.06, 1.0), clampf(sqrt(rps / 12.5), 0.06, 1.0),
						clampf(rng / 3200.0, 0.06, 1.0), clampf(sqrt(sp / 420.0), 0.0, 1.0)],
				"values": [str(int(dmg)), "%.1f/s" % rps, str(int(rng)), str(int(sp)) if sp > 0.0 else "—"],
			})
	return _cache[wid]


static func ammo_text(wid: int) -> String:
	return "Infinite ammo" if Weapons.infinite(wid) else "Max ammo %d" % Weapons.max_ammo(wid)
