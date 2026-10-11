class_name Player
extends CharacterBody2D
## A fighter. Physics runs at a fixed 60 Hz; the drawn skin is interpolated between
## physics steps so motion stays smooth on 120/144 Hz displays and in browsers.
## Combat outcomes (damage, death, pickups) are decided by World, never here.

enum Mode { LOCAL, BOT, PUPPET }       # PUPPET = driven by network updates (remote player / host's bots)

const HALF := Vector2(11, 23)          # movement hitbox half-size (22 x 46 px)
const RUN_SPEED := 320.0
const ACCEL := 2600.0
const AIR_ACCEL := 1700.0
const FRICTION := 3000.0
const GRAVITY := 1900.0
const MAX_FALL := 1150.0
const JUMP_V := 660.0
const DOUBLE_JUMP_V := 600.0
const JUMP_CUT := 0.45                 # releasing jump early keeps this fraction of upward speed
const DODGE_SPEED := 680.0
const DODGE_TIME := 0.24
const DODGE_COOLDOWN := 0.75
const PAD_V := 1550.0
const COYOTE := 0.1
const JUMP_BUFFER := 0.12
const DROP_TIME := 0.22
const SHOULDER := Vector2(0, -11)
const CLIMB_SPEED := 200.0
const SPAWN_PROTECT := 1.5

var world: Node                        # owning World
var mode := Mode.LOCAL
var brain: RefCounted                  # drives BOT-mode input: BotBrain or DummyBrain (has update())
var team := 0                          # 0 = free-for-all; teams fight anyone not on their side
var eid := 0
var look: Dictionary
var display_name := ""
var weapon := Weapons.ENFORCER
var aim := 0.0

# Combat state (authoritative copy lives on the server = this machine for now).
var alive := false
var health := 100
var armor := 0
var owned := 0                         # bitmask of weapon ids
var ammo := PackedInt32Array()
var amp_time := 0.0
var protect_time := 0.0
var respawn_at := 0.0
var last_attacker := 0
var last_hit_time := -100.0
var status := {}                       # Status kind -> seconds left
var status_src := {}                   # Status kind -> [source eid, weapon id] (server credit)
var dot_acc := {}                      # Status kind -> time since last damage tick (server)
# Spawn-room rules (see World._spawn_rules).
var zone_time := 0.0                   # loiter meter: seconds spent in spawn rooms
var left_spawn := false                # has left the spawn room since last spawning
var purge_ticks := 0
var purge_acc := 0.0

# Per-step input (keyboard/mouse for the local player; a brain for bots).
var in_move := 0.0
var in_jump := false
var in_jump_held := false
var in_down := false
var in_down_held := false
var in_dodge := false
var in_fire := false
var in_alt := false

var _coyote := 0.0
var _buffer := 0.0
var _can_double := false
var _air_dodge_used := false
var _dodge_time := 0.0
var _dodge_cd := 0.0
var _dodge_dir := 1.0
var _drop_time := 0.0
var _jump_cut_ok := false
var _fire_cd := 0.0
var _climbing := false
# Network puppet state (latest update from the owner / host).
var _net_pos := Vector2.ZERO
var _net_vel := Vector2.ZERO
var _net_age := 0.0
var _net_flags := 0
const NET_GROUNDED := 1
const NET_CLIMBING := 2
const NET_DODGING := 4
var _regrab_cd := 0.0

# Visual state.
var skin: Node2D
var pose := CharPainter.Pose.new()
var hurt_flash := 0.0
var _prev_pos := Vector2.ZERO
var _step_dist := 0.0
var _was_floor := true
var _last_vy := 0.0
var _shadow_y := 0.0           # ground height under the feet, for the drop shadow


