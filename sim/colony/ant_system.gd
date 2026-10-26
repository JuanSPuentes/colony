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

enum State { EXPLORE, GO_TO_FOOD, CARRY_HOME, DIG, FLEE_WATER, IDLE, FLEE_DANGER, EVACUATE, NURSE, GUARD, ATTACK, CARRY_EGG }
enum Mode { EXPLORE, FOOD, NEST, DIG, FLEE, PLANT, TOWARD, AWAY, STORE }

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
	Color("ff8040"),  # GUARDIA
	Color("ff0000"),  # ATTACK
	Color("9b59b6"),  # CARRY_EGG (mismo morado del Zángano)
]
const STATE_NAMES: Array[String] = ["EXPLORAR", "IR A COMIDA", "LLEVAR A CASA", "CAVAR", "HUIR DEL AGUA", "DESCANSO",
	"HUIR DEL PELIGRO", "EVACUAR", "CUIDAR CRÍA", "GUARDIA", "ATACAR", "CARGAR HUEVO"]
const DX: Array[int] = [1, 1, 0, -1, -1, -1, 0, 1]
const DY: Array[int] = [0, 1, 1, 1, 0, -1, -1, -1]
const FAR := NestDistanceField.FAR
## `preload` (no el `class_name` global) para evitar el ciclo de resolución de tipos: este
## archivo se referencia a sí mismo como tipo dentro de `ant_caste_ai.gd`.
const AntCasteAI = preload("res://sim/colony/ant_caste_ai.gd")

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
## Qué está cargando mientras `carry[i] == 1`: 0 = hoja, 1 = restos de un cadáver (Punto 4, valen
## más comida al entregarse). Solo importa en el momento de `_deliver()`.
var carry_kind := PackedByteArray()
## Solo lo usa el Zángano: índice en `BroodSystem` del huevo que está cargando ahora, -1 si
## ninguno (ver `_think_drone`).
var carry_egg := PackedInt32Array()
## Fase 14: punto de patrulla del soldado (columna del mapa a la que va por la superficie), -1 sin
## punto elegido, -2 "volviendo a revisar el nido". Ver `AntCasteAI.think_soldier`.
var patrol_x := PackedInt32Array()
## Fase 14: distancias por los túneles hasta la celda de la reina, para que los zánganos la escolten
## (`AntCasteAI.escort_queen`). Se recalcula solo si la reina cambia de celda o cambia el terreno.
## Fase 17: campos de distancia POR LOS TÚNELES hasta una celda destino (`path_field`), para las
## hormigas que van a un punto concreto del nido (zánganos: Guardería, un huevo, la reina, una
## amenaza). Caché por celda destino; se vacía si cambia el terreno o si junta demasiados.
var _paths := {}
var _paths_terrain := -1
const PATH_CACHE_MAX := 24
var _rally_cell := -1
var _rally_terrain := -1
var hp := PackedFloat32Array()
var timer := PackedFloat32Array()
var stuck_t := PackedFloat32Array()
var check_acc := PackedFloat32Array()
## Fase 9: bando (0 = jugador, 1 = rival — ver `sim/colony/rival_colony.gd`). Aditivo: todo lo que
## no pasa `ant_faction` a `add_ant_at` sigue creando hormigas de bando 0, igual que siempre.
var faction := PackedByteArray()
## Índices de cada bando ([0] jugador, [1] rival), en orden ascendente. `_nearest_enemy_index` recorre
## solo el bando buscado en vez de todas las hormigas: con 300 hormigas y una oleada de 20 rivales,
## cada búsqueda pasaba por las 300 (y la llaman todas al pensar, y los zánganos cada tick). Se
## rehace solo cuando nace una hormiga (`_grow`); las muertas se siguen saltando por `alive`.
var _members: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
var _members_dirty := true

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
	_members_dirty = true
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
	carry_kind.resize(total)
	carry_egg.resize(total)
	patrol_x.resize(total)
	hp.resize(total)
	timer.resize(total)
	stuck_t.resize(total)
	check_acc.resize(total)
	faction.resize(total)


