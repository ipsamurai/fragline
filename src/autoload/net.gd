extends Node
## PvP networking: room codes + WebRTC peer-to-peer (host = authoritative, clients = puppets).
##
## Signaling: a small HTTP service (tools/serve.py on the LAN)
## swaps WebRTC offers/answers/candidates for a 6-character room code. After that the host's
## game talks to each client directly. All game RPCs live on this autoload so they resolve to
## /root/Net on every peer, and are forwarded to the active World.

signal lobby_changed                   # players joined/left, or the host changed settings
signal status_changed(text: String)
signal match_started(info: Dictionary) # client: host started (or we joined mid-match)
signal left(reason: String)            # connection ended (host left, kicked, failed)

enum Role { OFFLINE, HOST, CLIENT }

const PROTOCOL := 1
const MAX_PLAYERS := 8
const POLL_FAST := 0.25
const POLL_SLOW := 1.0
const CONNECT_TIMEOUT := 15.0          # client: give up if the host never connects
## No STUN/TURN on the LAN: devices connect over their local addresses.
## Internet play would add STUN/TURN servers here.
const ICE := {"iceServers": []}

var role := Role.OFFLINE
var code := ""
var my_id := 0
var lan_url := ""                      # http://<lan-ip>:<port> of the signaling/web server
var lobby := {}                        # peer id -> {"name", "look"}
var config := {}                       # host's match setup
var world: Node                        # active World (set by Main)
var in_match := false
var debug := false                     # web ?debug=1: publish match state to window.__fragline
var _debug_t := 0.0

var _token := ""
var _base := ""
var _rtc: WebRTCMultiplayerPeer
var _conns := {}                       # peer id -> WebRTCPeerConnection
var _poll_t := 0.0
var _poll_busy := false
var _session := 0                      # bumped by close(): a host()/join() in flight sees it and bails
var _connect_left := -1.0              # client: seconds left to reach the host (< 0 = not waiting)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(func() -> void: _fail("The host left the match."))


## WebRTC is built into browsers; desktop builds need Godot's webrtc-native extension.
func webrtc_available() -> bool:
	if OS.has_feature("web"):
		return true
	return ClassDB.class_exists("WebRTCLibPeerConnection")   # registered by webrtc-native


func _signal_base() -> String:
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("location.origin", true))
	return "http://127.0.0.1:8000"


# --- hosting / joining ------------------------------------------------------------------

## Returns "" on success, or an error message. If close() (or another host/join) ran while it was
## waiting it bails and returns "" without hosting: check `role` before showing the lobby.
func host(match_config: Dictionary) -> String:
	close()
	var session := _session
	_base = _signal_base()
	var r := await _post("host", {})
	if session != _session:
		if not r.has("error"):
			_post("leave", {"code": r.get("code", ""), "token": r.get("token", "")})   # drop the unwanted room
		return ""
	if r.has("error"):
		return "Couldn't create a room: %s" % r.error
	code = r.code
	my_id = 1
	_token = r.token
	role = Role.HOST
	config = match_config
	_rtc = WebRTCMultiplayerPeer.new()
	_rtc.create_server()
	multiplayer.multiplayer_peer = _rtc
	lobby = {1: {"name": Settings.player_name, "look": Settings.look()}}
	var info := await _get_info()
	if session != _session:
		return ""                                           # close() already left the room
	lan_url = info.get("lan", _base)
	_set_title()
	lobby_changed.emit()
	return ""


## Returns "" on success or when cancelled (whoever called close() already moved the UI on),
## else an error message.
const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # matches tools/serve.py
const CODE_LEN := 6


## True for a well-formed room code (6 characters from the server's alphabet).
static func valid_code(c: String) -> bool:
	if c.length() != CODE_LEN:
		return false
	for ch in c:
		if not CODE_ALPHABET.contains(ch):
			return false
	return true


func join(room_code: String) -> String:
	close()
	room_code = room_code.strip_edges().to_upper()
	if not valid_code(room_code):
		return "That room code doesn't look right (6 letters and digits)."
	var session := _session
	_base = _signal_base()
	var r := await _post("join", {"code": room_code})
	if session != _session:
		if not r.has("error"):
			_post("leave", {"code": room_code.strip_edges().to_upper(), "token": r.get("token", "")})
		return ""
	if r.has("error"):
		return "Couldn't join: %s" % r.error
	code = room_code.strip_edges().to_upper()
	my_id = int(r.id)
	_token = r.token
	role = Role.CLIENT
	_rtc = WebRTCMultiplayerPeer.new()
	_rtc.create_client(my_id)
	multiplayer.multiplayer_peer = _rtc
	_connect_left = CONNECT_TIMEOUT
	status_changed.emit("Connecting to the host…")
	_set_title()
	return ""


