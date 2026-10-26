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
## Mismo motivo que `EraSystem`: evitar el ciclo de resolución.
const SeasonSystem = preload("res://sim/colony/season_system.gd")
## Fase 14: mismo motivo.
const TutorialLevel = preload("res://sim/colony/tutorial_level.gd")

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
## Fase 24: niebla bajo tierra. null salvo en "Juego normal" con mapa al azar (las pruebas, el
## Nivel 0 y los otros modos ven todo, como siempre).
var fog: Fog
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
## Fase 14: Nivel 0 (tutorial jugable). false salvo `spawn_tutorial_start()`; implica `incremental`.
var tutorial_level := false
var tutorial_battle_started := false
var econ: IncrementalEconomy
## Fase 9: mejoras de colonia del modo incremental (siempre existe, como el resto de los sistemas
## "siempre creados"; solo se puede comprar algo en `sim.incremental`, ver `Upgrades.can_buy`).
var upgrades: Upgrades
## Fase 10 (tutorial del modo incremental): cuántos huevos/mejoras se compraron en total. Solo lo
## usa `view/tutorial_view.gd` para saber si ya se cumplió ese paso, mismo espíritu que
## `food_painted`/`dug` para el tutorial de la colonia con reina.
var eggs_bought := 0
var upgrades_bought := 0

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
## Fase 9: estación actual del modo incremental (0..`SeasonSystem.SEASON_COUNT`-1) y la colonia
## rival que ataca al final de cada una — ver `sim/colony/season_system.gd`/`rival_colony.gd`.
## Reemplaza la condición de victoria de la Fase 8 (retirada): esto es lo que ahora decide
## `game_over`/`victory` para el modo incremental.
var season_index := 0
## Fase 17: día (`day_number()`) en que empezó la estación actual (ver `SeasonSystem.day_in_season`).
var season_start_day := 1
var rival_colony: RivalColony

var _terrain_seen := -1
var _storage_rooms_seen := -1
var _storage_terrain_seen := -1
var _jobs_seen := -1
var _dig_dirty := true
var _dig_was_wet := false
## Fase 22: sube unas veces por segundo mientras hay agua; los caminos que esquivan el agua
## (bolsones de hongos) se recalculan cuando cambia.
var water_epoch := 0


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
	fields.water = water
	fields.water_block = cfg.flee_level
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
	rival_colony = RivalColony.new(self)
	econ = IncrementalEconomy.new(self)
	upgrades = Upgrades.new(self)
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
##
## Fase 15 (`fresh_layout`, solo lo activa `main.gd` para "Juego normal" de verdad): el nido
## arranca cerrado, sin el pozo hacia la superficie — el jugador decide por dónde abrirlo — y los
## árboles se reparten al azar (cantidad y distancias). Opcional a propósito: las pruebas y el
## Nivel 0 siguen con el mapa de siempre (pozo abierto, árboles a distancias fijas), del que
## dependen sus resultados y el orden de las lecciones.
func spawn_incremental_start(fresh_layout := false) -> void:
	incremental = true
	if fresh_layout:
		_seal_shaft()
		_carve_side_chambers()
		_place_plants_random()
		enable_fog()
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


## Fase 14: Nivel 0. La misma colonia mínima que "Juego normal", sin lluvia automática ni araña
## (ver `tick()`) y con más comida al empezar; el final lo decide `TutorialLevel`, no las estaciones.
func spawn_tutorial_start() -> void:
	spawn_incremental_start()
	tutorial_level = true
	colony.food = cfg.tut_start_food
	rain_start_tick = -1


