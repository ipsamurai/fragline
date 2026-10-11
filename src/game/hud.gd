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

# Announcer + big centre callouts (UT style).
const MULTI_COL := [Color.WHITE, Color.WHITE, Color("ffb703"), Color("ff9f1c"), Color("ff6b35"), Color("ff3d7f"), Color("ff1744")]
const MULTI_SAY := ["", "", "Double kill!", "Multi kill!", "Mega kill!", "Ultra kill!", "Monster kill!"]
const SPREE_COL := {5: Color("ffd166"), 10: Color("ffb703"), 15: Color("ff9f1c"), 20: Color("ff4d6d"), 25: Color("c77dff")}
const SPREE_SAY := {5: "Killing spree!", 10: "Rampage!", 15: "Dominating!", 20: "Unstoppable!", 25: "Godlike!"}
const FRAG_CALLS := {5: ["5 FRAGS REMAIN", "Five frags remain."], 3: ["3 FRAGS REMAIN", "Three frags remain."],
		1: ["1 FRAG REMAINS", "One frag remains."]}
const TIME_CALLS := [[300.0, "5 MINUTES REMAIN", "Five minutes remain."], [60.0, "1 MINUTE REMAINS", "One minute remains."],
		[30.0, "30 SECONDS REMAIN", "Thirty seconds remain."]]
const COUNT_SAY := ["", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten"]
const MSG_POP := [1.15, 1.4, 1.45, 1.6]       # pop-in start scale per tier
const MSG_SIZE := [40, 44, 48, 54]            # font size per tier
const HEAD_WINDOW := 0.1                      # s between a noted headshot and the kill it caused
var _msg_len := 1.0                           # how long the current message was shown for
var _msg_prio := 0
var _msg_pop := 1.15
var _msg_size := 40
var _msg_shake := 0.0
var _lead := 0                                # you: 0 behind, 1 tied for the lead, 2 leading
var _frag_called := {}                        # frags-remaining calls already made
var _time_prev := -1.0
var _head_by := {}                            # victim eid -> attacker of their last headshot
var _head_at := {}                            # victim eid -> world.clock of that headshot


## Big centre message. An active message is replaced only by one of equal or higher `prio`
## (results 9, callouts 3, headshot/humiliation 2, info 1, time ticks 0). `tier`: 0 plain,
## 1 callout pop, 2 multi-kill pop + shake, 3 headline. Returns false if it was outranked.
func message(text: String, sub := "", color := Color.WHITE, time := 2.2, prio := 1, tier := 0) -> bool:
	if time >= 1e6:                                  # the results headline (show_end)
		prio = 9
		tier = 3
	if _msg_t > 0.0 and prio < _msg_prio:
		return false
	_msg = text
	_msg_sub = sub
	_msg_color = color
	_msg_t = time
	_msg_len = time
	_msg_prio = prio
	_msg_pop = MSG_POP[clampi(tier, 0, 3)]
	_msg_size = MSG_SIZE[clampi(tier, 0, 3)]
	_msg_shake = 0.0
	return true


func hit_marker(head: bool) -> void:
	_hit_t = 0.18
	_hit_head = head
	_sfx("ui_click", -10.0, 1.6 if head else 1.2)


## Announcer line for "you" (never for the menu's background match).
## End-of-match lines (show_end) are always CRITICAL.
func _announce(text: String, prio := Announcer.NORMAL) -> void:
	if not world.demo:
		Announcer.say(text, Announcer.CRITICAL if _show_end else prio)


## Feedback sounds for "you" — silent for the menu's background match, where eid 1 is a bot.
func _sfx(n: String, db := 0.0, pitch := 1.0) -> void:
	if not world.demo:
		Sfx.play(n, db, pitch)


func hurt(_amount: int) -> void:
	_hurt_t = 0.45


func flash(time: float) -> void:
	_flash_t = time


## Pickup toast above the weapon bar: gun sprite (or a small glyph) + "+ Rocket Launcher".
func pickup_message(it: Dictionary) -> void:
	var names := {"h": "+25 Health", "H": "Mega Health", "a": "+50 Armor", "D": "DAMAGE AMP!"}
	var wid: int = it.wid if not names.has(it.type) and it.wid >= 0 and it.wid < Weapons.COUNT else -1
	var text: String = names.get(it.type, Weapons.LIST[it.wid].name if it.wid >= 0 else "")
	if wid >= 0:
		text = "+ " + text
	var iw := _fit_w(wid, TOAST_ICON) if wid >= 0 else 18.0
	var tw := FONT_N.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TOAST_SZ).x
	_toasts.append({"text": text, "color": world.pickups.color_of(it), "wid": wid, "type": it.type,
			"iw": iw, "w": 12.0 + iw + 8.0 + tw + 14.0, "end": _now() + 2.2})
	if _toasts.size() > 3:
		_toasts.pop_front()


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
	var first_blood := killer != victim and not _first_blood
	if first_blood:
		_first_blood = true
	# Callouts are for "you" only (bots' achievements stay in the kill feed). Every LAN peer runs
	# this with its own my_eid, so clients announce their own frags.
	var shown := false                                 # a callout of ours is up: extras go on its sub-line
	if victim == world.my_eid:
		_spree = 0
		_multi = 0
		if killer != victim and r.has(killer):
			shown = message("FRAGGED", "by %s" % kname, Color("ff4d6d"), 2.2, 3, 1)
	elif killer == world.my_eid:
		_spree += 1
		_multi = _multi + 1 if world.clock - _last_kill < MULTI_WINDOW else 1
		_last_kill = world.clock
		_sfx("frag", 0.0 if first_blood else -4.0)
		var sub := "You fragged %s" % vname
		var mi := mini(_multi, MULTI.size() - 1)
		var done := false                              # the headline is taken; later callouts are voice-only
		if first_blood:
			done = true
			message("FIRST BLOOD", sub, Color("ff4d6d"), 2.4, 3, 3)
			_announce("First blood!", Announcer.HIGH)
		elif SPREES.has(_spree):
			done = true
			message(SPREES[_spree], "%d frags without dying" % _spree, SPREE_COL[_spree], 2.6, 3, 3)
			_announce(SPREE_SAY[_spree], Announcer.HIGH)
		if _multi >= 2:
			if not done and message(MULTI[mi], sub, MULTI_COL[mi], 2.2, 3, 2):
				_msg_shake = 2.0 + 2.0 * mi             # MONSTER KILL rattles hardest
			done = true
			_announce(MULTI_SAY[mi], Announcer.HIGH)
		if _was_headshot(victim, killer):
			if not done:
				message("HEADSHOT", sub, Color("fff3b0"), 1.8, 2, 1)
			done = true
			_announce("Headshot!")
		if wid == Weapons.ENFORCER and r.has(victim) and int(r[victim].kills) >= 5:
			if not done:
				message("HUMILIATION", sub, Color("ff8fd8"), 2.0, 2, 1)
			done = true
			_announce("Humiliation!")
		if not done:
			message(sub, "", Color.WHITE, 1.6, 1, 0)
		shown = _msg_t > 0.0
	# Match-state lines (after every frag, whoever scored): lead changes and frags remaining.
	var extra := ""
	var extra_col := Color("ffd166")
	var lead := _lead_check()
	if not lead.is_empty():
		extra = lead[0]
		extra_col = lead[2]
		_announce(lead[1])
	var remain := _frags_remaining_check()
	if not remain.is_empty():
		extra = remain[0] if extra == "" else extra + "  ·  " + remain[0]
		_announce(remain[1])
	if extra != "":
		if shown:
			_msg_sub = extra if _msg_sub == "" else _msg_sub + "  ·  " + extra
		else:
			message(extra, "", extra_col, 2.0, 1, 1)


## World calls this from Ev.HIT when a hit was a headshot (`a[5]`), so the kill it causes says "Headshot!".
func note_headshot(victim: int, attacker: int) -> void:
	_head_by[victim] = attacker
	_head_at[victim] = world.clock


func _was_headshot(victim: int, killer: int) -> bool:
	if _head_by.get(victim, 0) == killer and world.clock - float(_head_at.get(victim, -1e9)) <= HEAD_WINDOW:
		return true
	return _hit_head and _hit_t > 0.15          # fallback: hit_marker() just flagged our headshot


