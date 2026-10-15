class_name Terrain
extends RefCounted
## Grid terrain, rooms, water levels, dig designations and path-finding.
## Walkable = TUNNEL cells anywhere, plus the AIR row directly above the soil (the ground line).

signal cell_changed(cell: Vector2i)

var cells := PackedByteArray()
var rooms := PackedByteArray()
var water := PackedFloat32Array()
## Vector2i -> {"claimed": int ant id or -1, "progress": float}
var dig_jobs := {}
var astar := AStarGrid2D.new()
var rng := RandomNumberGenerator.new()
var tunnel_count := 0


func _init(seed_value: int = 1) -> void:
	rng.seed = seed_value
	cells.resize(Cfg.W * Cfg.H)
	rooms.resize(Cfg.W * Cfg.H)
	water.resize(Cfg.W * Cfg.H)
	astar.region = Rect2i(0, 0, Cfg.W, Cfg.H)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	_generate()


func idx(c: Vector2i) -> int:
	return c.y * Cfg.W + c.x


func type_at(c: Vector2i) -> int:
	if not Cfg.in_bounds(c):
		return Cfg.Cell.ROCK
	return cells[idx(c)]


func room_at(c: Vector2i) -> int:
	if not Cfg.in_bounds(c):
		return Cfg.Room.NONE
	return rooms[idx(c)]


func water_at(c: Vector2i) -> float:
	if not Cfg.in_bounds(c):
		return 0.0
	return water[idx(c)]


func is_walkable(c: Vector2i) -> bool:
	if not Cfg.in_bounds(c):
		return false
	var t := cells[idx(c)]
	return t == Cfg.Cell.TUNNEL or (t == Cfg.Cell.AIR and c.y == Cfg.SURFACE_ROW)


func is_surface(c: Vector2i) -> bool:
	return c.y == Cfg.SURFACE_ROW


