class_name Simulation
extends RefCounted
## Orquesta todos los sistemas en un orden fijo. No sabe nada de pantallas ni de nodos.
## Un tick = 1 / cfg.tick_rate segundos. Toda la aleatoriedad sale de `rng` (con semilla).
##
## Fase 1: reina, cría, cámaras, economía, 3 feromonas más y araña son ADITIVOS. Si nadie llama
## a `spawn_colony_court()` (como en toda la Fase 0 y sus pruebas, que solo usan `Simulation.new`
## directamente), `queen_id` queda en -1 y la araña, las eras y la puesta de huevos nunca se
## activan: el comportamiento es exactamente el de la Fase 0. El juego real (`main.gd`) sí la
## llama, así que la escena jugable tiene colonia completa.
##
## Fase 3: `spawn_incremental_start()` (lo que llama hoy `main.gd`) activa el modo incremental:
## colonia diminuta, todo medido en comida, compra de obreras/soldados, plantas que rebrotan, día y
## noche, y sin araña ni eras. Igual que antes, si nadie lo llama, `incremental` queda en false y
## las Fases 0-2 corren exactamente como siempre.

enum Weather { CLEAR, WARNING, RAINING }
enum Era { FOUNDATION, YOUNG, MATURE }

## `preload` (no `class_name`) para evitar el ciclo de resolución: este archivo se referencia a
## sí mismo como tipo (`Simulation.Era`) dentro de `era_system.gd`.
const EraSystem = preload("res://sim/colony/era_system.gd")

var cfg: SimConfig
var rng := RandomNumberGenerator.new()
var tick_count := 0
var dt := 0.05
var world: WorldGrid
var food: PheromoneField
var home: PheromoneField
var danger: PheromoneField
var attack: PheromoneField
var evacuate: PheromoneField
var water: WaterSim
var fields: NestDistanceField
var ants: AntSystem
var plants: Array[Plant] = []
## Punto 4: restos de hormigas y amenazas muertas, recolectables por obreras (ver `AntSystem`).
var corpses: Array[Corpse] = []
var corpse_parts_stored := 0
var rooms: RoomSystem
var colony: Colony
var brood: BroodSystem
var spider: Spider
## Fase 5: segunda amenaza, solo en la colonia con reina (no en el modo incremental, ver `tick()`).
var centipede: Centipede
## Fase 7: tercera amenaza, misma condición que `centipede`.
var mantis: Mantis
## Fase 3: false salvo que se llame a `spawn_incremental_start()`.
var incremental := false
## Fase 6: false salvo que se llame a `spawn_test_start()`. Sandbox sin victoria/derrota (ver
## `tick()`), para probar amenazas y castas a voluntad sin que una partida real se corte.
var test_mode := false
var econ: IncrementalEconomy

var leaves_stored := 0
var delivered := 0
var deaths := 0
var dug := 0
## Fase 5: true desde la primera vez que `cmd_paint_food` pinta una celda con éxito. Solo lo usa
## el tutorial guiado (ver `view/tutorial_view.gd`) para saber si ya se cumplió el primer paso.
var food_painted := false
var dig_violations := 0
var stuck_recoveries := 0
var total_leaves_left := 0

var weather := Weather.CLEAR
var rain_start_tick := -1
var rain_end_tick := -1
var rains_started := 0

## Fase 1: -1 mientras no haya colonia completa (ver nota arriba).
var queen_id := -1
## Orden del jugador para mover a la reina (`cmd_move_queen`): -1 si no hay ninguna en curso.
## `queen_goal_cell` es el índice plano de la celda destino; `queen_goal_dist` es una BFS de una
## sola vez contra esa celda (no se recalcula si cambia el terreno mientras camina: simplificación
## deliberada, ver README). `AntSystem._think_queen` la sigue greedy, igual que `Mode.NEST` sigue
## `fields.nest_dist`.
var queen_goal_cell := -1
var queen_goal_dist := PackedInt32Array()
var era := Era.FOUNDATION
var game_over := false
var game_over_reason := ""
## Fase 4: true si `game_over` se puso por ganar, no por perder. `game_over` sigue siendo la única
## bandera que detiene `tick()` (ver el `if game_over: return` al principio): ganar y perder paran
## la partida igual, esta bandera solo distingue cuál de las dos pantallas mostrar.
var victory := false
var spiders_spawned := 0
var spider_next_s := 0.0
var centipedes_spawned := 0
var centipede_next_s := 0.0
var mantises_spawned := 0
var mantis_next_s := 0.0
var notifications: Array[String] = []
const MAX_NOTIFICATIONS := 5

