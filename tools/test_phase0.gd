extends SceneTree
## Pruebas de la simulación sin pantalla. Cada escenario crea una Simulation nueva y comprueba
## un criterio de aceptación; donde tiene sentido, se compara con y sin la acción del jugador
## usando la misma semilla.
## Uso: godot --headless --path . --script tools/test_phase0.gd      (código de salida 1 si algo falla)

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_t_determinism()
	_t_foraging()
	_t_trail_forms()
	_t_pheromone_rules()
	_t_paint_helps()
	_t_dig()
	_t_weather_timer()
	_t_flood_shapes()
	_t_flee_and_die()
	_t_movement_validity()
	_t_performance()
	print("RESULTADO: %d correctas, %d fallidas" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("[%s] %s %s" % ["OK " if ok else "FALLA", label, detail])


func _cfg(ants := 100, rain := false) -> SimConfig:
	var c := SimConfig.new()
	c.initial_ants = ants
	c.rain_auto = rain
	return c


func _run(sim: Simulation, seconds: float) -> void:
	for i in int(seconds * sim.cfg.tick_rate):
		sim.tick()


# --- Escenarios ---------------------------------------------------------------------------------------

func _t_determinism() -> void:
	var results: Array[int] = []
	for run in 3:
		var seed_value := 77 if run < 2 else 78
		var sim := Simulation.new(_cfg(100, true), seed_value)
		sim.cmd_mark(61, sim.cfg.surface_y + 2)
		_run(sim, 10.0)
		for x in range(40, 55):
			sim.cmd_paint_food(x, sim.cfg.surface_y - 1, 0.5)
		sim.cmd_force_rain()
		_run(sim, 20.0)
		results.append(sim.checksum())
	_check("misma semilla y mismas acciones dan el mismo resultado", results[0] == results[1], "huellas %d / %d" % [results[0], results[1]])
	_check("otra semilla da un resultado distinto", results[0] != results[2])


func _t_foraging() -> void:
	var sim := Simulation.new(_cfg(100), 5)
	_run(sim, 120.0)
	var carried := 0
	for i in sim.ants.count:
		carried += sim.ants.carry[i]
	_check("100 obreras encuentran, cargan y depositan hojas sin ayuda", sim.leaves_stored >= 30, "hojas=%d entregas=%d" % [sim.leaves_stored, sim.delivered])
	_check("el contador de hojas coincide con las hojas tomadas de las plantas", sim.leaves_stored + carried + 0 == sim.plants.size() * sim.cfg.leaves_per_plant - sim.total_leaves_left, "almacenadas %d + en camino %d" % [sim.leaves_stored, carried])


func _t_trail_forms() -> void:
	var best := 0.0
	var best_plant := -1
	for seed_value in [5, 6, 7]:
		var sim := Simulation.new(_cfg(100), seed_value)
		var w := sim.world.w
		var sy := sim.cfg.surface_y
		var best_here := 0.0
		for sec in 24:
			_run(sim, 5.0)
			if sim.time_s() < 100.0:
				continue
			for pi in sim.plants.size():
				var pl := sim.plants[pi]
				var x0 := mini(sim.cfg.nest_x, pl.cell.x)
				var x1 := maxi(sim.cfg.nest_x, pl.cell.x)
				if x1 - x0 < 10:
					continue
				var covered := 0
				for x in range(x0, x1 + 1):
					var m := 0.0
					for y in range(sy - 3, sy):
						m = maxf(m, sim.food.data[y * w + x])
					if m > 0.05:
						covered += 1
				best_here = maxf(best_here, float(covered) / float(x1 - x0 + 1))
		best = maxf(best, best_here)
		print("   semilla %d: mejor cobertura de ruta planta-nido = %.2f" % [seed_value, best_here])
	_check("en 2-3 min se forma sola una ruta de feromona entre una planta y el nido", best >= 0.7, "cobertura máxima=%.2f" % best)


func _t_pheromone_rules() -> void:
	var cfg := _cfg(0)
	var sim := Simulation.new(cfg, 3)
	sim.food.data[100] = 1.0
	sim.home.data[100] = 1.0
	_run(sim, 60.0)
	var expected := exp(-cfg.food_decay_per_s * 60.0)
	_check("la feromona de comida decae con el tiempo", absf(sim.food.data[100] - expected) < 0.02, "%.3f (esperado %.3f)" % [sim.food.data[100], expected])
	var slow := Simulation.new(cfg, 3)
	var fast := Simulation.new(cfg, 3)
	slow.food.data[100] = 1.0
	fast.food.data[100] = 1.0
	_run(slow, 20.0)
	fast.cmd_force_rain()
	_run(fast, 20.0)
	var ratio := log(fast.food.data[100]) / log(slow.food.data[100])
	_check("durante la lluvia decae 4 veces más rápido", absf(ratio - cfg.rain_decay_mult) < 0.4, "razón de decaimiento = %.2f" % ratio)
	var ants := Simulation.new(_cfg(100), 4)
	_run(ants, 60.0)
	_check("las que salen del nido depositan feromona de hogar", ants.home.active > 20, "celdas=%d" % ants.home.active)
	_check("las que vuelven cargadas depositan feromona de comida", ants.food.active > 20, "celdas=%d" % ants.food.active)
	# Una ruta sin uso se apaga sola.
	var gone := Simulation.new(_cfg(0), 4)
	for x in range(40, 60):
		gone.food.data[(gone.cfg.surface_y - 1) * gone.world.w + x] = 1.0
	_run(gone, 400.0)
	_check("una ruta abandonada se apaga", gone.food.active == 0, "celdas restantes=%d" % gone.food.active)


func _far_cfg() -> SimConfig:
	var c := _cfg(100)
	c.plant_count = 1
	c.plant_min_dist = 50
	c.plant_max_dist = 50
	c.leaves_per_plant = 400
	return c


func _t_paint_helps() -> void:
	var with_paint := 0
	var without := 0
	var t20_with := 0.0
	var t20_without := 0.0
	var first_with := 0.0
	var first_without := 0.0
	for seed_value in [3, 8, 11]:
		for variant in 2:
			var sim := Simulation.new(_far_cfg(), seed_value)
			var pl := sim.plants[0]
			if variant == 1:
				# Igual que arrastrar con el mouse desde el nido hacia la planta (rampa creciente).
				var step := 1 if pl.cell.x > sim.cfg.nest_x else -1
				var n := 0
				for x in range(sim.cfg.nest_x, pl.cell.x + step, step):
					var v := minf(1.0, sim.cfg.paint_start + sim.cfg.paint_ramp * n)
					for dy in range(-1, 2):
						sim.cmd_paint_food(x, sim.cfg.surface_y - 1 + dy, v)
					n += 1
			var first := -1.0
			var t20 := -1.0
			for i in 20 * 150:
				sim.tick()
				if first < 0.0 and sim.delivered > 0:
					first = sim.time_s()
				if t20 < 0.0 and sim.delivered >= 20:
					t20 = sim.time_s()
			first = first if first >= 0.0 else 150.0
			t20 = t20 if t20 >= 0.0 else 150.0
			if variant == 1:
				with_paint += sim.delivered
				first_with += first
				t20_with += t20
			else:
				without += sim.delivered
				first_without += first
				t20_without += t20
	print("   planta lejana (50 celdas), media de 3 semillas: primera entrega %.0f s con pintura / %.0f s sin ella" % [first_with / 3.0, first_without / 3.0])
	_check("pintar feromona hacia una planta lejana hace que la encuentren antes (entrega nº 20, misma semilla)", t20_with / 3.0 < t20_without / 3.0 * 0.8, "%.0f s con pintura vs %.0f s sin ella" % [t20_with / 3.0, t20_without / 3.0])
	_check("pintar feromona aumenta las hojas recolectadas de la planta lejana", with_paint > without * 1.3, "con=%d sin=%d (3 semillas, 150 s)" % [with_paint, without])


func _t_dig() -> void:
	var sim := Simulation.new(_cfg(0), 5)
	var sy := sim.cfg.surface_y
	var nx := sim.cfg.nest_x
	_check("no se puede marcar tierra que no toca un espacio abierto", not sim.cmd_mark(30, sy + 10))
	var rock := Vector2i(-1, -1)
	for y in range(sy + 4, sim.world.h - 2):
		for x in sim.world.w:
			if sim.world.type_at(x, y) == WorldGrid.Cell.ROCK and rock.x < 0:
				rock = Vector2i(x, y)
	_check("la roca no se puede marcar", not sim.world.can_mark(rock.x, rock.y))
	var cells: Array[Vector2i] = [Vector2i(nx + 1, sy + 2), Vector2i(nx + 2, sy + 2), Vector2i(nx + 3, sy + 2), Vector2i(nx + 3, sy + 3)]
	var ok := true
	for c in cells:
		ok = ok and sim.cmd_mark(c.x, c.y)
	_check("se pueden marcar celdas adyacentes a un espacio abierto o a otra marcada", ok)
	_run(sim, 120.0)
	var still := 0
	for c in cells:
		if sim.world.type_at(c.x, c.y) == WorldGrid.Cell.MARKED:
			still += 1
	_check("sin obreras, las celdas marcadas nunca desaparecen solas", still == 4 and sim.dug == 0, "marcadas=%d excavadas=%d" % [still, sim.dug])
	# Con obreras.
	var sim2 := Simulation.new(_cfg(100), 5)
	for c in cells:
		sim2.cmd_mark(c.x, c.y)
	var done_at := -1.0
	for i in 20 * 150:
		sim2.tick()
		if done_at < 0.0 and sim2.world.marked_count == 0:
			done_at = sim2.time_s()
	var tunnels := 0
	for c in cells:
		if sim2.world.type_at(c.x, c.y) == WorldGrid.Cell.TUNNEL:
			tunnels += 1
	_check("las obreras cavan las celdas marcadas", tunnels == 4 and sim2.dug == 4, "listas en %.0f s" % done_at)
	_check("cada celda la cava una hormiga que está pegada a ella", sim2.dig_violations == 0, "violaciones=%d" % sim2.dig_violations)
	var nd := sim2.fields.nest_dist[cells[3].y * sim2.world.w + cells[3].x]
	_check("el campo de distancias se recalcula con el túnel nuevo", nd < NestDistanceField.FAR, "distancia al nido=%d" % nd)
	var sim3 := Simulation.new(_cfg(0), 5)
	sim3.cmd_mark(cells[0].x, cells[0].y)
	sim3.cmd_mark(cells[1].x, cells[1].y)
	sim3.cmd_unmark(cells[0].x, cells[0].y)
	_check("se puede desmarcar con clic derecho", sim3.world.type_at(cells[0].x, cells[0].y) == WorldGrid.Cell.DIRT and sim3.world.marked_count == 1)


func _t_weather_timer() -> void:
	var cfg := _cfg(0, true)
	cfg.rain_first_s = 30.0
	cfg.rain_duration_s = 10.0
	var sim := Simulation.new(cfg, 2)
	var warned_at := -1.0
	var rain_at := -1.0
	var end_at := -1.0
	for i in 20 * 60:
		sim.tick()
		if warned_at < 0.0 and sim.weather == Simulation.Weather.WARNING:
			warned_at = sim.time_s()
		if rain_at < 0.0 and sim.weather == Simulation.Weather.RAINING:
			rain_at = sim.time_s()
		if rain_at >= 0.0 and end_at < 0.0 and sim.weather == Simulation.Weather.CLEAR:
			end_at = sim.time_s()
	_check("el temporizador avisa 10 s antes de la lluvia", absf(rain_at - warned_at - 10.0) < 0.2 and absf(rain_at - 30.0) < 0.2, "aviso %.1f s, lluvia %.1f s, fin %.1f s" % [warned_at, rain_at, end_at])
	_check("la lluvia termina sola", absf(end_at - rain_at - 10.0) < 0.2)


func _carve(sim: Simulation, x0: int, y0: int, x1: int, y1: int) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			sim.world.cells[y * sim.world.w + x] = WorldGrid.Cell.TUNNEL


func _t_flood_shapes() -> void:
	# Un túnel en U con una cámara alta al final del brazo derecho.
	var sim := Simulation.new(_cfg(0), 9)
	var sy := sim.cfg.surface_y
	_carve(sim, 90, sy, 90, sy + 12)  # brazo izquierdo, abierto a la superficie
	_carve(sim, 90, sy + 12, 102, sy + 12)  # fondo de la U
	_carve(sim, 102, sy + 5, 102, sy + 12)  # brazo derecho
	_carve(sim, 100, sy + 2, 104, sy + 4)  # cámara alta, encima del nivel que alcanza el agua
	sim.cmd_force_rain()
	_run(sim, sim.cfg.rain_duration_s + 3.0)
	var bottom := 0.0
	for x in range(91, 102):
		bottom += sim.water.level[(sy + 12) * sim.world.w + x]
	var high := 0.0
	for y in range(sy + 2, sy + 5):
		for x in range(100, 105):
			high += sim.water.level[y * sim.world.w + x]
	_check("un túnel en U retiene el agua en el fondo", bottom / 11.0 > 0.8, "nivel medio del fondo=%.2f" % (bottom / 11.0))
	_check("una cámara alta queda seca", high < 0.01, "agua en la cámara alta=%.3f" % high)
	var vol_end := sim.water.volume
	_run(sim, 120.0)
	_check("tras la lluvia el agua se evapora poco a poco", sim.water.volume < vol_end and sim.water.volume > 0.0, "volumen %.1f -> %.1f en 120 s" % [vol_end, sim.water.volume])
	# El agua solo entra por celdas abiertas a la superficie.
	var sealed := Simulation.new(_cfg(0), 9)
	_carve(sealed, 90, sy + 3, 96, sy + 6)
	sealed.cmd_force_rain()
	_run(sealed, 20.0)
	var sealed_w := 0.0
	for y in range(sy + 3, sy + 7):
		for x in range(90, 97):
			sealed_w += sealed.water.level[y * sealed.world.w + x]
	_check("una cavidad cerrada no recibe agua", sealed_w < 0.001)
	# Mismo volumen, forma distinta: el nido por defecto (cámara abajo) se llena más que la U.
	var nest := Simulation.new(_cfg(0), 9)
	nest.cmd_force_rain()
	_run(nest, nest.cfg.rain_duration_s + 3.0)
	var chamber := 0.0
	for c in nest.world.nest_cells:
		chamber += nest.water.level[c]
	_check("la cámara baja del nido por defecto se inunda", chamber / nest.world.nest_cells.size() > 0.5, "nivel medio=%.2f" % (chamber / nest.world.nest_cells.size()))


func _t_flee_and_die() -> void:
	var sy := 22
	# Con salida: en un túnel inundado hay una rama seca a pocas celdas.
	var sim := Simulation.new(_cfg(0), 9)
	_carve(sim, 90, sy, 90, sy + 12)
	_carve(sim, 90, sy + 12, 102, sy + 12)
	_carve(sim, 95, sy + 7, 95, sy + 12)
	sim.world.passable_version += 1
	sim.tick()
	for x in range(91, 102):
		sim.water.add((sy + 12) * sim.world.w + x, 0.8)
	for k in 10:
		sim.ants.add_ant_at(Vector2i(92 + k, sy + 12))
	var fled := false
	for i in 20 * 20:
		sim.tick()
		if sim.ants.state_counts[AntSystem.State.FLEE_WATER] > 0:
			fled = true
	var safe := 0
	for i in sim.ants.count:
		if sim.ants.alive[i] == 1:
			var c := sim.ants._cell_index(sim.ants.pos[i])
			if sim.water.level[c] < sim.cfg.flee_level:
				safe += 1
	_check("las hormigas en agua profunda huyen hacia celdas secas", fled and safe >= 8, "a salvo=%d de 10, vivas=%d" % [safe, sim.ants.alive_count])
	# Sin salida: una cámara cerrada llena de agua.
	var trap := Simulation.new(_cfg(0), 9)
	_carve(trap, 70, sy + 20, 73, sy + 21)
	trap.world.passable_version += 1
	trap.tick()
	for y in range(sy + 20, sy + 22):
		for x in range(70, 74):
			trap.water.add(y * trap.world.w + x, 1.0)
	for k in 6:
		trap.ants.add_ant_at(Vector2i(70 + k % 4, sy + 20 + k % 2))
	_run(trap, 15.0)
	_check("si no pueden salir, las hormigas mueren", trap.ants.alive_count == 0 and trap.deaths == 6, "vivas=%d muertes=%d" % [trap.ants.alive_count, trap.deaths])


func _t_movement_validity() -> void:
	var cfg := _cfg(100, true)
	cfg.rain_first_s = 40.0
	var sim := Simulation.new(cfg, 21)
	sim.cmd_add_ants(400)
	var bad := 0
	var sy := cfg.surface_y
	for k in 60:
		sim.cmd_mark(cfg.nest_x + 1 + k % 12, sy + 2 + k / 12)
	for i in 20 * 240:
		sim.tick()
		if i % 4 == 0:
			var ants := sim.ants
			for a in ants.count:
				if ants.alive[a] == 1:
					var c := ants.pos[a] / cfg.cell_px
					if not sim.world.is_passable(floori(c.x), floori(c.y)):
						bad += 1
	_check("ninguna hormiga atraviesa tierra o roca (500 hormigas, excavando y con lluvia)", bad == 0, "violaciones=%d en %d ticks" % [bad, 20 * 240 / 4])
	_check("ninguna hormiga pasa más de 3 s sin avanzar", sim.ants.max_stuck_seen < cfg.stuck_seconds + 0.01, "máximo=%.1f s, recuperaciones=%d" % [sim.ants.max_stuck_seen, sim.stuck_recoveries])
	_check("las hormigas siguen vivas o murieron ahogadas, no desaparecen", sim.ants.alive_count + sim.deaths == 500, "vivas=%d muertas=%d" % [sim.ants.alive_count, sim.deaths])


func _t_performance() -> void:
	# El presupuesto de 500 hormigas se relajó de 12 a 16 ms al llegar la Fase 1: hay que decaer
	# 3 feromonas más y comprobar cámaras/peligro por hormiga, incluso sin reina. Sigue muy por
	# debajo de los 33 ms (30 FPS) que exige el criterio de rendimiento de la Fase 1.
	for n in [100, 500]:
		var sim := Simulation.new(_cfg(n), 3)
		_run(sim, 5.0)
		var t0 := Time.get_ticks_usec()
		var ticks := 20 * 20
		for i in ticks:
			sim.tick()
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / ticks
		var budget := 12.0 if n == 100 else 16.0
		_check("coste de simulación con %d hormigas dentro del presupuesto (50 ms por tick)" % n, ms < budget, "%.2f ms por tick" % ms)
