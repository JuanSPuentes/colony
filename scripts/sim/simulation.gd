class_name Simulation
extends RefCounted
## Owns the whole colony simulation. No rendering or UI in here: the view reads this state
## and the UI sends commands (cmd_*). Fixed time step, deterministic for a given seed.

signal notified(text: String, kind: String)
signal fx_emitted(kind: String, pos: Vector2)

const SPECIES := SpeciesDefs.LEAFCUTTER

var seed_value := 1
var rng := RandomNumberGenerator.new()
var t := 0.0
var terrain: Terrain
var pher: Pheromones
var flood: Flood
var weather: Weather
var colony: Colony
var ants: Array[Ant] = []
var brood: Array[Brood] = []
var sources: Array[FoodSource] = []
var queen: Ant = null
var spider: Spider = null
var puddle_src: FoodSource = null

var counts := {}
var worker_count := 0
var digger_count := 0
var entrance_danger := 0.0
var outcome := 0  # 0 running, 1 won, 2 lost
var outcome_reason := ""
var stats := {
	"deliveries": 0, "dug": 0, "ants_lost": 0, "born": 0, "spiders_defeated": 0,
	"drowned": 0, "killed_by_spider": 0, "brood_lost": 0,
}
var log: Array[Dictionary] = []

var _next_ant_id := 1
var _next_src_id := 1
var _next_spider := 0
var _spider_plan: Array[Dictionary] = []
var _once := {}
var _room_cache := {}
var _room_dirty := true
var _opening_xs: Array[int] = []
var _buckets := {}
var _slow_acc := 0.0


func _init(seed_in: int = 1) -> void:
	seed_value = seed_in
	rng.seed = seed_in
	terrain = Terrain.new(seed_in)
	pher = Pheromones.new()
	flood = Flood.new(terrain)
	weather = Weather.new()
	colony = Colony.new(SPECIES)
	terrain.cell_changed.connect(func(_c: Vector2i) -> void: _room_dirty = true)
	var d := Cfg.DAY_LENGTH
	_spider_plan = [
		{"start": 2.6 * d, "hp": 90.0, "power": 1},
		{"start": 5.2 * d, "hp": 130.0, "power": 2},
		{"start": 7.6 * d, "hp": 170.0, "power": 3},
		{"start": 9.2 * d, "hp": 140.0, "power": 2},
	]
	_make_sources()
	_spawn_initial()
	colony.recompute_caps(room_list(Cfg.Room.STORAGE).size())
	notify("Welcome! Leafcutter colony founded. Workers will search for leaves.", "info")


# --- Setup --------------------------------------------------------------------------------

func _add_source(kind: int, x: int, amount: float, regrow: float, infinite := false) -> FoodSource:
	var s := FoodSource.new()
	s.id = _next_src_id
	_next_src_id += 1
	s.kind = kind
	s.cell = Vector2i(x, Cfg.SURFACE_ROW)
	s.amount = amount
	s.max_amount = amount
	s.regrow = regrow
	s.infinite = infinite
	sources.append(s)
	return s


func _make_sources() -> void:
	_add_source(Cfg.SrcKind.FOOD, 26, 80.0, 0.35).discovered = true
	_add_source(Cfg.SrcKind.FOOD, 55, 80.0, 0.35).discovered = true
	_add_source(Cfg.SrcKind.FOOD, 67, 65.0, 0.35)
	_add_source(Cfg.SrcKind.FOOD, 15, 60.0, 0.35)
	_add_source(Cfg.SrcKind.FOOD, 76, 65.0, 0.35)
	_add_source(Cfg.SrcKind.WATER, 7, 0.0, 0.0, true)
	puddle_src = _add_source(Cfg.SrcKind.WATER, Cfg.ENTRANCE_X + 7, 0.0, 0.0)
	puddle_src.temporary = true


func _spawn_initial() -> void:
	var s := Cfg.SURFACE
	queen = spawn_ant(Cfg.Caste.QUEEN, Vector2i(Cfg.ENTRANCE_X, s + 15))
	var cells: Array[Vector2i] = []
	for y in range(s + 2, s + 14):
		for x in range(30, 51):
			var c := Vector2i(x, y)
			if terrain.type_at(c) == Cfg.Cell.TUNNEL:
				cells.append(c)
	for i in 18:
		var a := spawn_ant(Cfg.Caste.WORKER, cells[rng.randi() % cells.size()])
		if i < 3:
			a.mem_food = sources[0]
		elif i < 6:
			a.mem_food = sources[1]
		a.known_water = i % 2 == 0 and i < 10
	for i in 6:
		spawn_ant(Cfg.Caste.NURSE, Vector2i(33 + i % 3, s + 8 + i % 2))
	for i in 5:
		spawn_ant(Cfg.Caste.SOLDIER, Vector2i(Cfg.ENTRANCE_X, s + 2 + i % 3))