## Fase 14: dónde deja la reina un huevo nuevo: en una celda libre al lado suyo (no debajo). Antes
## nacía exactamente en su posición y el sprite del huevo, más chico, quedaba tapado por la reina:
## con la reina quieta en una cámara Real nueva, los huevos "no aparecían".
func egg_spot() -> Vector2:
	var q := ants.pos[queen_id]
	var cx := floori(q.x / cfg.cell_px)
	var cy := floori(q.y / cfg.cell_px)
	var free: Array[Vector2i] = []
	for k in 8:
		var nx: int = cx + AntSystem.DX[k]
		var ny: int = cy + AntSystem.DY[k]
		if ny >= cfg.surface_y and world.is_passable(nx, ny):
			free.append(Vector2i(nx, ny))
	if free.is_empty():
		return q
	var c := free[rng.randi() % free.size()]
	# Un poco de desorden dentro de la celda: varios huevos en la misma no se tapan entre sí.
	var jitter := Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.25, 0.25)) * cfg.cell_px
	return (Vector2(c) + Vector2(0.5, 0.5)) * cfg.cell_px + jitter


## Fase 14: la guía pide la batalla final del Nivel 0 (ver `sim/colony/tutorial_level.gd`).
func cmd_start_tutorial_battle() -> bool:
	return TutorialLevel.start_battle(self)


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


## Fase 15: rellena con tierra el pozo inicial (de la superficie a la cámara), dejando la cámara
## del nido cerrada. Las obreras no pueden salir hasta que el jugador marque por dónde cavar.
func _seal_shaft() -> void:
	for y in range(cfg.surface_y, cfg.surface_y + cfg.shaft_depth):
		var i := y * world.w + cfg.nest_x
		world.cells[i] = WorldGrid.Cell.DIRT
		world.changed.append(i)
	world.passable_version += 1
	world.jobs_version += 1
	fields.recompute_terrain()
	fields.recompute_dig()


## Fase 17: Juego normal arranca con las tres cámaras hechas: la Real (la cámara de siempre), una
## Guardería a la izquierda y un Almacén a la derecha, cada una unida a la Real por un pasillo corto.
## Así la comida tiene a dónde ir desde el principio y los zánganos a dónde llevar los huevos. Las
## rocas nunca aparecen tan cerca del nido (`WorldGrid.generate`), así que siempre caben.
func _carve_side_chambers() -> void:
	var w := world.w
	var half := cfg.chamber_w / 2
	var y0 := cfg.surface_y + cfg.shaft_depth
	var mid := y0 + cfg.chamber_h / 2
	for side in [-1, 1]:
		var room_type := WorldGrid.Room.NURSERY if side < 0 else WorldGrid.Room.STORAGE
		# Pasillo de 2 celdas desde el borde de la Real.
		for k in range(1, 3):
			var cx: int = cfg.nest_x + side * (half + k)
			world.cells[mid * w + cx] = WorldGrid.Cell.TUNNEL
			world.changed.append(mid * w + cx)
		# Cámara de 5 x `chamber_h` a continuación.
		for k in range(3, 8):
			var cx2: int = cfg.nest_x + side * (half + k)
			for y in range(y0, y0 + cfg.chamber_h):
				var i := y * w + cx2
				world.cells[i] = WorldGrid.Cell.TUNNEL
				world.room[i] = room_type
				world.changed.append(i)
	world.rooms_version += 1
	world.passable_version += 1
	fields.recompute_terrain()
	fields.recompute_dig()


## Fase 15: árboles al azar — cantidad, lado y distancia al nido sin un patrón fijo, solo con una
## separación mínima para que no se encimen y sin tapar la superficie justo encima del nido.
func _place_plants_random() -> void:
	plants.clear()
	total_leaves_left = 0
	var n := cfg.plant_count + rng.randi_range(-2, 3)
	var used: Array[int] = []
	var tries := 0
	while plants.size() < n and tries < 400:
		tries += 1
		var x := rng.randi_range(3, world.w - 4)
		if absi(x - cfg.nest_x) < 6:
			continue
		var clash := false
		for ux in used:
			if absi(ux - x) < 4:
				clash = true
				break
		if clash:
			continue
		used.append(x)
		var leaves := cfg.leaves_per_plant + rng.randi_range(-10, 15)
		plants.append(Plant.new(Vector2i(x, cfg.surface_y - 1), leaves))
		total_leaves_left += leaves
	_place_giants(used)
	_carve_mushroom_pockets()
	econ.known_plants = PackedByteArray()
	econ.known_plants.resize(plants.size())


