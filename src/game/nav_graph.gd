class_name NavGraph
extends RefCounted
## Bot navigation graph built from the tile grid (same movement rules as the map checker).
## Nodes: cells a fighter can stand in, plus ladder cells. Directed links carry how to
## traverse them (walk, jump, fall off a ledge, drop through a platform, climb, jump pad).

enum Link { WALK, JUMP, FALL, DROP, CLIMB, PAD }

const MAX_RISE := 5             # rows a double jump can climb
const MAX_JUMP_DX := 6          # columns a jump can cross
const MAX_DROP := 6             # rows a jump may land below its start
const ZONE_WEIGHT := 6.0        # spawn rooms: bots pass through, never linger
const TRAP_WEIGHT := 3.0        # laser beams / vent columns: prefer other routes

var level: Level
var astar := AStar2D.new()
var _ids := PackedInt32Array()  # cell index -> node id (-1 = none)
var _cells: Array[Vector2i] = []
var _links := {}                # (a << 20) | b -> Link


func build(p_level: Level) -> void:
	level = p_level
	_ids.resize(level.w * level.h)
	_ids.fill(-1)
	for y in level.h:
		for x in level.w:
			if _standable(x, y) or _climbable(x, y):
				_add_node(Vector2i(x, y))
	for id in _cells.size():
		_link_from(id)
	_apply_weights()


# --- queries ---------------------------------------------------------------------