## Soil-side rooms: how many cells of each room type exist.
func room_cells(room: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(Cfg.SURFACE, Cfg.H):
		for x in Cfg.W:
			if rooms[y * Cfg.W + x] == room and cells[y * Cfg.W + x] == Cfg.Cell.TUNNEL:
				out.append(Vector2i(x, y))
	return out


func _set_type(c: Vector2i, t: int) -> void:
	cells[idx(c)] = t
	astar.set_point_solid(c, not is_walkable(c))


func _generate() -> void:
	for y in Cfg.H:
		for x in Cfg.W:
			var t := Cfg.Cell.SOIL
			if y < Cfg.SURFACE:
				t = Cfg.Cell.AIR
			elif y >= Cfg.H - 2:
				t = Cfg.Cell.ROCK
			cells[y * Cfg.W + x] = t
	# Boulders, kept away from the starting nest.
	for i in 26:
		var cx := rng.randi_range(3, Cfg.W - 4)
		var cy := rng.randi_range(Cfg.SURFACE + 4, Cfg.H - 5)
		if absi(cx - Cfg.ENTRANCE_X) < 14 and cy < Cfg.SURFACE + 22:
			continue
		var r := rng.randi_range(1, 2)
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if dx * dx + dy * dy <= r * r + 1 and rng.randf() < 0.9:
					var c := Vector2i(cx + dx, cy + dy)
					if Cfg.in_bounds(c) and cells[idx(c)] == Cfg.Cell.SOIL:
						cells[idx(c)] = Cfg.Cell.ROCK
	var ex := Cfg.ENTRANCE_X
	var s := Cfg.SURFACE
	for y in range(s, s + 9):
		cells[y * Cfg.W + ex] = Cfg.Cell.TUNNEL
	for x in range(32, 49):
		cells[(s + 8) * Cfg.W + x] = Cfg.Cell.TUNNEL
	for y in range(s + 8, s + 14):
		cells[y * Cfg.W + ex] = Cfg.Cell.TUNNEL
	for y in range(s + 8, s + 10):
		for x in range(32, 36):
			cells[y * Cfg.W + x] = Cfg.Cell.TUNNEL
			rooms[y * Cfg.W + x] = Cfg.Room.NURSERY
		for x in range(45, 49):
			cells[y * Cfg.W + x] = Cfg.Cell.TUNNEL
			rooms[y * Cfg.W + x] = Cfg.Room.STORAGE
	for y in range(s + 14, s + 17):
		for x in range(37, 44):
			cells[y * Cfg.W + x] = Cfg.Cell.TUNNEL
			rooms[y * Cfg.W + x] = Cfg.Room.ROYAL
	for y in Cfg.H:
		for x in Cfg.W:
			var c := Vector2i(x, y)
			astar.set_point_solid(c, not is_walkable(c))
	_recount()


func _recount() -> void:
	tunnel_count = 0
	for y in range(Cfg.SURFACE, Cfg.H):
		for x in Cfg.W:
			if cells[y * Cfg.W + x] == Cfg.Cell.TUNNEL:
				tunnel_count += 1


## Cells in row SURFACE that are open to the sky (entrances that let rain in).
func openings() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in Cfg.W:
		if cells[Cfg.SURFACE * Cfg.W + x] == Cfg.Cell.TUNNEL:
			out.append(Vector2i(x, Cfg.SURFACE))
	return out


# --- Digging ----------------------------------------------------------------------------

func hardness(y: int) -> float:
	return 2.5 + float(y - Cfg.SURFACE) * 0.07


func has_access(c: Vector2i) -> bool:
	for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var n: Vector2i = c + d
		if is_walkable(n) or dig_jobs.has(n):
			return true
	return false


func can_designate_dig(c: Vector2i) -> bool:
	if not Cfg.in_bounds(c) or type_at(c) != Cfg.Cell.SOIL or dig_jobs.has(c):
		return false
	return has_access(c)


func designate_dig(c: Vector2i) -> bool:
	if not can_designate_dig(c):
		return false
	dig_jobs[c] = {"claimed": -1, "progress": 0.0}
	cell_changed.emit(c)
	return true


func cancel_dig(c: Vector2i) -> void:
	if dig_jobs.has(c):
		dig_jobs.erase(c)
		cell_changed.emit(c)


## The tunnel/surface cell an ant must stand on to dig cell c (nearest to `from`).
func dig_access_cell(c: Vector2i, from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var n: Vector2i = c + d
		if is_walkable(n) and water_at(n) < 0.35:
			var dist: int = absi(n.x - from.x) + absi(n.y - from.y)
			if dist < best_d:
				best_d = dist
				best = n
	return best


func unclaimed_jobs() -> int:
	var n := 0
	for k in dig_jobs:
		if dig_jobs[k]["claimed"] == -1:
			n += 1
	return n


func claim_job(ant_id: int, from: Vector2i) -> Array:
	## Returns [job_cell, access_cell] or [] when no reachable unclaimed job exists.
	var best_cell := Vector2i(-1, -1)
	var best_access := Vector2i(-1, -1)
	var best_d := 1 << 30
	for k in dig_jobs:
		var job: Dictionary = dig_jobs[k]
		if job["claimed"] != -1:
			continue
		var access := dig_access_cell(k, from)
		if access.x < 0:
			continue
		var dist: int = absi(access.x - from.x) + absi(access.y - from.y)
		if dist < best_d:
			best_d = dist
			best_cell = k
			best_access = access
	if best_cell.x < 0:
		return []
	dig_jobs[best_cell]["claimed"] = ant_id
	return [best_cell, best_access]


func release_job(c: Vector2i) -> void:
	if dig_jobs.has(c):
		dig_jobs[c]["claimed"] = -1


func complete_dig(c: Vector2i) -> void:
	dig_jobs.erase(c)
	_set_type(c, Cfg.Cell.TUNNEL)
	tunnel_count += 1
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n := Vector2i(c.x + dx, c.y + dy)
			if Cfg.in_bounds(n):
				cell_changed.emit(n)


func set_room(c: Vector2i, room: int) -> bool:
	if type_at(c) != Cfg.Cell.TUNNEL or c.y < Cfg.SURFACE:
		return false
	if rooms[idx(c)] == room:
		return false
	rooms[idx(c)] = room
	cell_changed.emit(c)
	return true


# --- Queries ------------------------------------------------------------------------------

func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not is_walkable(from) or not is_walkable(to):
		return out
	if from == to:
		out.append(from)
		return out
	var p := astar.get_id_path(from, to)
	for v in p:
		out.append(v)
	return out


func set_water_weight(c: Vector2i) -> void:
	var w := water[idx(c)]
	astar.set_point_weight_scale(c, 1.0 + (w * 10.0 if w > 0.25 else 0.0))


## Breadth-first search over walkable cells for the nearest cell satisfying `pred`.
func bfs_find(start: Vector2i, pred: Callable, max_depth: int = 40) -> Vector2i:
	if not is_walkable(start):
		return Vector2i(-1, -1)
	var seen := {start: true}
	var frontier: Array[Vector2i] = [start]
	var depth := 0
	while not frontier.is_empty() and depth <= max_depth:
		var next: Array[Vector2i] = []
		for c in frontier:
			if pred.call(c):
				return c
			for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var n: Vector2i = c + d
				if not seen.has(n) and is_walkable(n):
					seen[n] = true
					next.append(n)
		frontier = next
		depth += 1
	return Vector2i(-1, -1)
