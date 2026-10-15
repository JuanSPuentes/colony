class_name Flood
extends RefCounted
## Grid water model. Rain pours into tunnel cells that are open to the sky, water falls,
## spreads sideways to equalise levels and, once a cell is full, pushes upward.
## Drainage chambers soak water into the deep soil. Everything slowly seeps away.

const STEP := 0.2
const CAP := 1.0
const DRAIN_CAP := 2.5
const DRAIN_RATE := 0.45  # volume per second removed from drain cells
const SEEP_RATE := 0.012
const INFLOW := 0.55  # volume per second per opening at full rain

var terrain: Terrain
var wet := {}  # Vector2i -> true
var _acc := 0.0
var _flip := false
var max_level := 0.0


func _init(t: Terrain) -> void:
	terrain = t


func cap_of(c: Vector2i) -> float:
	return DRAIN_CAP if terrain.room_at(c) == Cfg.Room.DRAIN else CAP


func add_water(c: Vector2i, v: float) -> void:
	if terrain.type_at(c) != Cfg.Cell.TUNNEL:
		return
	var i := terrain.idx(c)
	terrain.water[i] += v
	wet[c] = true


func total() -> float:
	var s := 0.0
	for c in wet:
		s += terrain.water[terrain.idx(c)]
	return s


func step(dt: float, rain: float) -> void:
	_acc += dt
	if _acc < STEP:
		return
	var d := _acc
	_acc = 0.0
	_flip = not _flip
	if rain > 0.02:
		for o in terrain.openings():
			add_water(o, rain * INFLOW * d)
			# Shallow tunnels seep rain through the soil as well.
			for dy in range(0, 3):
				var c := Vector2i(o.x, o.y + dy)
				add_water(c, rain * 0.03 * d)
	if wet.is_empty():
		max_level = 0.0
		return
	var keys: Array = wet.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y > b.y)
	var w := terrain.water
	var touched := {}
	for c: Vector2i in keys:
		var i := terrain.idx(c)
		var amount := w[i]
		if amount <= 0.0005 or terrain.cells[i] != Cfg.Cell.TUNNEL:
			continue
		# Fall.
		var below := Vector2i(c.x, c.y + 1)
		if terrain.type_at(below) == Cfg.Cell.TUNNEL:
			var bi := terrain.idx(below)
			var space := cap_of(below) - w[bi]
			var move := minf(amount, maxf(space, 0.0))
			if move > 0.0:
				w[i] -= move
				w[bi] += move
				wet[below] = true
				touched[below] = true
				amount = w[i]
		# Spread sideways.
		if amount > 0.01:
			var dirs := [-1, 1] if _flip else [1, -1]
			for dx in dirs:
				var n := Vector2i(c.x + dx, c.y)
				if terrain.type_at(n) != Cfg.Cell.TUNNEL:
					continue
				var ni := terrain.idx(n)
				var diff := w[i] - w[ni]
				if diff > 0.02:
					var room_left := cap_of(n) - w[ni]
					var move2 := minf(diff * 0.3, maxf(room_left, 0.0))
					if move2 > 0.0:
						w[i] -= move2
						w[ni] += move2
						wet[n] = true
						touched[n] = true
		# Overflow upward.
		var over := w[i] - cap_of(c)
		if over > 0.0:
			var above := Vector2i(c.x, c.y - 1)
			if terrain.type_at(above) == Cfg.Cell.TUNNEL:
				var ai := terrain.idx(above)
				var room_up := cap_of(above) - w[ai]
				var move3 := minf(over, maxf(room_up, 0.0))
				if move3 > 0.0:
					w[i] -= move3
					w[ai] += move3
					wet[above] = true
					touched[above] = true
	# Drain + seepage, then clean up dry cells.
	max_level = 0.0
	var dry: Array[Vector2i] = []
	for c in wet:
		var i := terrain.idx(c)
		var loss := SEEP_RATE * d
		if terrain.room_at(c) == Cfg.Room.DRAIN:
			loss += DRAIN_RATE * d
		w[i] = maxf(0.0, w[i] - loss)
		if w[i] <= 0.001:
			w[i] = 0.0
			dry.append(c)
		else:
			max_level = maxf(max_level, w[i])
		terrain.set_water_weight(c)
	for c in dry:
		wet.erase(c)
		terrain.set_water_weight(c)