func add_ants(n: int) -> void:
	var nest := sim.world.nest_cells
	for k in n:
		var c: int = nest[sim.rng.randi() % nest.size()]
		add_ant_at(Vector2i(c % sim.world.w, c / sim.world.w))


## Crea una hormiga en el centro de la celda dada (con un pequeño desfase aleatorio). `ant_faction`
## (Fase 9): 0 = jugador (de siempre), 1 = rival — ver `sim/colony/rival_colony.gd`.
func add_ant_at(cell: Vector2i, ant_caste: int = CasteDefs.Caste.WORKER, ant_faction: int = 0) -> int:
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
	carry_kind[i] = 0
	carry_egg[i] = -1
	patrol_x[i] = -1
	hp[i] = (cfg.queen_hp_base if ant_caste == CasteDefs.Caste.QUEEN else cfg.ant_hp) * CasteDefs.HP_MULT[ant_caste]
	# Fase 9: mejora de vida, solo bando jugador (las rivales no se benefician de tus mejoras).
	if ant_faction == 0:
		hp[i] *= sim.upgrades.hp_mult
	timer[i] = sim.rng.randf_range(0.0, cfg.rest_seconds_max)
	stuck_t[i] = 0.0
	check_acc[i] = sim.rng.randf() * 0.5
	faction[i] = ant_faction
	count += 1
	alive_count += 1
	return i


## Fase 13: al comprar un nivel de mejora de vida, sube también la vida de toda hormiga viva del
## bando del jugador (antes solo afectaba a las que nacieran después). `ratio` es el cambio del
## multiplicador (nuevo/viejo): escala `hp[i]` proporcional en vez de curar de golpe, así una
## hormiga a la mitad de vida sigue a la mitad de vida en el nuevo máximo.
func apply_hp_upgrade(ratio: float) -> void:
	for i in count:
		if alive[i] == 1 and faction[i] == 0:
			hp[i] *= ratio


## Fase 17: punto de reunión de los soldados en una batalla: la celda de la superficie más cerca
## del nido por los túneles (la salida). -1 si el nido no tiene salida (nido cerrado). Se recalcula
## solo si cambió el terreno.
func rally_cell() -> int:
	if sim.world.passable_version != _rally_terrain:
		_rally_terrain = sim.world.passable_version
		_rally_cell = -1
		var best := FAR
		var y := sim.cfg.surface_y - 1
		for x in sim.world.w:
			var c := y * sim.world.w + x
			var nd := sim.fields.nest_dist[c]
			if nd < best:
				best = nd
				_rally_cell = c
	return _rally_cell


func queen_field() -> PackedInt32Array:
	return path_field(_cell_index(pos[sim.queen_id]))


func path_field(goal: int) -> PackedInt32Array:
	if sim.world.passable_version != _paths_terrain:
		_paths_terrain = sim.world.passable_version
		_paths.clear()
	if not _paths.has(goal):
		if _paths.size() >= PATH_CACHE_MAX:
			_paths.clear()
		_paths[goal] = sim.fields.bfs_from([goal])
	return _paths[goal]


## Un paso por los túneles bajando por `dist` (un campo de `path_field`), sin cortar esquinas de
## tierra, igual que `_step`. Devuelve false si desde acá no hay camino (se queda quieta).
func step_along(i: int, cx: int, cy: int, ci: int, dist: PackedInt32Array) -> bool:
	var world := sim.world
	var best_k := -1
	var best_d: int = dist[ci]
	for k in 8:
		var nx := cx + DX[k]
		var ny := cy + DY[k]
		if not world.is_passable(nx, ny):
			continue
		if DX[k] != 0 and DY[k] != 0:
			if not world.is_passable(cx + DX[k], cy) or not world.is_passable(cx, cy + DY[k]):
				continue
		var nd: int = dist[ny * world.w + nx]
		if nd < best_d:
			best_d = nd
			best_k = k
	if best_k < 0:
		target[i] = pos[i]
		return false
	target[i] = _center(cx + DX[best_k], cy + DY[best_k])
	return true