func _init() -> void:
	collision_layer = 0                 # players never block each other or bullets
	collision_mask = 0
	set_collision_mask_value(Level.LAYER_SOLID, true)
	set_collision_mask_value(Level.LAYER_ONEWAY, true)
	floor_snap_length = 6.0
	var shape := RectangleShape2D.new()
	shape.size = HALF * 2.0
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)
	skin = Node2D.new()
	skin.draw.connect(_draw_skin)
	add_child(skin)
	ammo.resize(Weapons.COUNT)
	visible = false


func setup(p_world: Node, p_eid: int, p_mode: Mode, p_look: Dictionary, p_name: String) -> void:
	world = p_world
	eid = p_eid
	mode = p_mode
	look = p_look
	display_name = p_name


func teleport(pos: Vector2) -> void:
	global_position = pos
	_prev_pos = pos
	velocity = Vector2.ZERO


func facing() -> float:
	return 1.0 if cos(aim) >= 0.0 else -1.0


## Shot hitbox: taller than the movement box so the helmet can be hit.
func hit_rect() -> Rect2:
	return Rect2(global_position + Vector2(-12, -36), Vector2(24, 59))


func is_head_hit(p: Vector2) -> bool:
	return p.y < global_position.y - 14.0


## Barrel tip of the held pixel-art gun (matches CharPainter: trigger hand HAND_REACH along the
## aim from the shoulder, sprite grip at the hand, mirrored vertically when aiming left).
func muzzle() -> Vector2:
	var m := GunSprites.muzzle_offset(weapon) * GunSprites.hold_scale(weapon)
	m.y *= facing()
	return global_position + SHOULDER + Vector2.from_angle(aim) * CharPainter.HAND_REACH + m.rotated(aim)


# --- life cycle ------------------------------------------------------------------

func spawn_at(pos: Vector2) -> void:
	alive = true
	visible = true
	health = 100
	armor = 0
	amp_time = 0.0
	protect_time = SPAWN_PROTECT
	owned = 1 << Weapons.ENFORCER
	ammo.fill(0)
	weapon = Weapons.ENFORCER
	_fire_cd = 0.3
	_dodge_time = 0.0
	_climbing = false
	_net_pos = pos
	_net_vel = Vector2.ZERO
	_clear_status()
	zone_time = 0.0
	left_spawn = false
	purge_ticks = 0
	purge_acc = 0.0
	teleport(pos)


func die() -> void:
	alive = false
	visible = false
	velocity = Vector2.ZERO
	_clear_status()


func _clear_status() -> void:
	status.clear()
	status_src.clear()
	dot_acc.clear()
	skin.modulate = Color.WHITE


## Weapons are offline anywhere the body overlaps a spawn room or its barrier door.
func in_no_fire_zone() -> bool:
	return world.level.touches_zone(hit_rect())


func is_climbing() -> bool:
	return _climbing


func has_status(kind: int) -> bool:
	return status.has(kind)


## Movement multiplier from slows (1.0 = normal).
func _slow() -> float:
	return Status.INFO[Status.CHILL].slow if status.has(Status.CHILL) else 1.0


func push(impulse: Vector2) -> void:
	velocity += impulse
	_jump_cut_ok = false


# --- inventory -------------------------------------------------------------------

func owns(wid: int) -> bool:
	return owned & (1 << wid) != 0


func has_ammo(wid: int) -> bool:
	return owns(wid) and (Weapons.infinite(wid) or ammo[wid] > 0)


func select_weapon(wid: int) -> void:
	if wid == weapon or not has_ammo(wid):
		return
	weapon = wid
	_fire_cd = maxf(_fire_cd, 0.18)
	_low_ammo_latched = _is_low_ammo()     # switching to a low weapon doesn't count as a crossing
	_play_equip(wid)


func cycle_weapon(dir: int) -> void:
	for i in range(1, Weapons.COUNT):
		var w := posmod(weapon + dir * i, Weapons.COUNT)
		if has_ammo(w):
			select_weapon(w)
			return


func best_weapon() -> int:
	var best := Weapons.ENFORCER
	for w in Weapons.COUNT:
		if has_ammo(w) and w != Weapons.REDEEMER and Weapons.LIST[w].prio > Weapons.LIST[best].prio:
			best = w
	return best


