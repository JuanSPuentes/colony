class_name Pheromones
extends RefCounted
## Five pheromone fields over the grid. Values are 0..1 intensities that decay over time
## (much faster on the surface while it rains). Only active cells are iterated.

## Decay rate per second (exponential).
const DECAY := {
	Cfg.Phero.FOOD: 0.010,
	Cfg.Phero.HOME: 0.005,
	Cfg.Phero.DANGER: 0.050,
	Cfg.Phero.ATTACK: 0.045,
	Cfg.Phero.EVACUATE: 0.022,
}
const MIN_VALUE := 0.02

var fields: Array[PackedFloat32Array] = []
var active: Array[Dictionary] = []  # per type: Vector2i -> true
var _acc := 0.0


func _init() -> void:
	for t in 5:
		var f := PackedFloat32Array()
		f.resize(Cfg.W * Cfg.H)
		fields.append(f)
		active.append({})


func get_v(t: int, c: Vector2i) -> float:
	if not Cfg.in_bounds(c):
		return 0.0
	return fields[t][c.y * Cfg.W + c.x]


func add(t: int, c: Vector2i, v: float) -> void:
	if not Cfg.in_bounds(c):
		return
	var i := c.y * Cfg.W + c.x
	fields[t][i] = minf(1.0, fields[t][i] + v)
	active[t][c] = true


func set_max(t: int, c: Vector2i, v: float) -> void:
	if not Cfg.in_bounds(c):
		return
	var i := c.y * Cfg.W + c.x
	if v > fields[t][i]:
		fields[t][i] = minf(1.0, v)
		active[t][c] = true


func erase_cell(t: int, c: Vector2i) -> void:
	if Cfg.in_bounds(c):
		fields[t][c.y * Cfg.W + c.x] = 0.0
		active[t].erase(c)


func clear_type(t: int) -> void:
	for c in active[t].keys():
		fields[t][c.y * Cfg.W + c.x] = 0.0
	active[t].clear()


func count(t: int) -> int:
	return active[t].size()


## Called every simulation tick; the real work happens every 0.25 s.
func step(dt: float, rain: float) -> void:
	_acc += dt
	if _acc < 0.25:
		return
	var d := _acc
	_acc = 0.0
	for t in 5:
		var rate: float = DECAY[t]
		var f := fields[t]
		var dead: Array[Vector2i] = []
		for c in active[t]:
			var i: int = c.y * Cfg.W + c.x
			var r := rate
			if c.y <= Cfg.SURFACE_ROW:
				r *= 1.0 + rain * 9.0  # rain washes trails off the ground
			var v: float = f[i] * exp(-r * d)
			if v < MIN_VALUE:
				f[i] = 0.0
				dead.append(c)
			else:
				f[i] = v
		for c in dead:
			active[t].erase(c)


## Strongest walkable neighbour (8-neighbourhood) that is not in `avoid`; (-1,-1) if none beats `above`.
func best_neighbor(t: int, c: Vector2i, terrain: Terrain, avoid: Array, above: float) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_v := above
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var n := Vector2i(c.x + dx, c.y + dy)
			if avoid.has(n) or not terrain.is_walkable(n):
				continue
			var v := get_v(t, n)
			if v > best_v:
				best_v = v
				best = n
	return best


## Weighted sum of pheromone along the ground line in one direction (distance-weighted).
func line_score(t: int, c: Vector2i, dir: int, reach: int) -> float:
	var s := 0.0
	for k in range(1, reach + 1):
		s += get_v(t, Vector2i(c.x + dir * k, c.y)) * (1.0 - 0.1 * (k - 1))
	return s


## Highest value of this type within a Chebyshev radius.
func max_in_radius(t: int, c: Vector2i, radius: int) -> float:
	var m := 0.0
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			m = maxf(m, get_v(t, Vector2i(c.x + dx, c.y + dy)))
	return m


## Location of the strongest cell of a type within `radius` columns of c (surface or tunnels).
func strongest_near(t: int, c: Vector2i, radius: int, min_value: float) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_v := min_value
	for k in active[t]:
		if absi(k.x - c.x) > radius or absi(k.y - c.y) > radius:
			continue
		var v := fields[t][k.y * Cfg.W + k.x]
		if v > best_v:
			best_v = v
			best = k
	return best
