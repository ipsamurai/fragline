class_name MatchStats
extends Node
## Per-player match stats, built only from World events (World.event_applied), so the same
## numbers come out offline, on a LAN host and on LAN clients (apply_event runs everywhere).
## Also picks the end-of-match awards and paints / saves the shareable 1200x630 recap card.
##
## Accuracy: every SHOT event adds its pellet count (8 for flak, 3 for a rocket volley), every
## non-DoT HIT on someone else adds one hit. Splash and piercing can hit several players with
## one pellet, so the ratio is capped at 100%.

const MULTI_WINDOW := 3.0                 # same window as the HUD's multi-kill announcer
const MIN_ACC_PELLETS := 10               # pellets fired before you qualify for Sharpshooter
const SPLASH_WIDS := [Weapons.ROCKET, Weapons.GRENADE, Weapons.REDEEMER]
const PX_PER_M := 32.0                    # one tile = one metre
const LONGSHOT_MIN := 480.0               # px; shorter frags don't earn "Long shot"
const RECAP_SIZE := Vector2i(1200, 630)
const GUN_SPRITES := "res://src/game/gun_sprites.gd"
const MULTI_NAMES := ["", "", "DOUBLE KILL", "MULTI KILL", "MEGA KILL", "ULTRA KILL", "MONSTER KILL"]

enum Award { MVP, SHARPSHOOTER, RAMPAGE, NUKE, HEADHUNTER, DEMOLITION, LONGSHOT, BRUISER }
const AWARD_INFO := {
	Award.MVP: {"title": "MVP", "color": Color("ffc93c")},
	Award.SHARPSHOOTER: {"title": "SHARPSHOOTER", "color": Color("39e1ff")},
	Award.RAMPAGE: {"title": "RAMPAGE", "color": Color("ff6b3d")},
	Award.NUKE: {"title": "NUCLEAR OPTION", "color": Color("e9f1ff")},
	Award.HEADHUNTER: {"title": "HEADHUNTER", "color": Color("ff4d6d")},
	Award.DEMOLITION: {"title": "DEMOLITION", "color": Color("ff9f1c")},
	Award.LONGSHOT: {"title": "LONG SHOT", "color": Color("a78bfa")},
	Award.BRUISER: {"title": "HEAVY HITTER", "color": Color("4ade80")},
}

static var _gs: Script                     # GunSprites, once it exists (another agent's file)
static var _gs_checked := false

var world: World
var stats := {}                            # eid -> Dictionary (see _blank())
var version := 0                           # bumps on every change: a cheap cache key
var end_clock := -1.0                      # world.clock when the match ended


func _init(w: World = null) -> void:
	name = "MatchStats"
	world = w


func _ready() -> void:
	if world == null:
		world = get_parent() as World
	world.event_applied.connect(on_event)


func _blank() -> Dictionary:
	var zeros := []
	zeros.resize(Weapons.COUNT)
	zeros.fill(0)
	return {"shots": 0, "pellets": 0, "hits": 0, "heads": 0, "dmg": 0, "taken": 0,
			"frags": 0, "deaths": 0, "suicides": 0, "spree": 0, "best_spree": 0,
			"multi": 0, "best_multi": 0, "multis": 0, "last_kill": -100.0,
			"wshots": zeros.duplicate(), "wfrags": zeros.duplicate(),
			"longest": 0.0, "longest_wid": -1, "pickups": 0, "nukes": 0, "splash": 0}


## Stats for one player (created on first use, so late joiners just work).
func of(eid: int) -> Dictionary:
	if not stats.has(eid):                     # no throwaway default dict per event
		stats[eid] = _blank()
	return stats[eid]