## Fase 4: -1 hasta que la colonia (no incremental) llega a Colonia madura por primera vez; desde
## ahí mide cuánto tiempo de simulación lleva viva en esa era para la condición de victoria.
var _mature_since_s := -1.0

var _terrain_seen := -1
var _jobs_seen := -1
var _dig_dirty := true


func _init(config: SimConfig, seed_value: int = -1) -> void:
	cfg = config
	dt = 1.0 / float(cfg.tick_rate)
	rng.seed = cfg.world_seed if seed_value < 0 else seed_value
	world = WorldGrid.new(cfg)
	world.generate(rng)
	food = PheromoneField.new(world.w, world.h, cfg.food_decay_per_s)
	home = PheromoneField.new(world.w, world.h, cfg.home_decay_per_s)
	danger = PheromoneField.new(world.w, world.h, cfg.danger_decay_per_s)
	attack = PheromoneField.new(world.w, world.h, cfg.attack_decay_per_s)
	evacuate = PheromoneField.new(world.w, world.h, cfg.evacuate_decay_per_s)
	water = WaterSim.new(world)
	fields = NestDistanceField.new(world)
	_place_plants()
	fields.recompute_terrain()
	fields.recompute_dig()
	_terrain_seen = world.passable_version
	_jobs_seen = world.jobs_version
	rooms = RoomSystem.new(world, fields, cfg)
	rooms.maybe_recompute()
	colony = Colony.new(cfg)
	brood = BroodSystem.new(self)
	spider = Spider.new(self)
	centipede = Centipede.new(self)
	mantis = Mantis.new(self)
	econ = IncrementalEconomy.new(self)
	ants = AntSystem.new(self)
	ants.add_ants(cfg.initial_ants)
	if cfg.rain_auto:
		rain_start_tick = int(cfg.rain_first_s * cfg.tick_rate)


## Fase 1: añade la reina y las nodrizas iniciales. Lo llama `main.gd` para el juego real; las
## pruebas de la Fase 0 nunca lo llaman, así que su comportamiento no cambia.
func spawn_colony_court() -> void:
	var cell := Vector2i(cfg.nest_x, cfg.surface_y + cfg.shaft_depth + 1)
	queen_id = ants.add_ant_at(cell, CasteDefs.Caste.QUEEN)
	for k in cfg.initial_nurses:
		var c: int = world.nest_cells[rng.randi() % world.nest_cells.size()]
		ants.add_ant_at(Vector2i(c % world.w, c / world.w), CasteDefs.Caste.NURSE)


## Fase 3: arranque del modo incremental. Descarta las obreras de `cfg.initial_ants` que creó el
## constructor y empieza con una colonia mínima: reina, unas pocas obreras, un soldado y una larva.
func spawn_incremental_start() -> void:
	incremental = true
	# Arranca el reloj ya pasado el amanecer (`DayNight.FADE`): a tick_count=0 el mundo se ve casi
	# negro un instante (el amanecer empieza oscuro y se aclara), aunque `is_night()` ya dé "de
	# día" — así la partida se ve a pleno día desde el primer frame, no a mitad de esa animación.
	tick_count = int(DayNight.FADE * cfg.day_length_s / dt)
	ants = AntSystem.new(self)
	var cell := Vector2i(cfg.nest_x, cfg.surface_y + cfg.shaft_depth + 1)
	queen_id = ants.add_ant_at(cell, CasteDefs.Caste.QUEEN)
	for k in cfg.inc_start_workers:
		ants.add_ant_at(_random_nest_cell(), CasteDefs.Caste.WORKER)
	for k in cfg.inc_start_soldiers:
		ants.add_ant_at(_random_nest_cell(), CasteDefs.Caste.SOLDIER)
	for k in cfg.inc_start_larvae:
		brood.lay_egg(CasteDefs.Caste.WORKER, ants.pos[queen_id])
		brood.stage[brood.stage.size() - 1] = BroodSystem.Stage.LARVA
		brood.timer[brood.timer.size() - 1] = cfg.larva_time_s
	colony.food = cfg.inc_start_food
	colony.water = 0.0
	if cfg.rain_auto:
		rain_start_tick = int(cfg.inc_rain_first_s * cfg.tick_rate)
	ants._recount()


