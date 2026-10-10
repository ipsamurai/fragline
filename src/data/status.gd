class_name Status
## Status effects (damage over time, slows, weapon jams). Durations are set by the source;
## re-applying refreshes to the longer of the two. All tuning lives here.

enum { BURN, POISON, CHILL, SHOCK }

const TICK := 0.5                      # damage-over-time interval (seconds)

const INFO := {
	BURN: {"name": "BURNING", "color": Color("ff8a3d"), "tick_dmg": 5,
		"tint": Color(1.15, 0.88, 0.75)},
	POISON: {"name": "POISONED", "color": Color("8bff4d"), "tick_dmg": 3,
		"tint": Color(0.85, 1.12, 0.8)},          # health pickups cure it
	CHILL: {"name": "CHILLED", "color": Color("8fe3ff"), "slow": 0.55, "jump": 0.85,
		"tint": Color(0.75, 0.92, 1.25)},
	SHOCK: {"name": "JAMMED", "color": Color("ffe94d"),           # weapons can't fire
		"tint": Color(1.1, 1.1, 0.85)},
}

## Which status a map's floor vents inflict, by map style, and for how long.
const VENT_STATUS := {
	"industrial": [BURN, 2.5], "foundry": [BURN, 3.0], "jungle": [POISON, 6.0],
	"ice": [CHILL, 3.0], "space": [CHILL, 2.5], "city": [SHOCK, 1.5],
}