func on_event(kind: int, a: Array) -> void:
	match kind:
		World.Ev.SHOT:
			var wid: int = a[1]
			if wid < 0 or wid >= Weapons.COUNT:
				return
			var s := of(a[0])
			s.shots += 1
			var wd: Dictionary = Weapons.LIST[wid]     # (Weapons.stats() would copy for alt fire)
			var alt: Dictionary = wd.get("alt", wd) if a[2] else wd
			s.pellets += int(alt.get("pellets", wd.get("pellets", 1)))
			s.wshots[wid] += 1
		World.Ev.HIT:
			var victim: int = a[0]
			var attacker: int = a[3]
			var dmg: int = a[1]
			var dot: int = a[6] if a.size() > 6 else -1
			of(victim).taken += dmg
			if attacker != victim and attacker != 0:
				var s := of(attacker)
				s.dmg += dmg
				if dot < 0:
					s.hits += 1
					if a[5]:
						s.heads += 1
		World.Ev.DIED:
			var victim: int = a[0]
			var killer: int = a[1]
			var wid: int = a[2]
			var v := of(victim)
			v.deaths += 1
			v.spree = 0
			v.multi = 0
			if killer == victim or killer == 0:
				v.suicides += 1
			else:
				var k := of(killer)
				k.frags += 1
				k.spree += 1
				k.best_spree = maxi(k.best_spree, k.spree)
				k.multi = k.multi + 1 if world.clock - float(k.last_kill) <= MULTI_WINDOW else 1
				k.last_kill = world.clock
				k.best_multi = maxi(k.best_multi, k.multi)
				if k.multi == 2:
					k.multis += 1                        # one per chain, however long it gets
				if wid >= 0 and wid < Weapons.COUNT:
					k.wfrags[wid] += 1
					if wid in SPLASH_WIDS:
						k.splash += 1
					if wid == Weapons.REDEEMER:
						k.nukes += 1
					var ke: Player = world.entities.get(killer)
					if ke and a.size() > 3:
						var d: float = ke.global_position.distance_to(a[3])
						if d > k.longest:
							k.longest = d
							k.longest_wid = wid
		World.Ev.PICKUP:
			if a.size() > 2 and not a[1] and int(a[2]) != 0:
				of(a[2]).pickups += 1
		World.Ev.END:
			end_clock = world.clock
		_:
			return
	version += 1


# --- derived numbers --------------------------------------------------------------------

## Hit ratio 0..1, or -1 when nothing was fired.
func accuracy(eid: int) -> float:
	var s := of(eid)
	return minf(float(s.hits) / s.pellets, 1.0) if s.pellets > 0 else -1.0


func accuracy_text(eid: int) -> String:
	var acc := accuracy(eid)
	return "%d%%" % roundi(acc * 100.0) if acc >= 0.0 else "—"


## Weapon with the most frags (else the most shots), or -1.
func favourite(eid: int) -> int:
	var s := of(eid)
	for key in ["wfrags", "wshots"]:
		var arr: Array = s[key]
		var best := -1
		for w in arr.size():
			if arr[w] > 0 and (best < 0 or arr[w] > arr[best]):
				best = w
		if best >= 0:
			return best
	return -1


func kills(eid: int) -> int:
	return int(world.roster[eid].kills) if world.roster.has(eid) else int(of(eid).frags)


func deaths(eid: int) -> int:
	return int(world.roster[eid].deaths) if world.roster.has(eid) else int(of(eid).deaths)


func kd(eid: int) -> float:
	return float(kills(eid)) / maxi(deaths(eid), 1)


## Current players, best first: frags, then fewer deaths, then damage dealt.
func standings() -> Array:
	var eids := world.roster.keys()
	eids.sort_custom(func(x: int, y: int) -> bool:
		var kx := kills(x)
		var ky := kills(y)
		if kx != ky:
			return kx > ky
		if deaths(x) != deaths(y):
			return deaths(x) < deaths(y)
		return int(of(x).dmg) > int(of(y).dmg))
	return eids


func rank_of(eid: int) -> int:
	return standings().find(eid) + 1


