class_name AntSystem
extends RefCounted
## Todas las hormigas como arrays de datos (ningún nodo por hormiga). Cada hormiga decide cada
## 3-5 ticks (desfasadas entre sí); el movimiento se aplica en cada tick y el render lo interpola.
##
## Fase 1: se añadió `caste` (Reina, Obrera, Nodriza, Soldado). La Obrera se comporta exactamente
## igual que en la Fase 0 (sus multiplicadores en `CasteDefs` son 1.0) para no romper esa
## regresión. La Reina no decide ni se mueve (vive en la cámara Real); Nodriza y Soldado tienen
## su propio `_think_*`. Los estados nuevos (FLEE_DANGER, EVACUATE, NURSE, GUARD, ATTACK) son
## aditivos: si nada pinta esas feromonas (como en la Fase 0) nunca se activan.

enum State { EXPLORE, GO_TO_FOOD, CARRY_HOME, DIG, FLEE_WATER, IDLE, FLEE_DANGER, EVACUATE, NURSE, GUARD, ATTACK }
enum Mode { EXPLORE, FOOD, NEST, DIG, FLEE, PLANT, TOWARD, AWAY }

const STATE_COLORS: Array[Color] = [
	Color("e6d84a"),  # EXPLORE
	Color("5fe05f"),  # GO_TO_FOOD
	Color("ff9a3c"),  # CARRY_HOME
	Color("c06bff"),  # DIG
	Color("ff4a4a"),  # FLEE_WATER
	Color("7fb6ff"),  # IDLE
	Color("ff2fb0"),  # FLEE_DANGER
	Color("ffffff"),  # EVACUATE
	Color("4fd4e0"),  # NURSE
	Color("ff8040"),  # GUARD
	Color("ff0000"),  # ATTACK
]
const STATE_NAMES: Array[String] = ["EXPLORAR", "IR A COMIDA", "LLEVAR A CASA", "CAVAR", "HUIR DEL AGUA", "DESCANSO",
	"HUIR DEL PELIGRO", "EVACUAR", "CUIDAR CRÍA", "GUARDIA", "ATACAR"]
const DX: Array[int] = [1, 1, 0, -1, -1, -1, 0, 1]
const DY: Array[int] = [0, 1, 1, 1, 0, -1, -1, -1]
const FAR := NestDistanceField.FAR

var sim: Simulation
var count := 0
var alive_count := 0
var state_counts: Array[int] = []

var pos := PackedVector2Array()
var prev := PackedVector2Array()
var heading := PackedVector2Array()
var target := PackedVector2Array()
var last_check := PackedVector2Array()
var state := PackedInt32Array()
var caste := PackedInt32Array()
var next_think := PackedInt32Array()
var last_think := PackedInt32Array()
var trip_steps := PackedInt32Array()
var job := PackedInt32Array()
var last_cell := PackedInt32Array()
var ignore_until := PackedInt32Array()
var alive := PackedByteArray()
var carry := PackedByteArray()
var hp := PackedFloat32Array()
var timer := PackedFloat32Array()
var stuck_t := PackedFloat32Array()
var check_acc := PackedFloat32Array()

var max_stuck_seen := 0.0
var _bfs_q := PackedInt32Array()
var _bfs_seen := PackedInt32Array()
var _bfs_parent := PackedInt32Array()
var _bfs_stamp := 0
var _dirs: Array[Vector2] = []


func _init(s: Simulation) -> void:
	sim = s
	for k in 8:
		_dirs.append(Vector2(DX[k], DY[k]).normalized())
	state_counts.resize(State.size())


func _grow(n: int) -> void:
	var total := count + n
	pos.resize(total)
	prev.resize(total)
	heading.resize(total)
	target.resize(total)
	last_check.resize(total)
	state.resize(total)
	caste.resize(total)
	next_think.resize(total)
	last_think.resize(total)
	trip_steps.resize(total)
	job.resize(total)
	last_cell.resize(total)
	ignore_until.resize(total)
	alive.resize(total)
	carry.resize(total)
	hp.resize(total)
	timer.resize(total)
	stuck_t.resize(total)
	check_acc.resize(total)