## Fase 19: 1-2 árboles gigantes, lejos del nido (`giant_min_dist`), con mucho más para cosechar.
func _place_giants(used: Array[int]) -> void:
	var n := rng.randi_range(cfg.giant_count_min, cfg.giant_count_max)
	var placed := 0
	var tries := 0
	while placed < n and tries < 300:
		tries += 1
		var x := rng.randi_range(4, world.w - 5)
		if absi(x - cfg.nest_x) < cfg.giant_min_dist:
			continue
		var clash := false
		for ux in used:
			if absi(ux - x) < 7:
				clash = true
				break
		if clash:
			continue
		used.append(x)
		var leaves := int(round(cfg.leaves_per_plant * cfg.giant_leaves_mult))
		var g := Plant.new(Vector2i(x, cfg.surface_y - 1), leaves)
		g.kind = Plant.Kind.GIANT
		plants.append(g)
		total_leaves_left += leaves
		placed += 1


## Fase 19: cuevitas cerradas en la primera capa de tierra con un bolsón de hongos cada una. Se
## abren (TUNNEL) pero sin conexión al nido: hasta que el jugador cave hasta ahí, nadie llega.
func _carve_mushroom_pockets() -> void:
	var n := rng.randi_range(cfg.mushroom_pockets_min, cfg.mushroom_pockets_max)
	var top := cfg.surface_y + 5
	var bottom := cfg.surface_y + int((world.h - cfg.surface_y) * 0.28)
	var taken: Array[Rect2i] = []
	var tries := 0
	while taken.size() < n and tries < 400:
		tries += 1
		var center := Vector2i(rng.randi_range(6, world.w - 7), rng.randi_range(top, bottom))
		var cells := _pocket_shape(center)
		var box := _bounds(cells)
		if not _pocket_fits(cells, box, taken):
			continue
		taken.append(box)
		_carve_pocket(cells)
	world.passable_version += 1
	world.jobs_version += 1
	fields.recompute_terrain()
	fields.recompute_dig()


## Fase 20: forma de una cueva de hongos — un óvalo irregular (no un rectángulo), más ancho que
## alto y con el piso más parejo que el techo, para que los hongos tengan dónde pararse.
func _pocket_shape(center: Vector2i) -> Array[Vector2i]:
	var rx := rng.randf_range(3.2, 4.4)
	var ry := rng.randf_range(1.5, 2.1)
	var out: Array[Vector2i] = []
	for dy in range(-3, 4):
		for dx in range(-5, 6):
			var fx := float(dx) / rx
			var fy := float(dy) / ry
			# Techo más irregular que el piso.
			var wobble := rng.randf_range(-0.25, 0.3) if dy < 0 else rng.randf_range(-0.08, 0.12)
			if fx * fx + fy * fy <= 1.0 + wobble:
				out.append(center + Vector2i(dx, dy))
	return out


static func _bounds(cells: Array[Vector2i]) -> Rect2i:
	var r := Rect2i(cells[0], Vector2i.ONE)
	for c in cells:
		r = r.expand(c).expand(c + Vector2i.ONE)
	return r


## Cabe si no pisa roca, no se acerca a otra cueva y no hay nada abierto (nido, cámaras, túneles) a
## menos de 3 celdas: tiene que estar cerrada, para que haya que cavar hasta ella.
func _pocket_fits(cells: Array[Vector2i], box: Rect2i, taken: Array[Rect2i]) -> bool:
	if box.position.y <= cfg.surface_y + 2 or box.end.y >= world.h - 2 or box.position.x < 2 or box.end.x > world.w - 2:
		return false
	for t in taken:
		if t.grow(4).intersects(box):
			return false
	for c in cells:
		if world.type_at(c.x, c.y) == WorldGrid.Cell.ROCK:
			return false
	for yy in range(box.position.y - 3, box.end.y + 3):
		for xx in range(box.position.x - 3, box.end.x + 3):
			if world.in_bounds(xx, yy) and yy >= cfg.surface_y and world.is_open(xx, yy):
				return false
	return true


