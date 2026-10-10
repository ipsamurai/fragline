class_name Hud
extends CanvasLayer
## In-match HUD, drawn with plain draw calls on one Control (cheap: one canvas item).
## Also owns the pause overlay and the announcer messages (multi-kills, sprees).

const FONT := UiTheme.TITLE
const FONT_N := UiTheme.FONT
const MULTI := ["", "", "DOUBLE KILL", "MULTI KILL", "MEGA KILL", "ULTRA KILL", "MONSTER KILL"]
const SPREES := {5: "KILLING SPREE", 10: "RAMPAGE", 15: "DOMINATING", 20: "UNSTOPPABLE", 25: "GODLIKE"}
const MULTI_WINDOW := 3.0
const ACCENT := UiTheme.ACCENT

var world: World
var _canvas: Control
var _pause: Control
var _pause_box: VBoxContainer
var _results: Control
var _feed: Array[Dictionary] = []     # {text, color, t}
var _msg := ""
var _msg_sub := ""
var _msg_color := Color.WHITE
var _msg_t := 0.0
var _hit_t := 0.0
var _hit_head := false
var _hurt_t := 0.0
var _flash_t := 0.0
var _multi := 0
var _last_kill := -10.0
var _spree := 0
var _first_blood := false
var _show_end := false


func _ready() -> void:
	UiTheme.get_theme()                    # also sets the fonts' fallback for symbols like ∞
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_hud)
	add_child(_canvas)
	_build_pause()


func _process(delta: float) -> void:
	_msg_t -= delta
	_hit_t -= delta
	_hurt_t -= delta
	_flash_t -= delta
	for f in _feed:
		f.t -= delta
	_feed = _feed.filter(func(f: Dictionary) -> bool: return f.t > 0.0)
	_canvas.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not world.ended and not world.demo:
		_toggle_pause()
		get_viewport().set_input_as_handled()


# --- messages from World ----------------------------------------------------------

func message(text: String, sub := "", color := Color.WHITE, time := 2.2) -> void:
	_msg = text
	_msg_sub = sub
	_msg_color = color
	_msg_t = time


func hit_marker(head: bool) -> void:
	_hit_t = 0.18
	_hit_head = head
	Sfx.play("ui_click", -10.0, 1.6 if head else 1.2)


func hurt(_amount: int) -> void:
	_hurt_t = 0.45


func flash(time: float) -> void:
	_flash_t = time


func pickup_message(it: Dictionary) -> void:
	var names := {"h": "+25 Health", "H": "Mega Health", "a": "+50 Armor", "D": "DAMAGE AMP!"}
	var text: String = names.get(it.type, Weapons.LIST[it.wid].name if it.wid >= 0 else "")
	_feed.append({"text": "+ " + text, "color": world.pickups.color_of(it), "t": 2.0})


func on_death(victim: int, killer: int, wid: int) -> void:
	var r := world.roster
	var vname: String = r[victim].name if r.has(victim) else "?"
	var kname: String = r[killer].name if r.has(killer) else "?"
	var env := {World.HAZARD: "void" if world.level.def.style in ["city", "space"] else "lava",
			World.LASER: "laser", World.VENT: "vent", World.PURGE: "spawn purge"}
	var text: String
	if killer == victim:
		text = "%s  died to the %s" % [vname, env[wid]] if env.has(wid) else "%s  self-destructed" % vname
	else:
		var how: String = env[wid] if env.has(wid) else String(Weapons.LIST[wid].name)
		text = "%s  [%s]  %s" % [kname, how, vname]
	var mine := killer == world.my_eid or victim == world.my_eid
	_feed.append({"text": text, "color": ACCENT if mine else Color(0.85, 0.88, 0.95), "t": 6.0})
	if _feed.size() > 6:
		_feed.pop_front()
	if killer != victim and not _first_blood:
		_first_blood = true
		if killer == world.my_eid:
			message("FIRST BLOOD", "", Color("ff4d6d"))
			Sfx.play("frag")
			return
	if victim == world.my_eid:
		_spree = 0
		_multi = 0
		if killer != victim and r.has(killer):
			message("FRAGGED", "by %s" % kname, Color("ff4d6d"))
	elif killer == world.my_eid:
		_spree += 1
		_multi = _multi + 1 if world.clock - _last_kill < MULTI_WINDOW else 1
		_last_kill = world.clock
		Sfx.play("frag", -4.0)
		if SPREES.has(_spree):
			message(SPREES[_spree], "%d frags without dying" % _spree, Color("ffd166"), 2.6)
		elif _multi >= 2:
			message(MULTI[mini(_multi, MULTI.size() - 1)], "", Color("ff9f1c"))
		else:
			message("You fragged %s" % vname, "", Color.WHITE, 1.6)