## Called by World after a pickup grants a weapon we didn't have.
func on_new_weapon(wid: int) -> void:
	if mode == Mode.LOCAL and Settings.auto_switch and Weapons.LIST[wid].prio > Weapons.LIST[weapon].prio:
		select_weapon(wid)


# --- audio hooks: equip, flak pump, low-ammo warning, falling wind ------------------------

const LOW_AMMO_DIV := 5                # warn at <= 1/5 (20%) of max ammo
const FALL_SFX_SPEED := 900.0          # falling faster than this plays the wind loop
const FALL_SFX_DB := -6.0
const PUMP_DELAY := 0.35               # Flak primary: pump-action sound after each shot
static var _equip_names := PackedStringArray()   # per weapon id: "equip_N" if present, else "weapon_switch"
var _low_ammo_latched := false         # already warned for this crossing below 20%
var _pump_t := 0.0                     # > 0: flak pump pending (counts down in _audio_tick)
var _equip_quiet_until := 0            # msec; rate-limits bot equip sounds
var _fall_snd: AudioStreamPlayer2D     # local player's wind loop (child of this node)
var _fall_k := 0.0                     # wind loop volume, 0..1


## Equip sound for a weapon switch: loud and non-positional for "you", quiet in-world for bots.
func _play_equip(wid: int) -> void:
	if mode == Mode.PUPPET:
		return
	if _equip_names.is_empty():
		for w in Weapons.COUNT:
			var n := "equip_%d" % w
			_equip_names.append(n if Sfx.has_sound(n) else "weapon_switch")
	if mode == Mode.LOCAL:
		if not world.demo:
			Sfx.play(_equip_names[wid], -3.0)
		return
	var now := Time.get_ticks_msec()
	if now >= _equip_quiet_until:
		_equip_quiet_until = now + 600
		Sfx.play_at(_equip_names[wid], global_position, -12.0)


func _is_low_ammo() -> bool:
	return not Weapons.infinite(weapon) and ammo[weapon] * LOW_AMMO_DIV <= Weapons.max_ammo(weapon)


## Called right after a shot is requested (ammo already spent on this machine).
func _after_fire_audio(alt: bool) -> void:
	if weapon == Weapons.FLAK and not alt:
		_pump_t = PUMP_DELAY
	if mode != Mode.LOCAL:
		return
	var low := _is_low_ammo()
	if low and not _low_ammo_latched and ammo[weapon] > 0 and not world.demo:
		Sfx.play("low_ammo", -4.0)
	_low_ammo_latched = low


## Per-frame audio upkeep: the pending flak pump (everyone) and the falling wind (local only).
func _audio_tick(delta: float) -> void:
	if _pump_t > 0.0:
		_pump_t -= delta
		if _pump_t <= 0.0 and alive and weapon == Weapons.FLAK:
			Sfx.play_at("flak_pump", global_position, -6.0 if mode == Mode.LOCAL else -11.0)
	if mode != Mode.LOCAL and _fall_snd == null:
		return
	if mode != Mode.LOCAL or not alive or is_on_floor():
		_fall_k = 0.0                   # landed / died: cut immediately (land/death sounds cover it)
	else:
		var falling: bool = velocity.y > FALL_SFX_SPEED and not _climbing and not world.demo
		_fall_k = move_toward(_fall_k, 1.0 if falling else 0.0, delta * (2.5 if falling else 4.0))
	if _fall_k <= 0.0:
		if _fall_snd:
			_fall_snd.queue_free()
			_fall_snd = null
		return
	if _fall_snd == null:
		_fall_snd = Sfx.loop_at("fall_loop", self, global_position, -60.0)
		if _fall_snd == null:           # muted or file missing
			return
	_fall_snd.volume_db = FALL_SFX_DB + linear_to_db(_fall_k)


