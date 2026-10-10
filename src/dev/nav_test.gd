extends Node
## Dev tool (excluded from exports): bot navigation graph checks on every map.
## Run: godot --headless --path . -- --test=nav

var fails := 0


func _ready() -> void:
	Sfx.muted = true
	_run.call_deferred()


func _check(name: String, ok: bool, detail := "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("" if ok else "   " + detail))
	if not ok:
		fails += 1


func _run() -> void:
	var defs: Array = Maps.LIST.duplicate()
	defs.append(Maps.TRAINING)
	for def: Dictionary in defs:
		var level := Level.new()
		add_child(level)
		level.build(def)
		var t0 := Time.get_ticks_usec()
		var nav := NavGraph.new()
		nav.build(level)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var start_pos: Vector2 = level.spawns[0]
		var start := nav.nearest(start_pos)
		var missing: Array = []
		var targets: Array[Vector2] = []
		targets.append_array(level.spawns)
		targets.append_array(level.dummy_spawns)
		for it in level.pickups:
			targets.append(it.pos + Vector2(0, Level.T * 0.5 - Player.HALF.y - 1))
		for p in targets:
			var goal := nav.nearest(p)
			if nav.path(start, goal).is_empty() and goal != start:
				missing.append(level.cell_of(p))
		# And back: every target can return to the first spawn (no one-way traps).
		var stranded: Array = []
		for p in targets:
			var from := nav.nearest(p)
			if nav.path(from, start).is_empty() and from != start:
				stranded.append(level.cell_of(p))
		_check("%s: graph reaches every spawn & item (%d nodes, %.0f ms)" % [def.name, nav.node_count(), ms],
				missing.is_empty(), "unreachable: %s" % str(missing))
		_check("%s: every spot can path back" % def.name, stranded.is_empty(), "stranded: %s" % str(stranded))
		_check("%s: builds fast enough for the web (<250 ms native)" % def.name, ms < 250.0, "%.0f ms" % ms)
		level.queue_free()
	print("DONE fails=%d" % fails)
	get_tree().quit(1 if fails else 0)
