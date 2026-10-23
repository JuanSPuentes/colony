extends SceneTree
## Pruebas de la Fase 15: nido cerrado + árboles al azar en "Juego normal", excavación continua,
## soldados que no se quedan pegados en un rastro de Ataque vacío, y la tarjeta de las feromonas.
## Uso: godot --headless --path . --script tools/test_phase15.gd      (código de salida 1 si algo falla)

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_t_default_start_unchanged()
	_t_fresh_layout_seals_nest()
	_t_fresh_layout_random_plants()
	_t_continuous_digging_opens_nest()
	_t_soldiers_release_empty_attack_trail()
	_t_soldiers_still_answer_real_threat()
	_t_coach_lessons()
	print("RESULTADO: %d correctas, %d fallidas" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("[%s] %s %s" % ["OK " if ok else "FALLA", label, detail])


func _cfg() -> SimConfig:
	var c := SimConfig.new()
	c.rain_auto = false
	return c


func _top_air(sim: Simulation) -> int:
	return (sim.cfg.surface_y - 1) * sim.world.w + sim.cfg.nest_x


func _t_default_start_unchanged() -> void:
	var sim := Simulation.new(_cfg(), 1)
	sim.spawn_incremental_start()
	_check("sin fresh_layout el nido sigue abierto (pruebas y Nivel 0 no cambian)",
		sim.fields.nest_dist[_top_air(sim)] < NestDistanceField.FAR)
	_check("sin fresh_layout siguen las plantas de siempre", sim.plants.size() == sim.cfg.plant_count)


func _t_fresh_layout_seals_nest() -> void:
	var sim := Simulation.new(_cfg(), 2)
	sim.spawn_incremental_start(true)
	_check("con fresh_layout el nido arranca cerrado (sin salida a la superficie)",
		sim.fields.nest_dist[_top_air(sim)] >= NestDistanceField.FAR)
	var shaft_dirt := true
	for y in range(sim.cfg.surface_y, sim.cfg.surface_y + sim.cfg.shaft_depth):
		shaft_dirt = shaft_dirt and sim.world.type_at(sim.cfg.nest_x, y) == WorldGrid.Cell.DIRT
	_check("el pozo inicial quedó relleno de tierra", shaft_dirt)
	_check("la cámara del nido sigue abierta (la reina tiene dónde estar)",
		sim.world.is_open(sim.cfg.nest_x, sim.cfg.surface_y + sim.cfg.shaft_depth))


func _t_fresh_layout_random_plants() -> void:
	var layouts := {}
	var min_gap := 999
	for seed_value in [11, 12, 13, 14]:
		var sim := Simulation.new(_cfg(), seed_value)
		sim.spawn_incremental_start(true)
		var xs: Array[int] = []
		for p in sim.plants:
			xs.append(p.cell.x)
		xs.sort()
		for k in range(1, xs.size()):
			min_gap = mini(min_gap, xs[k] - xs[k - 1])
		layouts[str(xs)] = true
		_check("semilla %d: el tamaño de known_plants coincide con las plantas" % seed_value,
			sim.econ.known_plants.size() == sim.plants.size())
	_check("los árboles cambian de lugar entre partidas", layouts.size() >= 3, "distintos=%d de 4" % layouts.size())
	_check("los árboles no se enciman", min_gap >= 4, "separación mínima=%d" % min_gap)


func _t_continuous_digging_opens_nest() -> void:
	var sim := Simulation.new(_cfg(), 5)
	sim.spawn_incremental_start(true)
	for y in range(sim.cfg.surface_y, sim.cfg.surface_y + sim.cfg.shaft_depth):
		sim.cmd_mark(sim.cfg.nest_x, y)
	var opened_at := -1.0
	for t in int(90.0 * sim.cfg.tick_rate):
		sim.tick()
		if sim.fields.nest_dist[_top_air(sim)] < NestDistanceField.FAR:
			opened_at = t * sim.dt
			break
	# Con el ir y volver de antes no se terminaba ni en 120 s (2 de 7 celdas).
	_check("las obreras cavan el túnel a la superficie de corrido (menos de 60 s)",
		opened_at >= 0.0 and opened_at < 60.0, "abierto a los %.1f s" % opened_at)
	_check("cavar de corrido no cava sin estar al lado", sim.dig_violations == 0)


func _soldier_trail_sim() -> Array:
	var cfg := _cfg()
	var sim := Simulation.new(cfg, 3)
	sim.spawn_incremental_start()
	var soldiers: Array[int] = []
	for k in 8:
		soldiers.append(sim.ants.add_ant_at(Vector2i(cfg.nest_x, cfg.surface_y - 1), CasteDefs.Caste.SOLDIER))
	for k in 15:
		sim.cmd_paint_phero(sim.attack, cfg.nest_x + 2 + k, cfg.surface_y - 1, minf(1.0, 0.3 + 0.05 * k))
	return [sim, soldiers]


func _t_soldiers_release_empty_attack_trail() -> void:
	var r := _soldier_trail_sim()
	var sim: Simulation = r[0]
	var soldiers: Array[int] = r[1]
	for i in int(40.0 * sim.cfg.tick_rate):
		sim.tick()
	var attacking := 0
	for s in soldiers:
		if sim.ants.alive[s] == 1 and sim.ants.state[s] == AntSystem.State.ATTACK:
			attacking += 1
	# Antes: 7 de 8 seguían en ATAQUE a los 40 s, persiguiendo un rastro sin nadie al final.
	_check("sin enemigo al final del rastro de Ataque, los soldados vuelven a patrullar",
		attacking <= 2, "en ATAQUE a los 40 s: %d de 8" % attacking)


func _t_soldiers_still_answer_real_threat() -> void:
	var r := _soldier_trail_sim()
	var sim: Simulation = r[0]
	var cell := Vector2i(sim.cfg.nest_x + 17, sim.cfg.surface_y - 1)
	var rival := sim.ants.add_ant_at(cell, CasteDefs.Caste.SOLDIER, 1)
	var hp0 := sim.ants.hp[rival]
	for i in int(30.0 * sim.cfg.tick_rate):
		sim.tick()
	_check("con un enemigo al final del rastro, los soldados igual llegan y pelean",
		sim.ants.alive[rival] == 0 or sim.ants.hp[rival] < hp0, "vida rival %.1f -> %.1f" % [hp0, sim.ants.hp[rival]])


func _t_coach_lessons() -> void:
	var cv := CoachView.new()
	var normal := cv._normal_lessons()
	var ids: Array[String] = []
	for l in normal:
		ids.append(l["id"])
	_check("Juego normal: \"Abre el nido\" va justo después de la bienvenida", ids.size() > 1 and ids[1] == "open", str(ids))
	_check("Juego normal: hay una tarjeta con las 5 feromonas", ids.has("pheromones"))
	var level0_ids: Array[String] = []
	for l in cv._level0_lessons():
		level0_ids.append(l["id"])
	_check("Nivel 0: también tiene la tarjeta de las 5 feromonas", level0_ids.has("pheromones"))
	var t: String = CoachView.PHEROMONES_TEXT
	var all_named := true
	for name in ["Comida", "Hogar", "Peligro", "Ataque", "Evacuar"]:
		all_named = all_named and t.contains(name)
	_check("la tarjeta nombra las cinco feromonas y a quién afectan", all_named)

	var sealed := Simulation.new(_cfg(), 6)
	sealed.spawn_incremental_start(true)
	var open_lesson: Dictionary = normal[1]
	_check("la lección se muestra con el nido cerrado", (open_lesson["when"] as Callable).call(sealed))
	var normal_sim := Simulation.new(_cfg(), 6)
	normal_sim.spawn_incremental_start()
	_check("y no se muestra si el nido ya tiene salida", not (open_lesson["when"] as Callable).call(normal_sim))
	cv.free()