func add_ants(n: int) -> void:
	var nest := sim.world.nest_cells
	for k in n:
		var c: int = nest[sim.rng.randi() % nest.size()]
		add_ant_at(Vector2i(c % sim.world.w, c / sim.world.w))


## Crea una hormiga en el centro de la celda dada (con un pequeño desfase aleatorio).
func add_ant_at(cell: Vector2i, ant_caste: int = CasteDefs.Caste.WORKER) -> int:
	_grow(1)
	var cfg := sim.cfg
	var i := count
	var p := _center(cell.x, cell.y) + Vector2(sim.rng.randf_range(-2.5, 2.5), sim.rng.randf_range(-2.0, 2.0))
	pos[i] = p
	prev[i] = p
	target[i] = p
	last_check[i] = p
	var a := sim.rng.randf() * TAU
	heading[i] = Vector2(cos(a), sin(a))
	state[i] = State.IDLE
	caste[i] = ant_caste
	next_think[i] = sim.tick_count + sim.rng.randi_range(0, cfg.think_ticks_max)
	last_think[i] = sim.tick_count
	trip_steps[i] = 0
	job[i] = -1
	last_cell[i] = _cell_index(p)
	ignore_until[i] = 0
	alive[i] = 1
	carry[i] = 0
	hp[i] = (cfg.queen_hp_base if ant_caste == CasteDefs.Caste.QUEEN else cfg.ant_hp) * CasteDefs.HP_MULT[ant_caste]
	timer[i] = sim.rng.randf_range(0.0, cfg.rest_seconds_max)
	stuck_t[i] = 0.0
	check_acc[i] = sim.rng.randf() * 0.5
	count += 1
	alive_count += 1
	return i


func _cell_index(p: Vector2) -> int:
	var cpx := float(sim.cfg.cell_px)
	var x := clampi(floori(p.x / cpx), 0, sim.world.w - 1)
	var y := clampi(floori(p.y / cpx), 0, sim.world.h - 1)
	return y * sim.world.w + x


func _center(x: int, y: int) -> Vector2:
	var cpx := float(sim.cfg.cell_px)
	return Vector2((x + 0.5) * cpx, (y + 0.5) * cpx)


# --- Tick -------------------------------------------------------------------------------------

func tick() -> void:
	var cfg := sim.cfg
	var dt := sim.dt
	var w := sim.world.w
	var cpx := float(cfg.cell_px)
	var lvl := sim.water.level
	var now := sim.tick_count
	for i in count:
		if alive[i] == 0:
			continue
		prev[i] = pos[i]
		var p := pos[i]
		var cx := clampi(floori(p.x / cpx), 0, w - 1)
		var cy := clampi(floori(p.y / cpx), 0, sim.world.h - 1)
		var ci := cy * w + cx
		var lv := lvl[ci]
		# Fase 3: en el modo incremental la reina no se ahoga (la colonia es demasiado chica al
		# principio para defenderse de una inundación); el resto de castas, sí.
		if lv > cfg.deep_level and not (sim.incremental and caste[i] == CasteDefs.Caste.QUEEN):
			hp[i] -= cfg.drown_damage_per_s * dt
			if hp[i] <= 0.0:
				_kill(i, true)
				continue
		if caste[i] == CasteDefs.Caste.QUEEN:
			# La reina no decide sola (sin EXPLORE/FOOD/etc.): solo camina cuando el jugador la
			# manda con `cmd_move_queen` (ver `_think_queen`), y se queda quieta el resto del
			# tiempo, igual que siempre.
			if sim.queen_goal_cell >= 0:
				_think_queen(i, cx, cy, ci)
				_move(i, dt, lv)
			continue
		if state[i] == State.DIG and job[i] >= 0:
			_dig_progress(i, dt)
		if now >= next_think[i]:
			_think(i, cx, cy, ci)
		_move(i, dt, lv)
		check_acc[i] += dt
		if check_acc[i] >= 0.5:
			_stuck_check(i, ci)
	if now % 10 == 0:
		_recount()