func show_end(winner: int) -> void:
	_show_end = true
	var name: String = world.roster[winner].name
	message("VICTORY" if winner == world.my_eid else "%s WINS" % name.to_upper(), "", Color("ffd166"), 1e9)
	Sfx.play("pickup_power")
	_results.visible = true
	var again: Button = _results.get_child(0).get_child(0)
	if world.is_net_client():                       # only the host can start the next match
		again.text = "Waiting for the host…"
		again.disabled = true
		(_results.get_child(0).get_child(1) as Button).text = "Leave"
	else:
		again.grab_focus()


# --- pause + results overlays --------------------------------------------------------

func _build_pause() -> void:
	_pause = ColorRect.new()
	(_pause as ColorRect).color = Color(0.02, 0.03, 0.06, 0.78)
	_pause.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.theme = UiTheme.get_theme()
	_pause.visible = false
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	_pause_box = VBoxContainer.new()
	_pause_box.custom_minimum_size.x = 300
	panel.add_child(_pause_box)
	_show_pause_menu()
	add_child(_pause)

	# Results: buttons under the scoreboard once the match is over.
	_results = MarginContainer.new()
	_results.theme = UiTheme.get_theme()
	_results.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 60)
	_results.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_results.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_results.visible = false
	var row := HBoxContainer.new()
	row.add_child(UiTheme.button("Play again", func() -> void: world.restart_requested.emit()))
	row.add_child(UiTheme.button("Main menu", func() -> void: world.menu_requested.emit()))
	_results.add_child(row)
	add_child(_results)


