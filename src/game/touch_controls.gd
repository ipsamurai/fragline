class_name TouchControls
extends CanvasLayer
## Twin-stick touch controls for phones and tablets (web build), drawn procedurally.
##   Left half:  floating move stick. x = move, push up = jump, push down = drop through.
##   Right half: floating aim stick. Direction = aim, pushed past the deadzone = primary fire.
##   Buttons on an arc around the aim area: JUMP, ALT, DODGE, NEXT weapon. Pause at the top.
## The Player reads the public state below each physics tick (see Player._read_local_input).
## Only touches that land on these controls are marked handled, so GUI taps still work.

const ACCENT := UiTheme.ACCENT
const FONT := UiTheme.TITLE
const MOVE_DEADZONE := 0.2               # of the stick radius
const UP_ON := 0.55                      # stick y past this (up) = jump; released below UP_OFF
const UP_OFF := 0.4
const DOWN_ON := 0.6
const DOWN_OFF := 0.45
const AIM_DEADZONE := 0.25
const ASSIST_ANGLE := deg_to_rad(14.0)
const ASSIST_RANGE := 950.0
const TEX_SIZE := 96

# --- public state (read by Player) ---------------------------------------------------------
var active := true                       # touch mode is on: Player uses this instead of mouse fire
var move := 0.0
var jump_pressed := false                # one-tick edges: cleared at the end of the next physics tick
var jump_held := false
var down_pressed := false
var down_held := false
var dodge_pressed := false
var fire := false
var alt := false
var aim_dir := Vector2.ZERO              # normalized; ZERO until the player first aims

var world: World

static var _wanted := -1                 # cached detection: -1 unknown, 0 no, 1 yes
static var _disk: ImageTexture
static var _ring: ImageTexture

var _canvas: Control
var _enabled := false
var _size := Vector2.ZERO
var _stick_r := 80.0
var _btn_r := 44.0
var _buttons := {}                       # name -> {"pos", "label"}
var _pause_rect := Rect2()
var _btn_touch := {}                     # button name -> touch index holding it
var _move_idx := -1
var _move_base := Vector2.ZERO
var _move_pos := Vector2.ZERO
var _aim_idx := -1
var _aim_base := Vector2.ZERO
var _aim_pos := Vector2.ZERO
var _stick_up := false
var _stick_down := false
var _cycle := 0
var _sig := []                           # redraw only when what's on screen changes


## True on touch devices (web: coarse pointer + touch points) or when forced with ?touch=1
## (web) / --touch (command line). ?touch=0 forces it off. Cached after the first call.
static func wanted() -> bool:
	if _wanted < 0:
		_wanted = 1 if _detect() else 0
	return _wanted == 1


static func _detect() -> bool:
	if "--touch" in OS.get_cmdline_user_args():
		return true
	if not OS.has_feature("web"):
		return false
	var q := str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('touch') || ''", true))
	if q == "1":
		return true
	if q == "0":
		return false
	var coarse: Variant = JavaScriptBridge.eval(
			"!!(navigator.maxTouchPoints > 0 && window.matchMedia && matchMedia('(pointer: coarse)').matches)", true)
	return typeof(coarse) == TYPE_BOOL and coarse


func _ready() -> void:
	layer = 11                           # above the HUD; hidden whenever the pause menu is up
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 100       # clear the edges after the players have read them
	_make_textures()
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_canvas.draw.connect(_draw_controls)
	add_child(_canvas)


func consume_weapon_cycle() -> int:
	if _cycle > 0:
		_cycle = 0
		return 1
	return 0


## Aim angle from `origin`, nudged onto the nearest visible enemy within ASSIST_ANGLE.
func assisted_aim(p: Player, origin: Vector2) -> float:
	var base := aim_dir.angle()
	if _aim_idx < 0:
		return base                      # only assist while the thumb is actually aiming
	var best := ASSIST_ANGLE
	var best_angle := base
	for e: Player in world.alive_players():
		if not world.is_enemy(p, e):
			continue
		var target := e.global_position + Player.SHOULDER
		var to := target - origin
		var d := to.length()
		if d < 1.0 or d > ASSIST_RANGE:
			continue
		var diff := absf(angle_difference(base, to.angle()))
		if diff < best and world.line_clear(origin, target):
			best = diff
			best_angle = to.angle()
	return best_angle


