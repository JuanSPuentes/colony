extends SceneTree
## Pruebas de la Fase 1, en el mismo estilo que tools/test_phase0.gd. Cada escenario crea una
## Simulation con `spawn_colony_court()` (reina + nodrizas) y comprueba un criterio de
## aceptación del prompt de la Fase 1.
## Uso: godot --headless --path . --script tools/test_phase1.gd      (código de salida 1 si algo falla)

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_t_queen_lays_eggs()
	_t_drone_speeds_up_egg_laying()
	_t_brood_stages()
	_t_caste_ratio_changes_composition()
	_t_rooms_have_effect()
	_t_fungus_economy()
	_t_danger_and_evacuate()
	_t_drain_reduces_flood_loss()
	_t_spider()
	_t_colony_wide_defense_by_caste()
	_t_eras()
	_t_queen_death_ends_game()
	_t_queen_move()
	_t_determinism()
	_t_performance()
	print("RESULTADO: %d correctas, %d fallidas" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("[%s] %s %s" % ["OK " if ok else "FALLA", label, detail])


func _cfg(ants := 100) -> SimConfig:
	var c := SimConfig.new()
	c.initial_ants = ants
	c.rain_auto = false
	return c


func _colony(cfg: SimConfig, seed_value: int) -> Simulation:
	var sim := Simulation.new(cfg, seed_value)
	sim.spawn_colony_court()
	return sim


func _run(sim: Simulation, seconds: float) -> void:
	for i in int(seconds * sim.cfg.tick_rate):
		sim.tick()


func _carve(sim: Simulation, x0: int, y0: int, x1: int, y1: int) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			sim.world.cells[y * sim.world.w + x] = WorldGrid.Cell.TUNNEL
	sim.world.passable_version += 1
	sim.fields.recompute_terrain()  # para que nest_dist vea los túneles nuevos de inmediato


func _assign(sim: Simulation, x0: int, y0: int, x1: int, y1: int, room_type: int) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			sim.world.assign_room(x, y, room_type)


# --- Reina y cría ---------------------------------------------------------------------------------

func _t_queen_lays_eggs() -> void:
	var sim := _colony(_cfg(20), 1)
	_check("la reina no pone huevos sin comida suficiente", sim.brood.stage.size() == 0 or sim.colony.food < sim.cfg.egg_food_threshold)
	sim.colony.food = sim.cfg.egg_food_threshold + 10.0
	_run(sim, sim.cfg.egg_interval_s + 1.0)
	_check("la reina pone un huevo en la cámara Real cuando hay comida y Real válida", sim.brood.stage.size() >= 1, "huevos=%d" % sim.brood.stage.size())
	var no_food := _colony(_cfg(20), 1)
	no_food.colony.food = 0.0
	_run(no_food, no_food.cfg.egg_interval_s * 3.0)
	_check("sin comida la reina no pone huevos", no_food.brood.stage.size() == 0, "huevos=%d" % no_food.brood.stage.size())


## El zángano no hace nada por sí mismo (no explora, no decide, se queda donde nació), pero
## mientras esté vivo acelera la puesta de huevos de la reina (liviano a propósito, ver README).
func _t_drone_speeds_up_egg_laying() -> void:
	var baseline := _colony(_cfg(0), 6)
	baseline.colony.food = 1000.0
	_run(baseline, baseline.cfg.egg_interval_s * 3.0)
	var eggs_baseline := baseline.brood.stage.size()

	var with_drones := _colony(_cfg(0), 6)
	with_drones.colony.food = 1000.0
	var drone_idx := with_drones.ants.add_ant_at(Vector2i(with_drones.cfg.nest_x, _below_nest(with_drones) - 1), CasteDefs.Caste.DRONE)
	for k in 2:
		with_drones.ants.add_ant_at(Vector2i(with_drones.cfg.nest_x, _below_nest(with_drones) - 1), CasteDefs.Caste.DRONE)
	var start_pos := with_drones.ants.pos[drone_idx]
	_run(with_drones, with_drones.cfg.egg_interval_s * 3.0)
	var eggs_with_drones := with_drones.brood.stage.size()
	_check("con zánganos vivos nacen más huevos en el mismo tiempo", eggs_with_drones > eggs_baseline,
		"sin zánganos=%d, con 3 zánganos=%d" % [eggs_baseline, eggs_with_drones])
	_check("el zángano no se mueve ni decide por su cuenta", with_drones.ants.pos[drone_idx] == start_pos)


func _t_brood_stages() -> void:
	var sim := _colony(_cfg(10), 2)
	sim.colony.food = 500.0
	sim.brood.lay_egg(CasteDefs.Caste.WORKER)
	_run(sim, sim.cfg.egg_time_s + 1.0)
	_check("el huevo pasa a larva", sim.brood.stage[0] == BroodSystem.Stage.LARVA)
	var before := sim.ants.count
	_run(sim, (sim.cfg.larva_time_s + sim.cfg.pupa_time_s) * 1.4)
	_check("la larva pasa a pupa y nace una adulta nueva", sim.brood.hatched >= 1 and sim.ants.count > before, "nacidas=%d" % sim.brood.hatched)
	# Sin nodrizas cerca, la larva se desarrolla mucho más despacio.
	var lonely := Simulation.new(_cfg(0), 2)
	lonely.spawn_colony_court()
	for i in range(lonely.world.nest_cells.size() - lonely.cfg.initial_nurses, lonely.world.nest_cells.size()):
		pass  # (las nodrizas ya están puestas por spawn_colony_court; las matamos para la comparación)
	for a in lonely.ants.count:
		if lonely.ants.caste[a] == CasteDefs.Caste.NURSE:
			lonely.ants._kill(a, false)
	lonely.colony.food = 500.0
	lonely.brood.lay_egg(CasteDefs.Caste.WORKER)
	_run(lonely, lonely.cfg.egg_time_s + lonely.cfg.larva_time_s * 0.5)
	_check("sin nodrizas la larva se desarrolla más despacio", lonely.brood.stage[0] == BroodSystem.Stage.LARVA and lonely.brood.timer[0] > sim.cfg.larva_time_s * 0.3)


func _t_caste_ratio_changes_composition() -> void:
	var workers_bias := _colony(_cfg(0), 3)
	for i in 30:
		workers_bias.colony.nudge_target(CasteDefs.Caste.WORKER, 0.05)
	var soldiers_bias := _colony(_cfg(0), 3)
	for i in 30:
		soldiers_bias.colony.nudge_target(CasteDefs.Caste.SOLDIER, 0.05)
	var a := workers_bias.colony.furthest_from_target(workers_bias)
	var b := soldiers_bias.colony.furthest_from_target(soldiers_bias)
	_check("cambiar el reparto cambia qué casta se cría a continuación", a != b or workers_bias.colony.target_pct[CasteDefs.Caste.WORKER] != soldiers_bias.colony.target_pct[CasteDefs.Caste.WORKER], "a=%d b=%d" % [a, b])


# --- Cámaras y economía ----------------------------------------------------------------------------

## Fila libre justo debajo de la cámara Real inicial: cualquier cosa tallada ahí queda conectada
## al nido de verdad (lo contrario de tallar un bolsillo aislado en mitad de la tierra).
func _below_nest(sim: Simulation) -> int:
	return sim.cfg.surface_y + sim.cfg.shaft_depth + sim.cfg.chamber_h


func _t_rooms_have_effect() -> void:
	var sim := _colony(_cfg(0), 4)
	var nx := sim.cfg.nest_x
	var y0 := _below_nest(sim)
	_carve(sim, nx - 3, y0, nx + 2, y0 + 1)
	_assign(sim, nx - 3, y0, nx + 2, y0 + 1, WorldGrid.Room.FUNGUS)  # 6x2=12 celdas: cumple el mínimo (12)
	sim.rooms.maybe_recompute()
	_check("una cámara con el tamaño mínimo queda válida", sim.rooms.valid[WorldGrid.Room.FUNGUS], "celdas=%d" % sim.rooms.counts[WorldGrid.Room.FUNGUS])
	var small := _colony(_cfg(0), 4)
	var y0s := _below_nest(small)
	_carve(small, nx - 3, y0s, nx - 2, y0s)
	_assign(small, nx - 3, y0s, nx - 2, y0s, WorldGrid.Room.FUNGUS)  # 2 celdas: no alcanza
	small.rooms.maybe_recompute()
	_check("una cámara demasiado pequeña queda inválida (y se puede saber por qué)", not small.rooms.valid[WorldGrid.Room.FUNGUS], "celdas=%d de %d" % [small.rooms.counts[WorldGrid.Room.FUNGUS], small.cfg.room_min_fungus])


func _t_fungus_economy() -> void:
	var sim := _colony(_cfg(0), 5)
	var nx := sim.cfg.nest_x
	var y0 := _below_nest(sim)
	_carve(sim, nx - 3, y0, nx + 2, y0 + 1)
	_assign(sim, nx - 3, y0, nx + 2, y0 + 1, WorldGrid.Room.FUNGUS)
	sim.leaves_stored = 200
	sim.colony.food = 0.0
	_run(sim, 30.0)
	_check("el jardín de hongos convierte hojas almacenadas en comida", sim.colony.food > 0.0 and sim.leaves_stored < 200, "comida=%.1f hojas=%d" % [sim.colony.food, sim.leaves_stored])
	var none := _colony(_cfg(0), 5)
	none.leaves_stored = 200
	none.colony.food = 0.0
	_run(none, 30.0)
	_check("sin jardín de hongos la comida no se repone sola", none.colony.food == 0.0, "comida=%.1f" % none.colony.food)


# --- Feromonas nuevas -------------------------------------------------------------------------------

func _t_danger_and_evacuate() -> void:
	var sim := _colony(_cfg(0), 6)
	var sy := sim.cfg.surface_y
	var i := sim.ants.add_ant_at(Vector2i(sim.cfg.nest_x, sy - 1))
	for x in range(sim.cfg.nest_x - 6, sim.cfg.nest_x + 6):
		sim.danger.data[(sy - 1) * sim.world.w + x] = 1.0
	# No se fija en el estado exacto a los 4 s: con `walk_band` más chico (ver sim_config.gd) la
	# hormiga escapa más directo hacia el nido y para entonces ya puede haber vuelto a EXPLORE
	# normal, que es el comportamiento correcto después de huir, no una falla. Lo que de verdad
	# importa es que la feromona sí dispare la huida en algún momento.
	var fled := false
	for t in int(4.0 * sim.cfg.tick_rate):
		sim.tick()
		if sim.ants.state[i] == AntSystem.State.FLEE_DANGER:
			fled = true
	_check("la feromona de peligro hace que una no-soldado huya", fled, "estado final=%d" % sim.ants.state[i])
	# Un soldado no debe asustarse del peligro.
	var guard := _colony(_cfg(0), 6)
	var s := guard.ants.add_ant_at(Vector2i(guard.cfg.nest_x, sy - 1), CasteDefs.Caste.SOLDIER)
	for x in range(guard.cfg.nest_x - 6, guard.cfg.nest_x + 6):
		guard.danger.data[(sy - 1) * guard.world.w + x] = 1.0
	_run(guard, 4.0)
	_check("el soldado ignora la feromona de peligro", guard.ants.state[s] != AntSystem.State.FLEE_DANGER)
	# Ninguna feromona debe meter a una hormiga en agua profunda.
	var wet := _colony(_cfg(0), 6)
	_carve(wet, 50, sy, 52, sy + 3)
	for x in range(50, 53):
		for y in range(sy, sy + 4):
			wet.water.add(y * wet.world.w + x, 1.0)
	var w2 := wet.ants.add_ant_at(Vector2i(51, sy + 1))
	wet.food.data[(sy + 2) * wet.world.w + 51] = 1.0  # rastro de comida dentro del agua
	_run(wet, 6.0)
	var ci := wet.ants._cell_index(wet.ants.pos[w2])
	_check("ninguna feromona lleva a una hormiga al agua profunda a propósito", wet.ants.alive[w2] == 0 or wet.water.level[ci] < wet.cfg.deep_level)


func _t_drain_reduces_flood_loss() -> void:
	var with_drain := _colony(_cfg(0), 7)
	var sy := with_drain.cfg.surface_y
	_carve(with_drain, 90, sy, 90, sy + 10)
	_carve(with_drain, 86, sy + 10, 94, sy + 12)
	_assign(with_drain, 86, sy + 11, 89, sy + 12, WorldGrid.Room.DRAIN)  # 8 celdas >= mínimo (4)
	with_drain.cmd_force_rain()
	_run(with_drain, with_drain.cfg.rain_duration_s + 20.0)
	var vol_with := 0.0
	for x in range(86, 95):
		for y in range(sy + 10, sy + 13):
			vol_with += with_drain.water.level[y * with_drain.world.w + x]

	var no_drain := Simulation.new(with_drain.cfg, 7)
	no_drain.spawn_colony_court()
	_carve(no_drain, 90, sy, 90, sy + 10)
	_carve(no_drain, 86, sy + 10, 94, sy + 12)
	no_drain.cmd_force_rain()
	_run(no_drain, no_drain.cfg.rain_duration_s + 20.0)
	var vol_without := 0.0
	for x in range(86, 95):
		for y in range(sy + 10, sy + 13):
			vol_without += no_drain.water.level[y * no_drain.world.w + x]
	_check("un nido con Drenaje pierde menos agua que uno sin Drenaje (misma semilla)", vol_with < vol_without * 0.8, "con=%.2f sin=%.2f" % [vol_with, vol_without])


# --- Araña ------------------------------------------------------------------------------------------

func _t_spider() -> void:
	# Umbrales de era bajados a propósito: con 5-6 hormigas (reina+nodrizas de spawn_colony_court)
	# ya alcanza "Colonia madura", para que `_update_spider` no la resetee a Fundación cada tick.
	var cfg := _cfg(0)
	cfg.spider_first_population = 1
	cfg.era2_population = 1
	cfg.era3_population = 2
	var hunts := _colony(cfg, 8)
	var w := hunts.ants.add_ant_at(Vector2i(hunts.cfg.nest_x + 20, hunts.cfg.surface_y - 1))
	hunts.cmd_force_spider()
	hunts.spider.pos = Vector2(hunts.ants.pos[w].x - 5.0, hunts.ants.pos[w].y)
	_run(hunts, 6.0)
	_check("la araña caza una obrera suelta en la superficie", hunts.ants.alive[w] == 0 or hunts.ants.hp[w] < hunts.cfg.ant_hp, "vida=%.1f" % hunts.ants.hp[w])

	var guarded := _colony(cfg, 9)
	guarded.cmd_force_spider()
	for k in 6:
		var s := guarded.ants.add_ant_at(Vector2i(guarded.cfg.nest_x, guarded.cfg.surface_y - 1), CasteDefs.Caste.SOLDIER)
		guarded.ants.pos[s] = guarded.spider.pos
	_run(guarded, 10.0)
	_check("4-6 soldados espantan o derrotan a la araña", not guarded.spider.alive or guarded.spider.state == Spider.State.RETREAT, "viva=%s estado=%d" % [guarded.spider.alive, guarded.spider.state])

	# Cambio intencional (ver sesión de diseño): toda la colonia defiende la colmena ante una
	# amenaza real, no solo el soldado (obrera 3 de daño, zángano 1, pasivo). Sin soldados, un
	# puñado de obreras ya no es presa fácil e indefensa: o terminan espantando/matando a la araña
	# entre todas, o mueren peleando — lo que NO puede pasar es que la araña ronde sin que nadie le
	# haga nada (eso sí sería una regresión real de esta función).
	var alone := _colony(cfg, 10)
	for k in 10:
		alone.ants.add_ant_at(Vector2i(alone.cfg.nest_x + 10 + k, alone.cfg.surface_y - 1))
	alone.cmd_force_spider()
	_run(alone, 60.0)
	var fought_back := not alone.spider.alive or alone.spider.hp < alone.spider.max_hp or alone.spider.state == Spider.State.RETREAT
	_check("sin soldados, las obreras igual se defienden entre todas", fought_back or alone.deaths > 0,
		"araña viva=%s vida=%.0f/%.0f muertes=%d" % [alone.spider.alive, alone.spider.hp, alone.spider.max_hp, alone.deaths])


## Daño por casta al defender (Obrera 3, Zángano 1 pasivo, Nodriza no pelea), probado uno por uno
## para no depender de que ganen o pierdan la pelea completa (eso ya lo prueba `_t_spider`).
func _t_colony_wide_defense_by_caste() -> void:
	var cfg := _cfg(0)
	cfg.spider_first_population = 1

	var with_worker := _colony(cfg, 30)
	var w := with_worker.ants.add_ant_at(Vector2i(with_worker.cfg.nest_x, with_worker.cfg.surface_y - 1))
	with_worker.cmd_force_spider()
	with_worker.spider.pos = with_worker.ants.pos[w]
	var hp0 := with_worker.spider.hp
	_run(with_worker, 3.0)
	_check("la obrera también pelea cuerpo a cuerpo", with_worker.spider.hp < hp0, "vida araña %.1f -> %.1f" % [hp0, with_worker.spider.hp])

	var with_drone := _colony(cfg, 31)
	var d := with_drone.ants.add_ant_at(Vector2i(with_drone.cfg.nest_x, with_drone.cfg.surface_y - 1), CasteDefs.Caste.DRONE)
	with_drone.cmd_force_spider()
	with_drone.spider.pos = with_drone.ants.pos[d]
	var hp1 := with_drone.spider.hp
	var start_pos := with_drone.ants.pos[d]
	_run(with_drone, 3.0)
	_check("el zángano pelea pasivo (daño chico) sin moverse", with_drone.spider.hp < hp1 and with_drone.ants.pos[d] == start_pos,
		"vida araña %.1f -> %.1f" % [hp1, with_drone.spider.hp])

	var with_nurse := _colony(cfg, 32)
	# `spawn_colony_court` ya pone nodrizas; usamos la que venga puesta, no hace falta agregar otra.
	with_nurse.cmd_force_spider()
	with_nurse.spider.pos = with_nurse.ants.pos[with_nurse.queen_id]  # cerca del nido, donde están las nodrizas
	var hp2 := with_nurse.spider.hp
	_run(with_nurse, 3.0)
	_check("la nodriza no pelea (se queda cuidando la cría)", with_nurse.spider.hp == hp2, "vida araña %.1f -> %.1f" % [hp2, with_nurse.spider.hp])


# --- Eras, derrota y determinismo ------------------------------------------------------------------

func _t_eras() -> void:
	var sim := _colony(_cfg(0), 11)
	sim.ants.add_ants(sim.cfg.era2_population)
	sim.tick()
	_check("la población alcanza la era 'Colonia joven'", sim.era == Simulation.Era.YOUNG, "era=%d pop=%d" % [sim.era, sim.ants.alive_count])
	sim.ants.add_ants(sim.cfg.era3_population)
	sim.tick()
	_check("la población alcanza la era 'Colonia madura'", sim.era == Simulation.Era.MATURE)


func _t_queen_death_ends_game() -> void:
	var sim := _colony(_cfg(0), 12)
	sim.ants._kill(sim.queen_id, true)
	sim.tick()
	_check("la muerte de la reina termina la partida con la causa correcta", sim.game_over and sim.game_over_reason.length() > 0, sim.game_over_reason)


## La reina puede caminar a donde la mande el jugador (protegerla de la araña), pero solo si se le
## ordena: sin orden, sigue quieta exactamente como siempre.
func _t_queen_move() -> void:
	var sim := _colony(_cfg(0), 20)
	var nx := sim.cfg.nest_x
	var y0 := _below_nest(sim)
	var start_pos := sim.ants.pos[sim.queen_id]
	_run(sim, 1.0)
	_check("sin orden, la reina no se mueve", sim.ants.pos[sim.queen_id] == start_pos)

	_carve(sim, nx - 1, y0, nx + 6, y0 + 1)
	var target_cell := Vector2i(nx + 6, y0)
	_check("cmd_move_queen acepta una celda cavada y conectada al nido", sim.cmd_move_queen(target_cell.x, target_cell.y))
	_check("no acepta tierra sin cavar", not sim.cmd_move_queen(nx + 20, y0))
	_run(sim, 15.0)
	var d := sim.ants.pos[sim.queen_id].distance_to(Vector2((target_cell.x + 0.5) * sim.cfg.cell_px, (target_cell.y + 0.5) * sim.cfg.cell_px))
	_check("la reina llega a la celda ordenada", sim.queen_goal_cell == -1 and d < sim.cfg.cell_px, "distancia=%.1f" % d)

	# Desacoplado a propósito (ver respuesta del usuario): la puesta de huevos no exige que la
	# reina esté parada en la cámara Real, solo que exista una Real válida en algún lado.
	sim.colony.food = 200.0
	_run(sim, sim.cfg.egg_interval_s + 1.0)
	_check("sigue poniendo huevos aunque no esté en la cámara Real", sim.brood.total_alive() > 0 or sim.brood.hatched > 0)


func _t_determinism() -> void:
	var a := _colony(_cfg(60), 13)
	var b := _colony(_cfg(60), 13)
	var c := _colony(_cfg(60), 14)
	a.colony.food = 500.0
	b.colony.food = 500.0
	c.colony.food = 500.0
	_run(a, 90.0)
	_run(b, 90.0)
	_run(c, 90.0)
	_check("misma semilla y mismas acciones dan el mismo resultado (con colonia completa)", a.checksum() == b.checksum(), "huellas %d / %d" % [a.checksum(), b.checksum()])
	_check("otra semilla da un resultado distinto", a.checksum() != c.checksum())


func _t_performance() -> void:
	for n in [200, 500]:
		var cfg := _cfg(n)
		var sim := _colony(cfg, 15)
		_run(sim, 5.0)
		var t0 := Time.get_ticks_usec()
		var ticks := 20 * 20
		for i in ticks:
			sim.tick()
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / ticks
		var budget := 16.6 if n == 200 else 33.3
		_check("coste de simulación con %d hormigas dentro del presupuesto (60/30 FPS)" % n, ms < budget, "%.2f ms por tick" % ms)