func _show_pause_menu() -> void:
	for c in _pause_box.get_children():
		c.queue_free()
	var title := UiTheme.label("PAUSED", "Title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_box.add_child(title)
	var first := UiTheme.button("Resume", _toggle_pause, "BigButton")
	_pause_box.add_child(first)
	_pause_box.add_child(UiTheme.button("Settings", _show_pause_settings, "BigButton"))
	if not world.is_net_client():
		_pause_box.add_child(UiTheme.button("Restart match", func() -> void: world.restart_requested.emit(), "BigButton"))
	_pause_box.add_child(UiTheme.button("Leave match" if world.net_role != Net.Role.OFFLINE else "Main menu",
			func() -> void: world.menu_requested.emit(), "BigButton"))
	first.grab_focus.call_deferred()


func _show_pause_settings() -> void:
	for c in _pause_box.get_children():
		c.queue_free()
	_pause_box.add_child(UiTheme.label("SETTINGS", "Title"))
	_pause_box.add_child(SettingsPanel.new())
	var back := UiTheme.button("Back", _show_pause_menu)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_pause_box.add_child(back)


func _toggle_pause() -> void:
	_pause.visible = not _pause.visible
	if _pause.visible:
		_show_pause_menu()
	world.set_paused(_pause.visible)


# --- drawing -----------------------------------------------------------------------

func _draw_hud() -> void:
	var c := _canvas
	var size := c.size
	var p := world.local_player
	if _hurt_t > 0.0 or (p.alive and p.health <= 30):
		var k := maxf(_hurt_t / 0.45, 0.35 + 0.15 * sin(world.clock * 6.0) if p.health <= 30 and p.alive else 0.0)
		_vignette(c, size, Color(0.9, 0.05, 0.1, 0.45 * k))
	if _flash_t > 0.0:
		c.draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, clampf(_flash_t, 0.0, 0.8)))
	# Status glow on the screen edges so you notice you're burning / poisoned / chilled.
	for kind in p.status:
		_vignette(c, size, Color(Status.INFO[kind].color, 0.16 + 0.06 * sin(world.clock * 8.0)))
	if _show_end:
		c.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.06, 0.6))   # results backdrop
	elif p.alive:
		_draw_vitals(c, size, p)
		_draw_weapons(c, size, p)
		_draw_spawn_room(c, size, p)
	else:
		_text(c, Vector2(size.x * 0.5, size.y * 0.62), "Respawning...", 20, Color(1, 1, 1, 0.8), FONT_N)
	_draw_score(c, size)
	_draw_feed(c, size)
	if _msg_t > 0.0:
		var a := clampf(_msg_t / 0.4, 0.0, 1.0)
		_text(c, Vector2(size.x * 0.5, size.y * 0.27), _msg, 40, Color(_msg_color, a), FONT, true)
		if _msg_sub != "":
			_text(c, Vector2(size.x * 0.5, size.y * 0.27 + 34), _msg_sub, 18, Color(1, 1, 1, 0.8 * a), FONT_N, true)
	if world.in_countdown():
		var n := ceili(world.countdown)
		_text(c, Vector2(size.x * 0.5, size.y * 0.42), str(n), 96, Color(ACCENT, 0.9), FONT, true)
		_text(c, Vector2(size.x * 0.5, size.y * 0.42 + 40), "GET READY", 18, Color(1, 1, 1, 0.8), FONT_N, true)
	if Input.is_action_pressed("scoreboard") or _show_end:
		_draw_scoreboard(c, size)
	if not _pause.visible and not _show_end:
		_draw_crosshair(c, c.get_local_mouse_position(), p, p.alive and p.in_no_fire_zone())


func _text(c: Control, pos: Vector2, s: String, sz: int, col: Color, font: Font = FONT, outline := false,
		align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var w := 1000.0
	var x := pos.x - w * 0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else (pos.x - w if align == HORIZONTAL_ALIGNMENT_RIGHT else pos.x)
	if outline:
		c.draw_string_outline(font, Vector2(x, pos.y), s, align, w, sz, 6, Color(0, 0, 0, col.a * 0.6))
	c.draw_string(font, Vector2(x, pos.y), s, align, w, sz, col)


func _panel(c: Control, r: Rect2) -> void:
	c.draw_rect(r, Color(0.04, 0.06, 0.1, 0.62))
	c.draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color(ACCENT, 0.5))


func _vignette(c: Control, size: Vector2, col: Color) -> void:
	var clear := Color(col, 0.0)
	var e := minf(size.x, size.y) * 0.18
	for r in [[Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, e), Vector2(0, e), true],
			[Vector2(0, size.y - e), Vector2(size.x, size.y - e), size, Vector2(0, size.y), false]]:
		var top: Color = col if r[4] else clear
		var bot: Color = clear if r[4] else col
		c.draw_polygon(PackedVector2Array([r[0], r[1], r[2], r[3]]), PackedColorArray([top, top, bot, bot]))
	c.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(e, 0), Vector2(e, size.y), Vector2(0, size.y)]),
			PackedColorArray([col, clear, clear, col]))
	c.draw_polygon(PackedVector2Array([Vector2(size.x - e, 0), Vector2(size.x, 0), size, Vector2(size.x - e, size.y)]),
			PackedColorArray([clear, col, col, clear]))