func _recount() -> void:
	for k in state_counts.size():
		state_counts[k] = 0
	for i in count:
		if alive[i] == 1:
			state_counts[state[i]] += 1


func _kill(i: int, drowned: bool) -> void:
	_release_job(i)
	alive[i] = 0
	alive_count -= 1
	if drowned:
		sim.deaths += 1
	carry[i] = 0


func _release_job(i: int) -> void:
	var j := job[i]
	if j >= 0:
		if sim.world.cells[j] == WorldGrid.Cell.MARKED:
			sim.world.job_claim[j] = -1
			sim.world.jobs_version += 1
		job[i] = -1


func _dig_progress(i: int, dt: float) -> void:
	var world := sim.world
	var j := job[i]
	if world.cells[j] != WorldGrid.Cell.MARKED:
		job[i] = -1
		state[i] = State.IDLE
		timer[i] = 0.0
		return
	world.job_progress[j] += dt
	if world.job_progress[j] >= sim.cfg.dig_seconds:
		var jx := j % world.w
		var jy := j / world.w
		var c := _cell_index(pos[i])
		if absi(c % world.w - jx) + absi(c / world.w - jy) != 1:
			sim.dig_violations += 1  # cavó sin estar al lado (no debería ocurrir)
		world.complete_dig(j)
		sim.dug += 1
		job[i] = -1
		state[i] = State.IDLE
		timer[i] = 0.0


func _move(i: int, dt: float, lv: float) -> void:
	var to := target[i] - pos[i]
	var d := to.length()
	if d < 0.01:
		return
	var cfg := sim.cfg
	var mult := CasteDefs.SPEED_MULT[caste[i]]
	if carry[i] == 1:
		mult *= cfg.carry_speed_mult
	if lv > 0.0:
		mult *= 1.0 - (1.0 - cfg.water_speed_mult) * minf(lv * 2.0, 1.0)
	var step := cfg.ant_speed * cfg.cell_px * dt * mult
	if d <= step:
		pos[i] = target[i]
	else:
		pos[i] += to / d * step
	var nc := _cell_index(pos[i])
	if nc != last_cell[i]:
		last_cell[i] = nc
		_on_enter(i, nc)


func _on_enter(i: int, ci: int) -> void:
	var cfg := sim.cfg
	trip_steps[i] += 1
	if carry[i] == 1:
		if trip_steps[i] < cfg.food_trail_range:
			sim.food.deposit(ci, cfg.food_deposit * (1.0 - float(trip_steps[i]) / cfg.food_trail_range))
		if state[i] == State.CARRY_HOME and sim.fields.nest_dist[ci] == 0:
			_deliver(i)
	elif state[i] == State.EXPLORE or state[i] == State.GO_TO_FOOD:
		var nd := sim.fields.nest_dist[ci]
		if nd < cfg.home_range:
			sim.home.deposit(ci, cfg.home_deposit * (1.0 - float(nd) / cfg.home_range))


func _deliver(i: int) -> void:
	sim.leaves_stored += 1
	sim.delivered += 1
	carry[i] = 0
	state[i] = State.IDLE
	trip_steps[i] = 0
	timer[i] = sim.rng.randf_range(sim.cfg.rest_seconds_min, sim.cfg.rest_seconds_max)
	target[i] = pos[i]


# --- Decisiones -----------------------------------------------------------------------------------

