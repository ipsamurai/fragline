class_name BotBrain
extends RefCounted
## Bot AI. Each physics step it fills a Player's input fields, exactly like a human would.
##   perceive  -> who can I see / who just shot me
##   choose    -> utility-scored goal (enemy, pickup, roam), A* path on the NavGraph
##   move      -> follow the path link by link (walk, jump, drop, climb, pad), wait out traps
##   fight     -> pick a weapon for the range, lead the target, fire after reacting

enum Skill { ROOKIE, REGULAR, VETERAN, ELITE, GODLIKE }

## reaction: s before firing at a newly seen enemy; aim_err: rad of wobble; track: aim turn rate;
## lead: how much of the target's motion it predicts; strafe/dodge: evasive movement odds;
## combo: uses shock combos; head: chance to aim for the head with hitscan; think: s between decisions.
const SKILLS := [
	{"name": "Rookie", "reaction": 0.7, "aim_err": 0.2, "track": 4.0, "lead": 0.3, "strafe": 0.3, "dodge": 0.0, "combo": false, "head": 0.0, "think": 0.5},
	{"name": "Regular", "reaction": 0.45, "aim_err": 0.11, "track": 7.0, "lead": 0.6, "strafe": 0.6, "dodge": 0.15, "combo": false, "head": 0.15, "think": 0.35},
	{"name": "Veteran", "reaction": 0.3, "aim_err": 0.065, "track": 11.0, "lead": 0.85, "strafe": 0.85, "dodge": 0.35, "combo": true, "head": 0.4, "think": 0.25},
	{"name": "Elite", "reaction": 0.2, "aim_err": 0.04, "track": 16.0, "lead": 1.0, "strafe": 1.0, "dodge": 0.55, "combo": true, "head": 0.7, "think": 0.2},
	{"name": "Godlike", "reaction": 0.12, "aim_err": 0.02, "track": 24.0, "lead": 1.0, "strafe": 1.0, "dodge": 0.75, "combo": true, "head": 0.9, "think": 0.15},
]
const SIGHT := 1100.0
const MEMORY := 3.0                     # seconds an unseen enemy stays "known"

var skill: Dictionary
var target: Player                      # current enemy (may be out of sight but remembered)
var target_visible := false
var action := ""                        # what the bot did last step (for debugging / tests)

var _p: Player
var _world: Node
var _nav: NavGraph
var _last_seen := Vector2.ZERO
var _last_seen_t := -100.0
var _seen_since := 0.0
var _think_t := 0.0
var _goal := -1
var _goal_is_enemy := false
var _path := PackedInt64Array()
var _path_i := 0
var _replan_t := 0.0
var _jump_hold := 0.0
var _airborne_t := 0.0                  # time since this bot launched a jump (prevents re-jumping)
var _double_done := false
var _strafe_dir := 1.0
var _strafe_t := 0.0
var _hop_t := 1.0
var _wobble := 0.0
var _stuck_pos := Vector2.ZERO
var _stuck_t := 0.0
var _combo_t := 0.0                     # shock combo: time since we fired a ball
var _was_engaged := false


func _init(level := Skill.REGULAR) -> void:
	skill = SKILLS[clampi(level, 0, SKILLS.size() - 1)]


func update(p: Player, delta: float) -> void:
	_p = p
	_world = p.world
	_nav = _world.get_nav()
	p.in_move = 0.0
	p.in_jump = false
	p.in_down = false
	p.in_down_held = false
	p.in_dodge = false
	p.in_fire = false
	p.in_alt = false
	_jump_hold -= delta
	_airborne_t += delta
	_think_t -= delta
	_replan_t -= delta
	if _think_t <= 0.0:
		_think_t = skill.think * randf_range(0.8, 1.2)
		_perceive()
		_choose_goal()
		_choose_weapon()
	var engaged := _engage(delta)
	if _was_engaged and not engaged and _goal >= 0:
		_set_goal(_goal, _goal_is_enemy)    # the fight moved us: re-path from where we are now
	_was_engaged = engaged
	if engaged:
		action = "engage" + (" dodge" if p.in_dodge else "") + (" hop" if p.in_jump else "")
	else:
		action = "idle"
		_follow_path()
	_fight(delta)
	_unstick(delta)
	p.in_jump_held = p.in_jump_held or _jump_hold > 0.0


