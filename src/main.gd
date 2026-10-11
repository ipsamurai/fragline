extends Node
## Entry point and screen flow:
##   menu (live bot match behind it) -> match / training -> results or pause -> menu.
## Dev tools (--test=, --shots=) skip the menu and drive maps directly.

var world: World
var menu: Menu
var _last_match := {}                 # config of the last match, for "Play again"


func _ready() -> void:
	add_child(FpsCounter.new())
	if TouchControls.wanted():
		Settings.quality = 0                     # phones: low effects for a steady frame rate
	Net.match_started.connect(_on_net_match_started)
	Net.left.connect(func(reason: String) -> void:
		show_menu()
		menu.show_notice(reason))
	if _start_dev_tool():
		return
	show_menu()
	_handle_url()


## Web links: ?join=CODE joins a LAN room; ?host=1 (&autostart=N) hosts one — handy for testing.
func _handle_url() -> void:
	if not OS.has_feature("web"):
		return
	var q := func(key: String) -> String:
		return str(JavaScriptBridge.eval("new URLSearchParams(location.search).get(%s) || ''" % JSON.stringify(key), true))
	Net.debug = q.call("debug") != ""
	if q.call("quality") != "":
		Settings.quality = clampi(int(q.call("quality")), 0, 2)
	var code: String = q.call("join")
	if q.call("bench") != "":
		_start_bench(float(q.call("bench")), int(q.call("map")), int(q.call("bots")) if q.call("bots") != "" else 7)
	elif code != "":
		join_lan(code)
	elif q.call("host") != "":
		await host_lan(Settings.match_prefs.duplicate())
		var need := int(q.call("autostart"))
		if need > 0:
			while Net.lobby.size() < need and Net.role == Net.Role.HOST:
				await Net.lobby_changed
			if Net.role == Net.Role.HOST:
				start_lan_match()