func _think(i: int, cx: int, cy: int, ci: int) -> void:
	var cfg := sim.cfg
	var now := sim.tick_count
	var think_dt := float(now - last_think[i]) * sim.dt
	last_think[i] = now
	next_think[i] = now + sim.rng.randi_range(cfg.think_ticks_min, cfg.think_ticks_max)
	var lv := sim.water.level[ci]
	if lv > cfg.flee_level and state[i] != State.FLEE_WATER:
		_release_job(i)
		state[i] = State.FLEE_WATER
	# Peligro y evacuación (Fase 1): el soldado no les teme. Estas condiciones nunca se cumplen
	# si nada pintó esas feromonas (como en toda la Fase 0), así que no cambian ese comportamiento.
	if caste[i] != CasteDefs.Caste.SOLDIER and state[i] != State.FLEE_WATER:
		if sim.danger.get_v(cx, cy) > cfg.danger_flee_threshold and state[i] != State.FLEE_DANGER:
			_release_job(i)
			state[i] = State.FLEE_DANGER
		elif sim.evacuate.get_v(cx, cy) > cfg.evacuate_threshold and state[i] != State.EVACUATE:
			_release_job(i)
			state[i] = State.EVACUATE
	if caste[i] == CasteDefs.Caste.NURSE and state[i] != State.FLEE_WATER:
		_think_nurse(i, cx, cy, ci)
		return
	if caste[i] == CasteDefs.Caste.SOLDIER and state[i] != State.FLEE_WATER:
		_think_soldier(i, cx, cy, ci, think_dt)
		return
	match state[i]:
		State.FLEE_WATER:
			if lv < cfg.safe_level:
				state[i] = State.CARRY_HOME if carry[i] == 1 else State.IDLE
				timer[i] = 0.5
				target[i] = pos[i]
			elif not _flee_bfs(cx, cy, ci, i):
				_step(i, cx, cy, ci, Mode.FLEE, null)
		State.FLEE_DANGER:
			if sim.danger.get_v(cx, cy) <= cfg.danger_flee_threshold * 0.4:
				state[i] = State.IDLE
				timer[i] = 0.5
				target[i] = pos[i]
			else:
				_step(i, cx, cy, ci, Mode.AWAY, sim.danger)
		State.EVACUATE:
			if sim.evacuate.get_v(cx, cy) <= 0.02:
				state[i] = State.IDLE
				timer[i] = 0.5
				target[i] = pos[i]
			else:
				_step(i, cx, cy, ci, Mode.AWAY, sim.evacuate)
		State.IDLE:
			_think_idle(i, cx, cy, ci, think_dt)
		State.EXPLORE:
			_think_explore(i, cx, cy, ci)
		State.GO_TO_FOOD:
			_think_food(i, cx, cy, ci)
		State.CARRY_HOME:
			if sim.fields.nest_dist[ci] == 0:
				_deliver(i)
			else:
				_step(i, cx, cy, ci, Mode.NEST, null)
		State.DIG:
			_think_dig(i, cx, cy, ci)


func _think_idle(i: int, cx: int, cy: int, ci: int, think_dt: float) -> void:
	var cfg := sim.cfg
	timer[i] -= think_dt
	var nd := sim.fields.nest_dist[ci]
	if nd > 1 and nd < FAR:
		_step(i, cx, cy, ci, Mode.NEST, null)  # volver al nido a descansar
	else:
		target[i] = pos[i]
	if timer[i] > 0.0:
		return
	if nd > 2 and nd < FAR:
		return
	# Elegir trabajo.
	var diggers := state_counts[State.DIG]
	var max_diggers := maxi(2, int(alive_count * cfg.max_diggers_fraction))
	if sim.world.marked_count > 0 and diggers < mini(sim.world.marked_count, max_diggers) and sim.fields.dig_dist[ci] < FAR:
		state[i] = State.DIG
		state_counts[State.DIG] += 1
	elif sim.total_leaves_left > 0:
		state[i] = State.EXPLORE
	else:
		timer[i] = 4.0  # sin trabajo: seguir descansando


func _plant_near(i: int) -> Plant:
	var cfg := sim.cfg
	var best: Plant = null
	var best_d := cfg.sight_cells * cfg.cell_px
	var p := pos[i]
	for pl in sim.plants:
		if pl.leaves <= 0:
			continue
		var d := p.distance_to(_center(pl.cell.x, pl.cell.y))
		if d < best_d:
			best_d = d
			best = pl
	return best


