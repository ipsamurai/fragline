class_name XRay
extends Node2D
## X-Ray vision (key X): shows the parts of a match you normally can't see.
##   - the bots' navigation graph (walk / jump / fall / drop / climb / jump-pad links)
##   - each bot's planned route, its goal, and what it's trying to do ("GET ROCKET", "HUNT VOLT")
##   - who each bot is targeting, whether it can see them, and how close it is to reacting
##   - respawn countdowns on items that have been taken
## Offline only (bots vs. you, training, the menu's live match): it would be a wallhack in LAN.

static var enabled := false            # survives match restarts within a session

const LINK_COLORS := [
	Color(0.35, 0.85, 1.0, 0.55),       # WALK
	Color(1.0, 0.78, 0.25, 0.09),       # JUMP   (dense: kept faint so routes stand out)
	Color(0.75, 0.5, 1.0, 0.12),        # FALL
	Color(1.0, 0.4, 0.7, 0.3),          # DROP
	Color(0.4, 1.0, 0.55, 0.7),         # CLIMB
	Color(1.0, 0.95, 0.4, 0.14),        # PAD
]
const LINK_NAMES := ["walk", "jump", "fall", "drop", "climb", "jump pad"]
const FADE_IN := 0.35

var world: World
var _graph: Node2D
var _segments: Array[PackedVector2Array] = []
var _fade := 0.0


func _ready() -> void:
	z_index = 3
	_graph = Node2D.new()
	_graph.draw.connect(_draw_graph)
	add_child(_graph)
	_apply()


func allowed() -> bool:
	return world.net_role == Net.Role.OFFLINE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("xray") and not event.is_echo() and allowed() and not world.paused:
		enabled = not enabled
		_fade = 0.0
		_apply()
		Sfx.play("ui_click" if enabled else "ui_back", -4.0, 1.4 if enabled else 1.0)
		if world.hud and not world.demo:
			if enabled:
				world.hud.message("X-RAY VISION", "seeing what the bots see", UiTheme.ACCENT, 1.4)
			else:
				world.hud.message("X-RAY OFF", "", Color(1, 1, 1, 0.7), 0.8)
		get_viewport().set_input_as_handled()


func _apply() -> void:
	var on := enabled and allowed()
	visible = on
	set_process(on)
	if on and _segments.is_empty() and world.level:
		_segments = world.get_nav().segments_by_type()
		_graph.queue_redraw()


func _process(delta: float) -> void:
	_fade = minf(_fade + delta / FADE_IN, 1.0)
	_graph.modulate.a = _fade
	queue_redraw()


func _view_rect() -> Rect2:
	var inv := get_viewport().get_canvas_transform().affine_inverse()
	var size := get_viewport().get_visible_rect().size
	return Rect2(inv * Vector2.ZERO, inv.basis_xform(size))


## Static: the whole graph, drawn once (one batched multiline per link type).
func _draw_graph() -> void:
	for kind in _segments.size():
		if not _segments[kind].is_empty():
			var wide := kind == NavGraph.Link.WALK or kind == NavGraph.Link.CLIMB
			_graph.draw_multiline(_segments[kind], LINK_COLORS[kind], 2.0 if wide else 1.0)


func _draw() -> void:
	var view := _view_rect()
	# Cool tint over the scene so the overlay reads clearly; a scan line sweeps in on activation.
	draw_rect(view, Color(0.0, 0.04, 0.09, 0.32 * _fade))
	if _fade < 1.0:
		var x := view.position.x + view.size.x * _fade
		draw_rect(Rect2(x - 3.0, view.position.y, 6.0, view.size.y), Color(UiTheme.ACCENT, 0.6 * (1.0 - _fade)))
	var font: Font = UiTheme.FONT
	_draw_items(font)
	for e: Player in world.alive_players():
		if e.brain is BotBrain:
			_draw_bot(e, e.brain, font)
	_draw_legend(view, font)


func _draw_items(font: Font) -> void:
	var now := world.clock
	for it: Dictionary in world.pickups.items:
		if it.active or it.get("dormant", false) or it.respawn_at == INF:
			continue
		var left: float = it.respawn_at - now
		if left <= 0.0:
			continue
		var txt := "%d" % ceili(left)
		var p: Vector2 = it.pos + Vector2(0, -26)
		draw_rect(Rect2(p - Vector2(15, 11), Vector2(30, 17)), Color(0, 0, 0, 0.6))
		_text(font, p + Vector2(-15, 2), txt, 30, 13, UiTheme.GOLD)


func _draw_bot(e: Player, b: BotBrain, font: Font) -> void:
	var col: Color = e.look.get("visor", UiTheme.ACCENT)
	var at := e.visual_position()
	# Route: from the bot through every node still ahead, ending in a goal diamond.
	var path := b.path_ahead()
	if path.size() > 0:
		var pts := PackedVector2Array([at])
		pts.append_array(path)
		draw_polyline(pts, Color(col, 0.25), 7.0)     # soft glow under the route
		draw_polyline(pts, Color(col.lightened(0.3), 0.95), 2.5)
		var g := path[path.size() - 1]
		draw_primitive(PackedVector2Array([g + Vector2(0, -9), g + Vector2(9, 0), g + Vector2(0, 9), g + Vector2(-9, 0)]),
				PackedColorArray([Color(col, 0.9)]), PackedVector2Array())
	# Target: solid red when in sight, dashed grey when only remembered.
	var t := b.target
	if t and is_instance_valid(t) and t.alive:
		var to := t.visual_position()
		if b.target_visible:
			draw_line(at, to, Color(1.0, 0.25, 0.3, 0.55), 1.5)
		else:
			draw_dashed_line(at, to, Color(1, 1, 1, 0.3), 1.5, 10.0)
		# Reaction meter: fills while the bot "notices" you; it can only fire once full.
		var r := b.reaction_progress()
		if r > 0.0:
			var bar := Rect2(at + Vector2(-17, -74), Vector2(34, 3))
			draw_rect(bar, Color(0, 0, 0, 0.6))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * r, bar.size.y)),
					Color(1.0, 0.3, 0.3) if r >= 1.0 else Color(1.0, 0.8, 0.3))
	var intent := b.intent()
	if intent != "":
		_text(font, at + Vector2(-90, -80), intent, 180, 11, Color(col, 0.95))


func _draw_legend(view: Rect2, font: Font) -> void:
	if world.demo:
		return
	var z := get_viewport().get_canvas_transform().get_scale().x
	var s := 1.0 / maxf(z, 0.01)
	var p := view.position + Vector2(18, view.size.y - 30.0 * s - 18.0 * LINK_NAMES.size() * s)
	draw_set_transform(p, 0.0, Vector2(s, s))
	_text(font, Vector2(0, 0), "X-RAY · bot navigation", 260, 13, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_LEFT)
	for i in LINK_NAMES.size():
		var y := 20.0 + 18.0 * i
		draw_rect(Rect2(0, y - 6, 18, 3), Color(LINK_COLORS[i], 0.9))
		_text(font, Vector2(26, y), LINK_NAMES[i], 200, 12, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_LEFT)
	draw_set_transform(Vector2.ZERO)


func _text(font: Font, pos: Vector2, s: String, width: float, size: int, col: Color,
		align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	draw_string_outline(font, pos, s, align, width, size, 4, Color(0, 0, 0, 0.75))
	draw_string(font, pos, s, align, width, size, col)