func close() -> void:
	_session += 1
	_connect_left = -1.0
	if role != Role.OFFLINE and code != "":
		_post("leave", {"code": code, "token": _token})     # fire and forget
	for c: WebRTCPeerConnection in _conns.values():
		c.close()
	_conns.clear()
	if _rtc:
		_rtc.close()
	_rtc = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	role = Role.OFFLINE
	code = ""
	my_id = 0
	lobby = {}
	in_match = false
	_set_title()


func _fail(reason: String) -> void:
	if role == Role.OFFLINE:
		return
	close()
	left.emit(reason)


func join_link() -> String:
	return "%s/?join=%s" % [lan_url, code] if code != "" else ""


# --- signaling ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if debug:
		_publish_debug(delta)
	if role == Role.CLIENT and _connect_left > 0.0:
		_connect_left -= delta
		if _connect_left <= 0.0:
			_fail("Couldn't reach the host")
			return
	if role == Role.OFFLINE or _poll_busy:
		return
	_poll_t -= delta
	if _poll_t > 0.0:
		return
	# Poll quickly while anyone is still connecting; slowly once everyone is in.
	var connecting := role == Role.CLIENT and not _conns.has(1)
	for c: WebRTCPeerConnection in _conns.values():
		connecting = connecting or c.get_connection_state() != WebRTCPeerConnection.STATE_CONNECTED
	_poll_t = POLL_FAST if connecting or role == Role.HOST else POLL_SLOW
	_poll()


func _poll() -> void:
	_poll_busy = true
	var session := _session
	var r := await _post("poll", {"code": code, "token": _token})
	_poll_busy = false
	if session != _session:
		return                                              # reply belongs to a room we've left
	if r.has("error"):
		if role == Role.CLIENT and not _conns.has(1):
			_fail("Lost the room: %s" % r.error)
		return
	for m in r.get("msgs", []):
		if typeof(m) == TYPE_DICTIONARY and typeof(m.get("msg")) == TYPE_DICTIONARY:
			_on_signal(int(m.get("from", 0)), m.msg)


func _on_signal(from: int, msg: Dictionary) -> void:
	match str(msg.get("type", "")):
		"joined":
			if role == Role.HOST and lobby.size() < MAX_PLAYERS and not _conns.has(from):
				_connect_to(from, true)
		"left":
			if _conns.has(from) and not lobby.has(from):
				_conns[from].close()
				_conns.erase(from)
		"offer":
			if role == Role.CLIENT and from == 1:
				var c := _connect_to(1, false)
				c.set_remote_description("offer", str(msg.get("sdp", "")))
		"answer":
			if _conns.has(from):
				_conns[from].set_remote_description("answer", str(msg.get("sdp", "")))
		"candidate":
			if _conns.has(from):
				_conns[from].add_ice_candidate(str(msg.get("media", "")), int(msg.get("index", 0)), str(msg.get("name", "")))


func _connect_to(peer: int, make_offer: bool) -> WebRTCPeerConnection:
	var c := WebRTCPeerConnection.new()
	c.initialize(ICE)
	c.session_description_created.connect(func(type: String, sdp: String) -> void:
		c.set_local_description(type, sdp)
		_send(peer, {"type": type, "sdp": sdp}))
	c.ice_candidate_created.connect(func(media: String, index: int, name: String) -> void:
		_send(peer, {"type": "candidate", "media": media, "index": index, "name": name}))
	_rtc.add_peer(c, peer)
	_conns[peer] = c
	if make_offer:
		c.create_offer()
	return c


func _send(to: int, msg: Dictionary) -> void:
	_post("send", {"code": code, "token": _token, "to": to, "msg": msg})


func _post(route: String, body: Dictionary) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = 8.0
	add_child(req)
	var err := req.request(_base + "/signal/" + route, ["Content-Type: application/json"],
			HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		req.queue_free()
		return {"error": "can't reach the game server"}
	var res: Array = await req.request_completed
	req.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return {"error": "can't reach the game server"}
	var parsed: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"error": "bad reply from the game server"}
	if res[1] != 200 and not parsed.has("error"):
		parsed.error = "HTTP %d" % res[1]
	return parsed


