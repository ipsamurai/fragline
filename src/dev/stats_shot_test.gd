extends Node
## Dev tool (excluded from exports): plays a short scripted match to the end and screenshots
## the results screen + the share recap. Needs a real renderer:
##   godot --path . --rendering-driver opengl3 --resolution 1600x900 -- --test=stats_shot [--out=DIR]

var out_dir := "user://"


func _ready() -> void:
	Sfx.muted = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	_run.call_deferred()


func _real(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))


func _run() -> void:
	var main := get_parent()
	main.start_match({"map": 2, "bots": 3, "skill": 2, "frags": 4, "minutes": 0})
	var w: World = main.world
	w.local_player.mode = Player.Mode.BOT
	w.local_player.brain = BotBrain.new(BotBrain.Skill.ELITE)
	await _real(4.5)
	# Pad the stats so every column / award has something to show.
	var me := w.my_eid
	var plan := {me: [Weapons.SHOCK, 34, 17, 3], -1: [Weapons.MINIGUN, 60, 21, 0], -2: [Weapons.ROCKET, 14, 9, 0],
			-3: [Weapons.FLAK, 9, 30, 0]}
	for eid: int in plan:
		var p: Array = plan[eid]
		for i in p[1]:
			w.apply_event(World.Ev.SHOT, [eid, p[0], false, Vector2(-999, -999), PackedVector2Array(), []])
		for i in p[2]:
			var victim: int = -1 if eid != -1 else me
			w.apply_event(World.Ev.HIT, [victim, 20, Vector2(-999, -999), eid, false, i < p[3], -1])
	Input.action_press("scoreboard")
	await _real(0.4)
	await _shot("scoreboard")
	Input.action_release("scoreboard")
	w._kill(w.entities[-3], -2, Weapons.ROCKET, Vector2.ZERO)
	w._kill(w.entities[-1], me, Weapons.SHOCK, Vector2.ZERO)
	w._kill(w.local_player, -2, Weapons.ROCKET, Vector2.ZERO)
	await _real(0.6)
	for v in [-1, -2, -3]:
		if w.ended:
			break
		w._kill(w.entities[v], me, Weapons.SHOCK if v != -3 else Weapons.SNIPER, Vector2.ZERO)
	if not w.ended:
		w._end_match(me)
	await _real(0.5)
	await _shot("results_early")
	await _real(4.0)
	await _shot("results")
	var st: MatchStats = w.get_node_or_null(^"MatchStats")
	if st:
		var img: Image = await st.render_recap()
		if img:
			img.save_png(out_dir.path_join("recap.png"))
			print("saved recap ", img.get_size())
		else:
			print("recap: no image")
	print("DONE fails=0")
	get_tree().quit()
