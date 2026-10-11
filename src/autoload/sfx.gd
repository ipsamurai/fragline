extends Node
## Pooled sound playback. Positional sounds use a small pool of AudioStreamPlayer2D
## so dozens of shots per second never allocate nodes.
##
## Sounds load by name from res://assets/audio/<name>.wav (preferred) or <name>.ogg.
## Names ending in "_loop" are imported as looping streams: play them with loop_at(), not play_at().

const POOL_2D := 28
const POOL_UI := 6
const DIR := "res://assets/audio/"

## name -> N: plays a random one of name1..nameN.
const VARIANTS := {
	"explode": 4, "hit": 2, "step": 6, "death": 6,
	"pistol": 3, "minigun": 3, "flak": 4, "rocket": 4, "sniper": 3,
}

## Per-name level trim (dB), added to the caller's volume_db so sounds from different packs
## sit together in the mix. Measured from each file's peak 50 ms loudness.
const VOLUME := {
	"pistol": -3.0, "minigun": -7.0, "flak": -1.0, "flak_alt": 0.0, "flak_pump": -3.0,
	"rocket": 1.0, "rocket_loop": -5.0, "grenade": -3.0, "sniper": -2.0,
	"pulse": -4.0, "shock_alt": -2.0,
	"explode": -1.0, "death": 5.0, "step": 5.0, "land": 6.0, "jump": 2.0,
	"pickup_weapon": -4.0, "low_ammo": -4.0, "fall_loop": 2.0,
	"kill_confirm": -5.0, "headshot": -2.0,
	"equip_0": -7.0, "equip_1": -8.0, "equip_2": -6.0, "equip_3": -7.0, "equip_4": -1.0,
	"equip_5": -1.0, "equip_6": 0.0, "equip_7": -5.0, "equip_8": -9.0,
}

## Sounds from the "FREE FPS SFX Pack" (CC BY-ND 4.0: no derivatives). They always play
## unmodified at pitch 1.0: no random jitter, and any pitch the caller asks for is ignored.
const FIXED_PITCH := {
	"flak": true, "flak_pump": true, "rocket": true, "rocket_loop": true, "sniper": true,
	"explode": true, "death": true, "step": true, "land": true, "jump": true,
	"low_ammo": true, "fall_loop": true, "equip_5": true,
}

## Max simultaneous positional voices per name. A further play steals that name's oldest
## voice instead of cutting off some other sound (rapid fire can't starve explosions).
const MAX_VOICES := {
	"minigun": 4, "pulse": 4, "pistol": 4, "step": 3, "hit": 4, "hit_armor": 3, "bounce": 3,
	"flak": 3, "flak_pump": 2, "explode": 5, "death": 3, "rocket": 4, "spawn": 3,
}
const DEFAULT_MAX_VOICES := 6

var _streams := {}
var _looped := {}           # name -> looping version of a stream (built once)
var _variant_names := {}    # name -> PackedStringArray of its variant names (no per-play string building)
var _pool_2d: Array[AudioStreamPlayer2D] = []
var _pool_ui: Array[AudioStreamPlayer] = []
var _slot_name := PackedStringArray()   # base name each 2D voice is playing
var _slot_seq := PackedInt64Array()     # start order of each 2D voice (lower = older)
var _seq := 0
var _next_ui := 0
var muted := false          # everything silent (headless tests)
var world_muted := false    # in-world sounds silent (menu background match); UI sounds still play


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_2D:
		var p := AudioStreamPlayer2D.new()
		p.bus = "SFX"
		p.max_distance = 1500.0
		p.attenuation = 1.6
		add_child(p)
		_pool_2d.append(p)
	_slot_name.resize(POOL_2D)
	_slot_seq.resize(POOL_2D)
	for i in POOL_UI:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool_ui.append(p)
	for n: String in VARIANTS:
		var names := PackedStringArray()
		for i in VARIANTS[n]:
			names.append("%s%d" % [n, i + 1])
		_variant_names[n] = names
	_preload.call_deferred()


## Load (and on the web, register as a playback sample) every sound up front, one per frame,
## so the first rocket of a match doesn't stall the single main thread decoding it.
func _preload() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	var names: Array[String] = []
	for f in dir.get_files():
		f = f.trim_suffix(".import").trim_suffix(".remap")
		if (f.ends_with(".wav") or f.ends_with(".ogg")) and not f.get_basename() in names:
			names.append(f.get_basename())
	for n in names:
		if not is_inside_tree():
			return
		if not _streams.has(n):
			var s := _load(n)
			_streams[n] = s
			if s and OS.has_feature("web") and not AudioServer.is_stream_registered_as_sample(s):
				AudioServer.register_stream_as_sample(s)
		await get_tree().process_frame


