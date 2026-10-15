class_name AntBrain
extends RefCounted
## Behaviour of every caste as lightweight state machines. All functions are static and take
## the Simulation; per-ant data lives in Ant. Decisions use pheromone values around the ant,
## path costs (A* with flood weights), colony needs, danger and the carry state.

const S := Cfg.State
const NONE_CELL := Vector2i(-1, -1)


static func update(a: Ant, sim, dt: float) -> void:
	a.prev_pos = a.pos
	a.damage_flash = maxf(0.0, a.damage_flash - dt)
	if a.state == S.DEAD:
		return
	var tr: Terrain = sim.terrain
	var wl := tr.water_at(a.cell)
	if wl > 0.45:
		sim.damage_ant(a, (wl - 0.3) * 9.0 * dt, "drowned")
		if a.state == S.DEAD:
			return
	if sim.colony.starving:
		sim.damage_ant(a, (0.04 if a.caste == Cfg.Caste.QUEEN else 0.1 / a.hardiness) * dt, "starved")
	if sim.colony.thirsty and a.state != S.DEAD:
		sim.damage_ant(a, (0.04 if a.caste == Cfg.Caste.QUEEN else 0.1 / a.hardiness) * dt, "thirst")
	if a.state == S.DEAD:
		return
	a.think_cd -= dt
	if a.think_cd <= 0.0:
		a.think_cd = 0.25 + sim.rng.randf() * 0.15
		_hazards(a, sim)
	var done := _move(a, sim, dt)
	if a.state == S.FLEE:
		if done:
			a.state = S.REST
			a.timer = 6.0 if a.flee_reason == "danger" else 4.0
		return
	if a.caste != Cfg.Caste.SOLDIER and a.state == S.REST:
		a.timer -= dt
		if a.timer <= 0.0:
			a.state = S.IDLE
		return
	match a.caste:
		Cfg.Caste.QUEEN:
			_queen(a, sim, dt, done)
		Cfg.Caste.WORKER:
			_worker(a, sim, dt, done)
		Cfg.Caste.NURSE:
			_nurse(a, sim, dt, done)
		Cfg.Caste.SOLDIER:
			_soldier(a, sim, dt, done)


# --- Movement -------------------------------------------------------------------------------

static func _speed_mod(a: Ant, sim) -> float:
	var m := 1.0
	if sim.terrain.water_at(a.cell) > 0.3:
		m *= 0.55
	if a.load_type != Cfg.Load.NONE:
		m *= 0.88
	if a.state == S.FLEE:
		m *= 1.25
	return m


## Advances along the current path. Returns true when there is no path left to follow.
static func _move(a: Ant, sim, dt: float) -> bool:
	a.moving = false
	if not a.has_path():
		return true
	var next: Vector2i = a.path[a.path_i]
	if not sim.terrain.is_walkable(next):
		a.clear_path()  # route blocked: the state logic re-plans or gives up
		return true
	var target := Cfg.cell_center(next)
	var step_len := a.speed * Cfg.CELL * _speed_mod(a, sim) * dt
	var to := target - a.pos
	var d := to.length()
	a.moving = true
	a.anim += dt * a.speed * 3.0
	if d > 0.001:
		a.move_dir = to / d
		if absf(to.x) > 0.5:
			a.facing = 1 if to.x > 0.0 else -1
	if d <= step_len:
		a.pos = target
		a.cell = next
		a.path_i += 1
		_on_enter_cell(a, sim)
		return not a.has_path()
	a.pos += to / d * step_len
	return false


static func _on_enter_cell(a: Ant, sim) -> void:
	if a.load_type == Cfg.Load.FOOD and a.cell.y == Cfg.SURFACE_ROW and not sim.near_opening(a.cell.x, 4):
		# Returning with food: lay a trail that is strongest near the food. No scent is laid
		# next to the entrance, otherwise every returning ant would build a hotspot there that
		# traps followers.
		var amount := 0.30 * maxf(0.2, 1.0 - float(a.dist_since) / 50.0)
		sim.pher.add(Cfg.Phero.FOOD, a.cell, amount)
		a.dist_since += 1
	elif a.load_type != Cfg.Load.NONE:
		a.dist_since += 1


static func _set_path(a: Ant, p: Array[Vector2i]) -> bool:
	if p.is_empty():
		return false
	a.set_path(p)
	return true