## Your lead changed since the last frag: [shown, spoken, colour], else []. Never in training.
func _lead_check() -> Array:
	var r := world.roster
	if world.training or world.demo or not r.has(world.my_eid) or r.size() < 2:
		return []
	var mine: int = r[world.my_eid].kills
	var best := -1000000
	for eid in r:
		if eid != world.my_eid:
			best = maxi(best, int(r[eid].kills))
	var state := 2 if mine > best and mine > 0 else (1 if mine == best and mine > 0 else 0)
	var was := _lead
	_lead = state
	if state == was:
		return []
	if state == 2:
		return ["YOU HAVE TAKEN THE LEAD", "You have taken the lead!", ACCENT]
	if state == 1:
		return ["TIED FOR THE LEAD", "Tied for the lead!", Color("ffd166")]
	return ["YOU HAVE LOST THE LEAD", "You have lost the lead!", Color("ff4d6d")]


## The leader just reached 5 / 3 / 1 frags from the limit (each called once a match): [shown, spoken], else [].
func _frags_remaining_check() -> Array:
	if world.frag_limit <= 0 or world.training or world.demo:
		return []
	var top := -1000000
	for eid in world.roster:
		top = maxi(top, int(world.roster[eid].kills))
	var left := world.frag_limit - top
	if not FRAG_CALLS.has(left) or left >= world.frag_limit or _frag_called.has(left):
		return []
	_frag_called[left] = true
	return FRAG_CALLS[left]


## Timed matches: World calls this every physics frame once the countdown is over (no allocations
## unless a line fires). 5 min / 1 min / 30 s warnings, then a spoken 10..1.
func time_warnings(left: float) -> void:
	var prev := _time_prev
	_time_prev = left
	if prev < 0.0 or left >= prev or _show_end or world.demo:
		return
	for tc: Array in TIME_CALLS:
		var th: float = tc[0]
		if prev > th and left <= th and world.time_limit > th + 1.0:
			message(tc[1], "", Color("ffd166"), 2.2, 2, 1)
			_announce(tc[2])
			return
	var n := ceili(left)
	if n >= 1 and n <= 10 and ceili(prev) > n:
		message(str(n), "", Color("ff4d6d"), 0.9, 0, 1)
		_announce(COUNT_SAY[n], Announcer.LOW)


func show_end(winner: int) -> void:
	_show_end = true
	if _pause.visible:                              # LAN: the match ended under the pause menu
		_pause.visible = false
		world.set_paused(false)
	var name: String = world.roster.get(winner, {"name": "?"}).name
	if winner == 0:
		message("DRAW", "nobody takes it", Color("ffd166"), 1e9)
		_announce("Draw!")
	else:
		message("VICTORY" if winner == world.my_eid else "%s WINS" % name.to_upper(), "", Color("ffd166"), 1e9)
		_announce("Flawless victory!" if winner == world.my_eid and world.roster.get(winner, {}).get("deaths", 1) == 0
				else ("Victory!" if winner == world.my_eid else "You have lost the match."))
	_sfx("pickup_power")
	_results.visible = true
	_build_results(winner)                          # post-match panel; reveals itself after a beat
	var again: Button = _res_again
	if world.is_net_client():                       # only the host can start the next match
		again.text = "Waiting for the host…"
		again.disabled = true
		_res_menu.text = "Leave"
	else:
		# Focus later, so a held Space/jump at the final frag doesn't instantly press "Play again".
		# A bound method (not a lambda) so the connection dies with the HUD if the world is freed.
		get_tree().create_timer(1.2, true).timeout.connect(_focus_again)


func _focus_again() -> void:
	if is_instance_valid(_res_again) and _res_again.is_visible_in_tree():
		_res_again.grab_focus()


# --- post-match results panel (built once, in show_end) ---------------------------------

const RES_REVEAL := 1.0                       # real seconds of headline + scoreboard before the panel
const RES_GOLD := Color("ffc93c")
const RES_RED := Color("ff4d6d")
var _res_root: Control
var _res_again: Button
var _res_menu: Button
var _res_recap: Button
var _res_note: Label
var _res_shown := false                       # panel revealed: the canvas scoreboard steps aside
var _res_counters: Array = []                 # [Label, target, kind] - kind 0 int, 1 percent, 2 x.xx
var _sb_rows: Array = []                      # cached Tab-scoreboard rows (see _sb_refresh)
var _sb_sig := -1
var _sb_ver := -1
var _sb_ms := 0


func _stats() -> MatchStats:
	return world.get_node_or_null(^"MatchStats") as MatchStats