# --- perception ----------------------------------------------------------------------

func _shoulder() -> Vector2:
	return _p.global_position + Player.SHOULDER


func _can_see(e: Player) -> bool:
	var from := _shoulder()
	if from.distance_to(e.global_position) > SIGHT:
		return false
	return _world.line_clear(from, e.global_position) or _world.line_clear(from, e.global_position + Vector2(0, -20))


func _perceive() -> void:
	var best: Player = null
	var best_d := INF
	for e: Player in _world.alive_players():
		if not _world.is_enemy(_p, e) or _world.level.zone_at(e.global_position) >= 0:
			continue
		var d := _p.global_position.distance_to(e.global_position)
		if d < best_d and _can_see(e):
			best_d = d
			best = e
	# Being shot makes us aware of the shooter even without line of sight.
	var shooter: Player = _world.entities.get(_p.last_attacker)
	if best == null and shooter and shooter.alive and _world.clock - _p.last_hit_time < 1.0:
		best = shooter
	if best:
		if best != target or not target_visible:
			_seen_since = _world.clock
		target = best
		target_visible = _can_see(best)
		_last_seen = best.global_position
		_last_seen_t = _world.clock
	else:
		target_visible = false
		if target and (not target.alive or _world.clock - _last_seen_t > MEMORY):
			target = null


# --- goals ---------------------------------------------------------------------------

func _choose_goal() -> void:
	var here := _p.global_position
	var best_score := -1.0
	var best_node := -1
	var best_enemy := false
	for it: Dictionary in _world.pickups.items:
		if not it.active:
			continue
		var v := _pickup_value(it)
		if v <= 0.0:
			continue
		var s := v / (1.0 + here.distance_to(it.pos) / 700.0)
		if s > best_score:
			best_score = s
			best_node = _nav.nearest(it.pos + Vector2(0, Level.T * 0.5 - Player.HALF.y - 1))
			best_enemy = false
	if target:
		var hunger := 55.0 if _p.health > 40 else 15.0
		var s := hunger / (1.0 + here.distance_to(_last_seen) / 900.0)
		if s > best_score:
			best_score = s
			best_node = _nav.nearest(_last_seen)
			best_enemy = true
	if best_node < 0 or best_score < 4.0:
		if _goal < 0 or _path_i >= _path.size():
			best_node = _roam_node()
		else:
			best_node = _goal
		best_enemy = false
	if best_node != _goal or _replan_t <= 0.0 or _off_path():
		_set_goal(best_node, best_enemy)


func _pickup_value(it: Dictionary) -> float:
	match it.type:
		"h":
			return 45.0 if _p.has_status(Status.POISON) else maxf(0.0, (100.0 - _p.health) * 0.5)
		"H":
			return 70.0 if _p.health < 150 else 0.0
		"a":
			return maxf(0.0, (150.0 - _p.armor) * 0.25)
		"D":
			return 60.0
		"w":
			var w: Dictionary = Weapons.LIST[it.wid]
			if not _p.owns(it.wid):
				return 90.0 if it.wid == Weapons.REDEEMER else w.prio * 8.0 + (25.0 if _p.owned == 1 else 0.0)
			if _p.ammo[it.wid] < w.ammo_max / 3.0:
				return w.prio * 3.0
	return 0.0


## A random walkable spot outside the spawn rooms.
func _roam_node() -> int:
	for i in 8:
		var id := randi() % _nav.node_count()
		var c := _nav.cell_of_node(id)
		if _world.level.zones[c.y * _world.level.w + c.x] < 0:
			return id
	return randi() % _nav.node_count()