## Intenta recoger una hoja o acercarse a una planta visible. Devuelve true si decidió algo.
func _plant_logic(i: int, cx: int, cy: int, ci: int) -> bool:
	var cfg := sim.cfg
	var pl := _plant_near(i)
	if pl == null:
		return false
	var pc := _center(pl.cell.x, pl.cell.y)
	if pos[i].distance_to(pc) <= cfg.pickup_cells * cfg.cell_px:
		pl.leaves -= 1
		sim.total_leaves_left -= 1
		if sim.incremental:
			sim.econ.known_plants[sim.plants.find(pl)] = 1
		carry[i] = 1
		trip_steps[i] = 0
		state[i] = State.CARRY_HOME
		_step(i, cx, cy, ci, Mode.NEST, null)
		return true
	state[i] = State.GO_TO_FOOD
	_step(i, cx, cy, ci, Mode.PLANT, pc)
	return true


## Fase 3 (solo modo incremental): la colonia recuerda las plantas de las que ya sacó hojas y las
## obreras que están en la superficie van directo a la conocida más cercana que tenga hojas. Con
## 3-10 obreras los rastros de feromona no se refrescan lo bastante y se desgastan por la punta de
## la planta (las obreras quedaban dando vueltas junto al nido); con 100 hormigas, como en las
## Fases 0-2, no hacía falta. Si ninguna conocida tiene hojas, se explora como siempre.
func _remembered_plant(i: int, cx: int, cy: int, ci: int) -> bool:
	if not sim.incremental or cy >= sim.cfg.surface_y:
		return false
	var known := sim.econ.known_plants
	var best: Plant = null
	var best_d := INF
	for k in sim.plants.size():
		var pl := sim.plants[k]
		if known[k] == 0 or pl.leaves <= 0:
			continue
		var d := absf(pos[i].x - _center(pl.cell.x, pl.cell.y).x)
		if d < best_d:
			best_d = d
			best = pl
	if best == null:
		return false
	state[i] = State.GO_TO_FOOD
	_step(i, cx, cy, ci, Mode.PLANT, _center(best.cell.x, best.cell.y))
	return true


func _food_here_max(cx: int, cy: int, ci: int) -> float:
	var m := sim.food.data[ci]
	for k in 8:
		m = maxf(m, sim.food.get_v(cx + DX[k], cy + DY[k]))
	return m


func _think_explore(i: int, cx: int, cy: int, ci: int) -> void:
	var cfg := sim.cfg
	if _plant_logic(i, cx, cy, ci) or _remembered_plant(i, cx, cy, ci):
		return
	if sim.total_leaves_left <= 0 and sim.world.marked_count == 0:
		state[i] = State.IDLE
		timer[i] = 3.0
		return
	if sim.tick_count >= ignore_until[i] and _food_here_max(cx, cy, ci) > cfg.food_follow_threshold:
		state[i] = State.GO_TO_FOOD
		_step(i, cx, cy, ci, Mode.FOOD, null)
		return
	_step(i, cx, cy, ci, Mode.EXPLORE, null)


func _think_food(i: int, cx: int, cy: int, ci: int) -> void:
	var cfg := sim.cfg
	if _plant_logic(i, cx, cy, ci) or _remembered_plant(i, cx, cy, ci):
		return
	var here := sim.food.data[ci]
	var best := 0.0
	for k in 8:
		best = maxf(best, sim.food.get_v(cx + DX[k], cy + DY[k]))
	if sim.tick_count < ignore_until[i] or maxf(here, best) < cfg.food_follow_threshold:
		state[i] = State.EXPLORE
		_step(i, cx, cy, ci, Mode.EXPLORE, null)
	elif here >= best + 0.002:
		# Fin del rastro sin comida a la vista: la hormiga borra la punta (la feromona de un
		# rastro agotado se va comiendo desde el final) y deja de fiarse de él un rato.
		sim.food.data[ci] = 0.0
		ignore_until[i] = sim.tick_count + int(cfg.ignore_trail_seconds * cfg.tick_rate)
		state[i] = State.EXPLORE
		_step(i, cx, cy, ci, Mode.EXPLORE, null)
	else:
		_step(i, cx, cy, ci, Mode.FOOD, null)