## Fase 6: arranque del modo Test (sandbox, sin victoria/derrota — ver `test_mode` en `tick()`).
## Reina + 20 obreras + 20 soldados + 9 zánganos (50 en total), igual composición fija cada vez
## que se reinicia. Mismo truco de reloj que `spawn_incremental_start()` para arrancar ya a pleno
## día. Sin lluvia automática a propósito: en este modo solo la dispara el panel de pruebas.
func spawn_test_start() -> void:
	test_mode = true
	tick_count = int(DayNight.FADE * cfg.day_length_s / dt)
	ants = AntSystem.new(self)
	var cell := Vector2i(cfg.nest_x, cfg.surface_y + cfg.shaft_depth + 1)
	queen_id = ants.add_ant_at(cell, CasteDefs.Caste.QUEEN)
	for k in cfg.test_start_workers:
		ants.add_ant_at(_random_nest_cell(), CasteDefs.Caste.WORKER)
	for k in cfg.test_start_soldiers:
		ants.add_ant_at(_random_nest_cell(), CasteDefs.Caste.SOLDIER)
	for k in cfg.test_start_drones:
		ants.add_ant_at(_random_nest_cell(), CasteDefs.Caste.DRONE)
	ants._recount()


func _random_nest_cell() -> Vector2i:
	var c: int = world.nest_cells[rng.randi() % world.nest_cells.size()]
	return Vector2i(c % world.w, c / world.w)


func _place_plants() -> void:
	var n := cfg.plant_count
	for k in n:
		var d := lerpf(cfg.plant_min_dist, cfg.plant_max_dist, (k + 0.5) / n) + rng.randf_range(-3.0, 3.0)
		var side := 1 if k % 2 == 0 else -1
		var x := clampi(cfg.nest_x + side * int(round(d)), 3, world.w - 4)
		plants.append(Plant.new(Vector2i(x, cfg.surface_y - 1), cfg.leaves_per_plant))
		total_leaves_left += cfg.leaves_per_plant


func time_s() -> float:
	return tick_count * dt


func notify(msg: String) -> void:
	notifications.append(msg)
	if notifications.size() > MAX_NOTIFICATIONS:
		notifications.pop_front()


func tick() -> void:
	if game_over:
		return
	tick_count += 1
	_update_weather()
	if tick_count % cfg.water_step_ticks == 0:
		water.step(dt * cfg.water_step_ticks)
	if tick_count % cfg.pheromone_step_ticks == 0:
		var mult := cfg.rain_decay_mult if weather == Weather.RAINING else 1.0
		var step_dt := dt * cfg.pheromone_step_ticks
		food.decay(step_dt, mult)
		home.decay(step_dt, mult)
		danger.decay(step_dt, mult)
		attack.decay(step_dt, mult)
		evacuate.decay(step_dt, mult)
	if world.passable_version != _terrain_seen:
		_terrain_seen = world.passable_version
		fields.recompute_terrain()
		_dig_dirty = true
	if world.jobs_version != _jobs_seen:
		_jobs_seen = world.jobs_version
		_dig_dirty = true
	if _dig_dirty and tick_count % cfg.field_refresh_ticks == 0:
		_dig_dirty = false
		fields.recompute_dig()
	rooms.maybe_recompute()
	_update_corpses(dt)
	ants.tick()
	# Todo lo que sigue solo existe si hay una colonia completa (ver nota en la cabecera).
	if incremental:
		# Fase 3: sin eras (la araña ya sí aparece, con su propio umbral de población).
		econ.tick(dt)
		econ.regrow_plants(dt)
		brood.tick(dt)
		if tick_count % 3 == 0:
			_update_spider(dt * 3.0, cfg.inc_spider_first_population)
		_check_game_over()
	elif queen_id >= 0:
		colony.tick(self, dt)
		brood.tick(dt)
		_update_era()
		# Fase 6: en el modo Test las amenazas actúan sin esperar a Colonia madura — el sandbox
		# arranca con una población fija (50) que puede quedar por debajo de `era3_population` y
		# nunca llegar sola a esa era; sin este `or test_mode`, aparecían (el jugador las hace
		# aparecer a mano) pero nunca se movían ni atacaban porque `.step()` no se llamaba nunca.
		if tick_count % 3 == 0 and (era == Era.MATURE or test_mode):
			_update_spider(dt * 3.0, cfg.spider_first_population)
			_update_centipede(dt * 3.0)
			_update_mantis(dt * 3.0)
		# El modo Test es un sandbox, nunca termina (ver `spawn_test_start`).
		if not test_mode:
			_check_game_over()
			_check_victory()