## Vida máxima real de la hormiga `i`: la misma cuenta con la que nace (`add_ant_at`), mejora de
## Vida incluida para el bando del jugador. Fase 17: el HUD mostraba el % contra la vida base, así
## que con la mejora comprada una hormiga sana figuraba con 115 % o más.
func max_hp(i: int) -> float:
	var c := caste[i]
	var m := (sim.cfg.queen_hp_base if c == CasteDefs.Caste.QUEEN else sim.cfg.ant_hp) * CasteDefs.HP_MULT[c]
	if faction[i] == 0:
		m *= sim.upgrades.hp_mult
	return m


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
		# Fase 9: hormigas rivales (ver `sim/colony/rival_colony.gd`) tienen su propia IA, mucho más
		# simple que el resto de este archivo (no cavan, no forrajean, no cuidan cría): solo avanzan
		# hacia la reina del jugador y pelean con lo que se les cruce en el camino.
		if faction[i] == 1:
			_tick_rival(i, cx, cy, ci, dt)
			continue
		if caste[i] == CasteDefs.Caste.QUEEN:
			# La reina no decide sola (sin EXPLORE/FOOD/etc.): solo camina cuando el jugador la
			# manda con `cmd_move_queen` (ver `_think_queen`), y se queda quieta el resto del
			# tiempo, igual que siempre.
			if sim.queen_goal_cell >= 0:
				_think_queen(i, cx, cy, ci)
				_move(i, dt, lv)
			continue
		if caste[i] == CasteDefs.Caste.DRONE:
			# Golpea a lo que tenga al alcance. Fase 14: además de cargar huevos hasta la Guardería,
			# defiende a la reina y a los huevos si una amenaza se les acerca, y sin tarea escolta a la
			# reina (ver `AntCasteAI.think_drone`); fuera de ese radio sigue sin perseguir a nadie.
			var threat = _nearest_threat(p, cfg.soldier_melee_range_px)
			if threat != null:
				threat.take_damage(CasteDefs.DAMAGE_PER_S[CasteDefs.Caste.DRONE] * dt * sim.upgrades.damage_mult)
			if now >= next_think[i]:
				_think_drone(i, cx, cy, ci)
			_move(i, dt, lv)
			if carry_egg[i] >= 0:
				sim.brood.pos[carry_egg[i]] = pos[i]  # el huevo "viaja" pegado al zángano
			check_acc[i] += dt
			if check_acc[i] >= 0.5:
				_stuck_check(i, ci)
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


## Hormigas vivas por casta, solo para las castas pedidas (las demás no entran en el resultado).
## Antes esto estaba duplicado en `hud.gd` (una vez para el modo incremental, otra para el modo
## con reina), cada copia iterando `count` por su cuenta.
func count_by_caste(castes: Array) -> Dictionary:
	var counts := {}
	for c in castes:
		counts[c] = 0
	for i in count:
		if alive[i] == 1 and counts.has(caste[i]):
			counts[caste[i]] += 1
	return counts