func _set_goal(node: int, enemy: bool) -> void:
	_goal = node
	_goal_is_enemy = enemy
	_path = _nav.path(_nav.nearest(_p.global_position), node)
	_path_i = 1 if _path.size() > 1 else 0
	_replan_t = 1.2


func _off_path() -> bool:
	if not _p.is_on_floor() or _path.is_empty():
		return false
	var here := _nav.nearest(_p.global_position)
	for i in range(maxi(0, _path_i - 1), mini(_path.size(), _path_i + 2)):
		if _path[i] == here:
			return false
	return true


# --- movement ------------------------------------------------------------------------

func _follow_path() -> void:
	while _path_i < _path.size() and _reached(_path[_path_i]):
		_path_i += 1
	if _path_i >= _path.size():
		return
	var next := _path[_path_i]
	var prev := _path[_path_i - 1] if _path_i > 0 else next
	var kind := _nav.link_type(prev, next)
	var pos := _p.global_position
	# Only execute a link from where it starts; otherwise the path is stale (knockback, fights).
	var start := _nav.pos_of(prev)
	var away := absf(start.x - pos.x) > Level.T * 1.5 or absf(start.y - pos.y) > Level.T * 1.5
	if kind < 0 or (away and _p.is_on_floor() and kind != NavGraph.Link.WALK):
		if _replan_t < 1.0:
			_set_goal(_goal, _goal_is_enemy)
		return
	var tp := _nav.pos_of(next)
	action = "path " + NavGraph.Link.keys()[kind] + " -> " + str(_nav.cell_of_node(next))
	var dx := tp.x - pos.x
	if _trap_ahead(tp):
		return                          # wait for the laser / vent to switch off
	var grounded := _p.is_on_floor()
	match kind:
		NavGraph.Link.WALK, NavGraph.Link.FALL:
			_move_x(dx)
		NavGraph.Link.DROP:
			if grounded and absf(dx) < 12.0:
				_p.in_down = true
			_move_x(dx)
		NavGraph.Link.CLIMB:
			if not _p.is_climbing():
				_move_x(dx)
			if tp.y < pos.y - 4.0:
				_p.in_jump_held = true
			elif tp.y > pos.y + 4.0:
				_p.in_down_held = true
			else:
				_move_x(dx)
		NavGraph.Link.JUMP:
			_jump_toward(_nav.pos_of(prev), tp, grounded)
		NavGraph.Link.PAD:
			if grounded:
				_move_x(dx)
			elif pos.y + Player.HALF.y < tp.y + Player.HALF.y - 6.0:
				_move_x(dx)


func _move_x(dx: float) -> void:
	# In the air, brake when our speed would carry us past the spot (floaty low-gravity jumps).
	if not _p.is_on_floor() and signf(_p.velocity.x) == signf(dx) and absf(dx) < absf(_p.velocity.x) * 0.12:
		_p.in_move = -signf(dx)
	elif absf(dx) > 4.0:
		_p.in_move = signf(dx)


## Rising jumps go up from the takeoff column and across as soon as nothing blocks sideways
## (so gap jumps keep their momentum but ledges aren't bonked from below). Double-jumps if
## the bot is dropping before it's over the target.
func _jump_toward(takeoff: Vector2, tp: Vector2, grounded: bool) -> void:
	var pos := _p.global_position
	var rising := tp.y < pos.y - 8.0
	if grounded and _airborne_t > 0.25:
		if rising and absf(pos.x - takeoff.x) > 8.0:
			_move_x(takeoff.x - pos.x)
			return
		_p.in_jump = true
		_jump_hold = 0.35
		_airborne_t = 0.0
		_double_done = false
		if not rising:
			_move_x(tp.x - pos.x)
		return
	var feet := pos.y + Player.HALF.y
	var land := tp.y + Player.HALF.y
	var dir := signf(tp.x - pos.x)
	var below_target := feet > land - 4.0
	var short := absf(tp.x - pos.x) > 20.0
	if not _double_done and _p.velocity.y > -140.0 and (below_target or (short and _p.velocity.y > 0.0)):
		_p.in_jump = true
		_jump_hold = 0.3
		_double_done = true
	if rising and below_target and not _side_clear(dir):
		return
	_move_x(tp.x - pos.x)