## Abre la cueva y pone el bolsón de hongos con su piso (las celdas abiertas con tierra debajo).
func _carve_pocket(cells: Array[Vector2i]) -> void:
	for c in cells:
		var i := c.y * world.w + c.x
		world.cells[i] = WorldGrid.Cell.TUNNEL
		world.changed.append(i)
	var floor_cells: Array[Vector2i] = []
	for c in cells:
		if not world.is_open(c.x, c.y + 1):
			floor_cells.append(c)
	floor_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
	var mush := Plant.new(floor_cells[floor_cells.size() / 2], cfg.mushroom_pieces)
	mush.kind = Plant.Kind.MUSHROOM
	mush.hue = rng.randi_range(0, 2)
	mush.pocket = cells
	plants.append(mush)
	total_leaves_left += cfg.mushroom_pieces


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
		if fog != null:
			fog.update(world, fields, cfg.surface_y)
		_dig_dirty = true
	if world.jobs_version != _jobs_seen:
		_jobs_seen = world.jobs_version
		_dig_dirty = true
	# Fase 21: `dig_dist` esquiva el agua profunda; mientras haya agua (y una vez más cuando se va)
	# hay que recalcularlo, porque el agua sube y baja sin que cambie el terreno.
	var wet := water.volume > 0.0
	if wet or _dig_was_wet:
		_dig_dirty = true
	_dig_was_wet = wet
	if _dig_dirty and tick_count % cfg.field_refresh_ticks == 0:
		_dig_dirty = false
		fields.recompute_dig()
		# Fase 22: los caminos a los bolsones de hongos (`AntSystem.mushroom_route`) también esquivan
		# el agua: se renuevan solos cuando cambia esta época, a la par de `dig_dist`.
		water_epoch += 1
	rooms.maybe_recompute()
	# Fase 17: en Juego normal la comida va al Almacén (ver `AntSystem._use_storage`).
	if incremental and (world.rooms_version != _storage_rooms_seen or fields.recomputes != _storage_terrain_seen):
		_storage_rooms_seen = world.rooms_version
		_storage_terrain_seen = fields.recomputes
		fields.recompute_storage()
	_update_corpses(dt)
	ants.tick()
	# Todo lo que sigue solo existe si hay una colonia completa (ver nota en la cabecera).
	if incremental:
		# Fase 3: sin eras (la araña ya sí aparece, con su propio umbral de población).
		econ.tick(dt)
		econ.regrow_plants(dt)
		brood.tick(dt)
		if tick_count % 3 == 0 and not tutorial_level:
			_update_spider(dt * 3.0, cfg.inc_spider_first_population)
		_check_game_over()
		# Fase 9: estaciones + colonia rival — decide game_over/victory de este modo (reemplaza la
		# condición de la Fase 8, retirada). Fase 14: el Nivel 0 tiene su propio final.
		if tutorial_level:
			TutorialLevel.update(self)
		else:
			SeasonSystem.update(self)
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
	var r := _threat_cycle(spider, step_dt, spiders_spawned, spider_next_s, first_population,
		cfg.spider_interval_s, cfg.spider_strength_growth,
		"¡Una araña acecha en la superficie!", "¡Otra araña acecha en la superficie!")
	spiders_spawned = r[0]
	spider_next_s = r[1]


## Fase 5: el ciempiés aparece después (`cfg.centipede_first_population` >
## `cfg.spider_first_population`) para que la amenaza escale. Solo en la colonia con reina.
func _update_centipede(step_dt: float) -> void:
	var r := _threat_cycle(centipede, step_dt, centipedes_spawned, centipede_next_s, cfg.centipede_first_population,
		cfg.centipede_interval_s, cfg.centipede_strength_growth,
		"¡Un ciempiés se metió por los túneles!", "¡Otro ciempiés se metió por los túneles!")
	centipedes_spawned = r[0]
	centipede_next_s = r[1]


