extends Node
## Pooled sound playback. Positional sounds use a small ring of AudioStreamPlayer2D
## so dozens of shots per second never allocate nodes.

const POOL_2D := 20
const POOL_UI := 4
const VARIANTS := {"explode": 3, "hit": 2, "step": 3}

var _streams := {}
var _pool_2d: Array[AudioStreamPlayer2D] = []
var _pool_ui: Array[AudioStreamPlayer] = []
var _next_2d := 0
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
	for i in POOL_UI:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool_ui.append(p)


func _stream(name: String) -> AudioStream:
	if VARIANTS.has(name):
		name = "%s%d" % [name, randi_range(1, VARIANTS[name])]
	if not _streams.has(name):
		var path := "res://assets/audio/%s.ogg" % name
		_streams[name] = load(path) if ResourceLoader.exists(path) else null
	return _streams[name]


## Stop everything on shutdown so no playback outlives the audio server.
func _exit_tree() -> void:
	for p in _pool_2d:
		p.stop()
	for p in _pool_ui:
		p.stop()


## Play a sound in the world. Silently ignores unknown names.
func play_at(name: String, pos: Vector2, volume_db := 0.0, pitch := 1.0) -> void:
	if muted or world_muted:
		return
	var s := _stream(name)
	if s == null:
		return
	var p := _pool_2d[_next_2d]
	_next_2d = (_next_2d + 1) % POOL_2D
	p.stream = s
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.play()


## A looping positional sound owned by `parent` (e.g. a missile's engine). The caller moves
## it and must free it when its source is gone. Returns null when muted or missing.
func loop_at(name: String, parent: Node, pos: Vector2, volume_db := 0.0) -> AudioStreamPlayer2D:
	if muted or world_muted:
		return null
	var base := _stream(name) as AudioStreamOggVorbis
	if base == null:
		return null
	var looped := base.duplicate() as AudioStreamOggVorbis
	looped.loop = true
	var p := AudioStreamPlayer2D.new()
	p.bus = "SFX"
	p.stream = looped
	p.max_distance = 1800.0
	p.volume_db = volume_db
	parent.add_child(p)
	p.global_position = pos
	p.play()
	return p


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
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()