# --- per-frame -------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_prev_pos = global_position
	if not alive or world.in_countdown():
		return
	amp_time = maxf(0.0, amp_time - delta)
	protect_time = maxf(0.0, protect_time - delta)
	for k in status.keys():
		status[k] -= delta
		if status[k] <= 0.0:
			status.erase(k)
	if mode == Mode.PUPPET:
		_puppet_step(delta)
		return
	if world.ended:
		# Results screen: nobody keeps running or shooting; gravity still settles everyone.
		in_move = 0.0
		in_jump = false
		in_jump_held = false
		in_down = false
		in_down_held = false
		in_dodge = false
		in_fire = false
		in_alt = false
		_simulate(delta)
		return
	if mode == Mode.LOCAL:
		_read_local_input()
	elif brain:
		brain.update(self, delta)
	_simulate(delta)
	_update_fire(delta)


func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.LOCAL or not alive or world.paused or world.input_blocked:
		return
	for i in Weapons.COUNT:
		if event.is_action_pressed("weapon_%d" % (i + 1)):
			select_weapon(i)
			return
	if event.is_action_pressed("next_weapon"):
		cycle_weapon(1)
	elif event.is_action_pressed("prev_weapon"):
		cycle_weapon(-1)


func _read_local_input() -> void:
	if world.paused or world.input_blocked:
		in_move = 0.0
		in_jump = false
		in_jump_held = false
		in_down = false
		in_down_held = false
		in_dodge = false
		in_fire = false
		in_alt = false
		return
	var t: TouchControls = world.touch
	if t and t.active:
		# Touch: sticks + buttons. Taps also emulate the mouse, so mouse fire is ignored here;
		# the keyboard still works for movement (e.g. a tablet with a keyboard).
		in_move = t.move if t.move != 0.0 else Input.get_axis("move_left", "move_right")
		in_jump = t.jump_pressed or Input.is_action_just_pressed("jump")
		in_jump_held = t.jump_held or Input.is_action_pressed("jump")
		in_down = t.down_pressed or Input.is_action_just_pressed("crouch")
		in_down_held = t.down_held or Input.is_action_pressed("crouch")
		in_dodge = t.dodge_pressed or Input.is_action_just_pressed("dodge")
		in_fire = t.fire
		in_alt = t.alt
		if t.aim_dir != Vector2.ZERO:
			aim = t.assisted_aim(self, global_position + SHOULDER)
		if t.consume_weapon_cycle() > 0:
			cycle_weapon(1)
		return
	in_move = Input.get_axis("move_left", "move_right")
	in_jump = Input.is_action_just_pressed("jump")
	in_jump_held = Input.is_action_pressed("jump")
	in_down = Input.is_action_just_pressed("crouch")
	in_down_held = Input.is_action_pressed("crouch")
	in_dodge = Input.is_action_just_pressed("dodge") or (in_down and absf(in_move) > 0.1 and is_on_floor())
	in_fire = Input.is_action_pressed("fire")
	in_alt = Input.is_action_pressed("alt_fire")
	aim = (get_global_mouse_position() - (global_position + SHOULDER)).angle()


func _update_fire(delta: float) -> void:
	_fire_cd -= delta
	if not (in_fire or in_alt) or _fire_cd > 0.0:
		return
	if status.has(Status.SHOCK) or in_no_fire_zone():   # jammed / in a spawn room: trigger clicks
		_fire_cd = 0.3
		if mode == Mode.LOCAL:
			Sfx.play("no_ammo", -10.0, 1.4)
		return
	var alt := in_alt and not in_fire
	var st := Weapons.stats(weapon, alt)
	var cost: int = st.get("cost", 1)
	if not Weapons.infinite(weapon) and ammo[weapon] < cost:
		_fire_cd = 0.25
		if mode == Mode.LOCAL:
			Sfx.play("no_ammo", -6.0)
		select_weapon(best_weapon())
		return
	_fire_cd = st.rate
	protect_time = 0.0                  # firing ends spawn protection
	if world.is_net_client() and not Weapons.infinite(weapon):
		ammo[weapon] -= cost            # predicted; the host's inventory updates correct it
	world.request_fire(self, weapon, alt, muzzle(), Vector2.from_angle(aim))
	_after_fire_audio(alt)              # flak pump + low-ammo warning
	if not has_ammo(weapon):            # e.g. the Redeemer after its one shot: don't wait for a dry click
		select_weapon(best_weapon())