## Fase 7: `cfg.mantis_first_population` queda entre las otras dos para que la amenaza de
## superficie escale antes que el ciempiés.
func _update_mantis(step_dt: float) -> void:
	var r := _threat_cycle(mantis, step_dt, mantises_spawned, mantis_next_s, cfg.mantis_first_population,
		cfg.mantis_interval_s, cfg.mantis_strength_growth,
		"¡Una mantis acecha camuflada en la superficie!", "¡Otra mantis acecha camuflada en la superficie!")
	mantises_spawned = r[0]
	mantis_next_s = r[1]


## Ciclo de vida común de las amenazas (antes copiado tres veces, una por amenaza): si está viva,
## actúa; si no, la primera aparece al llegar a `first_population` y las siguientes cada
## `interval` segundos, cada una más fuerte (`growth`). Devuelve `[spawned, next_s]` actualizados
## (los contadores siguen siendo variables separadas por amenaza: el guardado las lee por nombre).
## `threat` sin tipar: `Spider`, `Centipede` y `Mantis` no comparten clase base, solo la forma
## (`.alive`, `.step()`, `.spawn()`).
func _threat_cycle(threat, step_dt: float, spawned: int, next_s: float, first_population: int,
		interval: float, growth: float, first_msg: String, again_msg: String) -> Array:
	if threat.alive:
		threat.step(step_dt)
		return [spawned, next_s]
	# Fase 6: en el modo Test solo se mueve/ataca si ya está viva (la hizo aparecer el panel de
	# pruebas); nunca aparece sola por población o por el temporizador — el sandbox va a mano.
	if test_mode:
		return [spawned, next_s]
	if spawned == 0 and ants.alive_count >= first_population:
		threat.spawn(1.0)
		notify(first_msg)
		return [1, interval]
	if spawned > 0:
		next_s -= step_dt
		if next_s <= 0.0:
			threat.spawn(1.0 + growth * spawned)
			notify(again_msg)
			return [spawned + 1, interval]
	elif next_s <= 0.0:
		next_s = interval
	return [spawned, next_s]


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
				rain_start_tick = tick_count + int(_rain_interval_s() * cfg.tick_rate) if cfg.rain_auto else -1


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
	# Fase 14: lo que pinta el jugador en Comida y Hogar (los rastros a seguir) no se desgasta;
	# Peligro/Ataque/Evacuar siguen siendo avisos que se apagan solos, a propósito.
	if field == food or field == home:
		field.paint(y * world.w + x, value)
	else:
		field.set_max(y * world.w + x, value)
	# Fase 14: el pincel real (`main_input_tools.gd`) pinta por aquí, no por `cmd_paint_food`, así
	# que el objetivo "pinta Comida" del tutorial nunca se cumplía jugando.
	if field == food:
		food_painted = true
	return true


func cmd_erase_phero(field: PheromoneField, x: int, y: int) -> void:
	if world.in_bounds(x, y):
		field.clear_cell(y * world.w + x)


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
	var ok := incremental and econ.buy_egg()
	if ok:
		eggs_bought += 1
	return ok


## Fase 9: compra un nivel de mejora de colonia (`Upgrades.Stat`) con comida.
func cmd_buy_upgrade(stat: int) -> bool:
	var ok := incremental and upgrades.buy(stat)
	if ok:
		upgrades_bought += 1
	return ok


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


## Fase 23: segundos hasta la próxima lluvia. En Juego normal, al azar entre 1,5 y 2,5 días (antes
## llovía casi todos los días); en los demás modos, el intervalo fijo de siempre.
func _rain_interval_s() -> float:
	if incremental:
		return rng.randf_range(cfg.inc_rain_interval_min_s, cfg.inc_rain_interval_max_s)
	return cfg.rain_interval_s


## Fase 24: activa la niebla bajo tierra (Juego normal con mapa al azar; también al cargar una
## partida que la tenía). Se calcula del terreno actual.
func enable_fog() -> void:
	fog = Fog.new(world.w * world.h)
	fog.update(world, fields, cfg.surface_y)


## Fase 24: ¿la colonia ya descubrió este bolsón de hongos? Sin niebla, siempre.
func is_discovered(pl: Plant) -> bool:
	return fog == null or fog.any_revealed(pl.pocket, world.w)