func _kill(i: int, drowned: bool) -> void:
	_release_job(i)
	alive[i] = 0
	alive_count -= 1
	if drowned:
		sim.deaths += 1
	carry[i] = 0
	carry_kind[i] = 0
	if carry_egg[i] >= 0:
		sim.brood.claimed[carry_egg[i]] = -1  # el zángano murió a mitad de camino: el huevo queda libre
		carry_egg[i] = -1
	sim.spawn_corpse(pos[i], sim.cfg.corpse_food_value)  # Punto 4: deja restos recolectables


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
	# Fase 9: mejora de velocidad de trabajo (solo cavan hormigas del bando jugador, nunca rivales).
	world.job_progress[j] += dt * sim.upgrades.work_mult
	if world.job_progress[j] >= sim.cfg.dig_seconds:
		var jx := j % world.w
		var jy := j / world.w
		var c := _cell_index(pos[i])
		if absi(c % world.w - jx) + absi(c / world.w - jy) != 1:
			sim.dig_violations += 1  # cavó sin estar al lado (no debería ocurrir)
		world.complete_dig(j)
		sim.dug += 1
		job[i] = -1
		# Fase 15: si quedan celdas marcadas, sigue cavando la siguiente en vez de pasar a IDLE —
		# IDLE la mandaba de vuelta al nido a descansar después de CADA celda (`_think_idle`), así
		# que un túnel largo se cavaba en un ir y volver constante. Ahora sigue hasta terminarlo;
		# `_think_dig` la saca sola a IDLE si ya no hay nada alcanzable que cavar.
		if world.marked_count > 0:
			timer[i] = 0.0
		else:
			state[i] = State.IDLE
			timer[i] = 0.0


func _move(i: int, dt: float, lv: float) -> void:
	var to := target[i] - pos[i]
	var d := to.length()
	if d < 0.01:
		return
	var cfg := sim.cfg
	var mult := CasteDefs.SPEED_MULT[caste[i]]
	if faction[i] == 0:  # Fase 9: mejora de velocidad, solo bando jugador.
		mult *= sim.upgrades.speed_mult
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
		if state[i] == State.CARRY_HOME and _at_drop(ci):
			_deliver(i)
	elif state[i] == State.EXPLORE or state[i] == State.GO_TO_FOOD:
		var nd := sim.fields.nest_dist[ci]
		if nd < cfg.home_range:
			sim.home.deposit(ci, cfg.home_deposit * (1.0 - float(nd) / cfg.home_range))


## Fase 17: en Juego normal, con un Almacén válido y alcanzable, la carga se deja ahí; si no, en el
## nido como siempre (Modo infinito y las pruebas viejas no cambian: no es modo incremental).
func _use_storage(ci: int) -> bool:
	return sim.incremental and sim.rooms.valid[WorldGrid.Room.STORAGE] and sim.fields.storage_dist[ci] < FAR


func _at_drop(ci: int) -> bool:
	if _use_storage(ci):
		return sim.fields.storage_dist[ci] == 0
	return sim.fields.nest_dist[ci] == 0