func _think_dig(i: int, cx: int, cy: int, ci: int) -> void:
	var world := sim.world
	if job[i] >= 0:
		target[i] = pos[i]
		return
	var dd := sim.fields.dig_dist[ci]
	if dd >= FAR:
		state[i] = State.IDLE
		timer[i] = 1.0
		return
	if dd == 0:
		for k in [2, 6, 0, 4]:  # abajo, arriba, derecha, izquierda
			var nx: int = cx + DX[k]
			var ny: int = cy + DY[k]
			if world.in_bounds(nx, ny):
				var ni: int = ny * world.w + nx
				if world.cells[ni] == WorldGrid.Cell.MARKED and world.job_claim[ni] == -1:
					world.job_claim[ni] = i
					world.jobs_version += 1
					job[i] = ni
					target[i] = pos[i]
					return
		state[i] = State.IDLE  # otra hormiga se adelantó
		timer[i] = 0.0
		return
	_step(i, cx, cy, ci, Mode.DIG, null)


# --- Nodrizas y soldados (Fase 1) --------------------------------------------------------------

func _think_nurse(i: int, cx: int, cy: int, ci: int) -> void:
	var cfg := sim.cfg
	var nd := sim.fields.nest_dist[ci]
	if nd > cfg.nurse_range and nd < FAR:
		state[i] = State.NURSE
		_step(i, cx, cy, ci, Mode.NEST, null)
	else:
		state[i] = State.NURSE
		target[i] = pos[i]  # se queda cuidando la cría cerca del nido


func _think_soldier(i: int, cx: int, cy: int, ci: int, think_dt: float) -> void:
	var cfg := sim.cfg
	var sim_spider := sim.spider
	if sim_spider != null and sim_spider.alive:
		var d := pos[i].distance_to(sim_spider.pos)
		if d <= cfg.soldier_melee_range_px:
			state[i] = State.ATTACK
			target[i] = pos[i]
			sim_spider.take_damage(CasteDefs.DAMAGE_PER_S[CasteDefs.Caste.SOLDIER] * think_dt)
			return
		if d <= cfg.soldier_sight_px:
			state[i] = State.ATTACK
			_step(i, cx, cy, ci, Mode.PLANT, sim_spider.pos)
			return
	var here := sim.attack.data[ci]
	var best := here
	for k in 8:
		best = maxf(best, sim.attack.get_v(cx + DX[k], cy + DY[k]))
	if best > 0.02:
		state[i] = State.ATTACK
		_step(i, cx, cy, ci, Mode.TOWARD, sim.attack)
		return
	state[i] = State.GUARD
	var nd := sim.fields.nest_dist[ci]
	if nd > 2 and nd < FAR:
		_step(i, cx, cy, ci, Mode.NEST, null)
	else:
		target[i] = pos[i]