func _res_label(text: String, sz: int, col := Color.WHITE, font: Font = FONT_N,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _res_box(bg: Color, border: Color, radius := 10, margin := 16.0, top := 1, glow := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.border_width_top = top
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	if glow.a > 0.0:
		sb.shadow_color = glow
		sb.shadow_size = 16
	return sb


## A Control that paints itself with `painter(ci)` (DrawUtil-ready).
func _res_canvas(min_size: Vector2, painter: Callable) -> Control:
	var c := Control.new()
	c.custom_minimum_size = min_size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	DrawUtil.setup(c)
	c.draw.connect(func() -> void: painter.call(c))
	return c


func _res_counter(target: float, kind: int, sz: int, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := _res_label(_res_fmt(0.0 if target >= 0.0 else target, kind), sz, col, FONT, align)
	_res_counters.append([l, target, kind])
	return l


func _res_fmt(v: float, kind: int) -> String:
	match kind:
		1:
			return "%d%%" % roundi(v * 100.0) if v >= 0.0 else "—"
		2:
			return "%.2f" % v
	return str(roundi(v))


func _res_count(k: float) -> void:
	for c: Array in _res_counters:
		if is_instance_valid(c[0]) and c[1] >= 0.0:
			(c[0] as Label).text = _res_fmt(c[1] * k, c[2])


func _bot_tag(eid: int) -> String:
	if not world.roster.has(eid) or not world.roster[eid].get("bot", false):
		return ""
	var e: Player = world.entities.get(eid)
	if e and e.brain is BotBrain:
		return String((e.brain as BotBrain).skill.name).to_upper()
	return "DUMMY" if e and e.brain else "BOT"


func _build_results(winner: int) -> void:
	for ch in _results.get_children():
		ch.queue_free()
	_res_counters.clear()
	_res_shown = false
	var st := _stats()
	var me := world.my_eid
	_res_root = Control.new()
	_res_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_res_root.modulate.a = 0.0
	_res_root.visible = false
	_results.add_child(_res_root)
	var edge: Color = world.map_def.get("theme", {}).get("edge", ACCENT)
	var bg := ColorRect.new()
	bg.color = Color(0.012, 0.016, 0.035, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_res_root.add_child(bg)
	var deco := _res_canvas(Vector2.ZERO, func(ci: Control) -> void:
		var w := ci.size.x
		var clear := Color(edge, 0.0)
		DrawUtil.quad4(ci, Vector2.ZERO, Vector2(w, 0), Vector2(w, 150), Vector2(0, 150),
				Color(edge, 0.16), Color(edge, 0.16), clear, clear)
		DrawUtil.rect(ci, Rect2(0, 0, w, 3), edge)
		DrawUtil.glow(ci, Vector2(w * 0.5, 40), w * 0.35, Color(edge, 0.12)))
	deco.set_anchors_preset(Control.PRESET_FULL_RECT)
	_res_root.add_child(deco)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 14)
	_res_root.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	# Headline.
	var won := winner != 0 and winner == me
	var head_text := "VICTORY" if won else ("DRAW" if winner == 0 else "DEFEAT")
	var head_col := RES_GOLD if won or winner == 0 else RES_RED
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", -6)
	var title := _res_label(head_text, 56, head_col, FONT, HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(head_col, 0.18))
	title.name = "Title"
	head.add_child(title)
	var sub := String(world.map_def.get("name", "")).to_upper()
	if st:
		sub += "   ·   " + st.mode_text()
	if winner != 0 and winner != me and world.roster.has(winner):
		sub = "%s TAKES IT   ·   %s" % [String(world.roster[winner].name).to_upper(), sub]
	head.add_child(_res_label(sub, 15, Color(1, 1, 1, 0.6), FONT_N, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(head)

	var rows: Array[Control] = []
	var cards: Array[Control] = []
	var mine_panel: Control = null
	if st:
		var mid := HBoxContainer.new()
		mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
		mid.add_theme_constant_override("separation", 16)
		col.add_child(mid)
		mid.add_child(_res_standings(st, rows))
		mine_panel = _res_personal(st)
		mid.add_child(mine_panel)
		var aw := st.awards(4)
		if not aw.is_empty():
			var strip := HBoxContainer.new()
			strip.alignment = BoxContainer.ALIGNMENT_CENTER
			strip.add_theme_constant_override("separation", 14)
			for a: Dictionary in aw:
				var wrap := _res_award_card(st, a, aw.size())
				strip.add_child(wrap)
				cards.append(wrap.get_child(0))
			col.add_child(strip)
	else:
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(spacer)

	# Buttons + recap status line.
	var foot := VBoxContainer.new()
	foot.add_theme_constant_override("separation", 4)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 14)
	_res_again = UiTheme.button("Play again", func() -> void: world.restart_requested.emit())
	_res_again.add_theme_stylebox_override("normal", _res_box(Color(ACCENT, 0.2), Color(ACCENT, 0.8), 6, 10.0))
	_res_again.add_theme_stylebox_override("hover", _res_box(Color(ACCENT, 0.34), ACCENT, 6, 10.0, 1, Color(ACCENT, 0.35)))
	_res_again.add_theme_font_override("font", FONT)
	_res_again.add_theme_font_size_override("font_size", 20)
	_res_recap = UiTheme.button("Save recap", _on_save_recap)
	_res_menu = UiTheme.button("Main menu", func() -> void: world.menu_requested.emit())
	for b: Button in [_res_again, _res_recap, _res_menu]:
		b.custom_minimum_size = Vector2(190, 46)
		btns.add_child(b)
	_res_recap.visible = st != null
	foot.add_child(btns)
	_res_note = _res_label("", 13, Color(1, 1, 1, 0.6), FONT_N, HORIZONTAL_ALIGNMENT_CENTER)
	_res_note.custom_minimum_size.y = 18
	foot.add_child(_res_note)
	foot.modulate.a = 0.0
	col.add_child(foot)
	_res_animate(title, rows, mine_panel, cards, foot)


func _res_standings(st: MatchStats, rows: Array[Control]) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.5
	panel.add_theme_stylebox_override("panel", _res_box(Color(0.03, 0.045, 0.085, 0.92), Color(ACCENT, 0.22), 10, 14.0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	v.add_child(_res_label("FINAL STANDINGS", 14, Color(ACCENT, 0.9), FONT))
	var widths := [34, 0, 62, 62, 58, 58, 74]
	var header := _res_row(["#", "PLAYER", "FRAGS", "DEATHS", "K/D", "ACC", "FAVOURITE"], widths, 11, Color(1, 1, 1, 0.45))
	v.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 3)
	scroll.add_child(list)
	var order := st.standings()
	var row_h := clampf(250.0 / maxi(order.size(), 1), 30.0, 46.0)   # few players: roomier rows
	for i in order.size():
		var eid: int = order[i]
		var is_me := eid == world.my_eid
		var row := PanelContainer.new()
		row.custom_minimum_size.y = row_h
		var rbg := Color(ACCENT, 0.14) if is_me else Color(1, 1, 1, 0.035 if i % 2 == 0 else 0.015)
		var sb := _res_box(rbg, Color(0, 0, 0, 0), 6, 0.0)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		if is_me:
			sb.border_color = ACCENT
			sb.border_width_left = 3
		row.add_theme_stylebox_override("panel", sb)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		row.add_child(h)
		var rank_col := RES_GOLD if i == 0 else (Color(1, 1, 1, 0.85) if i < 3 else Color(1, 1, 1, 0.5))
		var rk := _res_label(str(i + 1), 18, rank_col, FONT)
		rk.custom_minimum_size.x = widths[0]
		h.add_child(rk)
		var name_box := HBoxContainer.new()
		name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_box.add_theme_constant_override("separation", 8)
		var nm := _res_label(st.display_name(eid), 17, ACCENT if is_me else Color.WHITE)
		name_box.add_child(nm)
		var tag := "YOU" if is_me else _bot_tag(eid)
		if tag != "":
			name_box.add_child(_res_pill(tag, ACCENT if is_me else Color(1, 1, 1, 0.55)))
		h.add_child(name_box)
		var cells := [str(st.kills(eid)), str(st.deaths(eid)), "%.2f" % st.kd(eid), st.accuracy_text(eid)]
		for c in cells.size():
			var l := _res_label(cells[c], 17 if c == 0 else 15, Color.WHITE if c == 0 else Color(1, 1, 1, 0.72),
					FONT if c == 0 else FONT_N, HORIZONTAL_ALIGNMENT_RIGHT)
			l.custom_minimum_size.x = widths[c + 2]
			h.add_child(l)
		var fav := st.favourite(eid)
		h.add_child(_res_canvas(Vector2(widths[6], 24), func(ci: Control) -> void:
			MatchStats.draw_gun_icon(ci, fav, Rect2(Vector2(14, 0), ci.size - Vector2(14, 0)))))
		row.modulate.a = 0.0
		rows.append(row)
		list.add_child(row)
	var tot_frags := 0
	var tot_dmg := 0
	var tot_shots := 0
	for eid: int in order:
		tot_frags += maxi(st.kills(eid), 0)
		tot_dmg += int(st.of(eid).dmg)
		tot_shots += int(st.of(eid).shots)
	v.add_child(_res_label("MATCH TOTALS   ·   %d frags   ·   %d damage   ·   %d shots fired" % [tot_frags, tot_dmg, tot_shots],
			12, Color(1, 1, 1, 0.45), FONT_N, HORIZONTAL_ALIGNMENT_CENTER))
	return panel


func _res_row(texts: Array, widths: Array, sz: int, col: Color) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_right", 10)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	m.add_child(h)
	for i in texts.size():
		var l := _res_label(texts[i], sz, col, FONT_N, HORIZONTAL_ALIGNMENT_LEFT if i < 2 else HORIZONTAL_ALIGNMENT_RIGHT)
		if widths[i] > 0:
			l.custom_minimum_size.x = widths[i]
		else:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
	return m


func _res_pill(text: String, col: Color) -> Control:
	var p := PanelContainer.new()
	var sb := _res_box(Color(col, 0.14), Color(col, 0.6), 4, 0.0)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(_res_label(text, 10, col.lerp(Color.WHITE, 0.3), FONT_N))
	return p


## "Your match": rank, your fighter with your favourite gun, count-up stat tiles.
func _res_personal(st: MatchStats) -> Control:
	var me := world.my_eid
	var s := st.of(me)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _res_box(Color(0.03, 0.045, 0.085, 0.92), Color(ACCENT, 0.22), 10, 14.0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(_res_label("YOUR MATCH", 14, Color(ACCENT, 0.9), FONT))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	v.add_child(top)
	var rank := st.rank_of(me)
	var fav := st.favourite(me)
	var p: Player = world.entities.get(me)
	var look: Dictionary = p.look if p else Settings.look()
	top.add_child(_res_canvas(Vector2(96, 104), func(ci: Control) -> void:
		var pose := CharPainter.Pose.new()
		pose.aim = -0.2
		pose.wid = maxi(fav, 0)
		var c := ci.size * Vector2(0.42, 0.52)
		DrawUtil.glow(ci, c, 54.0, Color(look.get("visor", ACCENT), 0.3))
		CharPainter.draw(ci, look, pose, Transform2D(0.0, Vector2(1.75, 1.75), 0.0, c))
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)))
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", -8)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	rv.add_child(_res_label(MatchStats.ordinal(rank).to_upper(), 52, RES_GOLD if rank == 1 else Color.WHITE, FONT))
	rv.add_child(_res_label("PLACE OF %d   ·   %s" % [world.roster.size(), st.display_name(me)], 13, Color(1, 1, 1, 0.6)))
	top.add_child(rv)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	var tiles := [["FRAGS", float(st.kills(me)), 0], ["ACCURACY", st.accuracy(me), 1], ["DAMAGE", float(s.dmg), 0],
			["BEST SPREE", float(s.best_spree), 0], ["HEADSHOTS", float(s.heads), 0], ["K/D", st.kd(me), 2]]
	for t: Array in tiles:
		var tile := PanelContainer.new()
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := _res_box(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), 6, 8.0)
		sb.border_color = Color(ACCENT, 0.7)
		sb.border_width_left = 2
		sb.content_margin_left = 12
		tile.add_theme_stylebox_override("panel", sb)
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", -4)
		tile.add_child(tv)
		tv.add_child(_res_label(t[0], 11, Color(1, 1, 1, 0.5)))
		tv.add_child(_res_counter(t[1], t[2], 26))
		grid.add_child(tile)
	# Favourite weapon + extras line.
	var fav_row := HBoxContainer.new()
	fav_row.add_theme_constant_override("separation", 10)
	v.add_child(fav_row)
	var fv := VBoxContainer.new()
	fv.add_theme_constant_override("separation", -4)
	fv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fv.add_child(_res_label("FAVOURITE WEAPON", 11, Color(1, 1, 1, 0.5)))
	var fname := String(Weapons.LIST[fav].name).to_upper() if fav >= 0 else "—"
	fv.add_child(_res_label(fname, 20, Weapons.LIST[fav].color if fav >= 0 else Color.WHITE, FONT))
	var extras := []
	if s.best_multi >= 2:
		extras.append(MatchStats.MULTI_NAMES[mini(s.best_multi, MatchStats.MULTI_NAMES.size() - 1)].capitalize())
	if s.longest >= 1.0:
		extras.append("longest frag %d m" % roundi(s.longest / MatchStats.PX_PER_M))
	extras.append("%d pickup%s" % [s.pickups, "" if s.pickups == 1 else "s"])
	fv.add_child(_res_label("   ·   ".join(extras), 12, Color(1, 1, 1, 0.55)))
	fav_row.add_child(fv)
	fav_row.add_child(_res_canvas(Vector2(130, 52), func(ci: Control) -> void:
		MatchStats.draw_gun_icon(ci, fav, Rect2(Vector2.ZERO, ci.size))))
	panel.modulate.a = 0.0
	return panel


func _res_award_card(st: MatchStats, a: Dictionary, count: int) -> Control:
	var acol: Color = a.color
	var mine: bool = a.eid == world.my_eid
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(260 if count <= 3 else 238, 92)
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.add_theme_stylebox_override("panel", _res_box(Color(acol, 0.12) if mine else Color(0.035, 0.05, 0.095, 0.96),
			Color(acol, 0.55), 10, 10.0, 3, Color(acol, 0.28 if mine else 0.14)))
	wrap.add_child(card)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	card.add_child(h)
	var id: int = a.id
	h.add_child(_res_canvas(Vector2(62, 62), func(ci: Control) -> void:
		MatchStats.draw_award_icon(ci, id, ci.size * 0.5, 22.0, acol)))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -3)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_res_label(a.title, 15, acol, FONT))
	var who := _res_label(("YOU · " if mine else "") + st.display_name(a.eid), 17, ACCENT if mine else Color.WHITE)
	who.clip_text = true
	who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(who)
	v.add_child(_res_label(a.value, 12, Color(1, 1, 1, 0.6)))
	h.add_child(v)
	card.modulate.a = 0.0
	return wrap


## Sequenced reveal on real time (the finale slow-mo scales game time).
func _res_animate(title: Control, rows: Array[Control], mine: Control, cards: Array[Control], foot: Control) -> void:
	var tw := create_tween().set_ignore_time_scale(true).set_parallel(true)
	var t0 := RES_REVEAL
	tw.tween_callback(func() -> void:
		_res_root.visible = true
		_res_shown = true
		_msg_t = minf(_msg_t, 0.3)                 # the canvas headline hands over to the panel
		title.pivot_offset = title.size * 0.5).set_delay(t0)
	tw.tween_property(_res_root, "modulate:a", 1.0, 0.35).set_delay(t0)
	tw.tween_property(title, "scale", Vector2.ONE, 0.45).from(Vector2(1.35, 1.35)) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(t0)
	for i in rows.size():
		tw.tween_property(rows[i], "modulate:a", 1.0, 0.25).set_delay(t0 + 0.2 + 0.06 * i)
	if mine:
		tw.tween_property(mine, "modulate:a", 1.0, 0.3).set_delay(t0 + 0.3)
		tw.tween_method(_res_count, 0.0, 1.0, 1.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT) \
				.set_delay(t0 + 0.35)
	for i in cards.size():
		var d := t0 + 0.7 + 0.16 * i
		tw.tween_property(cards[i], "modulate:a", 1.0, 0.3).set_delay(d)
		tw.tween_property(cards[i], "position:y", 0.0, 0.45).from(40.0) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(d)
		tw.tween_callback(_sfx.bind("ui_click", -8.0, 1.1 + 0.12 * i)).set_delay(d)
	tw.tween_property(foot, "modulate:a", 1.0, 0.35).set_delay(t0 + 0.8 + 0.16 * cards.size())


func _on_save_recap() -> void:
	var st := _stats()
	if st == null or _res_recap.disabled:
		return
	_res_recap.disabled = true
	_res_recap.text = "Rendering…"
	var note: String = await st.save_recap()
	if is_instance_valid(_res_recap):
		_res_recap.disabled = false
		_res_recap.text = "Save recap"
		_res_note.text = note


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

	# Results: full-screen post-match panel, filled in by show_end() -> _build_results().
	_results = Control.new()
	_results.theme = UiTheme.get_theme()
	_results.set_anchors_preset(Control.PRESET_FULL_RECT)
	_results.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_results.visible = false
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
	if _pause.visible:
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
		# UT-style callout: scale-in pop (tier start scale -> 1.0 over 0.15 s, white-hot at first),
		# a decaying shake for multi kills, then a fade. One transform, no extra canvas items.
		var a := clampf(_msg_t / 0.4, 0.0, 1.0)
		var age := _msg_len - _msg_t
		var k := clampf(age / 0.15, 0.0, 1.0)
		var s := lerpf(_msg_pop, 1.0, 1.0 - (1.0 - k) * (1.0 - k))
		var at := Vector2(size.x * 0.5, size.y * 0.27)
		if _msg_shake > 0.0 and age < 0.45 and not _show_end:
			var d := _msg_shake * (1.0 - age / 0.45)
			at += Vector2(sin(age * 90.0) * d, cos(age * 71.0) * d * 0.5)
		var mid := _msg_size * 0.35                     # scale about the text's middle, not its baseline
		c.draw_set_transform(at - Vector2(0, mid), 0.0, Vector2(s, s))
		_text(c, Vector2(0, mid), _msg, _msg_size, Color(_msg_color.lerp(Color.WHITE, 0.7 * (1.0 - k)), a), FONT, true)
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if _msg_sub != "":
			_text(c, Vector2(size.x * 0.5, size.y * 0.27 + 34 + (_msg_size - 40) * 0.4), _msg_sub, 18,
					Color(1, 1, 1, 0.8 * a * k), FONT_N, true)
	if world.in_countdown():
		var n := ceili(world.countdown)
		_text(c, Vector2(size.x * 0.5, size.y * 0.42), str(n), 96, Color(ACCENT, 0.9), FONT, true)
		_text(c, Vector2(size.x * 0.5, size.y * 0.42 + 40), "GET READY", 18, Color(1, 1, 1, 0.8), FONT_N, true)
	if Input.is_action_pressed("scoreboard") or _show_end:
		_draw_scoreboard(c, size)
	if not _pause.visible and not _show_end:
		var m := c.get_local_mouse_position()
		if world.touch and world.touch.active:      # touch: crosshair out along the aim, in screen space
			m = c.get_viewport().get_canvas_transform() * (p.visual_position() + Player.SHOULDER + Vector2.from_angle(p.aim) * 170.0)
		_draw_crosshair(c, m, p, p.alive and p.in_no_fire_zone())


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


# --- HUD polish: weapon bar, kill feed, pickup toasts, vitals, score ---------------------
# Everything here draws in passes (all rects, then all gun icons, then all text) so the GL
# batcher merges each pass into ~1 draw call; the gun icons share GunSprites' single atlas.
# Strings are cached and only rebuilt when the value behind them changes.

const KEYS := ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
const HUD_BG := Color(0.03, 0.05, 0.09, 0.74)
const NAME_COL := Color(0.9, 0.93, 1.0)
const LOW_COL := Color("ff4d6d")
const OVERHEAL_COL := Color("38bdf8")
const ARMOR_COL := Color("fbbf24")
const ENV_COL := Color("ff9f1c")
const HEAD_COL := Color("ffd166")
const FEED_SZ := 14
const BIG_SZ := 34                           # one size per font keeps text on few glyph-cache textures
const FEED_H := 25.0
const FEED_ICON := Vector2(54, 17)
const TOAST_SZ := 14
const TOAST_ICON := Vector2(46, 20)
const SLOT := Vector2(56, 46)
const SLOT_GAP := 5.0
var _kills: Array[Dictionary] = []          # structured kill-feed rows (feed_kill), newest last
var _toasts: Array[Dictionary] = []         # pickup toasts above the weapon bar, newest last
var _ammo_val := PackedInt32Array([-1, -1, -1, -1, -1, -1, -1, -1, -1])
var _ammo_str := PackedStringArray(["", "", "", "", "", "", "", "", ""])
var _wname := PackedStringArray()           # upper-case weapon names (built once)
var _max_str := PackedStringArray()         # "/ 50" per weapon (built once)
var _max_w := PackedFloat32Array()
var _hp_val := -9999
var _hp_str := ""
var _ar_val := -9999
var _ar_str := ""
var _sc_kills := -9999
var _sc_kills_str := ""
var _sc_rank := -1
var _sc_n := -1
var _sc_rank_str := ""
var _sc_lim := -9999
var _sc_lim_str := ""
var _tm_val := -1
var _tm_str := ""
var _amp_val := -1
var _amp_str := ""
var _pill_cache := {}
var _mode_s := ""                           # last GameMode.status_text (cached by GameMode)
var _mode_w := 0.0


func _now() -> float:
	return Time.get_ticks_msec() * 0.001


func _ensure_names() -> void:
	if not _wname.is_empty():
		return
	for i in Weapons.COUNT:
		_wname.append(String(Weapons.LIST[i].name).to_upper())
		var m := "" if Weapons.infinite(i) else "/ %d" % Weapons.max_ammo(i)
		_max_str.append(m)
		_max_w.append(FONT_N.get_string_size(m, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x)


func _ammo_s(p: Player, wid: int) -> String:
	var n: int = p.ammo[wid]
	if _ammo_val[wid] != n:
		_ammo_val[wid] = n
		_ammo_str[wid] = str(n)
	return _ammo_str[wid]


## No ammo count to show: infinite weapon, or a mode with infinite ammo (Gun Game, Instagib...).
func _inf(wid: int) -> bool:
	return Weapons.infinite(wid) or GameMode.infinite_ammo(world)


func _ammo_frac(p: Player, wid: int) -> float:
	if _inf(wid):
		return 1.0
	return clampf(float(p.ammo[wid]) / maxf(float(Weapons.max_ammo(wid)), 1.0), 0.0, 1.0)


## Width a gun icon takes when fitted (aspect kept) into a box of `box` size.
func _fit_w(wid: int, box: Vector2) -> float:
	var s := GunSprites.size(wid)
	return minf(box.x, box.y * s.x / maxf(s.y, 1.0))


## HUD panel: dark glass plate with neon corner brackets in `accent`.
func _hud_frame(c: Control, r: Rect2, accent: Color, k := 12.0) -> void:
	c.draw_rect(r, HUD_BG)
	c.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), Color(accent, 0.22))
	var col := Color(accent, 0.9)
	var p0 := r.position
	var p1 := r.end
	c.draw_rect(Rect2(p0, Vector2(k, 2)), col)
	c.draw_rect(Rect2(p0, Vector2(2, k)), col)
	c.draw_rect(Rect2(Vector2(p1.x - k, p0.y), Vector2(k, 2)), col)
	c.draw_rect(Rect2(Vector2(p1.x - 2, p0.y), Vector2(2, k)), col)
	c.draw_rect(Rect2(Vector2(p0.x, p1.y - 2), Vector2(k, 2)), col)
	c.draw_rect(Rect2(Vector2(p0.x, p1.y - k), Vector2(2, k)), col)
	c.draw_rect(Rect2(p1 - Vector2(k, 2), Vector2(k, 2)), col)
	c.draw_rect(Rect2(p1 - Vector2(2, k), Vector2(2, k)), col)


## 1px outline from four rects (batches with everything else; width-1 draw_rect may not).
func _outline(c: Control, r: Rect2, col: Color, w := 1.0) -> void:
	c.draw_rect(Rect2(r.position, Vector2(r.size.x, w)), col)
	c.draw_rect(Rect2(Vector2(r.position.x, r.end.y - w), Vector2(r.size.x, w)), col)
	c.draw_rect(Rect2(Vector2(r.position.x, r.position.y + w), Vector2(w, r.size.y - 2 * w)), col)
	c.draw_rect(Rect2(Vector2(r.end.x - w, r.position.y + w), Vector2(w, r.size.y - 2 * w)), col)


## Segmented neon bar; `bg` false draws only the fill (for overlays like overheal).
func _seg_bar(c: Control, pos: Vector2, segs: int, seg_w: float, h: float, frac: float, col: Color, bg := true) -> void:
	var gap := 2.0
	var filled := clampf(frac, 0.0, 1.0) * segs
	if bg and filled > 0.0:                      # soft glow behind the lit part
		var lit := floorf(filled) * (seg_w + gap) + fmod(filled, 1.0) * seg_w
		c.draw_rect(Rect2(pos - Vector2(2, 2), Vector2(lit + 4, h + 4)), Color(col, 0.16))
	for i in segs:
		var r := Rect2(pos + Vector2(i * (seg_w + gap), 0), Vector2(seg_w, h))
		if bg:
			c.draw_rect(r, Color(1, 1, 1, 0.08))
		var f := clampf(filled - i, 0.0, 1.0)
		if f > 0.0:
			c.draw_rect(Rect2(r.position, Vector2(seg_w * f, h)), col)
			c.draw_rect(Rect2(r.position, Vector2(seg_w * f, 2)), col.lerp(Color.WHITE, 0.55))


## Tiny pixel glyphs (plain rects, so they batch): health cross, armour shield, amp diamond, skull.
func _glyph(c: Control, kind: String, ctr: Vector2, col: Color, s := 1.0) -> void:
	match kind:
		"h", "H":
			c.draw_rect(Rect2(ctr + Vector2(-3, -8) * s, Vector2(6, 16) * s), col)
			c.draw_rect(Rect2(ctr + Vector2(-8, -3) * s, Vector2(16, 6) * s), col)
		"a":
			c.draw_rect(Rect2(ctr + Vector2(-7, -8) * s, Vector2(14, 8) * s), col)
			c.draw_rect(Rect2(ctr + Vector2(-5, 0) * s, Vector2(10, 4) * s), col)
			c.draw_rect(Rect2(ctr + Vector2(-3, 4) * s, Vector2(6, 3) * s), col)
			c.draw_rect(Rect2(ctr + Vector2(-1, 7) * s, Vector2(2, 2) * s), col)
			c.draw_rect(Rect2(ctr + Vector2(-1, -6) * s, Vector2(2, 9) * s), Color(0, 0, 0, 0.35 * col.a))
		"D":
			for row in 5:
				var hw := (2 - absi(row - 2)) * 3 + 1
				c.draw_rect(Rect2(ctr + Vector2(-hw, row * 3 - 7.5) * s, Vector2(hw * 2, 3) * s), col)
		"skull":
			c.draw_rect(Rect2(ctr + Vector2(-5, -6) * s, Vector2(10, 8) * s), col)
			c.draw_rect(Rect2(ctr + Vector2(-3, 2) * s, Vector2(6, 3) * s), col)
			var eye := Color(0.03, 0.04, 0.08, col.a)
			c.draw_rect(Rect2(ctr + Vector2(-3, -3) * s, Vector2(2, 3) * s), eye)
			c.draw_rect(Rect2(ctr + Vector2(1, -3) * s, Vector2(2, 3) * s), eye)
			c.draw_rect(Rect2(ctr + Vector2(-1, 2) * s, Vector2(1, 2) * s), eye)


func _draw_vitals(c: Control, size: Vector2, p: Player) -> void:
	var pr := Rect2(Vector2(16, size.y - 104), Vector2(300, 88))
	var hp := p.health
	var crit := hp <= 30
	var hc := Color("4ade80") if hp > 60 else (Color("fbbf24") if hp > 30 else LOW_COL)
	var pulse := 0.5 + 0.5 * sin(world.clock * 8.0)
	if _hp_val != hp:
		_hp_val = hp
		_hp_str = str(hp)
	if _ar_val != p.armor:
		_ar_val = p.armor
		_ar_str = str(p.armor)
	var has_ar := p.armor > 0
	var ac := ARMOR_COL if has_ar else Color(1, 1, 1, 0.3)
	_hud_frame(c, pr, LOW_COL if crit else ACCENT)
	var x0 := pr.position.x
	var hy := pr.position.y + 12.0
	var ay := pr.position.y + 50.0
	var bx := x0 + 108.0
	# Rect pass: glyphs + segmented bars.
	_glyph(c, "h", Vector2(x0 + 22, hy + 14), Color(hc, 0.55 + 0.45 * pulse) if crit else hc)
	_glyph(c, "a", Vector2(x0 + 22, ay + 14), ac)
	_seg_bar(c, Vector2(bx, hy + 14), 10, 16.0, 10.0, hp / 100.0, hc)
	if hp > 100:
		_seg_bar(c, Vector2(bx, hy + 14), 10, 16.0, 10.0, (hp - 100) / 99.0, OVERHEAL_COL, false)
	_seg_bar(c, Vector2(bx, ay + 14), 10, 16.0, 10.0, p.armor / 150.0, ARMOR_COL)
	# Text pass.
	var hcol := hc.lerp(Color.WHITE, 0.5 * pulse) if crit else (OVERHEAL_COL if hp > 100 else Color.WHITE)
	_text(c, Vector2(x0 + 38, hy + 28), _hp_str, BIG_SZ, hcol, FONT, false, HORIZONTAL_ALIGNMENT_LEFT)
	_text(c, Vector2(x0 + 38, ay + 28), _ar_str, BIG_SZ, Color.WHITE if has_ar else Color(1, 1, 1, 0.3), FONT, false, HORIZONTAL_ALIGNMENT_LEFT)
	_text(c, Vector2(bx, hy + 9), "HEALTH", 10, Color(1, 1, 1, 0.55), FONT_N, false, HORIZONTAL_ALIGNMENT_LEFT)
	_text(c, Vector2(bx, ay + 9), "ARMOR", 10, Color(1, 1, 1, 0.55), FONT_N, false, HORIZONTAL_ALIGNMENT_LEFT)
	# Power-up + status pills stacked above the vitals panel.
	var pill_x := pr.position.x
	var pill_y := pr.position.y - 30.0
	if p.amp_time > 0.0:
		var s := ceili(p.amp_time)
		if s != _amp_val:
			_amp_val = s
			_amp_str = "DAMAGE AMP %d" % s
		pill_x = _pill(c, Vector2(pill_x, pill_y), _amp_str, Color("c084fc"))
	for kind in p.status:
		var info: Dictionary = Status.INFO[kind]
		var key: int = int(kind) * 10000 + ceili(p.status[kind])
		var txt: String = _pill_cache.get(key, "")
		if txt == "":
			txt = "%s %d" % [info.name, ceili(p.status[kind])]
			_pill_cache[key] = txt
		pill_x = _pill(c, Vector2(pill_x, pill_y), txt, info.color)


## Small rounded label; returns the x where the next pill should start.
func _pill(c: Control, pos: Vector2, text: String, col: Color) -> float:
	var w := FONT_N.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 20.0
	var r := Rect2(pos, Vector2(w, 22))
	c.draw_rect(r, Color(col, 0.18))
	c.draw_rect(r, Color(col, 0.8), false, 1.5)
	c.draw_string(FONT_N, pos + Vector2(10, 16), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col.lerp(Color.WHITE, 0.3))
	return pos.x + w + 6.0


func _draw_weapons(c: Control, size: Vector2, p: Player) -> void:
	_ensure_names()
	var cur := p.weapon
	var wc: Color = Weapons.LIST[cur].color
	var inf := _inf(cur)
	var frac := _ammo_frac(p, cur)
	var empty := not inf and p.ammo[cur] <= 0
	var low := not inf and frac <= 0.25
	var pulse := 0.5 + 0.5 * sin(world.clock * 9.0)
	var keys := not world.touch                     # number-key hints (no keys on a phone)
	# Layout: current-weapon panel bottom right, slots bottom centre.
	var pr := Rect2(Vector2(size.x - 16 - 300, size.y - 104), Vector2(300, 88))
	var icon_box := Rect2(pr.position + Vector2(16, 14), Vector2(128, 60))
	var total := Weapons.COUNT * SLOT.x + (Weapons.COUNT - 1) * SLOT_GAP
	var x0 := (size.x - total) * 0.5
	var y := size.y - 24 - SLOT.y
	var cur_r := Rect2(Vector2(x0 + cur * (SLOT.x + SLOT_GAP), y), SLOT).grow(3)
	cur_r.position.y -= 6
	# --- pass 1: rects ----------------------------------------------------------------
	_hud_frame(c, pr, LOW_COL if low else wc)
	c.draw_rect(icon_box.grow(4), Color(wc, 0.05))
	c.draw_rect(Rect2(icon_box.position.x - 4, icon_box.end.y + 3, icon_box.size.x + 8, 1), Color(wc, 0.35))
	if not inf:                                     # ammo gauge under the count
		var bar := Rect2(pr.position + Vector2(160, pr.size.y - 9), Vector2(pr.size.x - 176, 3))
		c.draw_rect(bar, Color(1, 1, 1, 0.08))
		c.draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)),
				Color(LOW_COL, 0.45 + 0.55 * pulse) if low else wc)
	for i in Weapons.COUNT:
		if i == cur:
			continue
		var r := Rect2(Vector2(x0 + i * (SLOT.x + SLOT_GAP), y), SLOT)
		var owned := p.owns(i)
		c.draw_rect(r, Color(0.03, 0.05, 0.09, 0.72 if owned else 0.38))
		_outline(c, r, Color(1, 1, 1, 0.12 if owned else 0.05))
		if owned and not _inf(i):
			var f := _ammo_frac(p, i)
			var col: Color = Weapons.LIST[i].color if f > 0.0 else LOW_COL
			c.draw_rect(Rect2(r.position + Vector2(4, r.size.y - 4), Vector2((r.size.x - 8) * maxf(f, 0.04), 2)), Color(col, 0.75))
	# The selected slot last, so its glow sits over its neighbours.
	c.draw_rect(cur_r.grow(5), Color(wc, 0.06))
	c.draw_rect(cur_r.grow(2), Color(wc, 0.14))
	c.draw_rect(cur_r, Color(wc.darkened(0.82), 0.92))
	c.draw_rect(Rect2(cur_r.position, Vector2(cur_r.size.x, cur_r.size.y * 0.5)), Color(wc, 0.08))
	_outline(c, cur_r, Color(wc, 0.95), 2.0)
	c.draw_rect(Rect2(cur_r.position + Vector2(0, -4), Vector2(cur_r.size.x, 2)), Color(wc, 0.9))
	if not inf:
		c.draw_rect(Rect2(cur_r.position + Vector2(5, cur_r.size.y - 6), Vector2((cur_r.size.x - 10) * maxf(frac, 0.04), 2)),
				LOW_COL if low else wc)
	# --- pass 2: gun icons (one shared atlas) -----------------------------------------
	GunSprites.draw_icon(c, cur, icon_box, Color(1, 0.55, 0.55, 0.6) if empty else Color.WHITE)
	for i in Weapons.COUNT:
		var r := cur_r if i == cur else Rect2(Vector2(x0 + i * (SLOT.x + SLOT_GAP), y), SLOT)
		var box := Rect2(r.position + Vector2(7, 6), Vector2(r.size.x - 14, r.size.y - 20))
		var mod := Color.WHITE
		if not p.owns(i):
			mod = Color(0, 0, 0, 0.42)                      # dark silhouette
		elif not p.has_ammo(i):
			mod = Color(1, 0.3, 0.3, 0.45)                  # dry: dimmed red
		elif i != cur:
			mod = Color(0.82, 0.85, 0.9, 0.9)
		GunSprites.draw_icon(c, i, box, mod)
	# --- pass 3: text -------------------------------------------------------------------
	# (grouped by font + size: each size lives on its own glyph-cache texture = its own batch)
	var right := pr.end.x - 16
	if low:
		_text(c, Vector2(right, pr.position.y + 39), "NO AMMO" if empty else "LOW AMMO", 10,
				Color(LOW_COL, 0.55 + 0.45 * pulse), FONT_N, false, HORIZONTAL_ALIGNMENT_RIGHT)
	for i in Weapons.COUNT:
		var current := i == cur
		var r := cur_r if current else Rect2(Vector2(x0 + i * (SLOT.x + SLOT_GAP), y), SLOT)
		var owned := p.owns(i)
		if keys:
			_text(c, r.position + Vector2(4, 11), KEYS[i], 10, Color(1, 1, 1, 0.75 if current else (0.45 if owned else 0.2)),
					FONT_N, false, HORIZONTAL_ALIGNMENT_LEFT)
		if owned and not _inf(i):
			var dry: bool = p.ammo[i] <= 0
			var tcol := LOW_COL if dry or (current and low) else (Color.WHITE if current else Color(1, 1, 1, 0.7))
			_text(c, Vector2(r.get_center().x, r.end.y - (8 if current else 6)), _ammo_s(p, i), 10, tcol, FONT_N)
	if inf:
		_text(c, Vector2(right, pr.end.y - 18), "∞", BIG_SZ, Color.WHITE, FONT, false, HORIZONTAL_ALIGNMENT_RIGHT)
	else:
		var acol := LOW_COL if empty else (Color.WHITE.lerp(LOW_COL, pulse) if low else Color.WHITE)
		_text(c, Vector2(right, pr.end.y - 16), _max_str[cur], 14, Color(1, 1, 1, 0.45), FONT_N, false, HORIZONTAL_ALIGNMENT_RIGHT)
		_text(c, Vector2(right - _max_w[cur] - 6, pr.end.y - 16), _ammo_s(p, cur), BIG_SZ, acol, FONT, false, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(c, Vector2(right, pr.position.y + 25), _wname[cur], 16, wc.lerp(Color.WHITE, 0.15), FONT, false, HORIZONTAL_ALIGNMENT_RIGHT)


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
		_hud_frame(c, Rect2(Vector2(14, 14), Vector2(220, 62)), Color("ffc93c"))
		_text(c, Vector2(26, 42), "TRAINING ROOM", 18, Color("ffc93c"), FONT, false, HORIZONTAL_ALIGNMENT_LEFT)
		_text(c, Vector2(26, 64), "T — dummies & options", 13, Color(1, 1, 1, 0.7), FONT_N, false, HORIZONTAL_ALIGNMENT_LEFT)
		return
	# Rank without building/sorting a roster copy every frame: 1 + players strictly ahead.
	var me: Dictionary = world.roster[world.my_eid]
	var kills: int = me.kills
	var rank := 1
	var n := 0
	for eid in world.roster:
		n += 1
		if world.roster[eid].kills > kills:
			rank += 1
	if kills != _sc_kills:
		_sc_kills = kills
		_sc_kills_str = str(kills)
	if rank != _sc_rank or n != _sc_n:
		_sc_rank = rank
		_sc_n = n
		_sc_rank_str = "%s of %d" % [_ordinal(rank), n]
	if world.frag_limit != _sc_lim:
		_sc_lim = world.frag_limit
		_sc_lim_str = ("FRAGS / %d" % _sc_lim) if _sc_lim > 0 else "FRAGS"
	var lead := rank == 1
	var pr := Rect2(Vector2(16, 16), Vector2(210, 64))
	_hud_frame(c, pr, Color("ffd166") if lead else ACCENT)
	if world.frag_limit > 0:                    # progress to the frag limit along the bottom edge
		var bar := Rect2(pr.position + Vector2(84, 50), Vector2(pr.size.x - 100, 3))
		c.draw_rect(bar, Color(1, 1, 1, 0.1))
		c.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(float(kills) / world.frag_limit, 0.0, 1.0), 3)), ACCENT)
	# Game-mode strip under the score ("" in Deathmatch).
	var mode_s := GameMode.status_text(world, world.local_player) if world.local_player else ""
	if mode_s != _mode_s:
		_mode_s = mode_s
		_mode_w = FONT_N.get_string_size(mode_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var mr := Rect2(Vector2(16, 86), Vector2(_mode_w + 26, 24))
	if _mode_s != "":
		c.draw_rect(mr, HUD_BG)
		c.draw_rect(Rect2(mr.position, Vector2(3, mr.size.y)), Color("ffd166"))
		c.draw_rect(Rect2(mr.position + Vector2(0, mr.size.y - 1), Vector2(mr.size.x, 1)), Color("ffd166", 0.3))
	var tr := Rect2(Vector2(234, 16), Vector2(96, 64))
	var t := 0
	if world.time_limit > 0.0:
		t = ceili(world.time_left())
		if t != _tm_val:
			_tm_val = t
			_tm_str = "%d:%02d" % [floori(t / 60.0), t % 60]
		_hud_frame(c, tr, LOW_COL if t <= 30 else ACCENT)
	_text(c, Vector2(pr.position.x + 40, pr.position.y + 47), _sc_kills_str, BIG_SZ, Color.WHITE, FONT)
	_text(c, Vector2(pr.position.x + 84, pr.position.y + 42), _sc_rank_str, 16, Color("ffd166") if lead else ACCENT, FONT, false, HORIZONTAL_ALIGNMENT_LEFT)
	if world.time_limit > 0.0:
		var urgent := t <= 30
		var tcol := LOW_COL.lerp(Color.WHITE, 0.5 + 0.5 * sin(world.clock * 8.0)) if urgent else Color.WHITE
		_text(c, tr.position + Vector2(48, 50), _tm_str, 24, tcol, FONT)
		_text(c, tr.position + Vector2(48, 22), "TIME", 10, Color(1, 1, 1, 0.55), FONT_N)
	_text(c, Vector2(pr.position.x + 84, pr.position.y + 22), _sc_lim_str, 10, Color(1, 1, 1, 0.55), FONT_N, false, HORIZONTAL_ALIGNMENT_LEFT)
	if _mode_s != "":
		_text(c, mr.position + Vector2(14, 17), _mode_s, 13, Color("ffe8a8"), FONT_N, false, HORIZONTAL_ALIGNMENT_LEFT)


func _ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		suffix = ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
	return "%d%s" % [n, suffix]


## Structured kill-feed row, "Killer [gun icon] Victim" (World calls this right after on_death).
## Environmental deaths show a text tag ("LAVA") instead of the icon; self-kills drop the killer.
func feed_kill(killer_eid: int, victim_eid: int, wid: int, head := false) -> void:
	# on_death just appended this kill's text twin: hide it (the structured row replaces it).
	if not _feed.is_empty() and float(_feed.back().get("t", 0.0)) >= 5.99:
		_feed.back()["kill"] = true
	var r := world.roster
	var row := {"wid": wid, "head": head, "end": _now() + 6.0, "tag": "",
			"mine": killer_eid == world.my_eid or victim_eid == world.my_eid,
			"k": "" if killer_eid == victim_eid else String(r[killer_eid].name if r.has(killer_eid) else "?"),
			"v": String(r[victim_eid].name if r.has(victim_eid) else "?"),
			"kc": ACCENT if killer_eid == world.my_eid else NAME_COL,
			"vc": ACCENT if victim_eid == world.my_eid else Color(NAME_COL, 0.82)}
	var mw: float
	if wid >= 0 and wid < Weapons.COUNT:
		mw = _fit_w(wid, FEED_ICON)
	else:
		var env := {World.HAZARD: "void" if world.level.def.style in ["city", "space"] else "lava",
				World.LASER: "laser", World.VENT: "vent", World.PURGE: "spawn purge"}
		row.tag = String(env.get(wid, "world")).to_upper()
		mw = FONT_N.get_string_size(row.tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 12.0
	var kw := 0.0 if row.k == "" else FONT_N.get_string_size(row.k, HORIZONTAL_ALIGNMENT_LEFT, -1, FEED_SZ).x
	var vw := FONT_N.get_string_size(row.v, HORIZONTAL_ALIGNMENT_LEFT, -1, FEED_SZ).x
	row.kw = kw
	row.mw = mw
	row.w = 10.0 + (kw + 9.0 if kw > 0.0 else 0.0) + mw + (18.0 if head else 0.0) + 9.0 + vw + 10.0
	_kills.append(row)
	if _kills.size() > 5:
		_kills.pop_front()


func _draw_feed(c: Control, size: Vector2) -> void:
	var now := _now()
	while not _kills.is_empty() and float(_kills[0].end) <= now:
		_kills.pop_front()
	while not _toasts.is_empty() and float(_toasts[0].end) <= now:
		_toasts.pop_front()
	var right := size.x - 16.0
	var top := 16.0
	var n := _kills.size()
	# --- kill rows: plates (+ env tags, headshot skulls) / icons / names --------------------
	for i in n:
		var f: Dictionary = _kills[i]
		var a := clampf((float(f.end) - now) / 0.5, 0.0, 1.0)
		var r := Rect2(Vector2(right - float(f.w), top + i * FEED_H), Vector2(f.w, FEED_H - 4))
		if f.mine:
			c.draw_rect(r, Color(ACCENT.darkened(0.7), 0.7 * a))
			_outline(c, r, Color(ACCENT, 0.55 * a))
			c.draw_rect(Rect2(r.position, Vector2(3, r.size.y)), Color(ACCENT, a))
		else:
			c.draw_rect(r, Color(0.02, 0.03, 0.06, 0.55 * a))
		var mx: float = r.position.x + 10.0 + (float(f.kw) + 9.0 if float(f.kw) > 0.0 else 0.0)
		if f.tag != "":
			c.draw_rect(Rect2(mx, r.position.y + 3, f.mw, r.size.y - 6), Color(ENV_COL, 0.2 * a))
		if f.head:
			_glyph(c, "skull", Vector2(mx + float(f.mw) + 10.0, r.get_center().y), Color(HEAD_COL, a))
	for i in n:
		var f: Dictionary = _kills[i]
		if f.tag == "":
			var a := clampf((float(f.end) - now) / 0.5, 0.0, 1.0)
			var x: float = right - float(f.w) + 10.0 + (float(f.kw) + 9.0 if float(f.kw) > 0.0 else 0.0)
			GunSprites.draw_icon(c, f.wid, Rect2(Vector2(x, top + i * FEED_H + 2), Vector2(f.mw, FEED_ICON.y)), Color(1, 1, 1, a))
	for i in n:
		var f: Dictionary = _kills[i]
		var a := clampf((float(f.end) - now) / 0.5, 0.0, 1.0)
		var x0: float = right - float(f.w)
		var base: float = top + i * FEED_H + 15.0
		if float(f.kw) > 0.0:
			_text(c, Vector2(x0 + 10.0, base), f.k, FEED_SZ, Color(f.kc, a), FONT_N, false, HORIZONTAL_ALIGNMENT_LEFT)
		_text(c, Vector2(right - 10.0, base), f.v, FEED_SZ, Color(f.vc, a * f.vc.a), FONT_N, false, HORIZONTAL_ALIGNMENT_RIGHT)
	for i in n:
		var f: Dictionary = _kills[i]
		if f.tag != "":
			var a := clampf((float(f.end) - now) / 0.5, 0.0, 1.0)
			var mx: float = right - float(f.w) + 10.0 + (float(f.kw) + 9.0 if float(f.kw) > 0.0 else 0.0)
			_text(c, Vector2(mx + 6.0, top + i * FEED_H + 14.0), f.tag, 10, Color(ENV_COL, a), FONT_N, false, HORIZONTAL_ALIGNMENT_LEFT)
	# --- legacy text rows (anything not replaced by a structured kill row) -------------------
	var y := top + n * FEED_H + 15.0
	for f in _feed:
		if f.get("kill", false):
			continue
		var a := clampf(f.t / 0.5, 0.0, 1.0)
		_text(c, Vector2(right - 4.0, y), f.text, 14, Color(f.color, a), FONT_N, true, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 22.0
	# --- pickup toasts: centred above the weapon bar, newest at the bottom -------------------
	var nt := _toasts.size()
	var ty := size.y - 24 - SLOT.y - 44.0
	for i in nt:
		var f: Dictionary = _toasts[nt - 1 - i]
		var r := _toast_rect(f, size, ty - i * 28.0, now)
		var a := _toast_alpha(f, now)
		var col: Color = f.color
		c.draw_rect(r, Color(0.02, 0.03, 0.06, 0.6 * a))
		c.draw_rect(Rect2(r.position, Vector2(3, r.size.y)), Color(col, a))
		c.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 1), Vector2(r.size.x, 1)), Color(col, 0.35 * a))
		if f.wid < 0:
			_glyph(c, f.type, Vector2(r.position.x + 12.0 + 9.0, r.get_center().y), Color(col, a), 0.8)
	for i in nt:
		var f: Dictionary = _toasts[nt - 1 - i]
		if f.wid >= 0:
			var r := _toast_rect(f, size, ty - i * 28.0, now)
			GunSprites.draw_icon(c, f.wid, Rect2(r.position + Vector2(12, 2), Vector2(f.iw, TOAST_ICON.y)), Color(1, 1, 1, _toast_alpha(f, now)))
	for i in nt:
		var f: Dictionary = _toasts[nt - 1 - i]
		var r := _toast_rect(f, size, ty - i * 28.0, now)
		var col: Color = f.color
		_text(c, Vector2(r.position.x + 12.0 + float(f.iw) + 8.0, r.position.y + 17.0), f.text, TOAST_SZ,
				Color(col.lerp(Color.WHITE, 0.25), _toast_alpha(f, now)), FONT_N, false, HORIZONTAL_ALIGNMENT_LEFT)