func _deliver(i: int) -> void:
	if carry_kind[i] == 1:
		sim.corpse_parts_stored += 1
	else:
		sim.leaves_stored += 1
	carry_kind[i] = 0
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
	# Defensa de la colmena: ante una amenaza real (hoy la araña; más adelante otros insectos) toda
	# la colonia pelea, no solo el soldado — cada casta con su propio daño (`CasteDefs.DAMAGE_PER_S`).
	# Tiene prioridad sobre huir de la feromona de Peligro (que sigue existiendo tal cual para avisos
	# del jugador sin amenaza real detrás) pero no sobre ahogarse. La Nodriza se queda cuidando la
	# cría; el Soldado sigue con su propio `_think_soldier` (ya reacciona a esto de siempre).
	if caste[i] != CasteDefs.Caste.NURSE and caste[i] != CasteDefs.Caste.SOLDIER and state[i] != State.FLEE_WATER:
		var threat = _nearest_threat(pos[i], cfg.soldier_sight_px)
		if threat != null and not can_reach(pos[i], threat.pos):
			threat = null  # Fase 16: la ve a través de la tierra pero no hay camino (ver `can_reach`)
		if threat != null:
			if state[i] != State.ATTACK:
				_release_job(i)
			_think_defend(i, cx, cy, ci, threat, think_dt)
			return
		elif state[i] == State.ATTACK:
			# La amenaza ya no está (murió o se fue de rango): vuelve a decidir desde cero.
			state[i] = State.IDLE
			target[i] = pos[i]
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
			if _at_drop(ci):
				_deliver(i)
			else:
				_step(i, cx, cy, ci, Mode.STORE if _use_storage(ci) else Mode.NEST, null)
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
	# Fase 14: tope por celdas cavables a la vez (`dig_frontier`), no por el total marcado: un túnel
	# de 15 celdas se cava de a una, y mandar más obreras solo las hacía ir y volver.
	var can_dig := mini(sim.fields.dig_frontier, sim.world.marked_count)
	# Fase 17: el tope de excavadoras deja obreras libres para buscar comida; sin salida a la
	# superficie (nido cerrado) no hay comida que buscar, así que cavan todas las que tengan dónde.
	if sim.fields.surface_dist[ci] < FAR:
		can_dig = mini(can_dig, max_diggers)
	if sim.world.marked_count > 0 and diggers < can_dig and sim.fields.dig_dist[ci] < FAR:
		state[i] = State.DIG
		state_counts[State.DIG] += 1
	elif (sim.total_leaves_left > 0 or not sim.corpses.is_empty()) and sim.fields.surface_dist[ci] < FAR:
		# Punto 4: hay que salir a EXPLORE también si solo quedan cadáveres por recoger (sin hojas),
		# si no, `_corpse_logic` (que solo se llama desde EXPLORE/GO_TO_FOOD) nunca se evalúa y la
		# colonia deja de recoger restos para siempre en cuanto se agotan las hojas.
		# Fase 17: solo si hay salida a la superficie. Con el nido todavía cerrado, "explorar" era dar
		# vueltas adentro para siempre, y una obrera explorando nunca mira si hay algo para cavar.
		state[i] = State.EXPLORE
	else:
		timer[i] = 4.0  # sin trabajo: seguir descansando


## Punto 4: igual que `_plant_near`, pero sobre `sim.corpses` en vez de `sim.plants`. Ignora un
## cadáver que hoy está bajo agua profunda: `_step(Mode.PLANT, ...)` ya evita cruzar esas celdas
## (ver más abajo), así que perseguirlo sería perseguir algo inalcanzable hasta que el agua baje;
## mejor dejar que una obrera siga buscando hojas mientras tanto y lo intente más tarde.
func _corpse_near(i: int) -> Corpse:
	var cfg := sim.cfg
	var best: Corpse = null
	var best_d := cfg.sight_cells * cfg.cell_px
	var p := pos[i]
	for c in sim.corpses:
		if c.food_value <= 0.0:
			continue
		if sim.water.level[_cell_index(c.pos)] >= cfg.flee_level:
			continue
		var d := p.distance_to(c.pos)
		if d < best_d:
			best_d = d
			best = c
	return best