# --- Hazards ---------------------------------------------------------------------------------

static func _hazards(a: Ant, sim) -> void:
	if a.state == S.FLEE or a.state == S.DEAD:
		return
	var tr: Terrain = sim.terrain
	var ph: Pheromones = sim.pher
	var c := a.cell
	var limit := 0.18 if a.caste == Cfg.Caste.QUEEN else 0.3
	if tr.water_at(c) > limit:
		if _flee(a, sim, "water"):
			return
	if ph.get_v(Cfg.Phero.EVACUATE, c) > 0.3:
		if _flee(a, sim, "evac"):
			return
	if a.caste == Cfg.Caste.SOLDIER or a.caste == Cfg.Caste.QUEEN:
		return
	if c.y == Cfg.SURFACE_ROW:
		if sim.weather.rain > 0.3 and a.lost_until < sim.t and sim.rng.randf() < 0.05:
			a.lost_until = sim.t + 20.0 + sim.rng.randf() * 20.0  # rain washes the scent away
		var ahead := Vector2i(c.x + a.heading * 3, c.y)
		var dv := maxf(ph.get_v(Cfg.Phero.DANGER, c), ph.get_v(Cfg.Phero.DANGER, ahead))
		if dv > 0.45:
			_flee(a, sim, "danger")
	elif ph.get_v(Cfg.Phero.DANGER, c) > 0.4:
		_flee(a, sim, "danger")


static func _flee(a: Ant, sim, reason: String) -> bool:
	var tr: Terrain = sim.terrain
	var ph: Pheromones = sim.pher
	var target := NONE_CELL
	match reason:
		"water":
			target = tr.bfs_find(a.cell, func(n: Vector2i) -> bool: return tr.water_at(n) < 0.08, 60)
		"evac":
			target = tr.bfs_find(a.cell, func(n: Vector2i) -> bool: return ph.get_v(Cfg.Phero.EVACUATE, n) < 0.1 and tr.water_at(n) < 0.1, 60)
		"danger":
			if a.cell.y == Cfg.SURFACE_ROW:
				var safe := Vector2i(Cfg.ENTRANCE_X, Cfg.SURFACE + 4)
				if tr.is_walkable(safe) and tr.water_at(safe) < 0.2:
					target = safe
			if target.x < 0:
				target = tr.bfs_find(a.cell, func(n: Vector2i) -> bool: return ph.get_v(Cfg.Phero.DANGER, n) < 0.1 and tr.water_at(n) < 0.1, 60)
	if target.x < 0 or target == a.cell:
		return false
	var p := tr.find_path(a.cell, target)
	if p.is_empty():
		return false
	drop_tasks(a, sim)
	a.set_path(p)
	a.state = S.FLEE
	a.flee_reason = reason
	return true


## Releases whatever the ant was reserving (dig job, brood) when it is interrupted or dies.
static func drop_tasks(a: Ant, sim) -> void:
	if a.job_cell.x >= 0:
		sim.terrain.release_job(a.job_cell)
		a.job_cell = NONE_CELL
	if a.carrying_brood != null:
		a.carrying_brood.carrier = null
		a.carrying_brood.mover = null
		a.carrying_brood = null
	if a.brood_target != null:
		if a.brood_target.tender == a:
			a.brood_target.tender = null
		if a.brood_target.mover == a:
			a.brood_target.mover = null
		a.brood_target = null
	a.target_src = null


# --- Queen -------------------------------------------------------------------------------------

static func _queen(a: Ant, sim, dt: float, _done: bool) -> void:
	if a.state != S.IDLE:
		return
	a.timer -= dt
	if a.timer > 0.0:
		return
	a.timer = 4.0 + sim.rng.randf() * 5.0
	var royal: Array[Vector2i] = sim.room_list(Cfg.Room.ROYAL)
	if royal.is_empty():
		return
	var tgt: Vector2i = royal[sim.rng.randi() % royal.size()]
	if sim.terrain.water_at(tgt) < 0.12:
		_set_path(a, sim.terrain.find_path(a.cell, tgt))


# --- Worker ------------------------------------------------------------------------------------