## Nothing solid beside the body in direction `dir` (safe to drift sideways mid-jump).
func _side_clear(dir: float) -> bool:
	var lvl: Level = _world.level
	for y in [-Player.HALF.y + 4.0, 0.0, Player.HALF.y - 4.0]:
		var c := lvl.cell_of(_p.global_position + Vector2(dir * (Player.HALF.x + 10.0), y))
		if lvl.cell(c.x, c.y) == Level.SOLID:
			return false
	return true


func _reached(id: int) -> bool:
	var tp := _nav.pos_of(id)
	var d := tp - _p.global_position
	if _p.is_climbing():
		return absf(d.x) < 10.0 and absf(d.y) < 12.0
	return absf(d.x) < 10.0 and absf(d.y) < 16.0 and _p.is_on_floor()


## Don't walk into a laser that's firing (or about to) or a vent that's erupting.
func _trap_ahead(tp: Vector2) -> bool:
	var traps: Traps = _world.traps
	var probe := Rect2(tp - Vector2(Player.HALF.x, Player.HALF.y), Player.HALF * 2.0)
	for d in _world.level.lasers:
		if traps.laser_state(d) != Traps.OFF and traps.laser_rect(d).intersects(probe) \
				and not traps.laser_rect(d).intersects(_p.hit_rect()):
			return true
	for d in _world.level.vents:
		if traps.vent_state(d) != Traps.OFF and traps.vent_rect(d).intersects(probe) \
				and not traps.vent_rect(d).intersects(_p.hit_rect()):
			return true
	return false


## In a fight at a comfortable range, strafe and hop instead of path-following.
func _engage(delta: float) -> bool:
	if target == null or not target_visible:
		return false
	var w: Dictionary = Weapons.LIST[_p.weapon]
	var band: Vector2 = w.bot_range
	var dist := _p.global_position.distance_to(target.global_position)
	if dist > band.y:
		return false                    # too far: keep following the path toward them
	_strafe_t -= delta
	if _strafe_t <= 0.0 or not _safe_step(_strafe_dir):
		_strafe_dir = -_strafe_dir if randf() < 0.6 or not _safe_step(_strafe_dir) else _strafe_dir
		_strafe_t = randf_range(0.35, 1.1)
	var away := signf(_p.global_position.x - target.global_position.x)
	if dist < band.x and _safe_step(away):
		_p.in_move = away
	elif randf() < skill.strafe:
		_p.in_move = _strafe_dir if _safe_step(_strafe_dir) else 0.0
	_hop_t -= delta
	if _hop_t <= 0.0 and _p.is_on_floor():
		_hop_t = randf_range(0.6, 2.2) / maxf(skill.strafe, 0.2)
		_p.in_jump = true
		_jump_hold = randf_range(0.1, 0.3)
		_airborne_t = 0.0
	if randf() < skill.dodge * delta and _safe_step(_strafe_dir):
		_p.in_dodge = true
		_p.in_move = _strafe_dir
	return true


## True if a step in `dir` keeps solid ground under us (no ledges, lava or void).
func _safe_step(dir: float) -> bool:
	if dir == 0.0:
		return true
	if _trap_ahead(_p.global_position + Vector2(dir * 48.0, 0)):
		return false
	var lvl: Level = _world.level
	var c := lvl.cell_of(_p.global_position + Vector2(dir * 26.0, Player.HALF.y + 4.0))
	for i in 3:
		var k := lvl.cell(c.x, c.y + i)
		if k == Level.HAZARD:
			return false
		if k == Level.SOLID or k == Level.ONEWAY:
			return lvl.zone_at(Vector2((c.x + 0.5) * Level.T, (c.y + i - 0.5) * Level.T)) < 0
	return false