## Intenta recoger restos de un cadáver o acercarse a uno visible. Devuelve true si decidió algo;
## mismo espíritu que `_plant_logic`, un viaje se lleva todo el valor del cadáver (no hay "varias
## partes" por cuerpo, simplificación deliberada).
func _corpse_logic(i: int, cx: int, cy: int, ci: int) -> bool:
	var cfg := sim.cfg
	var c := _corpse_near(i)
	if c == null:
		return false
	if pos[i].distance_to(c.pos) <= cfg.pickup_cells * cfg.cell_px:
		c.food_value = 0.0
		carry[i] = 1
		carry_kind[i] = 1
		trip_steps[i] = 0
		state[i] = State.CARRY_HOME
		_step(i, cx, cy, ci, Mode.NEST, null)
		return true
	state[i] = State.GO_TO_FOOD
	_step(i, cx, cy, ci, Mode.PLANT, c.pos)
	return true


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
	# Fase 17: sin salida a la superficie (nido cerrado) no hay nada que explorar: a descansar, que
	# desde ahí se elige cavar. Antes las obreras iniciales de Juego normal salían a explorar antes de
	# que el jugador marcara nada y quedaban atrapadas así, sin cavar lo que se marcaba después.
	if sim.fields.surface_dist[ci] >= FAR:
		state[i] = State.IDLE
		timer[i] = 0.5
		target[i] = pos[i]
		return
	if _corpse_logic(i, cx, cy, ci) or _plant_logic(i, cx, cy, ci) or _remembered_plant(i, cx, cy, ci):
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
	if _corpse_logic(i, cx, cy, ci) or _plant_logic(i, cx, cy, ci) or _remembered_plant(i, cx, cy, ci):
		return
	var here := sim.food.data[ci]
	var best := 0.0
	for k in 8:
		best = maxf(best, sim.food.get_v(cx + DX[k], cy + DY[k]))
	if sim.tick_count < ignore_until[i] or maxf(here, best) < cfg.food_follow_threshold:
		state[i] = State.EXPLORE
		_step(i, cx, cy, ci, Mode.EXPLORE, null)
	elif cy < cfg.surface_y and here >= best + 0.002:
		# Fin del rastro sin comida a la vista: la hormiga borra la punta (la feromona de un
		# rastro agotado se va comiendo desde el final) y deja de fiarse de él un rato. Solo en la
		# superficie (Fase 16): bajo tierra el "pico" es el pozo del nido, no el final de un rastro.
		if sim.incremental:
			# Fase 16: en Juego normal las plantas rebrotan; borrar lo que pintó el jugador lo
			# dejaba sin camino cuando la planta volvía a tener hojas. Se borra solo lo depositado.
			sim.food.clear_deposit(ci)
		else:
			sim.food.clear_cell(ci)  # también lo pintado: un rastro a una planta agotada se va comiendo igual
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
		# Otra hormiga se adelantó con la celda de al lado. Fase 15: antes esto la mandaba a IDLE (y
		# de vuelta al nido a descansar); en un túnel de una celda de ancho solo cabe una excavadora
		# en el frente, así que la segunda iba y volvía sin parar. Ahora espera ahí su turno: cuando
		# la otra termina, el frente avanza y `dig_dist` la lleva a la celda siguiente.
		target[i] = pos[i]
		return
	_step(i, cx, cy, ci, Mode.DIG, null)


# --- Zángano: carga huevos a la Guardería -------------------------------------------------------

## El zángano no pasa por `_think()` (no pelea activo, no explora): lleva su propia cuenta de
## cuándo le toca pensar, igual que hace `_think()` para el resto. La decisión en sí vive en
## `AntCasteAI` (ver sección "Decisiones por casta" más abajo).
func _think_drone(i: int, cx: int, cy: int, ci: int) -> void:
	AntCasteAI.think_drone(self, i, cx, cy, ci)


# --- Nodrizas y soldados (Fase 1) --------------------------------------------------------------

func _think_nurse(i: int, cx: int, cy: int, ci: int) -> void:
	AntCasteAI.think_nurse(self, i, cx, cy, ci)