func match_seconds() -> float:
	var t := end_clock if end_clock >= 0.0 else world.clock
	return maxf(0.0, t - (World.COUNTDOWN if not world.training else 0.0))


func display_name(eid: int) -> String:
	return String(world.roster[eid].name) if world.roster.has(eid) else "?"


func mode_text() -> String:
	var parts := [("LAN " if world.net_role != Net.Role.OFFLINE else "") + GameMode.name_of(world.game_mode)]
	if world.low_gravity:
		parts.append("Low gravity")
	if world.frag_limit > 0:
		parts.append("%d frag limit" % world.frag_limit)
	var t := roundi(match_seconds())
	parts.append("%d:%02d" % [t / 60, t % 60])
	return " · ".join(parts)


## End-of-match awards: up to `limit`, each {id, eid, title, color, value}. Ties go to the
## better-placed player. Only awards somebody actually earned are returned.
func awards(limit := 4) -> Array:
	var order := standings()
	var out := []
	for id in [Award.MVP, Award.SHARPSHOOTER, Award.RAMPAGE, Award.NUKE, Award.HEADHUNTER,
			Award.DEMOLITION, Award.LONGSHOT, Award.BRUISER]:
		if out.size() >= limit:
			break
		var best := 0
		var best_v := 0.0
		for eid: int in order:
			var v := _award_metric(id, eid)
			if v > 0.0 and (best == 0 or v > best_v):
				best = eid
				best_v = v
		if best != 0:
			var info: Dictionary = AWARD_INFO[id]
			out.append({"id": id, "eid": best, "title": info.title, "color": info.color,
					"value": _award_text(id, best, best_v)})
	return out


func _award_metric(id: int, eid: int) -> float:
	var s := of(eid)
	match id:
		Award.MVP:
			return float(kills(eid)) + 0.001 * float(s.dmg) / 100.0 if kills(eid) > 0 else 0.0
		Award.SHARPSHOOTER:
			return accuracy(eid) if s.pellets >= MIN_ACC_PELLETS and s.hits > 0 else 0.0
		Award.RAMPAGE:
			return float(s.best_spree) if s.best_spree >= 2 else 0.0
		Award.NUKE:
			return float(s.nukes)
		Award.HEADHUNTER:
			return float(s.heads)
		Award.DEMOLITION:
			return float(s.splash)
		Award.LONGSHOT:
			return float(s.longest) if s.longest >= LONGSHOT_MIN else 0.0
		Award.BRUISER:
			return float(s.dmg)
	return 0.0


func _award_text(id: int, eid: int, v: float) -> String:
	match id:
		Award.MVP:
			return "%d frags · %.1f K/D" % [kills(eid), kd(eid)]
		Award.SHARPSHOOTER:
			return "%d%% accuracy" % roundi(v * 100.0)
		Award.RAMPAGE:
			return "%d frags in a row" % int(v)
		Award.NUKE:
			return "%d Redeemer frag%s" % [int(v), "" if int(v) == 1 else "s"]
		Award.HEADHUNTER:
			return "%d headshot%s" % [int(v), "" if int(v) == 1 else "s"]
		Award.DEMOLITION:
			return "%d splash frag%s" % [int(v), "" if int(v) == 1 else "s"]
		Award.LONGSHOT:
			return "%d m frag" % roundi(v / PX_PER_M)
		Award.BRUISER:
			return "%d damage dealt" % int(v)
	return ""


static func ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		suffix = ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
	return "%d%s" % [n, suffix]


# --- icons -----------------------------------------------------------------------------