# --- network -------------------------------------------------------------------------

## Local player's state for the host: position, velocity, aim, flags, weapon.
func pack_state() -> PackedFloat32Array:
	return PackedFloat32Array([global_position.x, global_position.y, velocity.x, velocity.y, aim,
			state_flags(), weapon])


func state_flags() -> int:
	return (NET_GROUNDED if is_on_floor() else 0) | (NET_CLIMBING if _climbing else 0) \
			| (NET_DODGING if _dodge_time > 0.0 else 0)


## Puppet: take the newest reported state (7 floats starting at `i`).
func net_update(data: PackedFloat32Array, i: int) -> void:
	_net_pos = Vector2(data[i], data[i + 1])
	_net_vel = Vector2(data[i + 2], data[i + 3])
	aim = data[i + 4]
	_net_flags = int(data[i + 5])
	weapon = clampi(int(data[i + 6]), 0, Weapons.COUNT - 1)
	_net_age = 0.0
	if _net_flags & NET_DODGING and _dodge_time <= 0.0:
		_dodge_time = DODGE_TIME
		_dodge_dir = signf(_net_vel.x) if _net_vel.x != 0.0 else facing()


## Smoothly chase the reported position, extrapolating briefly with its velocity.
## Big jumps (respawns, teleports) snap instead of sliding across the map.
func _puppet_step(delta: float) -> void:
	_net_age += delta
	_dodge_time = maxf(0.0, _dodge_time - delta)
	var target := _net_pos + _net_vel * minf(_net_age, 0.1)
	if global_position.distance_to(target) > 160.0:
		global_position = target
		_prev_pos = target
	else:
		global_position = global_position.lerp(target, 1.0 - exp(-20.0 * delta))
	velocity = _net_vel


## Ladders: touch one anywhere (standing, jumping or falling past) while holding W or S to
## grab it. W/S climb (also through platforms), sideways steps off, jump + direction leaps off.
## Returns true while climbing (normal movement is skipped for that step).
func _climb(delta: float) -> bool:
	_regrab_cd -= delta
	var lvl: Level = world.level
	var ladder_x := _touching_ladder()
	var on_ladder := not is_nan(ladder_x)
	var below := lvl.cell_of(_feet() + Vector2(0, 4))
	var ladder_below := is_on_floor() and lvl.is_ladder(below)
	if ladder_below and not on_ladder:
		ladder_x = (below.x + 0.5) * Level.T
	if not _climbing:
		var grab_up := on_ladder and in_jump_held and (not is_on_floor() or absf(in_move) < 0.5)
		var grab_down := in_down_held and (ladder_below or (on_ladder and not is_on_floor()))
		if _regrab_cd > 0.0 or not (grab_up or grab_down):
			return false
		_climbing = true
		_dodge_time = 0.0
	if not (on_ladder or ladder_below) or (absf(in_move) > 0.5 and not in_jump_held and not in_down_held):
		_climbing = false
		return false
	if in_jump and absf(in_move) > 0.1:
		_climbing = false
		_regrab_cd = 0.3
		velocity = Vector2(in_move * RUN_SPEED, -JUMP_V * 0.8)
		_jump_cut_ok = true
		return false
	var vertical := (1.0 if in_down_held else 0.0) - (1.0 if in_jump_held else 0.0)
	velocity.y = vertical * CLIMB_SPEED * _slow()
	velocity.x = (ladder_x - global_position.x) * 18.0
	set_collision_mask_value(Level.LAYER_ONEWAY, false)
	_can_double = true
	_air_dodge_used = false
	_last_vy = 0.0
	move_and_slide()
	if absf(velocity.y) > 1.0:
		_step_dist += absf(velocity.y) * delta
	return true


