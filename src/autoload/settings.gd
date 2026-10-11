extends Node
## Persistent player preferences + input bindings (saved to user://settings.cfg).
## On the web build user:// maps to IndexedDB, so settings survive reloads.

signal changed

const PATH := "user://settings.cfg"

var player_name := "Player"
var character := 0
var look_overrides := {}          # primary / secondary / visor / helmet overrides
var master_volume := 0.8
var music_volume := 0.6
var sfx_volume := 0.9
var quality := 1                  # 0 = low (half the particles, no lamp glow), 1 = high
var auto_quality := true          # drop to low automatically if a match keeps missing frames
var announcer := true             # spoken announcer lines (web: browser speech synthesis)
var screen_shake := true
var show_fps := false
var fullscreen := false
var auto_switch := true           # switch to newly picked-up weapons
## Last "Play" setup: arena, bot count, bot skill, frag limit, time limit (minutes, 0 = none).
var match_prefs := {"map": 0, "bots": 3, "skill": 1, "frags": 15, "minutes": 10, "mode": 0, "lowgrav": false}

## action -> default keys. Mouse buttons are fixed (fire / alt fire / wheel).
const DEFAULT_KEYS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_W, KEY_SPACE, KEY_UP],
	"crouch": [KEY_S, KEY_DOWN],
	"dodge": [KEY_SHIFT],
	"next_weapon": [KEY_E],
	"prev_weapon": [KEY_Q],
	"scoreboard": [KEY_TAB],
	"pause": [KEY_ESCAPE, KEY_P],
	"training": [KEY_T],
	"xray": [KEY_X],
}
## Actions the controls menu lets players rebind (their first key).
const REBINDABLE := ["move_left", "move_right", "jump", "crouch", "dodge", "next_weapon", "prev_weapon", "scoreboard", "xray"]
const ACTION_LABELS := {
	"move_left": "Move left", "move_right": "Move right", "jump": "Jump / climb",
	"crouch": "Drop down / climb down", "dodge": "Dodge", "next_weapon": "Next weapon",
	"prev_weapon": "Previous weapon", "scoreboard": "Scoreboard", "xray": "X-Ray vision",
}
var bindings := {}                # action -> primary keycode override


func _ready() -> void:
	load_settings()
	_build_input_map()
	if not OS.has_feature("web"):      # browsers refuse fullscreen without a click, so the web build starts windowed
		apply_display()



func look() -> Dictionary:
	return Characters.resolve(character, look_overrides)


func _build_input_map() -> void:
	for action in DEFAULT_KEYS:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action)
		var keys: Array = DEFAULT_KEYS[action].duplicate()
		if bindings.has(action):
			keys[0] = int(bindings[action])
		for k in keys:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	_add_mouse("fire", MOUSE_BUTTON_LEFT)
	_add_mouse("alt_fire", MOUSE_BUTTON_RIGHT)
	_add_mouse("next_weapon", MOUSE_BUTTON_WHEEL_DOWN)
	_add_mouse("prev_weapon", MOUSE_BUTTON_WHEEL_UP)
	for i in Weapons.COUNT:
		var action := "weapon_%d" % (i + 1)
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.physical_keycode = KEY_1 + i
			InputMap.action_add_event(action, ev)


func _add_mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)



func apply_audio() -> void:
	for pair in [["Master", master_volume], ["Music", music_volume], ["SFX", sfx_volume]]:
		var i := AudioServer.get_bus_index(pair[0])
		if i >= 0:
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(pair[1], 0.0001)))


func apply_display() -> void:
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)


## Bind `keycode` as `action`'s primary key. If another rebindable action has it as its primary,
## the two swap. Keys used elsewhere (pause, 1–9 weapon slots, other fixed keys) are refused.
## Returns "" or a short message for the player.
func rebind(action: String, keycode: int) -> String:
	if keycode == KEY_NONE:
		return "That key can't be bound."
	var key := OS.get_keycode_string(keycode)
	if keycode >= KEY_1 and keycode <= KEY_9:
		return "%s is a weapon slot key." % key
	var old_key := int(bindings.get(action, DEFAULT_KEYS[action][0]))
	if keycode == old_key:
		return ""
	var swap_with := ""
	for other: String in DEFAULT_KEYS:
		if other == action:
			continue
		var keys: Array = DEFAULT_KEYS[other].duplicate()
		if bindings.has(other):
			keys[0] = int(bindings[other])
		if not keycode in keys:
			continue
		if other in REBINDABLE and keys[0] == keycode:
			swap_with = other
		else:
			return "%s is already used by %s." % [key, ACTION_LABELS.get(other, other.capitalize())]
	bindings[action] = keycode
	var msg := ""
	if swap_with != "":
		bindings[swap_with] = old_key
		msg = "Swapped: %s is now %s." % [ACTION_LABELS[swap_with], OS.get_keycode_string(old_key)]
	_build_input_map()
	save_settings()
	return msg


func reset_bindings() -> void:
	bindings.clear()
	_build_input_map()
	save_settings()


func key_name(action: String) -> String:
	return OS.get_keycode_string(int(bindings.get(action, DEFAULT_KEYS[action][0])))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in ["player_name", "character", "look_overrides", "master_volume", "music_volume",
			"sfx_volume", "show_fps", "fullscreen", "quality", "auto_quality", "announcer",
			"screen_shake", "auto_switch", "match_prefs", "bindings"]:
		cfg.set_value("prefs", key, get(key))
	cfg.save(PATH)
	apply_audio()
	changed.emit()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for key in cfg.get_section_keys("prefs"):
			var value: Variant = cfg.get_value("prefs", key)
			if key in self and typeof(value) == typeof(get(key)):
				set(key, value)
	var defaults := {"map": 0, "bots": 3, "skill": 1, "frags": 15, "minutes": 10, "mode": 0, "lowgrav": false}
	defaults.merge(match_prefs, true)
	match_prefs = defaults
	player_name = player_name.strip_edges().left(16)
	if player_name.is_empty():
		player_name = "Player"
	character = clampi(character, 0, Characters.LIST.size() - 1)
	apply_audio()
