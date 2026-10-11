extends Node
## Dev tool (excluded from exports): touch controls + lobby QR code checks.
## Run: godot --headless --path . -- --test=touch   (add --qr-out=<file.png> to save the QR image)

var fails := 0


func _ready() -> void:
	Sfx.muted = true
	_run.call_deferred()


func _check(name: String, ok: bool, detail := "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("" if ok else "   " + detail))
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _touch(i: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = pos
	e.pressed = pressed
	get_viewport().push_input(e, true)             # viewport coords (the headless window is 0x0)
	if i == 0:                                     # what the browser's touch->mouse emulation does
		if pressed:
			Input.action_press("fire")
		else:
			Input.action_release("fire")


func _drag(i: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = pos
	get_viewport().push_input(e, true)


func _tap(i: int, pos: Vector2) -> void:
	_touch(i, pos, true)
	await _frames(2)
	_touch(i, pos, false)
	await _frames(2)


func _run() -> void:
	_qr_checks()
	var main := get_parent()
	TouchControls._wanted = 1                      # force touch mode on (desktop/headless)
	main.start_match({"map": 0, "bots": 1, "skill": 0, "frags": 50, "minutes": 0})
	var w: World = main.world
	w.countdown = 0.0
	await _frames(40)
	var t := w.touch
	var p := w.local_player
	_check("touch controls created in a match when wanted", t != null and t.active)
	if t == null:
		return _done()
	w.give_all_weapons(p)
	for e: Player in w.entities.values():          # keep the bot out of the way
		if e != p:
			e.brain = null
			e.in_move = 0.0
			e.in_fire = false
	await _frames(30)                              # land
	var size := t._size
	var r := t._stick_r
	print("viewport %s, stick r %.0f, player at %s floor=%s" % [size, r, p.global_position, p.is_on_floor()])

	# Move stick (left half).
	var x0 := p.global_position.x
	var base := Vector2(size.x * 0.2, size.y * 0.7)
	_touch(0, base, true)
	await _frames(2)
	_check("tapping a stick doesn't fire (emulated mouse ignored)", not p.in_fire,
			"fire action=%s" % Input.is_action_pressed("fire"))
	_drag(0, base + Vector2(r, 0))
	await _frames(20)
	_check("move stick right gives full move", is_equal_approx(t.move, 1.0) and p.in_move == 1.0, "move=%.2f" % t.move)
	_check("player runs right", p.global_position.x > x0 + 40.0, "dx=%.1f" % (p.global_position.x - x0))
	_drag(0, base + Vector2(-r * 2.0, 0))          # past the rim: base follows the thumb
	await _frames(3)
	_check("move stick left", t.move == -1.0 and t._move_base.x < base.x)
	_touch(0, base, false)
	await _frames(2)
	_check("release stops moving", t.move == 0.0 and p.in_move == 0.0)
	await _frames(30)

	# Flick up = jump.
	var on_floor := p.is_on_floor()
	_touch(0, base, true)
	await _frames(1)
	_drag(0, base + Vector2(0, -r * 0.9))
	var jumped := false
	for k in 6:
		await _frames(1)
		jumped = jumped or p.velocity.y < -300.0
	_check("move stick up jumps", jumped and t.jump_held, "on_floor=%s vy=%.0f" % [on_floor, p.velocity.y])
	_check("jump edge lasts one tick", not t.jump_pressed)
	_drag(0, base + Vector2(0, r * 0.9))
	await _frames(1)
	_check("move stick down = drop / crouch held", t.down_held)
	_touch(0, base, false)
	await _frames(40)

	# Aim stick (right half): aim + fire.
	var abase := Vector2(size.x * 0.55, size.y * 0.85)
	_touch(1, abase, true)
	await _frames(1)
	_drag(1, abase + Vector2(0, -r * 0.8))
	await _frames(3)
	_check("aim stick up aims up", absf(angle_difference(p.aim, -PI / 2.0)) < deg_to_rad(15.0), "aim=%.2f" % p.aim)
	_check("aim stick past the deadzone fires", t.fire and p.in_fire)
	_drag(1, abase + Vector2(-r * 0.8, 0))
	await _frames(2)
	_check("aim stick left aims left", absf(angle_difference(p.aim, PI)) < deg_to_rad(15.0), "aim=%.2f" % p.aim)
	_touch(1, abase, false)
	await _frames(2)
	_check("release stops firing, keeps aim", not t.fire and not p.in_fire and t.aim_dir.is_equal_approx(Vector2.LEFT))

	# Two thumbs at once.
	_touch(0, base, true)
	_touch(1, abase, true)
	await _frames(1)
	_drag(0, base + Vector2(r, 0))
	_drag(1, abase + Vector2(r, 0))
	await _frames(3)
	_check("multi-touch: move and aim together", t.move == 1.0 and t.fire and p.in_fire and p.in_move == 1.0)
	_touch(0, base, false)
	_touch(1, abase, false)
	await _frames(30)

	# Buttons.
	var b: Dictionary = t._buttons
	var wpn := p.weapon
	await _tap(2, b.next.pos)
	_check("SWAP cycles the weapon", p.weapon != wpn, "weapon %d -> %d" % [wpn, p.weapon])
	_touch(2, b.alt.pos, true)
	await _frames(2)
	_check("ALT held = alt fire", t.alt and p.in_alt and not p.in_fire)
	_touch(2, b.alt.pos, false)
	await _frames(2)
	_check("ALT released", not t.alt and not p.in_alt)
	await _frames(30)
	_touch(2, b.jump.pos, true)
	jumped = false
	for k in 6:
		await _frames(1)
		jumped = jumped or p.velocity.y < -300.0
	_touch(2, b.jump.pos, false)
	_check("JUMP button jumps", jumped)
	await _frames(40)
	_touch(2, b.dodge.pos, true)
	var dodged := false
	for k in 4:
		await _frames(1)
		dodged = dodged or p._dodge_time > 0.0
	_touch(2, b.dodge.pos, false)
	_check("DODGE button dodges", dodged)
	await _frames(10)

	# Aim assist: an enemy a few degrees off the aim line gets the shot.
	var bot: Player = null
	for e: Player in w.entities.values():
		if e != p:
			bot = e
	if bot and bot.alive:
		var origin := p.global_position + Player.SHOULDER
		bot.teleport(p.global_position + Vector2(260, 0))
		await _frames(1)
		var to := bot.global_position + Player.SHOULDER - origin
		t._aim_idx = 99                            # pretend a thumb is aiming
		t.aim_dir = Vector2.from_angle(to.angle() + deg_to_rad(9.0))
		var a := t.assisted_aim(p, origin)
		if w.line_clear(origin, origin + to):
			_check("aim assist snaps onto a nearby enemy", absf(angle_difference(a, to.angle())) < 0.01)
		else:
			print("SKIP  aim assist (no line of sight at the spawn)")
		t.aim_dir = Vector2.from_angle(to.angle() + deg_to_rad(40.0))
		a = t.assisted_aim(p, origin)
		_check("aim assist leaves wide misses alone", absf(angle_difference(a, t.aim_dir.angle())) < 0.01)
		t._aim_idx = -1

	# Pause button: pauses, then the controls let taps through to the GUI.
	await _tap(3, t._pause_rect.get_center())
	_check("pause button pauses", w.paused and w.hud._pause.visible)
	await _frames(2)
	_check("controls disabled while paused", not t._enabled and not t._press(4, base))
	w.hud._toggle_pause()
	await _frames(3)
	_check("controls back after resume", t._enabled and not w.paused)

	# Desktop is unaffected: no touch controls when not wanted.
	TouchControls._wanted = 0
	main.start_match({"map": 1, "bots": 0, "skill": 0, "frags": 5, "minutes": 0})
	await _frames(3)
	_check("no touch controls on desktop", main.world.touch == null)
	_done()


func _done() -> void:
	print("DONE fails=%d" % fails)
	get_tree().quit(1 if fails else 0)


## Encode a join link and sanity-check the symbol: size, finder pattern, format bits (ECC M).
func _qr_checks() -> void:
	var url := "http://192.168.1.20:8000/?join=K7QX2M"
	var tex := Menu.qr_texture(url)
	_check("QR texture made", tex != null)
	if tex == null:
		return
	var img := tex.get_image()
	var n := img.get_width() - 8
	_check("QR is version 3 (29 modules) with a 4-module quiet zone", n == 29 and img.get_height() == img.get_width(),
			"modules=%d" % n)
	var dark := func(x: int, y: int) -> int: return 1 if img.get_pixel(x + 4, y + 4).v < 0.5 else 0
	var finder_ok := true
	for i in 7:
		finder_ok = finder_ok and dark.call(i, 0) == 1 and dark.call(0, i) == 1 and dark.call(6, i) == 1 and dark.call(i, 6) == 1
	finder_ok = finder_ok and dark.call(1, 1) == 0 and dark.call(3, 3) == 1 and dark.call(7, 7) == 0
	_check("QR finder pattern", finder_ok)
	var quiet := true
	for i in img.get_width():
		quiet = quiet and img.get_pixel(i, 0).v > 0.5 and img.get_pixel(0, i).v > 0.5
	_check("QR quiet zone is white", quiet)
	# Format info, first copy (x = column, y = row) as in ISO/IEC 18004.
	var bits := 0
	for i in 6:
		bits |= dark.call(8, i) << i
	bits |= dark.call(8, 7) << 6
	bits |= dark.call(8, 8) << 7
	bits |= dark.call(7, 8) << 8
	for i in range(9, 15):
		bits |= dark.call(14 - i, 8) << i
	bits ^= 0x5412
	var data := bits >> 10
	var rem := data
	for i in 10:
		rem = (rem << 1) ^ ((rem >> 9) * 0x537)
	_check("QR format bits valid, ECC level M", (rem & 0x3FF) == (bits & 0x3FF) and (data >> 3) == 0,
			"bits=%x data=%x" % [bits, data])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--qr-out="):
			var big := img.duplicate() as Image
			big.resize(img.get_width() * 8, img.get_height() * 8, Image.INTERPOLATE_NEAREST)
			big.save_png(a.trim_prefix("--qr-out="))