func node_at(c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= level.w or c.y >= level.h:
		return -1
	return _ids[c.y * level.w + c.x]


func cell_of_node(id: int) -> Vector2i:
	return _cells[id]


## Where a fighter's body centre sits when occupying this node.
func pos_of(id: int) -> Vector2:
	var c := _cells[id]
	if _standable(c.x, c.y):
		return Vector2((c.x + 0.5) * Level.T, (c.y + 1) * Level.T - Player.HALF.y - 1)
	return Vector2((c.x + 0.5) * Level.T, (c.y + 0.5) * Level.T)


## How to get from a to b, or -1 if they aren't linked (caller should replan).
func link_type(a: int, b: int) -> int:
	return _links.get((a << 20) | b, -1)


## Node under a body position: the feet cell, the cells just below (mid-air), else nearest.
func nearest(body: Vector2) -> int:
	var feet := level.cell_of(body + Vector2(0, Player.HALF.y - 2))
	for dy in 4:
		var id := node_at(feet + Vector2i(0, dy))
		if id >= 0:
			return id
	var mid := node_at(level.cell_of(body))
	if mid >= 0:
		return mid
	return astar.get_closest_point(body)


func path(from_id: int, to_id: int) -> PackedInt64Array:
	if from_id < 0 or to_id < 0:
		return PackedInt64Array()
	return astar.get_id_path(from_id, to_id)


func node_count() -> int:
	return _cells.size()


# --- building ----------------------------------------------------------------------

func _free(x: int, y: int) -> bool:
	var k := level.cell(x, y)
	return k != Level.SOLID and k != Level.HAZARD


func _floor(x: int, y: int) -> bool:
	var k := level.cell(x, y)
	return k == Level.SOLID or k == Level.ONEWAY


func _standable(x: int, y: int) -> bool:
	return _free(x, y) and level.cell(x, y - 1) != Level.SOLID and _floor(x, y + 1)


func _climbable(x: int, y: int) -> bool:
	return level.is_ladder(Vector2i(x, y)) and _free(x, y - 1)


func _add_node(c: Vector2i) -> void:
	var id := _cells.size()
	_cells.append(c)
	_ids[c.y * level.w + c.x] = id
	astar.add_point(id, Vector2((c.x + 0.5) * Level.T, (c.y + 0.5) * Level.T))


func _connect(a: int, b: int, kind: Link) -> void:
	if a == b or a < 0 or b < 0:
		return
	var key := (a << 20) | b
	if _links.has(key):
		return
	_links[key] = kind
	astar.connect_points(a, b, false)


## First node straight down from (x, y), or -1 if the fall hits a hazard / nothing.
func _fall_to(x: int, y: int) -> int:
	for yy in range(y, level.h):
		if not _free(x, yy):
			return -1
		var id := node_at(Vector2i(x, yy))
		if id >= 0 and _standable(x, yy):
			return id
	return -1


## Jump path clearance: rise at the start column, cross at the top, descend at the target.
func _clear(ax: int, ay: int, bx: int, by: int) -> bool:
	var top := mini(ay, by) - 1
	for r in range(top - (1 if by < ay else 0), ay + 1):
		if not _free(ax, r):
			return false
	for x in range(mini(ax, bx), maxi(ax, bx) + 1):
		for r in range(top, mini(ay, by) + 1):
			if not _free(x, r):
				return false
	for r in range(top, by + 1):
		if not _free(bx, r):
			return false
	return true


func _link_from(id: int) -> void:
	var c := _cells[id]
	var x := c.x
	var y := c.y
	var stand := _standable(x, y)
	var ladder := _climbable(x, y)
	if ladder:
		for nb in [Vector2i(x, y - 1), Vector2i(x, y + 1)]:
			_connect(id, node_at(nb), Link.CLIMB)
	if stand:
		for d in [-1, 1]:
			var side := node_at(Vector2i(x + d, y))
			if side >= 0 and _standable(x + d, y):
				_connect(id, side, Link.WALK)
			elif side >= 0:
				_connect(id, side, Link.CLIMB)            # step onto a ladder beside us
			elif _free(x + d, y) and _free(x + d, y - 1):
				_connect(id, _fall_to(x + d, y), Link.FALL)
		if level.cell(x, y + 1) == Level.ONEWAY:
			var below := node_at(Vector2i(x, y + 1))
			if below >= 0:
				_connect(id, below, Link.CLIMB)           # ladder through this platform
			else:
				_connect(id, _fall_to(x, y + 2), Link.DROP)
		if level.is_pad(c):
			_pad_links(id, x, y)
	elif ladder:
		for d in [-1, 1]:                             # step off a ladder sideways
			var side := node_at(Vector2i(x + d, y))
			if side >= 0:
				_connect(id, side, Link.WALK)
			elif _free(x + d, y) and _free(x + d, y - 1):
				_connect(id, _fall_to(x + d, y), Link.FALL)
	if not stand:
		return
	# Jumps (single or double) to nearby nodes not already linked by walking.
	for by in range(y - MAX_RISE, y + MAX_DROP + 1):
		for bx in range(x - MAX_JUMP_DX, x + MAX_JUMP_DX + 1):
			if by == y and absi(bx - x) <= 1:
				continue
			var target := node_at(Vector2i(bx, by))
			if target < 0 or _links.has((id << 20) | target):
				continue
			if by == y and _walkable_run(x, bx, y):
				continue
			if _clear(x, y, bx, by):
				_connect(id, target, Link.JUMP)


func _walkable_run(ax: int, bx: int, y: int) -> bool:
	for x in range(mini(ax, bx), maxi(ax, bx) + 1):
		if not _standable(x, y):
			return false
	return true


func _pad_links(id: int, x: int, y: int) -> void:
	for by in range(y - 18, y - 1):
		for bx in range(x - 5, x + 6):
			var target := node_at(Vector2i(bx, by))
			if target < 0 or not _standable(bx, by):
				continue
			var ok := true
			for r in range(by - 1, y + 1):
				ok = ok and _free(x, r)
			for xx in range(mini(x, bx), maxi(x, bx) + 1):
				ok = ok and _free(xx, by - 1) and _free(xx, by)
			if ok:
				_connect(id, target, Link.PAD)


## Make spawn rooms and trap columns expensive so paths avoid lingering there.
func _apply_weights() -> void:
	for id in _cells.size():
		var c := _cells[id]
		var w := 1.0
		if level.zones.size() > 0 and level.zones[c.y * level.w + c.x] >= 0:
			w = ZONE_WEIGHT
		var center := Vector2((c.x + 0.5) * Level.T, (c.y + 0.5) * Level.T)
		for d in level.lasers:
			if absf(center.x - d.x) < Level.T and center.y >= d.top and center.y <= d.bottom:
				w = maxf(w, TRAP_WEIGHT)
		for d in level.vents:
			if absf(center.x - d.pos.x) < Level.T and center.y <= d.pos.y and center.y >= d.pos.y - 4 * Level.T:
				w = maxf(w, TRAP_WEIGHT)
		astar.set_point_weight_scale(id, w)