# --- state --------------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	jump_pressed = false
	down_pressed = false
	dodge_pressed = false


func _process(_delta: float) -> void:
	var size := get_viewport().get_visible_rect().size
	if size != _size:
		_size = size
		_layout()
	var p := world.local_player
	var enabled := not (world.paused or world.input_blocked or world.ended) and not _portrait()
	if enabled != _enabled:
		_enabled = enabled
		if not enabled:
			_reset()
	var sig := [_size, _enabled, is_instance_valid(p) and p.alive, p.weapon if is_instance_valid(p) else -1,
			_move_idx, _move_base, _move_pos, _aim_idx, _aim_base, _aim_pos, _btn_touch.size(), _btn_touch.keys(),
			world.paused, world.ended]
	if sig != _sig:
		_sig = sig
		_canvas.queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_reset()                         # releases can get lost when the page loses focus


func _portrait() -> bool:
	return _size.y > _size.x


func _reset() -> void:
	_btn_touch.clear()
	_move_idx = -1
	_aim_idx = -1
	_stick_up = false
	_stick_down = false
	move = 0.0
	jump_held = false
	down_held = false
	fire = false
	alt = false
	jump_pressed = false
	down_pressed = false
	dodge_pressed = false
	_cycle = 0


func _layout() -> void:
	var h := _size.y
	var w := _size.x
	_stick_r = h * 0.11
	_btn_r = h * 0.062
	# Buttons in a gamepad-style diamond above the aim thumb's resting spot (bottom right);
	# JUMP sits lowest, closest to the thumb.
	var d := Vector2(w - h * 0.22, h * 0.44)
	var o := h * 0.13
	_buttons = {
		"jump": {"pos": d + Vector2(0, o), "label": "JUMP"},
		"alt": {"pos": d + Vector2(-o, 0), "label": "ALT"},
		"dodge": {"pos": d + Vector2(o, 0), "label": "DODGE"},
		"next": {"pos": d + Vector2(0, -o), "label": "SWAP"},
	}
	var ps := h * 0.075
	_pause_rect = Rect2(Vector2(w * 0.5 - ps * 0.5, h * 0.015), Vector2(ps, ps))


# --- input --------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		var owned := _press(t.index, t.position) if t.pressed else _release(t.index)
		if owned:
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if _drag(d.index, d.position):
			get_viewport().set_input_as_handled()


func _press(i: int, pos: Vector2) -> bool:
	if not _enabled or _size == Vector2.ZERO:
		return false
	_release(i)                          # a reused index whose release we missed
	if _pause_rect.grow(_pause_rect.size.x * 0.3).has_point(pos):
		_reset()
		world.hud._toggle_pause()
		return true
	var p := world.local_player
	if not (is_instance_valid(p) and p.alive):
		return false                     # dead: leave taps to the GUI
	for b: String in _buttons:
		if not _btn_touch.has(b) and pos.distance_to(_buttons[b].pos) <= _btn_r * 1.2:
			_btn_touch[b] = i
			match b:
				"jump":
					jump_pressed = true
				"dodge":
					dodge_pressed = true
				"next":
					_cycle = 1
			_update_buttons()
			return true
	if pos.x < _size.x * 0.5:
		if _move_idx < 0:
			_move_idx = i
			_move_base = pos
			_move_pos = pos
			_update_move()
		return true
	if _aim_idx < 0:
		_aim_idx = i
		_aim_base = pos
		_aim_pos = pos
		_update_aim()
	return true


