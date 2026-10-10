extends Node
## Dev tool (excluded from exports): visits every map, simulates input, saves screenshots.
## Run: godot --path . -- --shots=<output_dir>

var out_dir := ""


func _ready() -> void:
	Sfx.muted = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			out_dir = a.trim_prefix("--shots=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _run() -> void:
	var main := get_parent()
	if "--only-menu" in OS.get_cmdline_user_args():
		await _menu()
		get_tree().quit()
		return
	for i in Maps.LIST.size():
		main._load_map(i)
		await _wait(0.7)
		_shot("map%d_idle" % i)
		Input.action_press("move_right")
		Input.action_press("jump")
		await _wait(0.25)
		Input.action_release("jump")
		await _wait(0.1)
		Input.action_press("jump")
		await _wait(0.1)
		Input.action_release("jump")
		await _wait(0.2)
		_shot("map%d_air" % i)
		Input.action_release("move_right")
		await _wait(0.6)
		Input.action_press("move_left")
		await _wait(0.45)
		_shot("map%d_run" % i)
		Input.action_release("move_left")
		await _wait(0.3)
		print("map %d player at %s on_floor=%s" % [i, main.world.local_player.global_position, main.world.local_player.is_on_floor()])
		_overview(main.world)
		await _wait(0.15)
		_shot("map%d_overview" % i)
	await _bots()
	await _combat()
	await _training()
	await _lineup()
	get_tree().quit()


## Every menu screen, the countdown, pause and results.
func _menu() -> void:
	var main := get_parent()
	main.show_menu()
	await _wait(1.5)
	_shot("menu_main")
	main.menu.show_play()
	await _wait(0.5)
	_shot("menu_play")
	main.menu.show_customize()
	await _wait(0.6)
	_shot("menu_customize")
	main.menu.show_settings()
	await _wait(0.5)
	_shot("menu_settings")
	main.menu.show_credits()
	await _wait(0.4)
	_shot("menu_credits")
	main.start_match({"map": 0, "bots": 3, "skill": 1, "frags": 15, "minutes": 10})
	await _wait(1.2)
	_shot("match_countdown")
	await _wait(2.5)
	main.world.hud._toggle_pause()
	await _wait(0.3)
	_shot("match_pause")
	main.world.hud._toggle_pause()
	main.world._end_match(World.LOCAL_EID)
	await _wait(0.5)
	_shot("match_results")


## Four bots fighting: you're a bot too, the camera follows you.
func _bots() -> void:
	var main := get_parent()
	main._load_map(0)
	var w: World = main.world
	w.local_player.mode = Player.Mode.BOT
	w.local_player.brain = BotBrain.new(BotBrain.Skill.VETERAN)
	for i in 4:
		await _wait(3.0)
		_shot("bots_%d" % i)
	_overview(w)
	await _wait(0.2)
	_shot("bots_overview")


func _training() -> void:
	var main := get_parent()
	main._load_training()
	await _wait(0.5)
	var w: World = main.world
	for i in 3:
		w.spawn_dummy()
	w.local_player.teleport(Vector2(11 * Level.T, 26 * Level.T - Player.HALF.y - 1))   # in the armory
	await _wait(0.6)
	_shot("training_armory")
	w.local_player.teleport(Vector2(30 * Level.T, 26 * Level.T - Player.HALF.y - 1))   # at the firing line
	w.local_player.armor = 60
	w.set_dummy_behaviour(DummyBrain.Behaviour.MOVE)
	await _wait(1.0)
	_shot("training_range")
	var ev := InputEventAction.new()
	ev.action = "training"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _wait(0.3)
	_shot("training_panel")
	_overview(w)
	await _wait(0.2)
	_shot("training_overview")


## Fire a few weapons at the dummies and capture effects + HUD.
func _combat() -> void:
	var main := get_parent()
	main._load_map(0)
	var w: World = main.world
	await _wait(0.8)
	var me := w.local_player
	for i in Weapons.COUNT:
		me.owned |= 1 << i
		me.ammo[i] = Weapons.max_ammo(i)
	var floor_y := w.level.size_px.y - 3 * Level.T - Player.HALF.y - 1
	me.teleport(Vector2(460, floor_y))
	var targets := 0
	for e: Player in w.entities.values():
		if e != me:
			e.teleport(Vector2(700 + targets * 70, floor_y))
			e.protect_time = 0.0
			targets += 1
	me.protect_time = 0.0
	me.armor = 50
	me.amp_time = 0.0
	Input.warp_mouse(Vector2(900, 380))
	await _wait(0.4)
	me.select_weapon(Weapons.ROCKET)
	w.request_fire(me, Weapons.ROCKET, false, me.muzzle(), Vector2.RIGHT)
	await _wait(0.28)
	_shot("combat_rocket")
	me.select_weapon(Weapons.SHOCK)
	await _wait(0.3)
	w.request_fire(me, Weapons.SHOCK, false, me.muzzle(), Vector2.RIGHT.rotated(-0.05))
	await _wait(0.05)
	_shot("combat_shock")
	me.select_weapon(Weapons.FLAK)
	await _wait(0.3)
	w.request_fire(me, Weapons.FLAK, false, me.muzzle(), Vector2.RIGHT)
	await _wait(0.12)
	_shot("combat_flak")
	# Traps: freeze the clock just inside each trap's active window.
	var laser: Dictionary = w.level.lasers[0]
	me.teleport(Vector2(laser.x - 120, floor_y))
	w.clock = Traps.LASER_PERIOD - 0.6 - laser.phase * Traps.LASER_PERIOD
	await _wait(0.25)
	_shot("trap_laser")
	var vent: Dictionary = w.level.vents[0]
	me.teleport(vent.pos + Vector2(-140, -Player.HALF.y - 1))
	w.clock = Traps.VENT_PERIOD - 0.45 - vent.phase * Traps.VENT_PERIOD
	await _wait(0.2)
	_shot("trap_vent")
	# One fighter per status effect, side by side.
	var row := [me]
	for e: Player in w.entities.values():
		if e != me:
			row.append(e)
	var kinds := [Status.BURN, Status.POISON, Status.CHILL, Status.SHOCK]
	for k in row.size():
		var e: Player = row[k]
		e.teleport(Vector2(560 + k * 90, floor_y))
		e.protect_time = 0.0
		w.apply_status(e, kinds[k], 30.0, e.eid, World.VENT)
		e.status_src[kinds[k]] = [e.eid, World.VENT]
		e.health = 900
	await _wait(0.6)
	_shot("status")


## All characters at 2.5x on a neutral backdrop, cycling through poses.
func _lineup() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	var sheet := Node2D.new()
	sheet.draw.connect(func() -> void:
		sheet.draw_rect(Rect2(0, 0, 1280, 720), Color("141a2a"))
		for i in Characters.LIST.size():
			var pose := CharPainter.Pose.new()
			pose.facing = 1.0 if i % 2 == 0 else -1.0
			pose.aim = [-0.3, PI + 0.4, 0.2, PI - 0.1][i % 4]
			pose.speed01 = [0.0, 1.0, 0.6, 0.0][i % 4]
			pose.phase = i * 1.3
			pose.air = i % 6 == 5
			pose.vy = -200.0
			pose.wid = i % Weapons.COUNT
			pose.lean = 0.1 * pose.speed01
			var pos := Vector2(110 + (i % 6) * 210, 200 + (i / 6) * 320)
			CharPainter.draw(sheet, Characters.resolve(i), pose, Transform2D(0.0, Vector2(2.5, 2.5), 0.0, pos))
			sheet.draw_set_transform(Vector2.ZERO)
			sheet.draw_string(ThemeDB.fallback_font, pos + Vector2(-60, 110), Characters.LIST[i].name,
					HORIZONTAL_ALIGNMENT_CENTER, 120, 22))
	layer.add_child(sheet)
	add_child(layer)
	await _wait(0.3)
	_shot("characters")


## Freeze the camera and zoom out to show the whole arena.
func _overview(w: World) -> void:
	w.set_process(false)
	w.hud.visible = false
	var view := w.get_viewport().get_visible_rect().size
	var z := minf(view.x / w.level.size_px.x, view.y / w.level.size_px.y)
	w.camera.limit_right = 100000
	w.camera.limit_bottom = 100000
	w.camera.limit_left = -100000
	w.camera.limit_top = -100000
	w.camera.zoom = Vector2(z, z)
	w.camera.global_position = w.level.size_px * 0.5
	w.background.follow(w.level.size_px * 0.5)


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	var world: World = get_parent().world
	if name.ends_with("_run") and world:
		var screen := world.get_viewport().get_canvas_transform() * world.local_player.visual_position()
		var r := Rect2i(Vector2i(screen) - Vector2i(60, 70), Vector2i(120, 120)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		var crop := img.get_region(r)
		crop.resize(r.size.x * 3, r.size.y * 3, Image.INTERPOLATE_NEAREST)
		crop.save_png("%s/%s_zoom.png" % [out_dir, name])
