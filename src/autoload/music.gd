extends Node
## Background music on the "Music" bus: the menu theme, and one looping track per arena
## (each map's "music" entry in Maps). Two players crossfade between tracks.
## Buses come from res://default_bus_layout.tres — never AudioServer.add_bus() at runtime:
## on the web that scrambles the bus order into a feedback loop and the browser mutes it all.

const MENU := "res://assets/music/menu.mp3"
const FADE := 1.5
const SILENT_DB := -40.0

var current := ""                       # path of the track playing (or fading in)
var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _tweens := {}                       # player -> its running fade Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS     # keeps playing while the game is paused
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.finished.connect(_on_finished.bind(p))
		add_child(p)
		_players.append(p)


func play_menu() -> void:
	play(MENU)


## The track assigned to a map (falls back to the menu theme if a map has none).
func play_map(def: Dictionary) -> void:
	play(def.get("music", MENU))


func play(path: String) -> void:
	if Sfx.muted or path == current:
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	current = path
	var old := _players[_active]
	_active = 1 - _active
	var nxt := _players[_active]
	nxt.stream = stream
	nxt.volume_db = SILENT_DB
	nxt.play()
	_fade(nxt, 0.0, false)
	if old.playing:
		_fade(old, SILENT_DB, true)


## Stop on shutdown so no playback outlives the audio server.
func _exit_tree() -> void:
	for p in _players:
		p.stop()


func stop() -> void:
	current = ""
	for p in _players:
		_fade(p, SILENT_DB, true)


## One fade per player: a newer fade replaces an older one, so a stale fade-out can't stop()
## a player that has since started the new track.
func _fade(p: AudioStreamPlayer, to_db: float, stop_after: bool) -> void:
	var old: Tween = _tweens.get(p)
	if old and old.is_valid():
		old.kill()
	var tw := create_tween()
	_tweens[p] = tw
	tw.tween_property(p, "volume_db", to_db, FADE)
	if stop_after:
		tw.tween_callback(p.stop)


## Every track loops. Done here rather than with AudioStreamMP3.loop, because the web
## build's sample playback ignores that flag.
func _on_finished(p: AudioStreamPlayer) -> void:
	if p == _players[_active] and current != "":
		p.play()