## Centre x of a ladder the body overlaps (sampled across the hitbox), or NAN.
func _touching_ladder() -> float:
	var lvl: Level = world.level
	var ys := [global_position.y - 16.0, global_position.y, global_position.y + HALF.y - 4.0]
	if _climbing:
		ys.append(global_position.y + HALF.y + 2.0)   # keep hold while stepping off the top
	for dx in [0.0, -10.0, 10.0]:
		for y: float in ys:
			var c := lvl.cell_of(Vector2(global_position.x + dx, y))
			if lvl.is_ladder(c):
				return (c.x + 0.5) * Level.T
	return NAN


func _simulate(delta: float) -> void:
	if _climb(delta):
		return
	var grav_scale: float = world.gravity_scale
	var fric: float = world.friction
	var on_floor := is_on_floor()
	if on_floor:
		_coyote = COYOTE
		_can_double = true
		_air_dodge_used = false
	else:
		_coyote -= delta
	_buffer = JUMP_BUFFER if in_jump else _buffer - delta

	# Dodge: short burst, once in the air until landing.
	_dodge_cd -= delta
	if in_dodge and _dodge_cd <= 0.0 and (on_floor or not _air_dodge_used):
		_dodge_dir = signf(in_move) if absf(in_move) > 0.1 else facing()
		_dodge_time = DODGE_TIME
		_dodge_cd = DODGE_COOLDOWN
		velocity.x = _dodge_dir * DODGE_SPEED * _slow()
		if not on_floor:
			_air_dodge_used = true
			velocity.y = minf(velocity.y, -180.0)
		Sfx.play_at("jump", global_position, -6.0, 1.4)
		world.fx.dust(_feet(), 6, Vector2(-_dodge_dir * 120.0, 0))

	if _dodge_time > 0.0:
		_dodge_time -= delta
	else:
		var target := in_move * RUN_SPEED * _slow()
		var accel := (ACCEL * fric) if on_floor else AIR_ACCEL
		if on_floor and absf(in_move) < 0.1:
			accel = FRICTION * fric
		velocity.x = move_toward(velocity.x, target, accel * delta)

	# Jump, coyote time, buffered jump, double jump, variable height.
	var jump_k: float = Status.INFO[Status.CHILL].jump if status.has(Status.CHILL) else 1.0
	if _buffer > 0.0 and _coyote > 0.0:
		velocity.y = -JUMP_V * jump_k
		_buffer = 0.0
		_coyote = 0.0
		_jump_cut_ok = true
		pose.squash = 0.8
		Sfx.play_at("jump", global_position, -8.0)
		world.fx.dust(_feet(), 5)
	elif in_jump and not on_floor and _coyote <= 0.0 and _can_double:
		velocity.y = -DOUBLE_JUMP_V * jump_k
		_can_double = false
		_jump_cut_ok = true
		pose.squash = 0.6
		Sfx.play_at("jump", global_position, -8.0, 1.25)
		world.fx.burst(_feet(), look.visor, 8, 140.0)
	if _jump_cut_ok and not in_jump_held and velocity.y < -JUMP_V * JUMP_CUT:
		velocity.y = -JUMP_V * JUMP_CUT
		_jump_cut_ok = false
	if velocity.y >= 0.0:
		_jump_cut_ok = false

	velocity.y = minf(velocity.y + GRAVITY * grav_scale * delta, MAX_FALL)

	# Drop through one-way platforms by briefly ignoring their layer.
	if in_down and on_floor and not world.level.is_ladder(world.level.cell_of(_feet() + Vector2(0, 4))):
		_drop_time = DROP_TIME
	_drop_time -= delta
	set_collision_mask_value(Level.LAYER_ONEWAY, _drop_time <= 0.0)

	# Jump pads launch to the same height regardless of map gravity.
	if on_floor and world.level.is_pad(world.level.cell_of(global_position + Vector2(0, HALF.y - 2))):
		velocity.y = -PAD_V * sqrt(grav_scale)
		_jump_cut_ok = false
		pose.squash = 1.0
		Sfx.play_at("jumppad", global_position, -2.0)
		world.fx.burst(_feet(), world.level.theme.edge, 16, 260.0)

	_last_vy = velocity.y
	move_and_slide()