static func _worker(a: Ant, sim, dt: float, done: bool) -> void:
	match a.state:
		S.IDLE:
			_worker_think(a, sim)
		S.EXPLORE, S.FOLLOW_TRAIL:
			if done:
				_surface_step(a, sim)
		S.TO_RESOURCE:
			var src := a.target_src
			if src == null or not src.available():
				a.target_src = null
				a.clear_path()
				a.state = S.IDLE
			elif done:
				a.state = S.COLLECT
				a.timer = 1.2
				src.discovered = true
		S.COLLECT:
			a.timer -= dt
			if a.timer <= 0.0:
				_finish_collect(a, sim)
		S.CARRY_HOME:
			if done:
				_arrive_home(a, sim)
		S.TO_DIG:
			if done:
				if sim.terrain.dig_jobs.has(a.job_cell):
					a.state = S.DIGGING
					a.timer = 0.0
				else:
					a.job_cell = NONE_CELL
					a.state = S.IDLE
		S.DIGGING:
			_dig_tick(a, sim, dt)
		_:
			a.state = S.IDLE


static func _worker_think(a: Ant, sim) -> void:
	if a.load_type != Cfg.Load.NONE:
		_plan_home(a, sim)
		return
	var tr: Terrain = sim.terrain
	var col: Colony = sim.colony
	var w_dig := 0.0
	if tr.unclaimed_jobs() > 0 and sim.digger_count < maxi(2, int(sim.worker_count * 0.4)):
		w_dig = 0.9
	var w_food := col.food_need()
	var w_water := col.water_need() * 0.9
	if sim.entrance_danger > 0.3:
		w_food = 0.0
		w_water = 0.0  # a predator is near the entrance: stay inside
	var total := w_dig + w_food + w_water
	if total < 0.05:
		a.state = S.REST
		a.timer = 1.5 + sim.rng.randf() * 1.5
		return
	var r: float = sim.rng.randf() * total
	if r < w_dig:
		var job := tr.claim_job(a.id, a.cell)
		if not job.is_empty():
			var p := tr.find_path(a.cell, job[1])
			if not p.is_empty():
				a.job_cell = job[0]
				a.set_path(p)
				a.state = S.TO_DIG
				return
			tr.release_job(job[0])
		a.state = S.REST
		a.timer = 1.0
	elif r < w_dig + w_food:
		_start_forage(a, sim, Cfg.Load.FOOD)
	else:
		_start_forage(a, sim, Cfg.Load.WATER)


static func _start_forage(a: Ant, sim, kind: int) -> void:
	a.want = kind
	if kind == Cfg.Load.FOOD:
		var m := a.mem_food
		if m != null and m.available() and sim.rng.randf() < 0.7:
			_go_to_source(a, sim, m)
			return
	elif a.known_water:
		var s: FoodSource = sim.nearest_source(a.cell, Cfg.SrcKind.WATER)
		if s != null:
			_go_to_source(a, sim, s)
			return
	if a.cell.y == Cfg.SURFACE_ROW:
		a.state = S.EXPLORE
		_surface_step(a, sim)
	else:
		_go_outside(a, sim)


static func _go_to_source(a: Ant, sim, src: FoodSource) -> void:
	var p: Array[Vector2i] = sim.terrain.find_path(a.cell, src.cell)
	if p.is_empty():
		a.state = S.REST
		a.timer = 1.5
		return
	a.target_src = src
	a.set_path(p)
	a.state = S.TO_RESOURCE


static func _go_outside(a: Ant, sim) -> void:
	var best := NONE_CELL
	var best_d := 1 << 30
	for o: Vector2i in sim.terrain.openings():
		var d: int = absi(o.x - a.cell.x) + absi(o.y - a.cell.y)
		if d < best_d:
			best_d = d
			best = Vector2i(o.x, Cfg.SURFACE_ROW)
	if best.x < 0 or not _set_path(a, sim.terrain.find_path(a.cell, best)):
		a.state = S.REST
		a.timer = 2.0
		return
	a.state = S.EXPLORE