## Punto 4: cualquier hormiga o amenaza puede dejar restos al morir (ver `AntSystem._kill` y
## `Spider.take_damage`). Único punto de entrada para que ambos no dupliquen la lógica de creación.
func spawn_corpse(p: Vector2, value: float) -> void:
	corpses.append(Corpse.new(p, value))


## Un cadáver desaparece solo si nadie lo recoge a tiempo (`corpse_decay_s`); una obrera ya lo deja
## en `food_value <= 0.0` al recogerlo, así que ese caso se limpia acá también, no hace falta que
## `AntSystem` sepa nada de esta lista más allá de leerla.
func _update_corpses(step_dt: float) -> void:
	if corpses.is_empty():
		return
	for i in range(corpses.size() - 1, -1, -1):
		var c := corpses[i]
		c.age += step_dt
		if c.food_value <= 0.0 or c.age >= cfg.corpse_decay_s:
			corpses.remove_at(i)


## Regla en `EraSystem` (sim/colony/): esto solo orquesta.
func _update_era() -> void:
	EraSystem.update_era(self)


## `first_population`: a partir de cuántas hormigas vivas puede aparecer la primera araña. El modo
## clásico la pasa solo al llegar a Colonia madura (`cfg.spider_first_population`); el incremental
## no tiene eras, así que usa su propio umbral (`cfg.inc_spider_first_population`) sin esperar nada
## más — ver dónde se llama esta función en `tick()`.
func _update_spider(step_dt: float, first_population: int) -> void:
	if spider.alive:
		spider.step(step_dt)
		return
	# Fase 6: en el modo Test solo se mueve/ataca si ya está viva (de que la hizo aparecer el
	# panel de pruebas); nunca aparece sola por población o por el temporizador de recurrencia —
	# el sandbox se controla a mano, no solo.
	if test_mode:
		return
	if spiders_spawned == 0 and ants.alive_count >= first_population:
		spider.spawn(1.0)
		spiders_spawned += 1
		spider_next_s = cfg.spider_interval_s
		notify("¡Una araña acecha en la superficie!")
		return
	if spiders_spawned > 0:
		spider_next_s -= step_dt
		if spider_next_s <= 0.0:
			spider.spawn(1.0 + cfg.spider_strength_growth * spiders_spawned)
			spiders_spawned += 1
			spider_next_s = cfg.spider_interval_s
			notify("¡Otra araña acecha en la superficie!")
	elif spider_next_s <= 0.0:
		spider_next_s = cfg.spider_interval_s


## Fase 5: igual forma que `_update_spider`, solo para la colonia con reina (no en incremental,
## igual que la condición de victoria — ver `tick()`): el ciempiés aparece después
## (`cfg.centipede_first_population` > `cfg.spider_first_population`) para que la amenaza escale.
func _update_centipede(step_dt: float) -> void:
	if centipede.alive:
		centipede.step(step_dt)
		return
	if test_mode:
		return
	if centipedes_spawned == 0 and ants.alive_count >= cfg.centipede_first_population:
		centipede.spawn(1.0)
		centipedes_spawned += 1
		centipede_next_s = cfg.centipede_interval_s
		notify("¡Un ciempiés se metió por los túneles!")
		return
	if centipedes_spawned > 0:
		centipede_next_s -= step_dt
		if centipede_next_s <= 0.0:
			centipede.spawn(1.0 + cfg.centipede_strength_growth * centipedes_spawned)
			centipedes_spawned += 1
			centipede_next_s = cfg.centipede_interval_s
			notify("¡Otro ciempiés se metió por los túneles!")
	elif centipede_next_s <= 0.0:
		centipede_next_s = cfg.centipede_interval_s