func spawn_ant(caste: int, cell: Vector2i) -> Ant:
	var def := SpeciesDefs.caste(SPECIES, caste)
	var a := Ant.new()
	a.id = _next_ant_id
	_next_ant_id += 1
	a.caste = caste
	a.cell = cell
	a.pos = Cfg.cell_center(cell) + Vector2(rng.randf_range(-3, 3), 0)
	a.prev_pos = a.pos
	a.hp = def["hp"]
	a.max_hp = def["hp"]
	a.speed = def["speed"] * rng.randf_range(0.92, 1.08)
	a.damage = def["damage"]
	a.carry_capacity = def["carry"]
	a.hardiness = rng.randf_range(0.6, 1.6)
	a.heading = 1 if rng.randf() < 0.5 else -1
	a.think_cd = rng.randf() * 0.4
	a.attack_cd = rng.randf() * 0.5
	ants.append(a)
	if caste == Cfg.Caste.QUEEN:
		a.state = Cfg.State.IDLE
	return a


func add_brood(cell: Vector2i, caste: int) -> Brood:
	var b := Brood.new()
	b.id = _next_ant_id
	_next_ant_id += 1
	b.cell = cell
	b.caste = caste
	brood.append(b)
	return b


# --- Public helpers used by AntBrain ----------------------------------------------------------

func notify(text: String, kind: String = "info") -> void:
	log.append({"t": t, "text": text, "kind": kind})
	if log.size() > 40:
		log.pop_front()
	notified.emit(text, kind)


func notify_once(key: String, text: String, kind: String = "info") -> void:
	if _once.has(key):
		return
	_once[key] = true
	notify(text, kind)


func fx(kind: String, pos: Vector2) -> void:
	fx_emitted.emit(kind, pos)


func day() -> int:
	return int(t / Cfg.DAY_LENGTH) + 1


func day_fraction() -> float:
	return fposmod(t, Cfg.DAY_LENGTH) / Cfg.DAY_LENGTH


func adult_count() -> int:
	var n := 0
	for a in ants:
		if a.state != Cfg.State.DEAD:
			n += 1
	return n


func room_list(room: int) -> Array[Vector2i]:
	if _room_dirty:
		_room_cache.clear()
		for r in 5:
			var empty: Array[Vector2i] = []
			_room_cache[r] = empty
		for y in range(Cfg.SURFACE, Cfg.H):
			for x in Cfg.W:
				var i := y * Cfg.W + x
				if terrain.cells[i] == Cfg.Cell.TUNNEL:
					_room_cache[terrain.rooms[i]].append(Vector2i(x, y))
		_room_dirty = false
		_opening_xs.clear()
		for o in terrain.openings():
			_opening_xs.append(o.x)
		colony.recompute_caps(_room_cache[Cfg.Room.STORAGE].size())
	return _room_cache[room]


## True when column x is within r columns of a nest opening (cached, refreshed with the rooms).
func near_opening(x: int, r: int) -> bool:
	room_list(Cfg.Room.NONE)  # refreshes caches when the terrain changed
	for ox in _opening_xs:
		if absi(ox - x) <= r:
			return true
	return false


func deposit_cell() -> Vector2i:
	var store := room_list(Cfg.Room.STORAGE)
	if store.is_empty():
		return Vector2i(Cfg.ENTRANCE_X, Cfg.SURFACE + 8)
	return store[rng.randi() % store.size()]


func free_nursery_cell() -> Vector2i:
	var cells := room_list(Cfg.Room.NURSERY)
	if cells.is_empty():
		return Vector2i(-1, -1)
	var used := {}
	for b in brood:
		used[b.cell] = used.get(b.cell, 0) + 1
	var start := rng.randi() % cells.size()
	for k in cells.size():
		var c := cells[(start + k) % cells.size()]
		if used.get(c, 0) < 2 and terrain.water_at(c) < 0.2:
			return c
	return Vector2i(-1, -1)


func find_source(cell: Vector2i, kind: int, radius: int) -> FoodSource:
	var best: FoodSource = null
	var best_d := radius + 1
	for s in sources:
		if s.kind == kind and s.available():
			var d := absi(s.cell.x - cell.x)
			if d < best_d:
				best_d = d
				best = s
	if best != null:
		best.discovered = true
	return best


func nearest_source(cell: Vector2i, kind: int) -> FoodSource:
	var best: FoodSource = null
	var best_d := 1 << 30
	for s in sources:
		if s.kind == kind and s.available():
			var d := absi(s.cell.x - cell.x)
			if d < best_d:
				best_d = d
				best = s
	return best