func _process(delta: float) -> void:
	_audio_tick(delta)                  # flak pump timer + falling wind (runs while dead to clean up)
	if not alive:
		return
	# Interpolate the drawn body between the last two physics positions.
	var f := Engine.get_physics_interpolation_fraction()
	skin.position = _prev_pos.lerp(global_position, f) - global_position
	var climbing := _climbing if mode != Mode.PUPPET else bool(_net_flags & NET_CLIMBING)
	var grounded := climbing or (is_on_floor() if mode != Mode.PUPPET else bool(_net_flags & NET_GROUNDED))
	var speed := absf(velocity.x) if not climbing else 0.0
	if grounded:
		_step_dist += speed * delta
		if _step_dist > 78.0:
			_step_dist = 0.0
			Sfx.play_at("step", global_position, -14.0)
		if not _was_floor and _last_vy > 300.0:
			pose.squash = -clampf(_last_vy / 1100.0, 0.35, 1.0)
			world.fx.dust(_feet(), 7 if _last_vy > 700.0 else 4)
			if _last_vy > 450.0:
				Sfx.play_at("land", global_position, -10.0)
	_was_floor = grounded
	pose.flash = maxf(0.0, pose.flash - delta)
	hurt_flash = maxf(0.0, hurt_flash - delta)
	_status_visuals()
	_update_pose(delta, grounded, speed)
	skin.queue_redraw()


## Particles + body tint for active statuses (cosmetic only).
func _status_visuals() -> void:
	var tint := Color.WHITE
	var fx: Fx = world.fx
	var at := visual_position()
	for k in status:
		var info: Dictionary = Status.INFO[k]
		tint = tint * info.tint
		if randf() > 0.35:
			continue
		var c: Color = info.color
		var p := at + Vector2(randf_range(-11, 11), randf_range(-30, 18))
		match k:
			Status.BURN:
				fx.emit(p, Vector2(randf_range(-20, 20), randf_range(-140, -70)), 0.4, 4.0, 1.0, c, -100.0, 1.0, true)
			Status.POISON:
				fx.emit(p, Vector2(randf_range(-15, 15), randf_range(-60, -30)), 0.7, 2.0, 4.5, Color(c, 0.7), -20.0, 0.5)
			Status.CHILL:
				fx.emit(p, Vector2(randf_range(-20, 20), randf_range(10, 50)), 0.6, 2.5, 0.5, Color(0.9, 0.98, 1.0, 0.9), 60.0, 0.5, true)
			Status.SHOCK:
				fx.emit(p, Vector2.from_angle(randf() * TAU) * 180.0, 0.12, 2.0, 0.3, c, 0.0, 0.0, true)
	if skin.modulate != tint:
		skin.modulate = tint


func visual_position() -> Vector2:
	return global_position + skin.position


func _feet() -> Vector2:
	return global_position + Vector2(0, HALF.y)