## Elige la mejor celda vecina según el modo y fija el objetivo de movimiento.
func _step(i: int, cx: int, cy: int, ci: int, mode: int, extra: Variant) -> void:
	var cfg := sim.cfg
	var world := sim.world
	var f := sim.fields
	var rng := sim.rng
	var w := world.w
	var best_k := -1
	var best_s := -1.0e9
	var head := heading[i]
	var on_surface := cy < cfg.surface_y
	var plant_pos := Vector2.ZERO
	var field: PheromoneField = null
	if mode == Mode.PLANT:
		plant_pos = extra
	elif mode == Mode.TOWARD or mode == Mode.AWAY:
		field = extra
	for k in 8:
		var nx := cx + DX[k]
		var ny := cy + DY[k]
		if not world.is_passable(nx, ny):
			continue
		if DX[k] != 0 and DY[k] != 0:
			if not world.is_passable(cx + DX[k], cy) or not world.is_passable(cx, cy + DY[k]):
				continue  # nada de cortar esquinas de tierra
		var ni := ny * w + nx
		var lw := sim.water.level[ni]
		if mode != Mode.FLEE and lw >= cfg.flee_level:
			continue  # solo se cruza agua huyendo; el resto espera a que baje
		var s := 0.0
		match mode:
			Mode.EXPLORE:
				s = cfg.w_persist * head.dot(_dirs[k]) + cfg.w_noise * rng.randf()
				s += cfg.w_food * sim.food.data[ni]
				s -= cfg.w_home_repel * sim.home.data[ni]
				if not on_surface:
					s += cfg.w_outward * float(f.surface_dist[ci] - f.surface_dist[ni])
				elif ny >= cfg.surface_y:
					s -= 2.0  # no meterse al nido por azar
				s -= 3.0 * lw
			Mode.FOOD:
				s = cfg.w_food * (sim.food.data[ni] - sim.food.data[ci]) * 10.0
				s += cfg.w_persist * head.dot(_dirs[k]) + 0.3 * rng.randf()
				if on_surface and ny >= cfg.surface_y:
					s -= 2.0
				s -= 3.0 * lw
			Mode.NEST:
				var nd := f.nest_dist[ni]
				if nd >= FAR:
					continue
				s = float(f.nest_dist[ci] - nd) * 2.0 + 0.2 * rng.randf() - 2.0 * lw
			Mode.DIG:
				var dd := f.dig_dist[ni]
				if dd >= FAR:
					continue
				s = float(f.dig_dist[ci] - dd) * 2.0 + 0.2 * rng.randf() - 2.0 * lw
			Mode.FLEE:
				s = -10.0 * lw + 0.6 * float(cy - ny) + 0.2 * rng.randf()
			Mode.PLANT:
				s = -_center(nx, ny).distance_to(plant_pos) / cfg.cell_px + 0.1 * rng.randf()
				if on_surface and ny >= cfg.surface_y:
					s -= 2.0
			Mode.TOWARD:
				s = (field.get_v(nx, ny) - field.get_v(cx, cy)) * 10.0
				s += cfg.w_persist * 0.3 * head.dot(_dirs[k]) + 0.2 * rng.randf()
				s -= 3.0 * lw
			Mode.AWAY:
				s = -field.get_v(nx, ny) * 10.0 + 0.2 * rng.randf()
				if not on_surface:
					s += 0.5 * float(f.surface_dist[ci] - f.surface_dist[ni])
				s -= 3.0 * lw
		if s > best_s:
			best_s = s
			best_k = k
	if best_k < 0:
		target[i] = pos[i]
		return
	target[i] = _center(cx + DX[best_k], cy + DY[best_k])
	heading[i] = (heading[i] * 0.4 + _dirs[best_k] * 0.6).normalized()


## Sigue la BFS de `sim.queen_goal_dist` (calculada una sola vez en `cmd_move_queen`) celda a celda,
## igual de greedy que `Mode.NEST` con `nest_dist`. Se llama todo tick mientras haya una orden en
## curso (no solo cada `next_think`): es una sola hormiga, no vale la pena esperar a que le toque
## pensar para que la orden del jugador se sienta inmediata.
func _think_queen(i: int, cx: int, cy: int, ci: int) -> void:
	if ci == sim.queen_goal_cell:
		sim.queen_goal_cell = -1
		target[i] = pos[i]
		return
	var world := sim.world
	var w := world.w
	var dist := sim.queen_goal_dist
	var best_k := -1
	var best_d: int = NestDistanceField.FAR
	for k in 8:
		var nx := cx + DX[k]
		var ny := cy + DY[k]
		if not world.is_passable(nx, ny):
			continue
		if DX[k] != 0 and DY[k] != 0:
			if not world.is_passable(cx + DX[k], cy) or not world.is_passable(cx, cy + DY[k]):
				continue  # nada de cortar esquinas de tierra, igual que `_step`
		var nd: int = dist[ny * w + nx]
		if nd < best_d:
			best_d = nd
			best_k = k
	if best_k < 0 or best_d >= NestDistanceField.FAR:
		sim.queen_goal_cell = -1  # sin camino posible (p.ej. alguien tapó el túnel): cancela la orden
		target[i] = pos[i]
		return
	target[i] = _center(cx + DX[best_k], cy + DY[best_k])