func _release(i: int) -> bool:
	var owned := false
	for b: String in _btn_touch.keys():
		if _btn_touch[b] == i:
			_btn_touch.erase(b)
			owned = true
	if owned:
		_update_buttons()
	if i == _move_idx:
		_move_idx = -1
		_update_move()
		owned = true
	if i == _aim_idx:
		_aim_idx = -1
		_update_aim()
		owned = true
	return owned


func _drag(i: int, pos: Vector2) -> bool:
	if i == _move_idx:
		_move_pos = pos
		_move_base = _follow(_move_base, pos)
		_update_move()
		return true
	if i == _aim_idx:
		_aim_pos = pos
		_aim_base = _follow(_aim_base, pos)
		_update_aim()
		return true
	return _btn_touch.values().has(i)


## Floating stick: the base trails the thumb once it's pushed past the rim.
func _follow(base: Vector2, pos: Vector2) -> Vector2:
	var off := pos - base
	return pos - off.normalized() * _stick_r if off.length() > _stick_r else base


func _update_move() -> void:
	if _move_idx < 0:
		move = 0.0
		_stick_up = false
		_stick_down = false
	else:
		var v := (_move_pos - _move_base) / _stick_r
		var ax := absf(v.x)
		move = 0.0 if ax < MOVE_DEADZONE else signf(v.x) * clampf((ax - MOVE_DEADZONE) / 0.4, 0.0, 1.0)
		var up := v.y < -(UP_OFF if _stick_up else UP_ON)
		var down := v.y > (DOWN_OFF if _stick_down else DOWN_ON)
		if up and not _stick_up:
			jump_pressed = true
		if down and not _stick_down:
			down_pressed = true
		_stick_up = up
		_stick_down = down
	_update_buttons()


func _update_aim() -> void:
	if _aim_idx < 0:
		fire = false
		return
	var off := _aim_pos - _aim_base
	fire = off.length() > _stick_r * AIM_DEADZONE
	if fire:
		aim_dir = off.normalized()


func _update_buttons() -> void:
	jump_held = _stick_up or _btn_touch.has("jump")
	down_held = _stick_down
	alt = _btn_touch.has("alt")


# --- drawing ------------------------------------------------------------------------------

static func _make_textures() -> void:
	if _disk:
		return
	var disk := Image.create_empty(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_LA8)
	var ring := Image.create_empty(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_LA8)
	var r := TEX_SIZE * 0.5
	var thick := TEX_SIZE * 0.06
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			disk.set_pixel(x, y, Color(1, 1, 1, clampf(r - 0.5 - d, 0.0, 1.0)))
			var ring_a := clampf(thick * 0.5 - absf(d - (r - thick * 0.5 - 1.0)) + 0.5, 0.0, 1.0)
			ring.set_pixel(x, y, Color(1, 1, 1, ring_a))
	_disk = ImageTexture.create_from_image(disk)
	_ring = ImageTexture.create_from_image(ring)