## Fase 7: igual forma que `_update_spider`/`_update_centipede`. `cfg.mantis_first_population`
## queda entre las otras dos para que la amenaza de superficie escale antes que el ciempiés.
func _update_mantis(step_dt: float) -> void:
	if mantis.alive:
		mantis.step(step_dt)
		return
	if test_mode:
		return
	if mantises_spawned == 0 and ants.alive_count >= cfg.mantis_first_population:
		mantis.spawn(1.0)
		mantises_spawned += 1
		mantis_next_s = cfg.mantis_interval_s
		notify("¡Una mantis acecha camuflada en la superficie!")
		return
	if mantises_spawned > 0:
		mantis_next_s -= step_dt
		if mantis_next_s <= 0.0:
			mantis.spawn(1.0 + cfg.mantis_strength_growth * mantises_spawned)
			mantises_spawned += 1
			mantis_next_s = cfg.mantis_interval_s
			notify("¡Otra mantis acecha camuflada en la superficie!")
	elif mantis_next_s <= 0.0:
		mantis_next_s = cfg.mantis_interval_s


func _check_game_over() -> void:
	if ants.alive[queen_id] == 0:
		game_over = true
		game_over_reason = "La reina murió."


## Regla en `EraSystem` (sim/colony/): esto solo orquesta. Ver ahí la nota de Fase 4 sobre de
## dónde sale `victory_survive_s`.
func _check_victory() -> void:
	EraSystem.check_victory(self)


# --- Clima --------------------------------------------------------------------------------------

func _update_weather() -> void:
	match weather:
		Weather.CLEAR:
			if rain_start_tick >= 0 and tick_count >= rain_start_tick - int(cfg.rain_warning_s * cfg.tick_rate):
				weather = Weather.WARNING
		Weather.WARNING:
			if tick_count >= rain_start_tick:
				_begin_rain()
		Weather.RAINING:
			if tick_count >= rain_end_tick:
				weather = Weather.CLEAR
				water.raining = false
				rain_start_tick = tick_count + int(cfg.rain_interval_s * cfg.tick_rate) if cfg.rain_auto else -1


func _begin_rain() -> void:
	weather = Weather.RAINING
	water.raining = true
	rains_started += 1
	rain_end_tick = tick_count + int(cfg.rain_duration_s * cfg.tick_rate)


## Segundos hasta que empiece la lluvia (o -1 si no hay una programada).
func rain_eta_s() -> float:
	if weather == Weather.RAINING or rain_start_tick < 0:
		return -1.0
	return maxf(0.0, (rain_start_tick - tick_count) * dt)


# --- Órdenes del jugador ---------------------------------------------------------------------------

func cmd_mark(x: int, y: int) -> bool:
	return world.mark(x, y)


func cmd_unmark(x: int, y: int) -> bool:
	return world.unmark(x, y)


func cmd_paint_food(x: int, y: int, value: float) -> bool:
	if not world.is_passable(x, y):
		return false
	food.set_max(y * world.w + x, value)
	food_painted = true
	return true


## Pinta cualquiera de las 5 feromonas sobre una celda pasable.
func cmd_paint_phero(field: PheromoneField, x: int, y: int, value: float) -> bool:
	if not world.is_passable(x, y):
		return false
	field.set_max(y * world.w + x, value)
	return true


func cmd_erase_phero(field: PheromoneField, x: int, y: int) -> void:
	if world.in_bounds(x, y):
		field.data[y * world.w + x] = 0.0


func cmd_assign_room(x: int, y: int, room_type: int) -> bool:
	return world.assign_room(x, y, room_type)


func cmd_clear_room(x: int, y: int) -> bool:
	return world.clear_room(x, y)


## Orden del jugador para mover a la reina a una celda pasable y conectada al nido (protegerla de
## la araña moviéndola lejos de la entrada, o acercarla a una cámara nueva). Devuelve si la orden
## se aceptó; no exige que la celda sea la cámara Real, cualquier túnel o superficie conectados al
## nido sirve. La reina sigue poniendo huevos igual mientras camina (ver README: desacoplado a
## propósito de dónde esté parada, solo importa que exista una Real válida en algún lado).
func cmd_move_queen(x: int, y: int) -> bool:
	if queen_id < 0 or ants.alive[queen_id] == 0:
		return false
	if not world.is_passable(x, y):
		return false
	var goal := y * world.w + x
	if fields.nest_dist[goal] >= NestDistanceField.FAR:
		return false
	queen_goal_cell = goal
	queen_goal_dist = fields.bfs_from([goal])
	return true


func cmd_nudge_caste(caste: int, amount: float) -> void:
	colony.nudge_target(caste, amount)


## Fase 5: lo usan los sliders de reparto de castas (valor absoluto, no relativo como la de arriba).
func cmd_set_caste_target(caste: int, value: float) -> void:
	colony.set_target(caste, value)