func _draw_vitals(c: Control, size: Vector2, p: Player) -> void:
	var base := Vector2(24, size.y - 24)
	_panel(c, Rect2(base + Vector2(-10, -92), Vector2(330, 102)))
	var hc := Color("4ade80") if p.health > 60 else (Color("fbbf24") if p.health > 30 else Color("f87171"))
	_text(c, base + Vector2(0, -26), str(p.health), 40, hc, FONT, false, HORIZONTAL_ALIGNMENT_LEFT)
	_text(c, base + Vector2(0, -74), "HEALTH", 11, Color(1, 1, 1, 0.6), FONT_N, false, HORIZONTAL_ALIGNMENT_LEFT)
	c.draw_rect(Rect2(base + Vector2(0, -14), Vector2(140, 7)), Color(1, 1, 1, 0.1))
	c.draw_rect(Rect2(base + Vector2(0, -14), Vector2(140 * minf(p.health / 100.0, 1.0), 7)), hc)
	if p.health > 100:
		c.draw_rect(Rect2(base + Vector2(0, -5), Vector2(140 * (p.health - 100) / 99.0, 3)), Color("38bdf8"))
	var ac := Color("fbbf24")
	_text(c, base + Vector2(170, -26), str(p.armor), 40, ac if p.armor > 0 else Color(1, 1, 1, 0.35), FONT, false, HORIZONTAL_ALIGNMENT_LEFT)
	_text(c, base + Vector2(170, -74), "ARMOR", 11, Color(1, 1, 1, 0.6), FONT_N, false, HORIZONTAL_ALIGNMENT_LEFT)
	c.draw_rect(Rect2(base + Vector2(170, -14), Vector2(140, 7)), Color(1, 1, 1, 0.1))
	c.draw_rect(Rect2(base + Vector2(170, -14), Vector2(140 * p.armor / 150.0, 7)), ac)
	# Power-up + status pills stacked above the vitals panel.
	var pill_x := base.x - 10.0
	var pill_y := base.y - 122.0
	if p.amp_time > 0.0:
		pill_x = _pill(c, Vector2(pill_x, pill_y), "DAMAGE AMP %d" % ceili(p.amp_time), Color("c084fc"))
	for kind in p.status:
		var info: Dictionary = Status.INFO[kind]
		pill_x = _pill(c, Vector2(pill_x, pill_y), "%s %d" % [info.name, ceili(p.status[kind])], info.color)


## Small rounded label; returns the x where the next pill should start.
func _pill(c: Control, pos: Vector2, text: String, col: Color) -> float:
	var w := FONT_N.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 20.0
	var r := Rect2(pos, Vector2(w, 22))
	c.draw_rect(r, Color(col, 0.18))
	c.draw_rect(r, Color(col, 0.8), false, 1.5)
	c.draw_string(FONT_N, pos + Vector2(10, 16), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col.lerp(Color.WHITE, 0.3))
	return pos.x + w + 6.0