func _toast_alpha(f: Dictionary, now: float) -> float:
	return clampf((float(f.end) - now) / 0.4, 0.0, 1.0)


## Toast plate: pops up 8px over its first 0.15 s.
func _toast_rect(f: Dictionary, size: Vector2, y: float, now: float) -> Rect2:
	var age := 2.2 - (float(f.end) - now)
	var rise := 8.0 * (1.0 - clampf(age / 0.15, 0.0, 1.0))
	var w: float = f.w
	return Rect2(Vector2((size.x - w) * 0.5, y + rise), Vector2(w, 24))


## Tab scoreboard (and the results backdrop until the results panel takes over). Row strings
## are cached: rebuilt when frags/deaths change, or at most ~3x a second for accuracy.
func _draw_scoreboard(c: Control, size: Vector2) -> void:
	if _res_shown:
		return
	_sb_refresh()
	var w := 640.0
	var h := 74.0 + _sb_rows.size() * 30.0
	var r := Rect2(Vector2((size.x - w) * 0.5, size.y * 0.36), Vector2(w, h))
	var x := r.position.x
	var dim := Color(1, 1, 1, 0.5)
	_panel(c, r)
	_text(c, r.position + Vector2(20, 32), "PLAYER", 12, dim, FONT_N, false, HORIZONTAL_ALIGNMENT_LEFT)
	_text(c, Vector2(x + w - 270, r.position.y + 32), "FRAGS", 12, dim, FONT_N, false, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(c, Vector2(x + w - 190, r.position.y + 32), "DEATHS", 12, dim, FONT_N, false, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(c, Vector2(x + w - 105, r.position.y + 32), "K/D", 12, dim, FONT_N, false, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(c, Vector2(x + w - 20, r.position.y + 32), "ACC", 12, dim, FONT_N, false, HORIZONTAL_ALIGNMENT_RIGHT)
	for i in _sb_rows.size():
		var row: Array = _sb_rows[i]
		var y := r.position.y + 64 + i * 30
		var is_me: bool = row[8]
		if is_me:
			c.draw_rect(Rect2(x + 6, y - 21, w - 12, 28), Color(ACCENT, 0.13))
			c.draw_rect(Rect2(x + 6, y - 21, 3, 28), ACCENT)
		var col := ACCENT if is_me else Color.WHITE
		_text(c, Vector2(x + 20, y), row[1], 17, RES_GOLD if i == 0 else Color(col, 0.7), FONT, false, HORIZONTAL_ALIGNMENT_LEFT)
		_text(c, Vector2(x + 50, y), row[2], 17, col, FONT_N, false, HORIZONTAL_ALIGNMENT_LEFT)
		if row[3] != "":
			_text(c, Vector2(x + 58 + row[9], y - 1), row[3], 11, Color(col, 0.55), FONT_N, false, HORIZONTAL_ALIGNMENT_LEFT)
		_text(c, Vector2(x + w - 270, y), row[4], 17, col, FONT, false, HORIZONTAL_ALIGNMENT_RIGHT)
		_text(c, Vector2(x + w - 190, y), row[5], 17, Color(col, 0.6), FONT, false, HORIZONTAL_ALIGNMENT_RIGHT)
		_text(c, Vector2(x + w - 105, y), row[6], 15, Color(col, 0.75), FONT_N, false, HORIZONTAL_ALIGNMENT_RIGHT)
		_text(c, Vector2(x + w - 20, y), row[7], 15, Color(col, 0.75), FONT_N, false, HORIZONTAL_ALIGNMENT_RIGHT)


## Rebuild the cached scoreboard rows when the score changes (no allocations otherwise).
func _sb_refresh() -> void:
	var sig := world.roster.size()
	for eid: int in world.roster:
		var d: Dictionary = world.roster[eid]
		sig = sig * 31 + eid * 7 + int(d.kills) * 977 + int(d.deaths) * 13
	var st := _stats()
	var ver := st.version if st else 0
	var now := Time.get_ticks_msec()
	if sig == _sb_sig and (ver == _sb_ver or now - _sb_ms < 300):
		return
	_sb_sig = sig
	_sb_ver = ver
	_sb_ms = now
	_sb_rows.clear()
	var order: Array = st.standings() if st else _sorted_roster().map(func(x: Array) -> int: return x[0])
	for i in order.size():
		var eid: int = order[i]
		var d: Dictionary = world.roster[eid]
		var kills := int(d.kills)
		var deaths := int(d.deaths)
		var name := String(d.name)
		var tag := "YOU" if eid == world.my_eid else _bot_tag(eid)
		_sb_rows.append([eid, str(i + 1), name, tag, str(kills), str(deaths),
				"%.2f" % (float(kills) / maxi(deaths, 1)), st.accuracy_text(eid) if st else "—",
				eid == world.my_eid, FONT_N.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x])


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