## ?bench=SECONDS: an all-bot match with the HUD showing, timed by Bench.
func _start_bench(seconds: float, map_index: int, bots: int) -> void:
	_clear()
	Sfx.world_muted = true
	world = _new_world()
	world.demo = true
	world.setup(Maps.LIST[posmod(map_index, Maps.LIST.size())], clampi(bots, 0, 11))
	world.hud.visible = true
	if "--xray" in OS.get_cmdline_user_args() or (OS.has_feature("web") and 			str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('xray') || ''", true)) != ""):
		XRay.enabled = true
		world.xray._apply()
	var b := Bench.new()
	b.duration = maxf(seconds, 5.0)
	add_child(b)


## Returns true if a dev tool was requested on the command line (excluded from exports).
func _start_dev_tool() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bench="):
			var map_index := 0
			for m in OS.get_cmdline_user_args():
				if m.begins_with("--map="):
					map_index = int(m.trim_prefix("--map="))
			_start_bench.call_deferred(float(arg.trim_prefix("--bench=")), map_index, 7)
			return true
		if arg.begins_with("--shots="):
			add_child(load("res://src/dev/shots.gd").new())
			return true
		if arg.begins_with("--test="):
			var test_name := arg.trim_prefix("--test=")
			if not test_name.is_valid_ascii_identifier():   # only res://src/dev/<name>_test.gd
				get_tree().quit(2)
				return true
			var script: GDScript = load("res://src/dev/%s_test.gd" % test_name)
			if script == null or not script.can_instantiate():
				push_error("Test script failed to load")
				get_tree().quit(2)
				return true
			add_child(script.new())
			return true
	return false


# --- flow --------------------------------------------------------------------------

func show_menu() -> void:
	_clear()
	Sfx.world_muted = true
	world = _new_world()
	world.demo = true
	world.setup(Maps.LIST[randi() % Maps.LIST.size()], 3)
	Music.play_menu()
	menu = Menu.new()
	menu.play_requested.connect(start_match)
	menu.training_requested.connect(start_training)
	menu.host_requested.connect(host_lan)
	menu.join_requested.connect(join_lan)
	menu.lobby_start_requested.connect(start_lan_match)
	menu.lobby_leave_requested.connect(func() -> void:
		Net.close()
		menu.show_play())
	add_child(menu)


func start_match(config: Dictionary) -> void:
	_last_match = config
	_clear()
	world = _new_world()
	world.bot_skill = int(config.get("skill", BotBrain.Skill.REGULAR)) as BotBrain.Skill
	world.frag_limit = int(config.get("frags", 15))
	world.time_limit = int(config.get("minutes", 0)) * 60.0
	world.game_mode = GameMode.sanitize(config.get("mode", GameMode.DEATHMATCH))
	world.low_gravity = bool(config.get("lowgrav", false))
	world.setup(Maps.LIST[clampi(int(config.get("map", 0)), 0, Maps.LIST.size() - 1)], int(config.get("bots", 3)))
	world.restart_requested.connect(func() -> void: start_match(_last_match))
	Music.play_map(world.map_def)


func start_training() -> void:
	_clear()
	world = _new_world()
	world.setup(Maps.TRAINING, 0)
	world.restart_requested.connect(start_training)
	Music.play_map(Maps.TRAINING)


# --- LAN PvP -------------------------------------------------------------------------

func host_lan(config: Dictionary) -> void:
	var err := await Net.host(config)
	if not is_instance_valid(menu):          # left the menu while the room was being created
		return
	if err != "":
		menu.show_notice(err)
		return
	if Net.role != Net.Role.HOST:            # cancelled (e.g. a second "Host match" click)
		return
	menu.show_lobby()


func join_lan(code: String) -> void:
	menu.show_lobby()
	var err := await Net.join(code)
	if err != "" and is_instance_valid(menu):
		menu.show_play()
		menu.show_notice(err)


## Host: start (or restart) the match for everyone in the lobby, with the host's settings.
func start_lan_match() -> void:
	var config: Dictionary = Net.config
	_last_match = config
	_clear()
	world = _new_world()
	world.net_role = Net.Role.HOST
	world.my_eid = Net.my_id
	world.lobby = Net.lobby
	world.bot_skill = int(config.get("skill", BotBrain.Skill.REGULAR)) as BotBrain.Skill
	world.frag_limit = int(config.get("frags", 15))
	world.time_limit = int(config.get("minutes", 0)) * 60.0
	world.game_mode = GameMode.sanitize(config.get("mode", GameMode.DEATHMATCH))
	world.low_gravity = bool(config.get("lowgrav", false))
	world.setup(Maps.LIST[clampi(int(config.get("map", 0)), 0, Maps.LIST.size() - 1)], int(config.get("bots", 0)))
	world.restart_requested.connect(start_lan_match)
	Net.world = world
	Net.start_match(world.describe())
	Music.play_map(world.map_def)


## Client: the host started a match (or we joined one in progress).
func _on_net_match_started(info: Dictionary) -> void:
	var included := false
	for row in info.get("players", []):
		if row is Array and not row.is_empty() and int(row[0]) == Net.my_id:
			included = true
	if not included:                         # our hello raced the host's Start; the re-send will include us
		return
	_clear()
	world = _new_world()
	world.my_eid = Net.my_id
	world.setup_client(info)
	Net.world = world
	Music.play_map(world.map_def)


func _new_world() -> World:
	var w := World.new()
	add_child(w)
	w.menu_requested.connect(func() -> void:
		Net.close()
		show_menu())
	return w


func _clear() -> void:
	Sfx.world_muted = false
	get_tree().paused = false
	Net.world = null
	if menu:
		menu.queue_free()
		menu = null
	if world:
		remove_child(world)        # its _exit_tree (cursor reset) runs now, not after the next world hides it
		world.queue_free()
		world = null


# --- dev-tool helpers (tests and screenshots load maps directly) -----------------------

func _load_map(i: int) -> void:
	start_match({"map": posmod(i, Maps.LIST.size()), "bots": 3, "frags": 15, "minutes": 0})
	world.countdown = 0.0


func _load_training() -> void:
	start_training()
