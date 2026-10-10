class_name DummyBrain
extends RefCounted
## Simple behaviours for training dummies (idle / move only / attack only). Fills a Player's
## input fields each physics step. The OPPONENT behaviour is handled by BotBrain instead.

enum Behaviour { IDLE, MOVE, ATTACK, OPPONENT }

const SIGHT := 1100.0

var behaviour := Behaviour.IDLE
var _dir := 1.0
var _turn_t := 0.0
var _jump_t := 1.0
var _hold_t := 0.0
var _dodge_t := 2.0
var _aim_err := 0.0
var _seen_t := 0.0                     # how long the target has been visible (reaction time)


func update(p: Player, delta: float) -> void:
	p.in_move = 0.0
	p.in_jump = false
	p.in_down = false
	p.in_down_held = false
	p.in_dodge = false
	p.in_fire = false
	p.in_alt = false
	_hold_t -= delta
	p.in_jump_held = _hold_t > 0.0
	if behaviour == Behaviour.MOVE:
		_move(p, delta)
	if behaviour == Behaviour.ATTACK:
		_attack(p, delta)
	elif absf(p.in_move) > 0.1:
		p.aim = 0.0 if p.in_move > 0.0 else PI


## Patrol back and forth, hop and dodge at random, never walk into hazards or off ledges.
func _move(p: Player, delta: float) -> void:
	var lvl: Level = p.world.level
	_turn_t -= delta
	var ahead := lvl.cell_of(p.global_position + Vector2(_dir * 24.0, Player.HALF.y + 4.0))
	var drop := true
	for i in 4:
		var k := lvl.cell(ahead.x, ahead.y + i)
		if k == Level.HAZARD:
			break
		if k == Level.SOLID or k == Level.ONEWAY:
			drop = false
			break
	if _turn_t <= 0.0 or p.is_on_wall() or (p.is_on_floor() and drop):
		_dir = -_dir
		_turn_t = randf_range(1.2, 3.0)
	p.in_move = _dir
	_jump_t -= delta
	if _jump_t <= 0.0 and p.is_on_floor():
		p.in_jump = true
		_hold_t = randf_range(0.1, 0.35)
		_jump_t = randf_range(0.8, 2.5)
	elif not p.is_on_floor() and p.velocity.y > -50.0 and randf() < 0.02:
		p.in_jump = true                 # occasional double jump near the apex
	_dodge_t -= delta
	if _dodge_t <= 0.0:
		p.in_dodge = true
		_dodge_t = randf_range(2.0, 4.0)


## Aim at the human player (with a little wobble) and shoot when they've been seen briefly.
func _attack(p: Player, delta: float) -> void:
	var world: Node = p.world
	var target: Player = world.local_player
	if target == null or not target.alive:
		_seen_t = 0.0
		return
	var from := p.global_position + Player.SHOULDER
	var to := target.global_position + Vector2(0, -8)
	if from.distance_to(to) > SIGHT or not world.line_clear(from, to):
		_seen_t = 0.0
		return
	_seen_t += delta
	_aim_err = lerpf(_aim_err, randf_range(-0.12, 0.12), 0.1)
	p.aim = (to - from).angle() + _aim_err
	p.in_fire = _seen_t > 0.35
