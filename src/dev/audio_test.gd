extends Node
## Dev tool (excluded from exports): every sound name the game uses loads, loops loop,
## one-shots don't, and the SFX bus has its limiter.
## Run: godot --headless --path . -- --test=audio

var fails := 0

## Names other code plays through dynamic strings or hooks, which a source scan can't see.
const REQUIRED := [
	"equip_0", "equip_1", "equip_2", "equip_3", "equip_4", "equip_5", "equip_6", "equip_7", "equip_8",
	"flak_pump", "rocket_loop", "fall_loop", "low_ammo", "kill_confirm", "headshot", "pickup_weapon",
	"pickup_health", "pickup_armor", "pickup_power", "hit", "hit_armor", "explode", "death", "step",
	"jump", "land", "nuke", "combo", "redeemer",
]
const LOOPS := ["rocket_loop", "fall_loop"]


func _ready() -> void:
	Sfx.muted = true
	_run.call_deferred()


func _check(name: String, ok: bool, detail := "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("" if ok else "   " + detail))
	if not ok:
		fails += 1


func _scan(dir_path: String, re: RegEx, out: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for d in dir.get_directories():
		_scan(dir_path.path_join(d), re, out)
	for f in dir.get_files():
		if not f.ends_with(".gd") or dir_path.ends_with("/dev"):
			continue
		var src := FileAccess.get_file_as_string(dir_path.path_join(f))
		for m in re.search_all(src):
			out[m.get_string(2)] = f


func _files_for(n: String) -> PackedStringArray:
	var out := PackedStringArray()
	if Sfx.VARIANTS.has(n):
		for i in Sfx.VARIANTS[n]:
			out.append("%s%d" % [n, i + 1])
	else:
		out.append(n)
	return out


func _run() -> void:
	var names := {}
	var re := RegEx.new()
	re.compile("(Sfx\\.(?:play|play_at|loop_at)|_sfx)\\(\"([a-z0-9_]+)\"")
	# Capture group 2 is the name; group 1 is the call.
	_scan("res://src", re, names)
	var re2 := RegEx.new()   # ternaries like Sfx.play_at("hit_armor" if armored else "hit", ...)
	re2.compile("(Sfx\\.\\w+\\(\"[a-z0-9_]+\" if [^,]*? else) \"([a-z0-9_]+)\"")
	_scan("res://src", re2, names)
	for w: Dictionary in Weapons.LIST:
		names[w.sound] = "weapons.gd"
		if w.has("alt") and w.alt.has("sound"):
			names[w.alt.sound] = "weapons.gd"
	for k: String in Weapons.PROJ:
		if Weapons.PROJ[k].has("loop_sound"):
			names[Weapons.PROJ[k].loop_sound] = "weapons.gd"
	for n: String in REQUIRED:
		if not names.has(n):
			names[n] = "required"
	_check("sound names collected", names.size() >= 30, str(names.size()))

	var keys := names.keys()
	keys.sort()
	var total := 0.0
	for n: String in keys:
		var info := PackedStringArray()
		var ok := true
		for f in _files_for(n):
			var s: AudioStream = Sfx._load(f)
			if s == null:
				ok = false
				info.append("%s MISSING" % f)
				continue
			var dur := s.get_length()
			total += dur
			var loops := false
			if s is AudioStreamWAV:
				loops = (s as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
			elif s is AudioStreamOggVorbis:
				loops = (s as AudioStreamOggVorbis).loop
			if n in LOOPS and not loops:
				ok = false
				info.append("%s should loop" % f)
			elif not (n in LOOPS) and loops:
				ok = false
				info.append("%s loops but is a one-shot" % f)
			if dur <= 0.0 or (dur > 3.2 and not loops and n != "redeemer"):
				ok = false
			info.append("%s %.2fs%s%s" % [f, dur, " loop" if loops else "",
					" (%s)" % s.get_class().trim_prefix("AudioStream")])
		print("      %-14s vol%+5.1f%s  %s   [%s]" % [n, Sfx.VOLUME.get(n, 0.0),
				" fixed-pitch" if Sfx.FIXED_PITCH.has(n) else "", ", ".join(info), names[n]])
		_check("sound '%s' loads" % n, ok, ", ".join(info))
	print("      total clip length %.1fs" % total)

	# Looping copies for loop_at work for both WAV and Ogg sources.
	for n in ["rocket_loop", "redeemer"]:
		var l := Sfx._make_loop(Sfx._stream(n))
		var lw := l as AudioStreamWAV
		var lo := l as AudioStreamOggVorbis
		_check("loop_at stream for '%s' loops" % n, (lw and lw.loop_mode != AudioStreamWAV.LOOP_DISABLED) or (lo and lo.loop))
	_check("variant pick resolves", Sfx._stream("minigun") != null and Sfx._stream("explode") != null)

	var sfx := AudioServer.get_bus_index("SFX")
	_check("SFX bus has a limiter", sfx >= 0 and AudioServer.get_bus_effect_count(sfx) >= 1
			and AudioServer.get_bus_effect(sfx, 0) is AudioEffectHardLimiter)

	# Voice cap: a burst of one name never takes more than its MAX_VOICES slots.
	Sfx.muted = false
	var was_world := Sfx.world_muted
	Sfx.world_muted = false
	for i in 20:
		Sfx.play_at("minigun", Vector2.ZERO, -80.0)
	await get_tree().process_frame
	var used := 0
	for i in Sfx.POOL_2D:
		if Sfx._slot_name[i] == "minigun" and Sfx._pool_2d[i].playing:
			used += 1
	_check("minigun capped at %d voices" % Sfx.MAX_VOICES.minigun, used <= Sfx.MAX_VOICES.minigun, str(used))
	for p in Sfx._pool_2d:
		p.stop()
	Sfx.world_muted = was_world
	Sfx.muted = true

	print("DONE fails=%d" % fails)
	get_tree().quit(1 if fails else 0)