## One-cell decision step on the ground line: sight, lost-ant homing, trail following, wandering.
static func _surface_step(a: Ant, sim) -> void:
	var tr: Terrain = sim.terrain
	var ph: Pheromones = sim.pher
	var c := a.cell
	if c.y != Cfg.SURFACE_ROW:
		_go_outside(a, sim)
		return
	var kind := Cfg.SrcKind.FOOD if a.want == Cfg.Load.FOOD else Cfg.SrcKind.WATER
	var src: FoodSource = sim.find_source(c, kind, 5)
	if src != null:
		_go_to_source(a, sim, src)
		return
	if a.lost_until > sim.t:
		_home_gradient_step(a, sim)
		return
	var dir := 0
	if a.want == Cfg.Load.FOOD and a.ignore_trail_until < sim.t:
		var info := {}
		dir = _gradient_dir(a, ph, Cfg.Phero.FOOD, info)
		if dir != 0:
			a.state = S.FOLLOW_TRAIL
		elif info.has("ended"):
			# Reached the end of the trail without finding food: stop trusting it for a while.
			a.ignore_trail_until = sim.t + 12.0
	if dir == 0:
		a.state = S.EXPLORE
		if sim.rng.randf() < 0.12:
			a.heading = -a.heading
		dir = a.heading
	var nx := c.x + dir
	if nx < 0 or nx >= Cfg.W:
		dir = -dir
		nx = c.x + dir
	a.heading = dir
	# Leave a faint scent pointing back to the nest.
	ph.set_max(Cfg.Phero.HOME, c, clampf(1.0 - absf(float(c.x - Cfg.ENTRANCE_X)) / 80.0, 0.12, 0.8))
	var p: Array[Vector2i] = [c, Vector2i(nx, c.y)]
	a.set_path(p)


## Direction (-1/+1) of a pheromone gradient along the ground line, or 0 when there is none.
## Climbs uphill, keeps its heading on plateaus and only turns when it is walking downhill.
## Sets info["ended"] when the ant has walked off the end of the trail.
static func _gradient_dir(a: Ant, ph: Pheromones, type: int, info: Dictionary) -> int:
	var c := a.cell
	var sl := ph.line_score(type, c, -1, 6)
	var sr := ph.line_score(type, c, 1, 6)
	if maxf(sl, sr) <= 0.06:
		return 0
	var cur := ph.get_v(type, c)
	var vf := ph.get_v(type, Vector2i(c.x + a.heading, c.y))
	var vb := ph.get_v(type, Vector2i(c.x - a.heading, c.y))
	var ahead := sr if a.heading == 1 else sl
	var behind := sl if a.heading == 1 else sr
	if cur < 0.08:
		return a.heading if ahead >= behind else -a.heading  # off the trail: toward the scent
	if vf > cur + 0.004:
		return a.heading
	if vb > cur + 0.004:
		return -a.heading
	if ahead >= 0.06:
		return a.heading
	info["ended"] = true
	return 0


static func _home_gradient_step(a: Ant, sim) -> void:
	var tr: Terrain = sim.terrain
	var c := a.cell
	var p: Array[Vector2i] = []
	var below := Vector2i(c.x, c.y + 1)
	if tr.is_walkable(below) and tr.type_at(below) == Cfg.Cell.TUNNEL:
		# Standing over a nest opening: the way home is straight down.
		p = [c, below]
		a.lost_until = 0.0
		a.set_path(p)
		return
	var dir := _gradient_dir(a, sim.pher, Cfg.Phero.HOME, {})
	if dir == 0:
		if sim.rng.randf() < 0.1:
			a.heading = -a.heading
		dir = a.heading
	var nx := c.x + dir
	if nx < 0 or nx >= Cfg.W:
		dir = -dir
		nx = c.x + dir
	a.heading = dir
	p = [c, Vector2i(nx, c.y)]
	a.set_path(p)


static func _finish_collect(a: Ant, sim) -> void:
	var src := a.target_src
	a.target_src = null
	if src == null or not src.available():
		a.state = S.IDLE
		return
	var took := src.take(a.carry_capacity)
	if src.kind == Cfg.SrcKind.FOOD:
		a.load_type = Cfg.Load.FOOD
		a.mem_food = src
	else:
		a.load_type = Cfg.Load.WATER
		a.known_water = true
	a.load_amount = took
	a.dist_since = 0
	_plan_home(a, sim)