## Weapon icon fitted into `rect`: GunSprites when that script exists, else the code-drawn gun.
static func draw_gun_icon(ci: CanvasItem, wid: int, rect: Rect2, modulate := Color.WHITE) -> void:
	if wid < 0 or wid >= Weapons.COUNT:
		return
	if not _gs_checked:
		_gs_checked = true
		if ResourceLoader.exists(GUN_SPRITES):
			var s = load(GUN_SPRITES)
			if s is Script:
				for m in (s as Script).get_script_method_list():
					if m.name == "draw_icon":
						_gs = s
						break
	if _gs:
		_gs.call("draw_icon", ci, wid, rect, modulate)
		return
	var w: Dictionary = Weapons.LIST[wid]
	var length: float = w.gun_len
	var sc := minf(rect.size.x * 0.9 / (length + 6.0), rect.size.y * 0.55 / (float(w.gun_w) + 8.0))
	var xf := Transform2D(0.0, Vector2(sc, sc), 0.0, rect.get_center() + Vector2((-length * 0.5 + 1.0) * sc, -2.0 * sc))
	CharPainter.draw_gun(ci, wid, xf)


## Award emblem centred on `c`, roughly `r` in radius.
static func draw_award_icon(ci: CanvasItem, id: int, c: Vector2, r: float, col: Color) -> void:
	DrawUtil.glow(ci, c, r * 1.9, Color(col, 0.28))
	DrawUtil.ring(ci, c, r, 1.6, Color(col, 0.55), 40)
	var dark := Color(0.03, 0.04, 0.08)
	var lite := col.lerp(Color.WHITE, 0.45)
	match id:
		Award.MVP:                                        # crown
			var by := c.y + r * 0.38
			var ty := c.y - r * 0.42
			DrawUtil.rect(ci, Rect2(c.x - r * 0.55, by - r * 0.16, r * 1.1, r * 0.22), col)
			for i in 3:
				var x := c.x + (i - 1) * r * 0.42
				var h := ty - (r * 0.12 if i == 1 else 0.0)
				DrawUtil.quad(ci, Vector2(x - r * 0.24, by - r * 0.14), Vector2(x, h), Vector2(x + r * 0.24, by - r * 0.14),
						Vector2(x + r * 0.24, by - r * 0.14), col)
				DrawUtil.circle(ci, Vector2(x, h - r * 0.06), r * 0.08, lite)
			DrawUtil.circle(ci, Vector2(c.x, by - r * 0.05), r * 0.06, dark)
		Award.SHARPSHOOTER:                               # crosshair
			DrawUtil.ring(ci, c, r * 0.5, 2.2, col, 32)
			for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				DrawUtil.line(ci, c + d * r * 0.22, c + d * r * 0.78, col, 2.6)
			DrawUtil.circle(ci, c, r * 0.09, lite)
		Award.RAMPAGE:                                    # flame
			var b := c + Vector2(0, r * 0.5)
			DrawUtil.fan(ci, PackedVector2Array([b + Vector2(0, 0), b + Vector2(-r * 0.42, -r * 0.3),
					b + Vector2(-r * 0.3, -r * 0.8), b + Vector2(0, -r * 1.25), b + Vector2(r * 0.3, -r * 0.8),
					b + Vector2(r * 0.42, -r * 0.3)]), col)
			DrawUtil.fan(ci, PackedVector2Array([b + Vector2(0, -r * 0.05), b + Vector2(-r * 0.2, -r * 0.25),
					b + Vector2(-r * 0.12, -r * 0.55), b + Vector2(0, -r * 0.78), b + Vector2(r * 0.12, -r * 0.55),
					b + Vector2(r * 0.2, -r * 0.25)]), Color(1, 0.92, 0.6))
		Award.NUKE:                                       # radiation trefoil
			for i in 3:
				var a0 := -PI * 0.5 + i * TAU / 3.0 - PI / 6.0
				DrawUtil.arc(ci, c, r * 0.48, a0, a0 + PI / 3.0, r * 0.2, col, 8)
			DrawUtil.circle(ci, c, r * 0.14, col)
		Award.HEADHUNTER:                                 # skull
			DrawUtil.circle(ci, c + Vector2(0, -r * 0.1), r * 0.5, col)
			DrawUtil.rect(ci, Rect2(c.x - r * 0.28, c.y + r * 0.2, r * 0.56, r * 0.32), col)
			DrawUtil.circle(ci, c + Vector2(-r * 0.2, -r * 0.08), r * 0.13, dark)
			DrawUtil.circle(ci, c + Vector2(r * 0.2, -r * 0.08), r * 0.13, dark)
			DrawUtil.quad(ci, c + Vector2(0, r * 0.06), c + Vector2(-r * 0.07, r * 0.2), c + Vector2(r * 0.07, r * 0.2),
					c + Vector2(r * 0.07, r * 0.2), dark)
			for i in 2:
				var x := c.x - r * 0.07 + i * r * 0.14
				DrawUtil.line(ci, Vector2(x, c.y + r * 0.34), Vector2(x, c.y + r * 0.52), dark, 1.6)
		Award.DEMOLITION:                                 # explosion burst
			for i in 8:
				var ang := i * TAU / 8.0 + PI / 8.0
				var d := Vector2.from_angle(ang)
				var n := d.orthogonal()
				var len := r * (0.82 if i % 2 == 0 else 0.6)
				DrawUtil.quad(ci, c + n * r * 0.2, c + d * len, c - n * r * 0.2, c - n * r * 0.2, col)
			DrawUtil.circle(ci, c, r * 0.32, lite)
			DrawUtil.circle(ci, c, r * 0.16, Color.WHITE)
		Award.LONGSHOT:                                   # scope line + arrowhead
			var a := c + Vector2(-r * 0.62, r * 0.42)
			var tip := c + Vector2(r * 0.62, -r * 0.42)
			var d := (tip - a).normalized()
			DrawUtil.line(ci, a, tip - d * r * 0.2, col, 2.6)
			DrawUtil.quad(ci, tip, tip - d * r * 0.36 + d.orthogonal() * r * 0.2,
					tip - d * r * 0.36 - d.orthogonal() * r * 0.2, tip - d * r * 0.36 - d.orthogonal() * r * 0.2, col)
			DrawUtil.ring(ci, a, r * 0.14, 1.6, lite, 16)
			DrawUtil.ring(ci, a, r * 0.28, 1.2, Color(lite, 0.6), 20)
		Award.BRUISER:                                    # lightning bolt
			DrawUtil.quad(ci, c + Vector2(r * 0.18, -r * 0.7), c + Vector2(-r * 0.36, r * 0.08), c + Vector2(-r * 0.02, r * 0.08),
					c + Vector2(r * 0.3, -r * 0.7), col)
			DrawUtil.quad(ci, c + Vector2(r * 0.02, -r * 0.08), c + Vector2(-r * 0.3, r * 0.7), c + Vector2(r * 0.36, -r * 0.08),
					c + Vector2(r * 0.36, -r * 0.08), col)