## La amenaza activa más cercana dentro de `max_range`, o null si no hay ninguna al alcance.
## Fase 7: ya hay tres (araña, ciempiés, mantis) y esto sigue siendo lo único que hace falta tocar
## para que toda la colonia (y el soldado) reaccione a una amenaza nueva — el resto de
## `_think_defend`/`_think_soldier` ya es genérico (solo necesita `.pos`, `.alive`, `.take_damage()`).
## Sin tipar el retorno a propósito: cada amenaza es una clase distinta (`Spider`, `Centipede`,
## `Mantis`) que no comparte una clase base, solo la misma forma (duck typing).
func _nearest_threat(p: Vector2, max_range: float):
	var best = null
	var best_d := max_range
	# Fase 14: la reina rival también es una amenaza (misma forma `.pos`/`.alive`/`.take_damage()`).
	# Antes no estaba en esta lista y ninguna hormiga podía dañarla: la batalla de fin de estación
	# solo se ganaba en las pruebas, que la matan a mano.
	var rq: RivalQueen = sim.rival_colony.queen if sim.rival_colony != null and sim.rival_colony.battle_active else null
	for t in [sim.spider, sim.centipede, sim.mantis, rq]:
		if t != null and t.alive:
			var d: float = p.distance_to(t.pos)
			if d <= best_d:
				best_d = d
				best = t
	# Fase 9: hormigas rivales (si hay una batalla en curso, ver `sim/colony/rival_colony.gd`)
	# cuentan igual que cualquier otra amenaza — la más cercana dentro de rango gana, sea araña o
	# una hormiga rival. `AntRef` envuelve un índice de este mismo array con la misma forma
	# (`.pos`/`.alive`/`.take_damage()`) que ya esperan `_think_defend`/`_think_soldier`.
	var enemy_idx := _nearest_enemy_index(p, best_d, 1)
	if enemy_idx >= 0:
		best = AntRef.new(self, enemy_idx)
	return best


## Índice de la hormiga viva de bando `want_faction` más cercana a `p` dentro de `max_range`, o -1.
func _nearest_enemy_index(p: Vector2, max_range: float, want_faction: int) -> int:
	if _members_dirty:
		_members_dirty = false
		_members[0].clear()
		_members[1].clear()
		for j in count:
			_members[faction[j]].append(j)
	var best := -1
	var best_d := max_range
	for j in _members[want_faction]:
		if alive[j] == 0:
			continue
		var d := p.distance_to(pos[j])
		if d < best_d:
			best_d = d
			best = j
	return best


## Fase 9: hormigas rivales (bando 1) — mucho más simples que el resto de este archivo: no cavan,
## no forrajean, no cuidan cría. Buscan la hormiga del jugador más cercana para pelear; sin
## ninguna a la vista, avanzan hacia la reina del jugador (el objetivo final de la oleada).
func _tick_rival(i: int, cx: int, cy: int, ci: int, dt: float) -> void:
	var cfg := sim.cfg
	var now := sim.tick_count
	if now >= next_think[i]:
		var think_dt := float(now - last_think[i]) * sim.dt
		last_think[i] = now
		next_think[i] = now + sim.rng.randi_range(cfg.think_ticks_min, cfg.think_ticks_max)
		var target_idx := _nearest_enemy_index(pos[i], cfg.soldier_sight_px, 0)
		if target_idx >= 0:
			state[i] = State.ATTACK
			if pos[i].distance_to(pos[target_idx]) <= cfg.soldier_melee_range_px:
				target[i] = pos[i]
				hp[target_idx] -= CasteDefs.DAMAGE_PER_S[caste[i]] * think_dt
				if hp[target_idx] <= 0.0:
					_kill(target_idx, false)
			else:
				_step(i, cx, cy, ci, Mode.PLANT, pos[target_idx])
		else:
			state[i] = State.EXPLORE
			var goal := pos[sim.queen_id] if sim.queen_id >= 0 and alive[sim.queen_id] == 1 else pos[i]
			_step(i, cx, cy, ci, Mode.PLANT, goal)
	_move(i, dt, sim.water.level[ci])