static func _plan_home(a: Ant, sim) -> void:
	if a.cell.y == Cfg.SURFACE_ROW and a.lost_until > sim.t:
		a.state = S.CARRY_HOME
		_home_gradient_step(a, sim)
		return
	var tr: Terrain = sim.terrain
	var p := tr.find_path(a.cell, sim.deposit_cell())
	if p.is_empty():
		p = tr.find_path(a.cell, Vector2i(Cfg.ENTRANCE_X, Cfg.SURFACE + 4))
	if p.is_empty():
		a.state = S.REST
		a.timer = 2.0
		return
	a.set_path(p)
	a.state = S.CARRY_HOME


static func _arrive_home(a: Ant, sim) -> void:
	if a.cell.y < Cfg.SURFACE:
		_plan_home(a, sim)
		return
	var amount := a.load_amount
	var kind := a.load_type
	var accepted := 0.0
	if kind == Cfg.Load.FOOD:
		accepted = sim.colony.add_food(amount)
	else:
		accepted = sim.colony.add_water(amount)
	if accepted < amount - 0.01:
		sim.notify_once("storage_full", "Storage is full - build more food storage chambers.", "warn")
	a.load_type = Cfg.Load.NONE
	a.load_amount = 0.0
	a.state = S.IDLE
	sim.stats["deliveries"] += 1
	sim.fx("deliver", a.pos)
	# Ants nearby learn where the resource is (food-sharing in the nest).
	for o: Ant in sim.ants_near(a.pos, Cfg.CELL * 3.0):
		if o != a and o.caste == Cfg.Caste.WORKER:
			if kind == Cfg.Load.WATER:
				o.known_water = true
			elif a.mem_food != null and o.mem_food == null and sim.rng.randf() < 0.4:
				o.mem_food = a.mem_food


static func _dig_tick(a: Ant, sim, dt: float) -> void:
	var tr: Terrain = sim.terrain
	if not tr.dig_jobs.has(a.job_cell):
		a.job_cell = NONE_CELL
		a.state = S.IDLE
		return
	var job: Dictionary = tr.dig_jobs[a.job_cell]
	job["progress"] += dt
	a.timer -= dt
	if a.timer <= 0.0:
		a.timer = 0.45
		sim.fx("dust", Cfg.cell_center(a.job_cell))
	if job["progress"] >= tr.hardness(a.job_cell.y):
		var done_cell := a.job_cell
		a.job_cell = NONE_CELL
		a.state = S.IDLE
		sim.complete_dig(done_cell)


# --- Nurse -------------------------------------------------------------------------------------

static func _nurse(a: Ant, sim, dt: float, done: bool) -> void:
	var tr: Terrain = sim.terrain
	match a.state:
		S.IDLE:
			_nurse_think(a, sim)
		S.MOVE_BROOD:
			var b := a.brood_target
			if b == null or b.hp <= 0.0 or not sim.brood.has(b):
				drop_tasks(a, sim)
				a.state = S.IDLE
				return
			if a.carrying_brood == null:
				if done:
					if a.cell == b.cell and b.carrier == null:
						var dest: Vector2i = sim.free_nursery_cell()
						var p := tr.find_path(a.cell, dest) if dest.x >= 0 else ([] as Array[Vector2i])
						if p.is_empty():
							drop_tasks(a, sim)
							a.state = S.IDLE
							return
						a.carrying_brood = b
						b.carrier = a
						a.set_path(p)
					else:
						_set_path(a, tr.find_path(a.cell, b.cell))
						if not a.has_path():
							drop_tasks(a, sim)
							a.state = S.IDLE
			else:
				b.cell = a.cell
				if done:
					b.carrier = null
					b.mover = null
					a.carrying_brood = null
					a.brood_target = null
					a.state = S.IDLE
		S.NURSING:
			var b2 := a.brood_target
			if b2 == null or b2.hp <= 0.0 or not sim.brood.has(b2):
				drop_tasks(a, sim)
				a.state = S.IDLE
				return
			if a.cell != b2.cell:
				if done:
					_set_path(a, tr.find_path(a.cell, b2.cell))
					if not a.has_path():
						drop_tasks(a, sim)
						a.state = S.IDLE
			else:
				b2.care = minf(1.0, b2.care + 0.16 * dt)
				if b2.care >= 0.98:
					drop_tasks(a, sim)
					a.state = S.IDLE
		_:
			a.state = S.IDLE