func _circle(c: Vector2, radius: float, col: Color, tex: Texture2D) -> void:
	_canvas.draw_texture_rect(tex, Rect2(c - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, col)


func _label(c: Vector2, s: String, size: int, col: Color) -> void:
	var w := maxf(_size.x, 400.0)
	_canvas.draw_string(FONT, Vector2(c.x - w * 0.5, c.y + size * 0.36), s, HORIZONTAL_ALIGNMENT_CENTER, w, size, col)


func _draw_controls() -> void:
	if _portrait():
		if not (world.paused or world.ended):
			_draw_rotate_hint()
		return
	var p := world.local_player
	if not _enabled or not is_instance_valid(p) or world.ended:
		return
	var h := _size.y
	# Pause button (top centre).
	var pr := _pause_rect
	_canvas.draw_rect(pr, Color(0.04, 0.06, 0.1, 0.55))
	_canvas.draw_rect(pr, Color(ACCENT, 0.6), false, 2.0)
	var bw := pr.size.x * 0.14
	var bh := pr.size.y * 0.46
	var cy := pr.position.y + (pr.size.y - bh) * 0.5
	_canvas.draw_rect(Rect2(Vector2(pr.get_center().x - bw * 1.6, cy), Vector2(bw, bh)), Color(1, 1, 1, 0.85))
	_canvas.draw_rect(Rect2(Vector2(pr.get_center().x + bw * 0.6, cy), Vector2(bw, bh)), Color(1, 1, 1, 0.85))
	if not p.alive:
		return
	var font_size := maxi(12, roundi(h * 0.024))
	# Buttons.
	for b: String in _buttons:
		var pos: Vector2 = _buttons[b].pos
		var down := _btn_touch.has(b)
		var col := ACCENT
		if b == "next":
			col = Weapons.LIST[p.weapon].color
		elif b == "alt":
			col = Color("ff5fa2")
		_circle(pos, _btn_r, Color(col, 0.38) if down else Color(0.03, 0.05, 0.09, 0.3), _disk)
		_circle(pos, _btn_r, Color(col, 1.0 if down else 0.6), _ring)
		_label(pos, _buttons[b].label, font_size, Color(1, 1, 1, 1.0 if down else 0.8))
	# Move stick (left), or a faint hint where it'll appear.
	var dim := Color(1, 1, 1, 0.16)
	if _move_idx >= 0:
		_draw_stick(_move_base, _move_pos, ACCENT)
	else:
		var hint := Vector2(_size.x * 0.16, h * 0.74)
		_circle(hint, _stick_r, dim, _ring)
		_label(hint, "MOVE", font_size, Color(1, 1, 1, 0.3))
	# Aim stick (right).
	var aim_col: Color = Weapons.LIST[p.weapon].color.lerp(Color.WHITE, 0.2)
	if _aim_idx >= 0:
		_draw_stick(_aim_base, _aim_pos, aim_col)
	else:
		var hint := Vector2(_size.x - h * 0.24, h * 0.8)
		_circle(hint, _stick_r, dim, _ring)
		_label(hint, "AIM · FIRE", font_size, Color(1, 1, 1, 0.3))


func _draw_stick(base: Vector2, pos: Vector2, col: Color) -> void:
	var off := (pos - base).limit_length(_stick_r)
	var knob := base + off
	_circle(base, _stick_r, Color(0.03, 0.05, 0.09, 0.35), _disk)
	_circle(base, _stick_r, Color(col, 0.55), _ring)
	if off.length() > 2.0:
		_canvas.draw_line(base, knob, Color(col, 0.5), 3.0)
	_circle(knob, _stick_r * 0.42, Color(col, 0.4), _disk)
	_circle(knob, _stick_r * 0.42, Color(1, 1, 1, 0.85), _ring)


func _draw_rotate_hint() -> void:
	var s := _size
	_canvas.draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.03, 0.06, 0.94))
	var c := s * 0.5
	var u := s.x * 0.09
	# A phone outline turning sideways.
	_canvas.draw_rect(Rect2(c + Vector2(-u * 2.2, -u * 1.9), Vector2(u * 1.1, u * 2.0)), Color(1, 1, 1, 0.5), false, 3.0)
	_canvas.draw_rect(Rect2(c + Vector2(u * 0.4, -u * 1.45), Vector2(u * 2.0, u * 1.1)), ACCENT, false, 4.0)
	var a := c + Vector2(-u * 0.85, -u * 1.95)
	var b := c + Vector2(u * 0.15, -u * 1.75)
	_canvas.draw_line(a, b, ACCENT, 3.0)
	_canvas.draw_line(b, b + Vector2(-u * 0.28, -u * 0.12), ACCENT, 3.0)
	_canvas.draw_line(b, b + Vector2(-u * 0.12, u * 0.25), ACCENT, 3.0)
	var fs := roundi(s.x * 0.065)
	_label(c + Vector2(0, u * 0.6), "ROTATE YOUR PHONE", fs, Color.WHITE)
	_label(c + Vector2(0, u * 0.6 + fs * 1.4), "FRAGLINE plays in landscape", roundi(fs * 0.6), Color(1, 1, 1, 0.65))