# --- recap card (share image) ------------------------------------------------------------

## Renders the recap through a one-shot SubViewport and saves it: a browser download on the
## web, a PNG in user:// on desktop. Returns a short status line for the UI.
func save_recap() -> String:
	var img := await render_recap()
	if img == null or img.is_empty():
		return "Couldn't render the recap here"
	var buf := img.save_png_to_buffer()
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(buf, "fragline-recap.png", "image/png")
		return "Recap downloaded — share it!"
	var path := "user://fragline-recap-%s.png" % Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "Couldn't save the recap"
	f.store_buffer(buf)
	f.close()
	return "Saved: " + ProjectSettings.globalize_path(path)


## The recap as an Image (null if this renderer can't read it back, e.g. headless).
func render_recap() -> Image:
	var vp := SubViewport.new()
	vp.size = RECAP_SIZE
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var card := Control.new()
	card.size = Vector2(RECAP_SIZE)
	DrawUtil.setup(card)
	card.draw.connect(paint_recap.bind(card))
	vp.add_child(card)
	add_child(vp)
	if DisplayServer.get_name() == "headless":       # nothing is drawn: frame_post_draw never comes
		await get_tree().process_frame
		vp.queue_free()
		return null
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = null
	if is_instance_valid(vp):
		var tex := vp.get_texture()
		img = tex.get_image() if tex else null
		vp.queue_free()
	return img