func cmd_force_rain() -> void:
	if weather != Weather.RAINING:
		_begin_rain()


## Fase 6: para el panel de pruebas, lo contrario de `cmd_force_rain` (sin reprogramar la próxima:
## en este modo la lluvia solo la dispara el jugador, nunca `cfg.rain_auto`).
func cmd_stop_rain() -> void:
	if weather == Weather.RAINING:
		water.raining = false
	weather = Weather.CLEAR
	rain_start_tick = -1


func cmd_add_ants(n: int) -> void:
	ants.add_ants(n)


## Fase 6: para el panel de pruebas, agregar cualquier casta a voluntad (la reina ya tiene la
## suya propia y no pasa por acá).
func cmd_add_caste_ants(caste: int, n: int) -> void:
	for k in n:
		ants.add_ant_at(_random_nest_cell(), caste)


## Fase 3: compra un huevo con comida; qué sale al nacer (obrera o soldado) es al azar.
func cmd_buy_egg() -> bool:
	return incremental and econ.buy_egg()


func cmd_cycle_auto_buy() -> void:
	if incremental:
		econ.cycle_auto()


func day_number() -> int:
	return DayNight.day_number(time_s(), cfg)


func is_night() -> bool:
	return DayNight.is_night(time_s(), cfg)


func cmd_force_spider() -> void:
	if queen_id >= 0 and not spider.alive:
		spider.spawn(1.0 + cfg.spider_strength_growth * spiders_spawned)
		spiders_spawned += 1
		spider_next_s = cfg.spider_interval_s  # si no, la siguiente se agenda casi de inmediato
		notify("¡Una araña acecha en la superficie!")


## Fase 5: para pruebas, igual que `cmd_force_spider`.
func cmd_force_centipede() -> void:
	if queen_id >= 0 and not centipede.alive:
		centipede.spawn(1.0 + cfg.centipede_strength_growth * centipedes_spawned)
		centipedes_spawned += 1
		centipede_next_s = cfg.centipede_interval_s
		notify("¡Un ciempiés se metió por los túneles!")


## Fase 7: para pruebas, igual que `cmd_force_spider`/`cmd_force_centipede`.
func cmd_force_mantis() -> void:
	if queen_id >= 0 and not mantis.alive:
		mantis.spawn(1.0 + cfg.mantis_strength_growth * mantises_spawned)
		mantises_spawned += 1
		mantis_next_s = cfg.mantis_interval_s
		notify("¡Una mantis acecha camuflada en la superficie!")


## Fase 6: para el panel de pruebas, hace desaparecer la amenaza sin dejar cadáver (es una acción
## de depuración, no un evento de juego real como morir o huir).
func cmd_remove_spider() -> void:
	spider.alive = false
	spider.state = Spider.State.GONE


func cmd_remove_centipede() -> void:
	centipede.alive = false
	centipede.state = Centipede.State.GONE


func cmd_remove_mantis() -> void:
	mantis.alive = false
	mantis.state = Mantis.State.GONE


## Resumen numérico del estado: sirve para comprobar la reproducibilidad.
func checksum() -> int:
	var h := 17
	for i in ants.count:
		if ants.alive[i] == 1:
			h = (h * 31 + int(ants.pos[i].x * 16.0) + int(ants.pos[i].y * 16.0) * 7 + ants.state[i]) & 0x7fffffff
	h = (h * 31 + leaves_stored * 13 + corpse_parts_stored * 19 + dug * 101 + deaths * 977) & 0x7fffffff
	h = (h * 31 + int(water.volume * 1000.0)) & 0x7fffffff
	# Punto 4: sin esto, dos partidas con cadáveres tirados en distinta posición/valor/edad daban la
	# misma huella (las pruebas de guardado/determinismo usan `checksum()` como única comprobación).
	for c in corpses:
		h = (h * 31 + int(c.pos.x * 16.0) + int(c.pos.y * 16.0) * 7 + int(c.food_value * 10.0)) & 0x7fffffff
	if queen_id >= 0:
		h = (h * 31 + int(colony.food * 10.0) + int(colony.water * 10.0) + brood.hatched * 7 + brood.died * 13) & 0x7fffffff
	if incremental:
		h = (h * 31 + econ.bought_eggs * 7 + total_leaves_left) & 0x7fffffff
	return h