func _draw_weapons(c: Control, size: Vector2, p: Player) -> void:
	# Current weapon + ammo (bottom right).
	var w: Dictionary = Weapons.LIST[p.weapon]
	var right := Vector2(size.x - 24, size.y - 24)
	_panel(c, Rect2(right + Vector2(-230, -92), Vector2(240, 102)))
	var ammo_text := "∞" if Weapons.infinite(p.weapon) else str(p.ammo[p.weapon])
	_text(c, right + Vector2(0, -16), ammo_text, 40, Color.WHITE, FONT, false, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(c, right + Vector2(0, -74), String(w.name).to_upper(), 12, w.color, FONT_N, false, HORIZONTAL_ALIGNMENT_RIGHT)
	# Weapon slots (bottom centre).
	var slot := Vector2(50, 40)
	var gap := 6.0
	var total := Weapons.COUNT * slot.x + (Weapons.COUNT - 1) * gap
	var x0 := (size.x - total) * 0.5
	var y := size.y - 24 - slot.y
	for i in Weapons.COUNT:
		var r := Rect2(Vector2(x0 + i * (slot.x + gap), y), slot)
		var owned := p.owns(i)
		var current := i == p.weapon
		var col: Color = Weapons.LIST[i].color
		if current:
			r = r.grow(3)
			r.position.y -= 6
		c.draw_rect(r, Color(0.04, 0.06, 0.1, 0.75 if owned else 0.35))
		c.draw_rect(r, Color(col, 0.9) if current else Color(1, 1, 1, 0.12 if owned else 0.05), false, 2.0 if current else 1.0)
		if owned:
			var alpha := 1.0 if p.has_ammo(i) else 0.3
			var len: float = Weapons.LIST[i].gun_len
			var s := 0.95
			var xf := Transform2D(0.0, Vector2(s, s), 0.0, r.get_center() + Vector2(-len * 0.5 * s + 2, -3))
			c.modulate = Color(1, 1, 1, alpha)
			CharPainter.draw_gun(c, i, xf)
			c.modulate = Color.WHITE
			if not Weapons.infinite(i):
				_text(c, r.end - Vector2(4, 3), str(p.ammo[i]), 10, Color(1, 1, 1, 0.75 * alpha), FONT_N, false, HORIZONTAL_ALIGNMENT_RIGHT)
		_text(c, r.position + Vector2(4, 12), str(i + 1), 10, Color(1, 1, 1, 0.5), FONT_N, false, HORIZONTAL_ALIGNMENT_LEFT)


## Banner while inside a spawn room: weapons offline + how long until the purge.
func _draw_spawn_room(c: Control, size: Vector2, p: Player) -> void:
	if world.level.zone_at(p.global_position) < 0:
		return
	var allowance := world.zone_allowance(p)
	var left := allowance - p.zone_time
	var r := Rect2(Vector2(size.x * 0.5 - 190, 92), Vector2(380, 50))
	var purging := left <= 0.0
	var col := Color("ff4d6d") if purging or left < 2.0 else ACCENT
	_panel(c, r)
	if purging:
		var a := 0.6 + 0.4 * sin(world.clock * 14.0)
		_text(c, r.position + Vector2(190, 24), "LEAVE THE SPAWN ROOM!", 18, Color(col, a), FONT, true)
		_text(c, r.position + Vector2(190, 42), "spawn purge active", 12, Color(1, 1, 1, 0.7), FONT_N)
	else:
		_text(c, r.position + Vector2(190, 22), "SPAWN ROOM  ·  weapons offline", 14, Color(1, 1, 1, 0.85), FONT_N)
		c.draw_rect(Rect2(r.position + Vector2(16, 32), Vector2(348, 6)), Color(1, 1, 1, 0.12))
		c.draw_rect(Rect2(r.position + Vector2(16, 32), Vector2(348 * clampf(left / allowance, 0.0, 1.0), 6)), col)
		_text(c, r.position + Vector2(364, 46), "%.1fs" % left, 11, col, FONT_N, false, HORIZONTAL_ALIGNMENT_RIGHT)


func _sorted_roster() -> Array:
	var rows := []
	for eid in world.roster:
		rows.append([eid, world.roster[eid]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1].kills > b[1].kills)
	return rows


func _draw_score(c: Control, _size: Vector2) -> void:
	if world.training:
		_panel(c, Rect2(Vector2(14, 14), Vector2(220, 62)))
		_text(c, Vector2(26, 42), "TRAINING ROOM", 18, Color("ffc93c"), FONT, false, HORIZONTAL_ALIGNMENT_LEFT)
		_text(c, Vector2(26, 64), "T — dummies & options", 13, Color(1, 1, 1, 0.7), FONT_N, false, HORIZONTAL_ALIGNMENT_LEFT)
		return
	var rows := _sorted_roster()
	var me: Dictionary = world.roster[world.my_eid]
	var rank := 1
	for i in rows.size():
		if rows[i][0] == world.my_eid:
			rank = i + 1
	_panel(c, Rect2(Vector2(14, 14), Vector2(200, 62)))
	_text(c, Vector2(26, 50), "%d" % me.kills, 30, Color.WHITE, FONT, false, HORIZONTAL_ALIGNMENT_LEFT)
	_text(c, Vector2(80, 38), ("FRAGS / %d" % world.frag_limit) if world.frag_limit > 0 else "FRAGS", 11, Color(1, 1, 1, 0.6), FONT_N, false, HORIZONTAL_ALIGNMENT_LEFT)
	_text(c, Vector2(80, 58), "%s of %d" % [_ordinal(rank), rows.size()], 15, ACCENT, FONT_N, false, HORIZONTAL_ALIGNMENT_LEFT)
	if world.time_limit > 0.0:
		var t := ceili(world.time_left())
		_panel(c, Rect2(Vector2(222, 14), Vector2(92, 62)))
		_text(c, Vector2(268, 38), "TIME", 11, Color(1, 1, 1, 0.6), FONT_N)
		_text(c, Vector2(268, 62), "%d:%02d" % [floori(t / 60.0), t % 60], 22, Color("f87171") if t <= 30 else Color.WHITE, FONT)


func _ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		suffix = ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
	return "%d%s" % [n, suffix]


func _draw_feed(c: Control, size: Vector2) -> void:
	var y := 34.0
	for f in _feed:
		var a := clampf(f.t / 0.5, 0.0, 1.0)
		_text(c, Vector2(size.x - 20, y), f.text, 14, Color(f.color, a), FONT_N, true, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 22.0


func _draw_scoreboard(c: Control, size: Vector2) -> void:
	var rows := _sorted_roster()
	var w := 460.0
	var h := 70.0 + rows.size() * 30.0
	var r := Rect2(Vector2((size.x - w) * 0.5, size.y * 0.36), Vector2(w, h))
	_panel(c, r)
	_text(c, r.position + Vector2(20, 32), "PLAYER", 12, Color(1, 1, 1, 0.6), FONT_N, false, HORIZONTAL_ALIGNMENT_LEFT)
	_text(c, r.position + Vector2(w - 110, 32), "FRAGS", 12, Color(1, 1, 1, 0.6), FONT_N, false, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(c, r.position + Vector2(w - 20, 32), "DEATHS", 12, Color(1, 1, 1, 0.6), FONT_N, false, HORIZONTAL_ALIGNMENT_RIGHT)
	for i in rows.size():
		var eid: int = rows[i][0]
		var d: Dictionary = rows[i][1]
		var y := r.position.y + 64 + i * 30
		var col := ACCENT if eid == world.my_eid else Color.WHITE
		_text(c, Vector2(r.position.x + 20, y), "%d.  %s" % [i + 1, d.name], 17, col, FONT_N, false, HORIZONTAL_ALIGNMENT_LEFT)
		_text(c, Vector2(r.position.x + w - 110, y), str(d.kills), 17, col, FONT, false, HORIZONTAL_ALIGNMENT_RIGHT)
		_text(c, Vector2(r.position.x + w - 20, y), str(d.deaths), 17, Color(col, 0.6), FONT, false, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_crosshair(c: Control, m: Vector2, p: Player, blocked := false) -> void:
	var col: Color = Weapons.LIST[p.weapon].color.lerp(Color.WHITE, 0.5)
	if blocked:                      # weapons offline: a crossed-out ring instead
		c.draw_arc(m, 9.0, 0.0, TAU, 20, Color(1, 0.35, 0.4, 0.9), 2.0, true)
		c.draw_line(m + Vector2(-6, 6), m + Vector2(6, -6), Color(1, 0.35, 0.4, 0.9), 2.0, true)
		return
	var gap := 5.0
	var len := 7.0
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		c.draw_line(m + d * gap, m + d * (gap + len), Color(0, 0, 0, 0.6), 4.0)
		c.draw_line(m + d * gap, m + d * (gap + len), col, 2.0)
	c.draw_circle(m, 1.5, col)
	if _hit_t > 0.0:
		var hc := Color(1, 0.8, 0.2) if _hit_head else Color(1, 0.3, 0.3)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			c.draw_line(m + d * 7.0, m + d * 14.0, hc, 2.5, true)