func ants_near(pos: Vector2, radius: float) -> Array[Ant]:
	var out: Array[Ant] = []
	var bs := Cfg.CELL * 4.0
	var bx := floori(pos.x / bs)
	var by := floori(pos.y / bs)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var key := Vector2i(bx + dx, by + dy)
			if _buckets.has(key):
				for a: Ant in _buckets[key]:
					if a.state != Cfg.State.DEAD and a.pos.distance_to(pos) <= radius:
						out.append(a)
	return out


func soldiers_near_entrance(radius_cells: int) -> int:
	var n := 0
	for a in ants:
		if a.caste == Cfg.Caste.SOLDIER and a.state != Cfg.State.DEAD:
			if absi(a.cell.x - Cfg.ENTRANCE_X) <= radius_cells and a.cell.y <= Cfg.SURFACE + 6:
				n += 1
	return n


func damage_ant(a: Ant, amount: float, cause: String) -> void:
	if a.state == Cfg.State.DEAD or amount <= 0.0:
		return
	a.hp -= amount
	a.damage_flash = 0.2
	if a.hp <= 0.0:
		kill_ant(a, cause)


func kill_ant(a: Ant, cause: String) -> void:
	if a.state == Cfg.State.DEAD:
		return
	AntBrain.drop_tasks(a, self)
	a.state = Cfg.State.DEAD
	a.clear_path()
	fx("death", a.pos)
	if a.caste == Cfg.Caste.QUEEN:
		outcome = 2
		match cause:
			"spider":
				outcome_reason = "The spider reached the royal chamber and killed the queen."
			"drowned":
				outcome_reason = "The queen drowned. The royal chamber flooded - build drainage and evacuate in time."
			_:
				outcome_reason = "The queen died of " + cause + "."
		notify(outcome_reason, "danger")
		return
	stats["ants_lost"] += 1
	if cause == "drowned":
		stats["drowned"] += 1
		notify_once("drown", "Ants are drowning! Paint Evacuate signals or dig a drain.", "danger")
	elif cause == "spider":
		stats["killed_by_spider"] += 1
	if a.load_type != Cfg.Load.NONE:
		a.load_type = Cfg.Load.NONE


func complete_dig(cell: Vector2i) -> void:
	terrain.complete_dig(cell)
	colony.food = maxf(0.0, colony.food - 0.4)
	stats["dug"] += 1
	fx("dust", Cfg.cell_center(cell))
	if cell.y == Cfg.SURFACE:
		notify("A new entrance opened - rain can flood through it.", "warn")


func on_spider_gone(killed: bool) -> void:
	if killed:
		stats["spiders_defeated"] += 1
	pher.clear_type(Cfg.Phero.DANGER)


# --- Player commands -------------------------------------------------------------------------------

func cmd_dig(c: Vector2i) -> bool:
	return terrain.designate_dig(c)


func cmd_room(c: Vector2i, room: int) -> bool:
	return terrain.set_room(c, room)


func cmd_phero(type: int, c: Vector2i, value: float) -> void:
	if terrain.is_walkable(c):
		pher.set_max(type, c, value)


func cmd_erase(c: Vector2i, radius: int) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var n := Vector2i(c.x + dx, c.y + dy)
			for tp in 5:
				pher.erase_cell(tp, n)
			terrain.cancel_dig(n)


func cmd_set_brood_caste(b: Brood, caste: int) -> bool:
	if b.stage == Cfg.Stage.PUPA or caste == Cfg.Caste.QUEEN:
		return false
	b.caste = caste
	return true


# --- Main step --------------------------------------------------------------------------------------

func step(dt: float) -> void:
	if outcome != 0:
		return
	t += dt
	var msg := weather.step(dt, t)
	if msg != "":
		notify(msg, "danger" if msg.begins_with("Rain begins") else "warn")
	puddle_src.amount = weather.puddle
	flood.step(dt, weather.rain)
	pher.step(dt, weather.rain)
	for s in sources:
		s.step(dt)
	_spider_events()
	_rebuild_buckets()
	_slow_acc += dt
	if _slow_acc >= 0.25:
		_slow_acc = 0.0
		_slow_update()
	for a in ants:
		AntBrain.update(a, self, dt)
	weather.puddle = maxf(0.0, puddle_src.amount - 0.02 * dt)
	if spider != null:
		spider.step(self, dt)
	_step_brood(dt)
	colony.step(dt, self)
	_cleanup()
	_check_outcome()


func _spider_events() -> void:
	if spider == null and _next_spider < _spider_plan.size():
		var plan := _spider_plan[_next_spider]
		if t >= plan["start"]:
			_next_spider += 1
			var side := -1 if rng.randf() < 0.5 else 1
			spider = Spider.new(side, plan["hp"], plan["power"])
			notify("A spider is approaching from the %s! Gather soldiers at the entrance." % ("left" if side < 0 else "right"), "danger")