## Obrera y Zángano (en combate activo; el Zángano además pelea pasivo si lo alcanzan, ver
## `tick()`) defendiendo la colmena: igual de simple que el Soldado (acercarse y pegar), pero con
## el daño de su propia casta (`CasteDefs.DAMAGE_PER_S`), bastante menor. Decisión en `AntCasteAI`.
## `threat` sin tipar: puede ser `Spider` o `Centipede` (ver `_nearest_threat`).
## Fase 16: ¿hay camino entre dos puntos? La amenaza se detecta en línea recta (a través de la tierra);
## sin esto, con el nido todavía cerrado y una araña arriba, las obreras de adentro soltaban la
## excavación para "ir a pelear" sin poder llegar, y volvían a cavar en cuanto la araña se alejaba un
## poco — en bucle, sin terminar nunca el túnel. Aproximación barata con `nest_dist`: los dos puntos
## están del mismo lado si ambos están conectados al nido o ninguno de los dos lo está (p.ej. los dos
## en la superficie con el nido cerrado).
func can_reach(a: Vector2, b: Vector2) -> bool:
	var ia := _cell_index(a)
	var ib := _cell_index(b)
	if ia < 0 or ib < 0 or ia >= sim.fields.nest_dist.size() or ib >= sim.fields.nest_dist.size():
		return true
	return (sim.fields.nest_dist[ia] < FAR) == (sim.fields.nest_dist[ib] < FAR)


func _think_defend(i: int, cx: int, cy: int, ci: int, threat, think_dt: float) -> void:
	AntCasteAI.think_defend(self, i, cx, cy, ci, threat, think_dt)


func _think_soldier(i: int, cx: int, cy: int, ci: int, think_dt: float) -> void:
	AntCasteAI.think_soldier(self, i, cx, cy, ci, think_dt)


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
				if on_surface:
					s = cfg.w_food * (sim.food.data[ni] - sim.food.data[ci]) * 10.0
				else:
					# Fase 16: bajo tierra, salir hacia la superficie en vez de seguir el gradiente de
					# Comida. Todas las que vuelven cargadas pasan por el pozo del nido y lo llenan de
					# feromona: el pozo terminaba siendo lo más fuerte del mapa (0.66 contra ~0.3 del
					# rastro pintado afuera), así que las que salían a buscar comida se metían más
					# adentro del nido y se quedaban dando vueltas en un valor parejo, sin salir nunca
					# aunque el rastro de afuera siguiera intacto. La comida siempre está arriba.
					s = cfg.w_outward * float(f.surface_dist[ci] - f.surface_dist[ni]) * 2.0
				s += cfg.w_persist * head.dot(_dirs[k]) + 0.3 * rng.randf()
				if on_surface and ny >= cfg.surface_y:
					s -= 2.0
				s -= 3.0 * lw
			Mode.NEST:
				var nd := f.nest_dist[ni]
				if nd >= FAR:
					continue
				s = float(f.nest_dist[ci] - nd) * 2.0 + 0.2 * rng.randf() - 2.0 * lw
			Mode.STORE:
				var sd := f.storage_dist[ni]
				if sd >= FAR:
					continue
				s = float(f.storage_dist[ci] - sd) * 2.0 + 0.2 * rng.randf() - 2.0 * lw
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
## pensar para que la orden del jugador se sienta inmediata. Decisión en `AntCasteAI`.
func _think_queen(i: int, cx: int, cy: int, ci: int) -> void:
	AntCasteAI.think_queen(self, i, cx, cy, ci)


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


## Fase 9: envuelve un índice de este mismo `AntSystem` con la misma forma que las amenazas de
## `sim/threats/` (`.pos`/`.alive`/`.take_damage()`), para que `_nearest_threat()` pueda devolver
## "la hormiga rival más cercana" sin que `_think_defend`/`_think_soldier` necesiten saber que es
## una hormiga y no una araña. Instancia nueva por llamada a `_nearest_threat` (no se guarda entre
## ticks), así que `pos`/`alive` quedan congelados al momento de crearla — correcto, porque quien
## la usa la lee de inmediato en el mismo tick.
class AntRef:
	var _ants: AntSystem
	var _idx: int
	var pos: Vector2
	var alive: bool

	func _init(a: AntSystem, i: int) -> void:
		_ants = a
		_idx = i
		pos = a.pos[i]
		alive = a.alive[i] == 1

	func take_damage(amount: float) -> void:
		_ants.hp[_idx] -= amount
		if _ants.hp[_idx] <= 0.0:
			_ants._kill(_idx, false)