func _get_info() -> Dictionary:
	var req := HTTPRequest.new()
	add_child(req)
	req.request(_base + "/signal/info")
	var res: Array = await req.request_completed
	req.queue_free()
	var parsed: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## Test hook (web, ?debug=1): who's in the match, where, and their health/score.
func _publish_debug(delta: float) -> void:
	_debug_t -= delta
	if _debug_t > 0.0 or not OS.has_feature("web"):
		return
	_debug_t = 0.5
	var state := {"role": role, "id": my_id, "code": code, "lobby": lobby.size(), "players": {}}
	if world and is_instance_valid(world) and world.level:
		state.clock = world.clock
		state.countdown = world.countdown
		for e: Player in world.entities.values():
			state.players[str(e.eid)] = {"x": roundi(e.global_position.x), "y": roundi(e.global_position.y),
					"alive": e.alive, "hp": e.health, "kills": world.roster[e.eid].kills, "mode": e.mode}
	JavaScriptBridge.eval("window.__fragline = %s" % JSON.stringify(state), true)


## Browser tab title shows the room code (handy for players, and used by the LAN tests).
func _set_title() -> void:
	if OS.has_feature("web"):
		var t := "FRAGLINE" + (" — room %s" % code if code != "" else "")
		JavaScriptBridge.eval("document.title = %s" % JSON.stringify(t), true)


# --- peers -------------------------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if role == Role.CLIENT and id == 1:
		_connect_left = -1.0
		status_changed.emit("Connected — waiting for the host")
		c_hello.rpc_id(1, Settings.player_name, Settings.look(), PROTOCOL)


func _on_peer_disconnected(id: int) -> void:
	if role == Role.HOST:
		_conns.erase(id)
		if lobby.erase(id):
			_push_lobby()
			if world:
				world.host_remove_peer(id)
	elif id == 1:
		_fail("The host left the match.")


func _push_lobby() -> void:
	lobby_changed.emit()
	if role == Role.HOST:
		s_lobby.rpc(lobby, config)


## Host: start (or restart) the match for everyone in the lobby.
func start_match(info: Dictionary) -> void:
	in_match = true
	s_start.rpc(info)


# --- RPCs: client -> host ------------------------------------------------------------------

@rpc("any_peer", "reliable")
func c_hello(pname: String, look: Dictionary, protocol: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if role != Role.HOST or lobby.has(id):
		return
	if protocol != PROTOCOL or lobby.size() >= MAX_PLAYERS:
		_rtc.disconnect_peer(id)
		return
	lobby[id] = {"name": Characters.clean_name(pname), "look": Characters.sanitize(look)}
	_push_lobby()
	if in_match and world:
		world.host_add_peer(id, lobby[id])               # late join: drop into the running match


@rpc("any_peer", "unreliable_ordered")
func c_state(data: PackedFloat32Array) -> void:
	if role == Role.HOST and world:
		world.host_client_state(multiplayer.get_remote_sender_id(), data)


@rpc("any_peer", "reliable")
func c_fire(wid: int, alt: bool, origin: Vector2, dir: Vector2) -> void:
	if role == Role.HOST and world:
		world.host_client_fire(multiplayer.get_remote_sender_id(), wid, alt, origin, dir)


# --- RPCs: host -> clients -----------------------------------------------------------------

@rpc("authority", "reliable")
func s_lobby(l: Dictionary, cfg: Dictionary) -> void:
	lobby = {}
	for id in l:
		lobby[int(id)] = {"name": Characters.clean_name(l[id].get("name")), "look": Characters.sanitize(l[id].get("look"))}
	config = cfg
	lobby_changed.emit()


@rpc("authority", "reliable")
func s_start(info: Dictionary) -> void:
	in_match = true
	match_started.emit(info)


@rpc("authority", "reliable")
func s_event(kind: int, args: Array) -> void:
	if world:
		world.apply_event(kind, args)


@rpc("authority", "unreliable_ordered")
func s_snapshot(clock: float, eids: PackedInt32Array, data: PackedFloat32Array) -> void:
	if world:
		world.client_snapshot(clock, eids, data)


@rpc("authority", "reliable")
func s_owner(kind: String, args: Array) -> void:
	if world:
		world.client_owner_message(kind, args)


## Host helper: send an owner-only message (impulse, inventory) to one client.
func to_owner(peer: int, kind: String, args: Array) -> void:
	if role == Role.HOST and peer != my_id:
		s_owner.rpc_id(peer, kind, args)
