extends Node
## Dev tool (excluded from exports): menu + match-flow checks. Restores your settings file after.
## Run: godot --headless --path . -- --test=menu

var fails := 0
var _backup := ""


func _ready() -> void:
	Sfx.muted = true
	if FileAccess.file_exists(Settings.PATH):
		_backup = FileAccess.get_file_as_string(Settings.PATH)
	_run.call_deferred()


func _check(name: String, ok: bool, detail := "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("" if ok else "   " + detail))
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _run() -> void:
	var main := get_parent()
	main.show_menu()
	await _frames(30)
	_check("menu shows over a live bot match", main.menu != null and main.world.demo and not main.world.hud.visible
			and main.world.local_player.mode == Player.Mode.BOT)
	main.menu.show_play()
	await _frames(2)
	_check("play screen lists every arena", main.menu._cards.size() == Maps.LIST.size())

	var cfg := {"map": 2, "bots": 2, "skill": 3, "frags": 5, "minutes": 1}
	main.menu.play_requested.emit(cfg)
	await _frames(5)
	var w: World = main.world
	_check("match uses the chosen setup", w.map_def.id == "foundry" and w.entities.size() == 3 and w.frag_limit == 5
			and w.time_limit == 60.0 and w.bot_skill == BotBrain.Skill.ELITE and main.menu == null)
	_check("countdown runs before the fight", w.in_countdown())
	var p: Player = w.local_player
	await _frames(20)
	var pos := p.global_position
	p.in_move = 1.0
	await _frames(10)
	_check("players are frozen during the countdown", p.global_position.is_equal_approx(pos))
	await _frames(int(World.COUNTDOWN * 60) + 10)
	_check("countdown ends", not w.in_countdown())

	w.clock = World.COUNTDOWN + w.time_limit + 1.0
	await _frames(3)
	_check("time limit ends the match with results", w.ended and w.hud._results.visible)
	w.restart_requested.emit()
	await _frames(5)
	_check("play again restarts the same setup", main.world != w and main.world.map_def.id == "foundry" and main.world.frag_limit == 5)

	w = main.world
	w.hud._toggle_pause()
	await _frames(2)
	_check("pause stops the game", get_tree().paused and w.hud._pause.visible)
	w.hud._show_pause_settings()
	await _frames(2)
	var has_settings := false
	for c in w.hud._pause_box.get_children():
		has_settings = has_settings or c is SettingsPanel
	_check("settings open from the pause menu", has_settings)
	w.menu_requested.emit()
	await _frames(5)
	_check("main menu from pause", main.menu != null and main.world.demo and not get_tree().paused)

	main.menu.show_customize()
	await _frames(2)
	Settings.look_overrides.primary = Color("ff3d81")
	main.menu._refresh_look()
	_check("customize changes your look", main.menu._preview.look.primary == Color("ff3d81"))

	var vol := Settings.master_volume
	Settings.master_volume = 0.33
	Settings.save_settings()
	Settings.master_volume = 1.0
	Settings.load_settings()
	_check("settings save and load", is_equal_approx(Settings.master_volume, 0.33))
	Settings.master_volume = vol

	Settings.rebind("jump", KEY_K)
	var has_k := false
	for ev in InputMap.action_get_events("jump"):
		has_k = has_k or (ev is InputEventKey and ev.physical_keycode == KEY_K)
	_check("rebinding a key works", has_k and Settings.key_name("jump") == "K")
	Settings.reset_bindings()

	main.menu.training_requested.emit()
	await _frames(5)
	_check("training starts from the menu", main.world.training and main.menu == null)

	# Buses must come from the layout file (runtime add_bus() breaks web audio — see music.gd).
	_check("audio buses from the default layout", AudioServer.bus_count == 3
			and AudioServer.get_bus_index("Music") == 1 and AudioServer.get_bus_index("SFX") == 2
			and AudioServer.get_bus_send(1) == &"Master" and AudioServer.get_bus_send(2) == &"Master")

	# Music: menu theme on the menu, each arena's own track in matches, every track looping.
	Sfx.muted = false
	main.show_menu()
	await _frames(5)
	var mp: AudioStreamPlayer = Music._players[Music._active]
	_check("menu plays the menu theme", Music.current == Music.MENU and mp.playing)
	mp.stop()
	Music._on_finished(mp)
	_check("tracks restart themselves when they end (web ignores MP3 loop)", mp.playing)
	var uses := {}
	for def in Maps.LIST:
		uses[def.music] = uses.get(def.music, 0) + 1
	_check("each combat track is shared by at least two arenas", uses.size() == 3 and uses.values().all(func(n: int) -> bool: return n >= 2))
	main.start_match({"map": 2, "bots": 1, "skill": 1, "frags": 10, "minutes": 0})
	await _frames(5)
	_check("a match plays its arena's track", Music.current == Maps.LIST[2].music and Music._players[Music._active].playing)
	main.start_training()
	await _frames(5)
	_check("training plays its track", Music.current == Maps.TRAINING.music)
	Sfx.muted = true

	# Put the player's real settings back.
	if _backup != "":
		var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.close()
	print("DONE fails=%d" % fails)
	get_tree().quit(1 if fails else 0)
