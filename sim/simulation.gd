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
var rooms: RoomSystem
var colony: Colony
var brood: BroodSystem
var spider: Spider
## Fase 3: false salvo que se llame a `spawn_incremental_start()`.
var incremental := false
var econ: IncrementalEconomy

var leaves_stored := 0
var delivered := 0
var deaths := 0
var dug := 0
var dig_violations := 0
var stuck_recoveries := 0
var total_leaves_left := 0

var weather := Weather.CLEAR
var rain_start_tick := -1
var rain_end_tick := -1
var rains_started := 0

## Fase 1: -1 mientras no haya colonia completa (ver nota arriba).
var queen_id := -1
var era := Era.FOUNDATION
var game_over := false
var game_over_reason := ""
var spiders_spawned := 0
var spider_next_s := 0.0
var notifications: Array[String] = []
const MAX_NOTIFICATIONS := 5

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
	ants = AntSystem.new(self)
	var cell := Vector2i(cfg.nest_x, cfg.surface_y + cfg.shaft_depth + 1)
	queen_id = ants.add_ant_at(cell, CasteDefs.Caste.QUEEN)
	for k in cfg.inc_start_workers:
		ants.add_ant_at(_random_nest_cell(), CasteDefs.Caste.WORKER)
	for k in cfg.inc_start_soldiers:
		ants.add_ant_at(_random_nest_cell(), CasteDefs.Caste.SOLDIER)
	for k in cfg.inc_start_larvae:
		brood.lay_egg(CasteDefs.Caste.WORKER)
		brood.stage[brood.stage.size() - 1] = BroodSystem.Stage.LARVA
		brood.timer[brood.timer.size() - 1] = cfg.larva_time_s
	colony.food = cfg.inc_start_food
	colony.water = 0.0
	if cfg.rain_auto:
		rain_start_tick = int(cfg.inc_rain_first_s * cfg.tick_rate)
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
		_apply_drainage(dt * cfg.water_step_ticks)
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
	ants.tick()
	# Todo lo que sigue solo existe si hay una colonia completa (ver nota en la cabecera).
	if incremental:
		# Fase 3: sin araña ni eras; la economía es solo comida.
		econ.tick(dt)
		econ.regrow_plants(dt)
		brood.tick(dt)
		_check_game_over()
	elif queen_id >= 0:
		colony.tick(self, dt)
		brood.tick(dt)
		_update_era()
		if tick_count % 3 == 0:
			_update_spider(dt * 3.0)
		_check_game_over()


func _apply_drainage(step_dt: float) -> void:
	if rooms.counts[WorldGrid.Room.DRAIN] <= 0:
		return
	var rate := rooms.capacity(WorldGrid.Room.DRAIN, cfg.drain_rate_per_cell) * step_dt
	if rate <= 0.0:
		return
	for i in world.room.size():
		if world.room[i] == WorldGrid.Room.DRAIN and water.level[i] > 0.0:
			var take := minf(water.level[i], rate)
			water.level[i] -= take
			water.wet[i] = water.level[i] > 0.0


func _update_era() -> void:
	var pop := ants.alive_count
	var new_era := Era.FOUNDATION
	if pop >= cfg.era3_population:
		new_era = Era.MATURE
	elif pop >= cfg.era2_population:
		new_era = Era.YOUNG
	if new_era != era:
		era = new_era
		match era:
			Era.YOUNG:
				notify("Nueva era: Colonia joven. Jardín de hongos y soldados disponibles.")
			Era.MATURE:
				notify("Nueva era: Colonia madura. Drenaje, Peligro, Ataque, Evacuar y la araña.")


func _update_spider(step_dt: float) -> void:
	if era != Era.MATURE:
		return
	if spider.alive:
		spider.step(step_dt)
		return
	if spiders_spawned == 0 and ants.alive_count >= cfg.spider_first_population:
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


func _check_game_over() -> void:
	if ants.alive[queen_id] == 0:
		game_over = true
		game_over_reason = "La reina murió."


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


func cmd_nudge_caste(caste: int, amount: float) -> void:
	colony.nudge_target(caste, amount)


func cmd_force_rain() -> void:
	if weather != Weather.RAINING:
		_begin_rain()


func cmd_add_ants(n: int) -> void:
	ants.add_ants(n)


## Fase 3: compra una hormiga de la casta dada (obrera o soldado) con comida.
func cmd_buy(caste: int) -> bool:
	return incremental and econ.buy(caste)


func cmd_cycle_auto_buy() -> void:
	if incremental:
		econ.cycle_auto()


func day_number() -> int:
	return DayNight.day_number(time_s(), cfg)


func is_night() -> bool:
	return DayNight.is_night(time_s(), cfg)


func cmd_force_spider() -> void:
	if queen_id >= 0 and not incremental and not spider.alive:
		spider.spawn(1.0 + cfg.spider_strength_growth * spiders_spawned)
		spiders_spawned += 1
		spider_next_s = cfg.spider_interval_s  # si no, la siguiente se agenda casi de inmediato
		notify("¡Una araña acecha en la superficie!")


## Resumen numérico del estado: sirve para comprobar la reproducibilidad.
func checksum() -> int:
	var h := 17
	for i in ants.count:
		if ants.alive[i] == 1:
			h = (h * 31 + int(ants.pos[i].x * 16.0) + int(ants.pos[i].y * 16.0) * 7 + ants.state[i]) & 0x7fffffff
	h = (h * 31 + leaves_stored * 13 + dug * 101 + deaths * 977) & 0x7fffffff
	h = (h * 31 + int(water.volume * 1000.0)) & 0x7fffffff
	if queen_id >= 0:
		h = (h * 31 + int(colony.food * 10.0) + int(colony.water * 10.0) + brood.hatched * 7 + brood.died * 13) & 0x7fffffff
	if incremental:
		h = (h * 31 + econ.bought[CasteDefs.Caste.WORKER] * 7 + econ.bought[CasteDefs.Caste.SOLDIER] * 11 + total_leaves_left) & 0x7fffffff
	return h