func _load(n: String) -> AudioStream:
	var path := DIR + n + ".wav"
	if not ResourceLoader.exists(path):
		path = DIR + n + ".ogg"
		if not ResourceLoader.exists(path):
			return null
	return load(path)


func _stream(name: String) -> AudioStream:
	var vn: PackedStringArray = _variant_names.get(name, PackedStringArray())
	if not vn.is_empty():
		name = vn[randi() % vn.size()]
	if not _streams.has(name):
		_streams[name] = _load(name)
	return _streams[name]


## True when a sound with this name (or its numbered variants) exists.
func has_sound(name: String) -> bool:
	return _stream(name) != null


## Stop everything on shutdown so no playback outlives the audio server.
func _exit_tree() -> void:
	for p in _pool_2d:
		p.stop()
	for p in _pool_ui:
		p.stop()


## Pick a 2D voice for `name`: steal its own oldest voice if it is at its cap, else a free
## voice, else the oldest voice overall.
func _pick_slot(name: String) -> int:
	var limit: int = MAX_VOICES.get(name, DEFAULT_MAX_VOICES)
	var same := 0
	var oldest_same := -1
	var free := -1
	var oldest := 0
	for i in POOL_2D:
		if _pool_2d[i].playing:
			if _slot_name[i] == name:
				same += 1
				if oldest_same < 0 or _slot_seq[i] < _slot_seq[oldest_same]:
					oldest_same = i
			if _slot_seq[i] < _slot_seq[oldest]:
				oldest = i
		elif free < 0:
			free = i
			oldest = i
	if same >= limit:
		return oldest_same
	return free if free >= 0 else oldest


## Play a sound in the world. Silently ignores unknown names.
func play_at(name: String, pos: Vector2, volume_db := 0.0, pitch := 1.0) -> void:
	if muted or world_muted:
		return
	var s := _stream(name)
	if s == null:
		return
	var i := _pick_slot(name)
	var p := _pool_2d[i]
	_slot_name[i] = name
	_seq += 1
	_slot_seq[i] = _seq
	p.stream = s
	p.global_position = pos
	p.volume_db = volume_db + VOLUME.get(name, 0.0)
	p.pitch_scale = 1.0 if FIXED_PITCH.has(name) else pitch * randf_range(0.94, 1.06)
	p.play()


## A looping positional sound owned by `parent` (e.g. a missile's engine). The caller moves
## it and must free it when its source is gone. Returns null when muted or missing.
func loop_at(name: String, parent: Node, pos: Vector2, volume_db := 0.0) -> AudioStreamPlayer2D:
	if muted or world_muted:
		return null
	if not _looped.has(name):
		var base := _stream(name)
		if base == null:
			return null
		_looped[name] = _make_loop(base)
	var p := AudioStreamPlayer2D.new()
	p.bus = "SFX"
	p.stream = _looped[name]
	p.max_distance = 1800.0
	p.volume_db = volume_db + VOLUME.get(name, 0.0)
	parent.add_child(p)
	p.global_position = pos
	p.play()
	return p


## The stream itself if it already loops (set at import), else a looping copy.
func _make_loop(s: AudioStream) -> AudioStream:
	if s is AudioStreamOggVorbis:
		if (s as AudioStreamOggVorbis).loop:
			return s
		var o := s.duplicate() as AudioStreamOggVorbis
		o.loop = true
		return o
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		if w.loop_mode != AudioStreamWAV.LOOP_DISABLED:
			return w
		var c := w.duplicate() as AudioStreamWAV
		c.loop_mode = AudioStreamWAV.LOOP_FORWARD
		c.loop_begin = 0
		c.loop_end = int(w.get_length() * w.mix_rate)
		return c
	return s


## Non-positional sound (UI, announcer stings, local feedback).
func play(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	if muted:
		return
	var s := _stream(name)
	if s == null:
		return
	var p := _pool_ui[_next_ui]
	_next_ui = (_next_ui + 1) % POOL_UI
	p.stream = s
	p.volume_db = volume_db + VOLUME.get(name, 0.0)
	p.pitch_scale = 1.0 if FIXED_PITCH.has(name) else pitch
	p.play()