func _rebuild_buckets() -> void:
	_buckets.clear()
	var bs := Cfg.CELL * 4.0
	for a in ants:
		if a.state == Cfg.State.DEAD:
			continue
		var key := Vector2i(floori(a.pos.x / bs), floori(a.pos.y / bs))
		if not _buckets.has(key):
			_buckets[key] = []
		_buckets[key].append(a)


func _slow_update() -> void:
	counts = {Cfg.Caste.QUEEN: 0, Cfg.Caste.WORKER: 0, Cfg.Caste.NURSE: 0, Cfg.Caste.SOLDIER: 0}
	digger_count = 0
	for a in ants:
		if a.state == Cfg.State.DEAD:
			continue
		counts[a.caste] += 1
		if a.state == Cfg.State.DIGGING or a.state == Cfg.State.TO_DIG:
			digger_count += 1
	worker_count = counts[Cfg.Caste.WORKER]
	entrance_danger = 0.0
	for x in range(Cfg.ENTRANCE_X - 14, Cfg.ENTRANCE_X + 15):
		entrance_danger = maxf(entrance_danger, pher.get_v(Cfg.Phero.DANGER, Vector2i(x, Cfg.SURFACE_ROW)))


func _step_brood(dt: float) -> void:
	var stage_time: Dictionary = SPECIES["stage_time"]
	var removed: Array[Brood] = []
	for b in brood:
		if b.carrier != null and b.carrier.state == Cfg.State.DEAD:
			b.carrier = null
		if b.carrier != null:
			b.cell = b.carrier.cell
		if b.tender != null and (b.tender.state != Cfg.State.NURSING or b.tender.brood_target != b):
			b.tender = null
		if b.mover != null and (b.mover.state == Cfg.State.DEAD or b.mover.brood_target != b):
			b.mover = null
		if terrain.water_at(b.cell) > 0.4:
			b.hp -= 10.0 * dt
		b.starving = false
		if b.stage == Cfg.Stage.LARVA:
			var def := SpeciesDefs.caste(SPECIES, b.caste)
			var rate: float = maxf(0.0, (def["cost"] - SPECIES["egg_cost"])) / stage_time[Cfg.Stage.LARVA]
			if colony.food > 0.0:
				colony.food = maxf(0.0, colony.food - rate * dt)
			else:
				b.hp -= 1.5 * dt
				b.starving = true
		if b.tender == null:
			b.care = maxf(0.0, b.care - 0.012 * dt)
		var room_mult := 1.25 if terrain.room_at(b.cell) == Cfg.Room.NURSERY else 0.85
		var speed := (0.5 + 0.5 * b.care) * room_mult
		if b.starving:
			speed *= 0.3
		b.progress += dt * speed / stage_time[b.stage]
		if b.hp <= 0.0:
			removed.append(b)
			stats["brood_lost"] += 1
			notify_once("brood_loss", "Brood is dying! Check food, flooding and nurses.", "warn")
		elif b.progress >= 1.0:
			if b.stage == Cfg.Stage.PUPA:
				removed.append(b)
				spawn_ant(b.caste, b.cell)
				stats["born"] += 1
				fx("birth", Cfg.cell_center(b.cell))
			else:
				b.stage += 1
				b.progress = 0.0
	for b in removed:
		brood.erase(b)


func _cleanup() -> void:
	var alive: Array[Ant] = []
	for a in ants:
		if a.state != Cfg.State.DEAD:
			alive.append(a)
	ants = alive
	if spider != null and spider.state == Spider.S.DEAD:
		spider = null


func _check_outcome() -> void:
	if outcome != 0:
		return
	if queen == null or queen.state == Cfg.State.DEAD:
		outcome = 2
		if outcome_reason == "":
			outcome_reason = "The queen is dead."
		return
	var adults := adult_count() - 1
	if colony.starving_t > 120.0:
		outcome = 2
		outcome_reason = "The colony starved: no food for two minutes. Send more workers to the leaf trails."
	elif colony.thirsty_t > 120.0:
		outcome = 2
		outcome_reason = "The colony died of thirst: no water for two minutes."
	elif adults <= 0 and brood.is_empty():
		outcome = 2
		outcome_reason = "Colony collapse: every worker, nurse and soldier is gone."
	elif t >= Cfg.WIN_DAYS * Cfg.DAY_LENGTH:
		if adults >= 10:
			outcome = 1
			outcome_reason = "The colony survived %d days with %d ants and a living queen." % [Cfg.WIN_DAYS, adults + 1]
		else:
			outcome = 2
			outcome_reason = "The queen lives, but fewer than 10 ants survived - the colony is not viable."
	if outcome != 0:
		notify(outcome_reason, "good" if outcome == 1 else "danger")