static func _nurse_think(a: Ant, sim) -> void:
	var tr: Terrain = sim.terrain
	var dest: Vector2i = sim.free_nursery_cell()
	var best: Brood = null
	var best_d := 1 << 30
	if dest.x >= 0:
		for b: Brood in sim.brood:
			if b.carrier == null and b.mover == null and tr.room_at(b.cell) != Cfg.Room.NURSERY:
				var d: int = absi(b.cell.x - a.cell.x) + absi(b.cell.y - a.cell.y)
				if d < best_d:
					best_d = d
					best = b
		if best != null:
			var p := tr.find_path(a.cell, best.cell)
			if not p.is_empty():
				best.mover = a
				a.brood_target = best
				a.set_path(p)
				a.state = S.MOVE_BROOD
				return
	best = null
	best_d = 1 << 30
	for b: Brood in sim.brood:
		if b.tender == null and b.carrier == null and b.care < 0.8:
			var d2: int = absi(b.cell.x - a.cell.x) + absi(b.cell.y - a.cell.y)
			if d2 < best_d:
				best_d = d2
				best = b
	if best != null:
		var p2 := tr.find_path(a.cell, best.cell)
		if not p2.is_empty():
			best.tender = a
			a.brood_target = best
			a.set_path(p2)
			a.state = S.NURSING
			return
	# Nothing urgent: linger near the nursery.
	var spots: Array[Vector2i] = sim.room_list(Cfg.Room.NURSERY)
	if not spots.is_empty() and sim.rng.randf() < 0.6:
		var s: Vector2i = spots[sim.rng.randi() % spots.size()]
		_set_path(a, tr.find_path(a.cell, s))
	a.state = S.REST
	a.timer = 3.0 + sim.rng.randf() * 4.0


# --- Soldier -----------------------------------------------------------------------------------

static func _soldier(a: Ant, sim, dt: float, done: bool) -> void:
	var sp: Spider = sim.spider
	if sp != null and sp.state != Spider.S.DEAD:
		var dist_cells := a.pos.distance_to(sp.pos) / Cfg.CELL
		var reach := 40.0 if sp.invading else 8.0
		if dist_cells <= reach:
			_engage(a, sim, sp, dt, done)
			return
	match a.state:
		S.ATTACK:
			if done:
				a.state = S.GUARD
				a.timer = 3.0
		S.IDLE:
			_soldier_think(a, sim)
		S.GUARD, S.REST:
			a.timer -= dt
			if a.timer <= 0.0:
				a.state = S.IDLE
		_:
			a.state = S.IDLE


static func _engage(a: Ant, sim, sp: Spider, dt: float, done: bool) -> void:
	if a.state != S.ATTACK:
		drop_tasks(a, sim)
		a.state = S.ATTACK
	var d := a.pos.distance_to(sp.pos)
	if d <= Cfg.CELL * 1.8:
		a.clear_path()
		a.facing = 1 if sp.pos.x >= a.pos.x else -1
		a.attack_cd -= dt
		if a.attack_cd <= 0.0:
			a.attack_cd = 0.9
			sp.take_damage(a.damage, sim)
			sim.fx("hit", sp.pos)
	else:
		a.repath_cd -= dt
		if a.repath_cd <= 0.0 or done:
			a.repath_cd = 0.5
			var p: Array[Vector2i] = sim.terrain.find_path(a.cell, sp.cell)
			if not p.is_empty():
				a.set_path(p)


static func _soldier_think(a: Ant, sim) -> void:
	var tgt: Vector2i = sim.pher.strongest_near(Cfg.Phero.ATTACK, a.cell, 45, 0.3)
	if tgt.x >= 0 and absi(tgt.x - a.cell.x) + absi(tgt.y - a.cell.y) > 2:
		if _set_path(a, sim.terrain.find_path(a.cell, tgt)):
			a.state = S.ATTACK  # responding to an attack signal
			return
	# Guard post around the entrance.
	var post := Vector2i(Cfg.ENTRANCE_X + sim.rng.randi_range(-5, 5), Cfg.SURFACE_ROW)
	if sim.rng.randf() < 0.3:
		post = Vector2i(Cfg.ENTRANCE_X, Cfg.SURFACE + sim.rng.randi_range(1, 3))
	_set_path(a, sim.terrain.find_path(a.cell, post))
	a.state = S.GUARD
	a.timer = 4.0 + sim.rng.randf() * 5.0