func _str(ci: CanvasItem, font: Font, pos: Vector2, text: String, sz: int, col: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	ci.draw_string(font, pos, text, align, width, sz, col)


func paint_recap(ci: Control) -> void:
	var W := float(RECAP_SIZE.x)
	var H := float(RECAP_SIZE.y)
	var theme: Dictionary = world.map_def.get("theme", {})
	var top: Color = theme.get("sky_top", Color("0b1220"))
	var bottom: Color = theme.get("sky_bottom", Color("1d2a3f"))
	var edge: Color = theme.get("edge", UiTheme.ACCENT)
	var gold := UiTheme.GOLD
	var title := UiTheme.TITLE
	var font := UiTheme.FONT
	var me := world.my_eid
	var s := of(me)
	# Backdrop: map-tinted gradient, faint grid, neon glows, diagonal light streak.
	var t0 := top.darkened(0.35)
	var t1 := bottom.darkened(0.45)
	DrawUtil.quad4(ci, Vector2.ZERO, Vector2(W, 0), Vector2(W, H), Vector2(0, H), t0, t0.lerp(t1, 0.3), t1, t1.lerp(t0, 0.2))
	for x in range(0, int(W) + 1, 40):
		ci.draw_rect(Rect2(x, 0, 1, H), Color(edge, 0.05))
	for y in range(0, int(H) + 1, 40):
		ci.draw_rect(Rect2(0, y, W, 1), Color(edge, 0.05))
	DrawUtil.glow(ci, Vector2(W * 0.18, H * 0.55), 420.0, Color(edge, 0.22))
	DrawUtil.glow(ci, Vector2(W * 0.95, H * 0.05), 380.0, Color(UiTheme.ACCENT, 0.16))
	DrawUtil.quad(ci, Vector2(W * 0.52, 0), Vector2(W * 0.6, 0), Vector2(W * 0.44, H), Vector2(W * 0.36, H), Color(1, 1, 1, 0.025))
	DrawUtil.rect(ci, Rect2(0, 0, W, 4), edge)
	DrawUtil.rect(ci, Rect2(0, H - 4, W, 4), Color(edge, 0.6))
	# Brand + match line.
	_str(ci, title, Vector2(56, 92), "FRAGLINE", 64, UiTheme.ACCENT)
	_str(ci, font, Vector2(60, 122), "MATCH RECAP", 16, Color(1, 1, 1, 0.55))
	_str(ci, title, Vector2(W - 56 - 600, 70), String(world.map_def.get("name", "?")).to_upper(), 34, Color.WHITE,
			HORIZONTAL_ALIGNMENT_RIGHT, 600)
	_str(ci, font, Vector2(W - 56 - 600, 100), mode_text(), 17, Color(1, 1, 1, 0.65), HORIZONTAL_ALIGNMENT_RIGHT, 600)
	# Your fighter holding your favourite gun, with your rank beside it.
	var fav := favourite(me)
	var p: Player = world.entities.get(me)
	var look: Dictionary = p.look if p else Settings.look()
	var pose := CharPainter.Pose.new()
	pose.facing = 1.0
	pose.aim = -0.25
	pose.wid = maxi(fav, 0)
	DrawUtil.glow(ci, Vector2(175, 320), 160.0, Color(look.get("visor", edge), 0.35))
	CharPainter.draw(ci, look, pose, Transform2D(0.0, Vector2(3.9, 3.9), 0.0, Vector2(160, 318)))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)   # the painter leaves its transform set
	var rank := rank_of(me)
	var n := world.roster.size()
	_str(ci, title, Vector2(330, 300), ordinal(rank).to_upper(), 120, gold if rank == 1 else Color.WHITE)
	_str(ci, font, Vector2(336, 336), "PLACE OF %d" % n, 18, Color(1, 1, 1, 0.6))
	_str(ci, title, Vector2(336, 380), display_name(me), 30, look.get("visor", UiTheme.ACCENT))
	if rank == 1:
		DrawUtil.rect(ci, Rect2(336, 398, 132, 30), Color(gold, 0.18))
		DrawUtil.rect(ci, Rect2(336, 398, 3, 30), gold)
		_str(ci, title, Vector2(350, 420), "VICTORY", 18, gold)
	# Stat tiles (2 x 2) + favourite weapon.
	var tiles := [["FRAGS", str(kills(me))], ["K/D", "%.2f" % kd(me)],
			["ACCURACY", accuracy_text(me)], ["BEST SPREE", str(s.best_spree)]]
	for i in tiles.size():
		var r := Rect2(Vector2(700 + (i % 2) * 230, 140 + (i / 2) * 112), Vector2(214, 98))
		DrawUtil.rect(ci, r, Color(0.02, 0.03, 0.06, 0.7))
		DrawUtil.rect(ci, Rect2(r.position, Vector2(3, r.size.y)), edge)
		_str(ci, font, r.position + Vector2(20, 30), tiles[i][0], 15, Color(1, 1, 1, 0.6))
		_str(ci, title, r.position + Vector2(18, 80), tiles[i][1], 44, Color.WHITE)
	var fr := Rect2(Vector2(700, 364), Vector2(444, 76))
	DrawUtil.rect(ci, fr, Color(0.02, 0.03, 0.06, 0.7))
	DrawUtil.rect(ci, Rect2(fr.position, Vector2(3, fr.size.y)), edge)
	_str(ci, font, fr.position + Vector2(20, 28), "FAVOURITE WEAPON", 15, Color(1, 1, 1, 0.6))
	if fav >= 0:
		_str(ci, title, fr.position + Vector2(20, 62), String(Weapons.LIST[fav].name).to_upper(), 26, Weapons.LIST[fav].color)
		draw_gun_icon(ci, fav, Rect2(fr.position + Vector2(fr.size.x - 170, 8), Vector2(150, 60)))
	else:
		_str(ci, title, fr.position + Vector2(20, 62), "—", 26, Color.WHITE)
	# Awards strip.
	var aw := awards(4)
	var y := 470.0
	_str(ci, font, Vector2(56, y), "AWARDS", 15, Color(1, 1, 1, 0.55))
	if aw.is_empty():
		_str(ci, font, Vector2(56, y + 52), "No awards this time — run it back.", 20, Color(1, 1, 1, 0.7))
	var cw := (W - 112.0 - 3 * 16.0) / 4.0
	for i in aw.size():
		var a: Dictionary = aw[i]
		var r := Rect2(Vector2(56 + i * (cw + 16.0), y + 14), Vector2(cw, 88))
		var col: Color = a.color
		var mine: bool = a.eid == me
		DrawUtil.rect(ci, r, Color(col, 0.16) if mine else Color(0.02, 0.03, 0.06, 0.7))
		DrawUtil.rect(ci, Rect2(r.position, Vector2(r.size.x, 3)), col)
		draw_award_icon(ci, a.id, r.position + Vector2(42, 46), 24.0, col)
		_str(ci, title, r.position + Vector2(80, 32), a.title, 17, col)
		_str(ci, font, r.position + Vector2(80, 56), ("YOU" if mine else display_name(a.eid)), 17, Color.WHITE)
		_str(ci, font, r.position + Vector2(80, 76), a.value, 14, Color(1, 1, 1, 0.6))
	_str(ci, font, Vector2(56, H - 22), "Neon arena shooter · play free in your browser", 15, Color(1, 1, 1, 0.45))
	_str(ci, title, Vector2(W - 56 - 400, H - 22), "#FRAGLINE", 18, Color(edge, 0.9), HORIZONTAL_ALIGNMENT_RIGHT, 400)
