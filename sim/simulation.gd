class_name Simulation
extends RefCounted
## Orquesta todos los sistemas en un orden fijo. No sabe nada de pantallas ni de nodos.
## Un tick = 1 / cfg.tick_rate segundos. Toda la aleatoriedad sale de `rng` (con semilla).

enum Weather { CLEAR, WARNING, RAINING }

var cfg: SimConfig
var rng := RandomNumberGenerator.new()
var tick_count := 0
var dt := 0.05
var world: WorldGrid
var food: PheromoneField
var home: PheromoneField
var water: WaterSim
var fields: NestDistanceField
var ants: AntSystem
var plants: Array[Plant] = []

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
	water = WaterSim.new(world)
	fields = NestDistanceField.new(world)
	_place_plants()
	fields.recompute_terrain()
	fields.recompute_dig()
	_terrain_seen = world.passable_version
	_jobs_seen = world.jobs_version
	ants = AntSystem.new(self)
	ants.add_ants(cfg.initial_ants)
	if cfg.rain_auto:
		rain_start_tick = int(cfg.rain_first_s * cfg.tick_rate)


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


func tick() -> void:
	tick_count += 1
	_update_weather()
	if tick_count % cfg.water_step_ticks == 0:
		water.step(dt * cfg.water_step_ticks)
	if tick_count % cfg.pheromone_step_ticks == 0:
		var mult := cfg.rain_decay_mult if weather == Weather.RAINING else 1.0
		var step_dt := dt * cfg.pheromone_step_ticks
		food.decay(step_dt, mult)
		home.decay(step_dt, mult)
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
	ants.tick()


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


func cmd_force_rain() -> void:
	if weather != Weather.RAINING:
		_begin_rain()


func cmd_add_ants(n: int) -> void:
	ants.add_ants(n)


## Resumen numérico del estado: sirve para comprobar la reproducibilidad.
func checksum() -> int:
	var h := 17
	for i in ants.count:
		if ants.alive[i] == 1:
			h = (h * 31 + int(ants.pos[i].x * 16.0) + int(ants.pos[i].y * 16.0) * 7 + ants.state[i]) & 0x7fffffff
	h = (h * 31 + leaves_stored * 13 + dug * 101 + deaths * 977) & 0x7fffffff
	h = (h * 31 + int(water.volume * 1000.0)) & 0x7fffffff
	return h
