extends SceneTree
## Pruebas de la Fase 38 (segundo reporte del playtest): las hormigas ya no quedan en bucle sobre los
## rastros de Comida pintados. Un rastro que se aplana (lo pintado satura en 1.0) cuenta como final;
## la que dio un rastro por agotado no vuelve a rondarlo; los soldados salen del nido sin desviarse.
## Uso: godot --headless --path . --script tools/test_phase38.gd      (código de salida 1 si algo falla)

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_t_flat_trail_is_an_end()
	_t_ignoring_ant_not_pulled()
	_t_surface_mode_ignores_food()
	_t_workers_keep_delivering()
	_t_enemy_above_tunnel()
	print("RESULTADO: %d correctas, %d fallidas" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("[%s] %s %s" % ["OK " if ok else "FALLA", label, detail])


func _fresh(seed_value: int) -> Simulation:
	var cfg := SimConfig.new()
	cfg.rain_auto = false
	var sim := Simulation.new(cfg, seed_value)
	sim.spawn_incremental_start(true)
	sim._set_shaft(WorldGrid.Cell.TUNNEL)
	sim.corpses.clear()
	return sim


func _worker(sim: Simulation) -> int:
	for i in sim.ants.count:
		if sim.ants.alive[i] == 1 and sim.ants.faction[i] == 0 and sim.ants.caste[i] == CasteDefs.Caste.WORKER:
			return i
	return -1


func _place(sim: Simulation, i: int, cell: Vector2i) -> int:
	sim.ants.pos[i] = Vector2((cell.x + 0.5) * sim.cfg.cell_px, (cell.y + 0.5) * sim.cfg.cell_px)
	return cell.y * sim.world.w + cell.x


func _t_flat_trail_is_an_end() -> void:
	var sim := _fresh(1)
	var cfg := sim.cfg
	var y := cfg.surface_y - 1
	for x in range(cfg.nest_x - 10, cfg.nest_x + 10):
		sim.cmd_paint_phero(sim.food, x, y, 1.0)  # meseta: todo saturado
	var i := _worker(sim)
	var cell := Vector2i(cfg.nest_x, y)
	var ci := _place(sim, i, cell)
	sim.ants.state[i] = AntSystem.State.GO_TO_FOOD
	sim.ants._think_food(i, cell.x, cell.y, ci)
	_check("en un rastro plano (saturado) la obrera da el rastro por terminado", sim.ants.ignore_until[i] > sim.tick_count and sim.ants.state[i] == AntSystem.State.EXPLORE)

	var sim2 := _fresh(1)
	for k in 20:
		sim2.cmd_paint_phero(sim2.food, cfg.nest_x - 10 + k, y, cfg.paint_start + cfg.paint_ramp * k)
	var j := _worker(sim2)
	var cj := _place(sim2, j, cell)
	sim2.ants.state[j] = AntSystem.State.GO_TO_FOOD
	sim2.ants._think_food(j, cell.x, cell.y, cj)
	_check("en un rastro que sube, lo sigue", sim2.ants.state[j] == AntSystem.State.GO_TO_FOOD and sim2.ants.target[j].x > sim2.ants.pos[j].x)


func _t_ignoring_ant_not_pulled() -> void:
	var sim := _fresh(2)
	var cfg := sim.cfg
	var y := cfg.surface_y - 1
	var cell := Vector2i(cfg.nest_x - 20, y)
	# Rastro fuerte solo a la izquierda de la obrera; ella mira a la derecha.
	sim.cmd_paint_phero(sim.food, cell.x - 1, y, 1.0)
	sim.cmd_paint_phero(sim.food, cell.x - 1, y - 1, 1.0)
	var i := _worker(sim)
	var ci := _place(sim, i, cell)
	sim.ants.heading[i] = Vector2.RIGHT
	sim.ants.ignore_until[i] = sim.tick_count + 1000
	var left := 0
	for k in 40:
		sim.ants._step(i, cell.x, cell.y, ci, AntSystem.Mode.EXPLORE, null)
		left += int(sim.ants.target[i].x < sim.ants.pos[i].x)
	_check("la que ignora un rastro ya no se deja atraer por él", left < 20, "%d de 40 hacia el rastro" % left)
	sim.ants.ignore_until[i] = 0
	left = 0
	for k in 40:
		sim.ants.heading[i] = Vector2.RIGHT
		sim.ants._step(i, cell.x, cell.y, ci, AntSystem.Mode.EXPLORE, null)
		left += int(sim.ants.target[i].x < sim.ants.pos[i].x)
	_check("sin ignorarlo, explorando sí lo sigue", left >= 30, "%d de 40 hacia el rastro" % left)


func _t_surface_mode_ignores_food() -> void:
	var sim := _fresh(3)
	var cfg := sim.cfg
	# Un soldado en la cámara Real con Comida pintada fuerte hacia el fondo (trazo al revés).
	var cell := Vector2i(cfg.nest_x, cfg.surface_y + cfg.shaft_depth)
	for dy in range(0, cfg.chamber_h):
		sim.cmd_paint_phero(sim.food, cfg.nest_x, cell.y + dy, 0.3 + 0.2 * dy)
	var i := _worker(sim)
	var ci := _place(sim, i, cell)
	var up := 0
	for k in 20:
		sim.ants._step(i, cell.x, cell.y, ci, AntSystem.Mode.SURFACE, null)
		up += int(sim.ants.target[i].y < sim.ants.pos[i].y)
	_check("Mode.SURFACE sube hacia la salida aunque la Comida tire para abajo", up >= 18, "%d de 20 hacia arriba" % up)


## El escenario del reporte: rastro saturado hasta un montón que se agota. Antes, a los 60 s todas las
## obreras quedaban dando vueltas por la meseta y no entregaban nada más.
func _t_workers_keep_delivering() -> void:
	var cfg: SimConfig = load("res://sim/core/default_config.tres").duplicate()
	cfg.rain_auto = false
	var sim := Simulation.new(cfg, 5)
	sim.spawn_incremental_start(true)
	sim._set_shaft(WorldGrid.Cell.TUNNEL)
	sim.cmd_add_caste_ants(CasteDefs.Caste.WORKER, 8)
	var y := cfg.surface_y - 1
	var dir := 1 if sim.rival_colony.home_x < cfg.nest_x else -1
	var fx := cfg.nest_x + dir * 25
	for k in 6:
		sim.corpses.append(Corpse.new(Vector2((fx + 0.5) * cfg.cell_px, cfg.surface_y * cfg.cell_px - 1.0), 5.0, Corpse.Kind.SEED))
	for s in 26:
		for yy in [y, y - 1]:
			sim.cmd_paint_phero(sim.food, cfg.nest_x + dir * s, yy, minf(1.0, cfg.paint_start + cfg.paint_ramp * s * 3))
	# Cuenta, de 60 a 120 s, las obreras "en bucle": yendo a la comida, paradas en lo pintado y sin
	# nada a la vista. Antes eran casi todas todo el tiempo.
	var looping := 0
	var samples := 0
	for t in 120 * cfg.tick_rate:
		sim.tick()
		if t < 60 * cfg.tick_rate or t % (5 * cfg.tick_rate) != 0:
			continue
		for i in sim.ants.count:
			if sim.ants.alive[i] == 1 and sim.ants.faction[i] == 0 and sim.ants.caste[i] == CasteDefs.Caste.WORKER:
				samples += 1
				var ci := sim.ants._cell_index(sim.ants.pos[i])
				if sim.ants.state[i] == AntSystem.State.GO_TO_FOOD and sim.food.is_painted(ci) and sim.ants._corpse_near(i) == null:
					looping += 1
	_check("con el rastro agotado, las obreras no quedan dando vueltas en él", looping * 4 < samples, "%d de %d muestras en bucle" % [looping, samples])


## El otro reporte: obreras en un túnel cerca de la superficie y una hormiga enemiga arriba. Antes
## iban hacia ella en línea recta, chocaban con la tierra y quedaban en bucle debajo hasta que
## moría. Ahora salen por el pozo y llegan a pelearla; y si no hay camino corto, siguen con lo suyo.
func _t_enemy_above_tunnel() -> void:
	var sim := _fresh(6)
	var cfg := sim.cfg
	# Túnel horizontal a 2 celdas de la superficie, desde el pozo hacia un costado.
	var ty := cfg.surface_y + 1
	for x in range(cfg.nest_x + 1, cfg.nest_x + 9):
		sim.world.cells[ty * sim.world.w + x] = WorldGrid.Cell.TUNNEL
	sim.world.passable_version += 1
	sim.fields.recompute_terrain()
	var enemy := sim.ants.add_ant_at(Vector2i(cfg.nest_x + 8, cfg.surface_y - 1), CasteDefs.Caste.SOLDIER, 1)
	var epos := sim.ants.pos[enemy]
	sim.ants.hp[enemy] = 1.0e6  # que no muera: se mide si llega a pelearla
	var w := _worker(sim)
	_place(sim, w, Vector2i(cfg.nest_x + 8, ty))  # al final del túnel, justo debajo de ella
	for t in 15 * cfg.tick_rate:
		sim.ants.pos[enemy] = epos
		sim.ants.target[enemy] = epos
		sim.tick()
	_check("la obrera sale por el pozo y llega a pelear con la enemiga de arriba", sim.ants.hp[enemy] < 1.0e6,
		"quedó a %.0f px, en la celda %s" % [sim.ants.pos[w].distance_to(epos), Vector2i(sim.ants.pos[w] / cfg.cell_px)])

	var closed := Simulation.new(cfg, 6)
	closed.spawn_incremental_start(true)  # nido cerrado: no hay camino
	var inside := (cfg.surface_y + cfg.shaft_depth + 1) * closed.world.w + cfg.nest_x
	var above := Vector2((cfg.nest_x + 0.5) * cfg.cell_px, (cfg.surface_y - 0.5) * cfg.cell_px)
	_check("sin camino corto, la enemiga de arriba se ignora", closed.ants.threat_step(inside, above) == AntSystem.THREAT_UNREACHABLE)