func _unstick(delta: float) -> void:
	if _p.in_move == 0.0 and not _p.is_climbing():
		_stuck_t = 0.0
		_stuck_pos = _p.global_position
		return
	if _p.global_position.distance_to(_stuck_pos) > 12.0:
		_stuck_t = 0.0
		_stuck_pos = _p.global_position
		return
	_stuck_t += delta
	if _stuck_t > 0.8 and _p.is_on_floor():
		_p.in_jump = true
		_jump_hold = 0.35
	if _stuck_t > 2.0:
		_stuck_t = 0.0
		_set_goal(_roam_node(), false)


# --- combat --------------------------------------------------------------------------

func _choose_weapon() -> void:
	var dist := _p.global_position.distance_to(target.global_position) if target else 600.0
	var best := _p.weapon
	var best_s := -INF
	for wid in Weapons.COUNT:
		if not _p.has_ammo(wid):
			continue
		var w: Dictionary = Weapons.LIST[wid]
		var band: Vector2 = w.bot_range
		var s: float = w.prio
		s += 4.0 if dist >= band.x and dist <= band.y else -4.0
		if wid in [Weapons.ROCKET, Weapons.GRENADE, Weapons.REDEEMER] and dist < 140.0:
			s -= 10.0                   # don't blow ourselves up
		if s > best_s:
			best_s = s
			best = wid
	_p.select_weapon(best)


func _fight(delta: float) -> void:
	_combo_t += delta
	if target == null or not target_visible or not target.alive:
		if absf(_p.in_move) > 0.1:
			_p.aim = lerp_angle(_p.aim, 0.0 if _p.in_move > 0.0 else PI, 1.0 - exp(-6.0 * delta))
		return
	var st := Weapons.stats(_p.weapon, false)
	var from := _shoulder()
	var aim_at := target.global_position
	if st.kind == Weapons.Kind.HITSCAN:
		if randf() < skill.head and _p.weapon in [Weapons.SNIPER, Weapons.ENFORCER]:
			aim_at.y -= 24.0
	else:
		var pd: Dictionary = Weapons.PROJ[st.proj]
		var t: float = from.distance_to(aim_at) / pd.speed
		aim_at += target.velocity * t * skill.lead
		aim_at.y -= 0.5 * pd.get("grav", 0.0) * t * t
		if _p.weapon == Weapons.ROCKET and target.is_on_floor() and skill.lead > 0.8:
			aim_at.y += 18.0            # rockets at the feet: splash is harder to dodge
	# Shock combo: shoot a ball, then beam it when it's near the target.
	var ball := _own_shock_ball()
	if ball and ball.pos.distance_to(target.global_position) < 130.0:
		aim_at = ball.pos
	_wobble = lerpf(_wobble, randf_range(-1.0, 1.0), 0.08)
	var desired: float = (aim_at - from).angle() + _wobble * skill.aim_err
	_p.aim = lerp_angle(_p.aim, desired, 1.0 - exp(-skill.track * delta))
	var ready: bool = _world.clock - _seen_since >= skill.reaction
	if not ready or absf(angle_difference(_p.aim, desired)) > 0.15:
		return
	if ball:
		_p.in_fire = ball.pos.distance_to(target.global_position) < 130.0
		return
	if _p.weapon == Weapons.SHOCK and skill.combo and _combo_t > 2.5 and from.distance_to(aim_at) > 260.0:
		_combo_t = 0.0
		_p.in_alt = true
		return
	if _p.weapon == Weapons.PULSE and from.distance_to(aim_at) < 420.0:
		_p.in_alt = true                # plasma wave up close
		return
	_p.in_fire = true


func _own_shock_ball() -> Projectiles.Proj:
	for pr in _world.projectiles.list:
		if pr.key == "shock_ball" and pr.owner_eid == _p.eid:
			return pr
	return null