## Busca la celda seca más cercana (BFS acotado) y se dirige a su primer paso.
func _flee_bfs(cx: int, cy: int, ci: int, i: int) -> bool:
	var world := sim.world
	var w := world.w
	var total := w * world.h
	if _bfs_seen.size() != total:
		_bfs_seen.resize(total)
		_bfs_parent.resize(total)
		_bfs_q.resize(total)
		_bfs_stamp = 0
		_bfs_seen.fill(0)
	_bfs_stamp += 1
	var level := sim.water.level
	var safe := sim.cfg.safe_level
	var cap := mini(sim.cfg.flee_search_cells, total - 1)
	var head := 0
	var tail := 1
	_bfs_q[0] = ci
	_bfs_seen[ci] = _bfs_stamp
	_bfs_parent[ci] = -1
	var found := -1
	while head < tail and tail < cap:
		var cur := _bfs_q[head]
		head += 1
		if cur != ci and level[cur] < safe:
			found = cur
			break
		var x := cur % w
		var y := cur / w
		for k in 4:
			var nx := x + (1 if k == 0 else (-1 if k == 1 else 0))
			var ny := y + (1 if k == 2 else (-1 if k == 3 else 0))
			if not world.is_passable(nx, ny):
				continue
			var ni := ny * w + nx
			if _bfs_seen[ni] == _bfs_stamp:
				continue
			_bfs_seen[ni] = _bfs_stamp
			_bfs_parent[ni] = cur
			_bfs_q[tail] = ni
			tail += 1
	if found < 0:
		return false
	var node := found
	while _bfs_parent[node] != ci and _bfs_parent[node] >= 0:
		node = _bfs_parent[node]
	target[i] = _center(node % w, node / w)
	return true


# --- Atascos ------------------------------------------------------------------------------------------

func _stuck_check(i: int, ci: int) -> void:
	var cfg := sim.cfg
	check_acc[i] = 0.0
	var moved := pos[i].distance_to(last_check[i])
	last_check[i] = pos[i]
	var exempt := false
	if state[i] == State.DIG and job[i] >= 0:
		exempt = true  # cavando
	elif state[i] == State.IDLE and sim.fields.nest_dist[ci] <= 2:
		exempt = true  # descansando en el nido
	elif state[i] == State.NURSE or state[i] == State.GUARD or state[i] == State.ATTACK:
		exempt = true  # quietas cuidando, de guardia o peleando cuerpo a cuerpo
	elif sim.water.max_level > 0.0 and sim.water.level[ci] < sim.cfg.safe_level:
		exempt = true  # esperando en seco a que baje el agua
	if moved >= cfg.stuck_min_move_px or exempt:
		stuck_t[i] = 0.0
		return
	stuck_t[i] += 0.5
	max_stuck_seen = maxf(max_stuck_seen, stuck_t[i])
	if stuck_t[i] >= cfg.stuck_seconds:
		_recover(i, ci)


## Más de 3 s sin avanzar: volver a decidir usando el campo de distancias al nido.
func _recover(i: int, ci: int) -> void:
	sim.stuck_recoveries += 1
	stuck_t[i] = 0.0
	_release_job(i)
	var cx := ci % sim.world.w
	var cy := ci / sim.world.w
	var f := sim.fields
	state[i] = State.CARRY_HOME if carry[i] == 1 else State.IDLE
	timer[i] = 0.5
	if f.nest_dist[ci] < FAR:
		_step(i, cx, cy, ci, Mode.NEST, null)
	else:
		_step(i, cx, cy, ci, Mode.EXPLORE, null)
	next_think[i] = sim.tick_count + 1