func _update_pose(delta: float, grounded: bool, speed: float) -> void:
	var speed01 := clampf(speed / RUN_SPEED, 0.0, 1.0)
	if grounded:
		pose.phase += speed * delta * 0.045
	pose.time += delta
	pose.facing = facing()
	pose.aim = aim
	pose.speed01 = speed01 if grounded else 0.0
	pose.air = not grounded
	pose.vy = velocity.y
	pose.wid = weapon
	pose.squash = lerpf(pose.squash, 0.0, 1.0 - exp(-12.0 * delta))
	var lean_target := 0.13 * speed01 * signf(velocity.x) * pose.facing if grounded else 0.0
	pose.lean = lerpf(pose.lean, lean_target, 1.0 - exp(-10.0 * delta))
	pose.roll = (1.0 - _dodge_time / DODGE_TIME) * TAU * _dodge_dir if _dodge_time > 0.0 else 0.0
	# Find the ground under the feet (up to 6 tiles) for the contact shadow.
	var lvl: Level = world.level
	var c := lvl.cell_of(_feet() - Vector2(0, 2))
	_shadow_y = -1.0
	for i in 7:
		var k := lvl.cell(c.x, c.y + i)
		if k == Level.SOLID or k == Level.ONEWAY:
			_shadow_y = (c.y + i) * Level.T
			break


func _draw_skin() -> void:
	# Everything below is DrawUtil (one batched draw call per fighter, shared across fighters);
	# only the name tag (font texture) breaks the batch.
	if skin.texture_filter != DrawUtil.FILTER:
		DrawUtil.setup(skin)
	if _shadow_y > 0.0:
		var feet_y := global_position.y + skin.position.y + HALF.y
		var height := maxf(0.0, _shadow_y - feet_y)
		var k := clampf(1.0 - height / 200.0, 0.0, 1.0)
		var center := Vector2(0, _shadow_y - global_position.y - skin.position.y)
		skin.draw_set_transform(center, 0.0, Vector2(1.0, 0.28))
		DrawUtil.circle(skin, Vector2.ZERO, 16.0 * (0.5 + 0.5 * k), Color(0, 0, 0, 0.35 * k))
		skin.draw_set_transform(Vector2.ZERO)
	# Damage-amp aura and spawn-protection bubble.
	if amp_time > 0.0:
		DrawUtil.circle(skin, Vector2(0, -6), 34.0, Color(0.7, 0.3, 1.0, 0.13 + 0.05 * sin(pose.time * 10.0)))
	CharPainter.draw(skin, look, pose)
	if protect_time > 0.0:
		DrawUtil.thin_ring(skin, Vector2(0, -6), 36.0, Color(look.visor, 0.35 + 0.25 * sin(pose.time * 14.0)))
	if hurt_flash > 0.0:
		DrawUtil.circle(skin, Vector2(0, -6), 30.0, Color(1, 0.3, 0.3, hurt_flash * 1.5))
	_draw_overhead()


## Health bar (green → amber → red, cyan overheal), armour strip under it, name above.
func _draw_overhead() -> void:
	const W := 34.0
	const HP_HI := Color(0.290, 0.871, 0.502)      # 4ade80
	const AMBER := Color(0.984, 0.749, 0.141)      # fbbf24
	const HP_LO := Color(0.973, 0.443, 0.443)      # f87171
	const OVERHEAL := Color(0.220, 0.741, 0.973)   # 38bdf8
	var top := Vector2(-W * 0.5, -50.0)
	var hp_col := HP_HI if health > 60 else (AMBER if health > 30 else HP_LO)
	DrawUtil.rect(skin, Rect2(top - Vector2(1, 1), Vector2(W + 2, 9)), Color(0, 0, 0, 0.55))
	DrawUtil.rect(skin, Rect2(top, Vector2(W * clampf(health / 100.0, 0.0, 1.0), 4)), hp_col)
	if health > 100:
		DrawUtil.rect(skin, Rect2(top, Vector2(W * (health - 100) / 99.0, 1.5)), OVERHEAL)
	if armor > 0:
		DrawUtil.rect(skin, Rect2(top + Vector2(0, 5), Vector2(W * minf(armor / 150.0, 1.0), 2)), AMBER)
	if mode != Mode.LOCAL:
		skin.draw_string(ThemeDB.fallback_font, Vector2(-60, -55), display_name, HORIZONTAL_ALIGNMENT_CENTER,
				120, 12, Color(1, 1, 1, 0.75))
