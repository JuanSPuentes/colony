extends SceneTree
## Pruebas de la Fase 16 (comportamiento, a pedido del jugador): obreras que cavan sin ir y volver,
## soldados que patrullan todo el mapa, huevos visibles al lado de la reina (no debajo, ni tapados
## por la capa de feromonas), zánganos en Juego normal que defienden a la reina y a los huevos.
## Uso: godot --headless --path . --script tools/test_phase16.gd      (código de salida 1 si algo falla)

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run()


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("[%s] %s %s" % ["OK " if ok else "FALLA", label, detail])


func _cfg() -> SimConfig:
	var c: SimConfig = load("res://sim/core/default_config.tres")
	c = c.duplicate()
	c.rain_auto = false
	return c


func _run() -> void:
	_t_dig_without_back_and_forth()
	_t_soldiers_patrol_whole_map()
	_t_eggs_next_to_queen()
	await _t_brood_drawn_above_overlay()
	_t_drones_in_normal_game()
	_t_drones_guard_queen()
	_t_drones_escort_queen()
	_t_save_keeps_patrol()
	print("RESULTADO: %d correctas, %d fallidas" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


## Túnel vertical de 15+ celdas (solo cavable por la punta) con muchas obreras y comida pintada.
func _t_dig_without_back_and_forth() -> void:
	var cfg := _cfg()
	var sim := Simulation.new(cfg, 12345)
	sim.spawn_incremental_start()
	sim.cmd_add_caste_ants(CasteDefs.Caste.WORKER, 14)
	var chamber_y := cfg.surface_y + cfg.shaft_depth + 1
	var marked := 0
	for k in range(1, 20):
		if sim.cmd_mark(cfg.nest_x, chamber_y + k):
			marked += 1
	var dig_choices := 0
	var was_dig := {}
	var t := 0
	while sim.world.marked_count > 0 and t < 200 * cfg.tick_rate:
		sim.tick()
		t += 1
		for i in sim.ants.count:
			if sim.ants.alive[i] == 1 and sim.ants.caste[i] == CasteDefs.Caste.WORKER:
				var d: bool = sim.ants.state[i] == AntSystem.State.DIG
				if d and not was_dig.get(i, false):
					dig_choices += 1
				was_dig[i] = d
	_check("un túnel de %d celdas se termina de cavar" % marked, sim.world.marked_count == 0 and sim.dug == marked, "cavadas=%d en %.0f s" % [sim.dug, t * sim.dt])
	_check("sin ir y volver: casi una decisión de cavar por celda", dig_choices <= marked + 4, "decisiones=%d celdas=%d" % [dig_choices, marked])
	_check("y sin tardar de más", t * sim.dt < 110.0, "%.0f s" % (t * sim.dt))


func _t_soldiers_patrol_whole_map() -> void:
	var cfg := _cfg()
	var sim := Simulation.new(cfg, 12345)
	sim.spawn_incremental_start()
	sim.cmd_add_caste_ants(CasteDefs.Caste.SOLDIER, 3)
	# Un rastro de comida pintado al costado: antes los soldados se quedaban dando vueltas junto a él.
	for x in range(cfg.nest_x, cfg.nest_x + 14):
		sim.cmd_paint_phero(sim.food, x, cfg.surface_y - 1, 0.3 + 0.012 * (x - cfg.nest_x))
	var lo := 9999
	var hi := -1
	var nest_visits := 0
	for t in 240 * cfg.tick_rate:
		sim.tick()
		if t % cfg.tick_rate != 0:
			continue
		for i in sim.ants.count:
			if sim.ants.alive[i] == 1 and sim.ants.caste[i] == CasteDefs.Caste.SOLDIER:
				var cx := int(sim.ants.pos[i].x / cfg.cell_px)
				lo = mini(lo, cx)
				hi = maxi(hi, cx)
				if sim.ants.patrol_x[i] == -2:
					nest_visits += 1
	_check("los soldados recorren casi todo el ancho del mapa", hi - lo >= int(sim.world.w * 0.75), "columnas %d..%d de 0..%d" % [lo, hi, sim.world.w - 1])
	_check("de vez en cuando vuelven a revisar el nido", nest_visits > 0)


func _t_eggs_next_to_queen() -> void:
	var cfg := _cfg()
	var sim := Simulation.new(cfg, 7)
	sim.spawn_incremental_start()
	sim.colony.food = 1000.0
	var q := sim.ants.pos[sim.queen_id]
	var ok := true
	var min_d := INF
	for k in 8:
		sim.cmd_buy_egg()
		var p := sim.brood.pos[sim.brood.pos.size() - 1]
		var c := Vector2i(floori(p.x / cfg.cell_px), floori(p.y / cfg.cell_px))
		ok = ok and sim.world.is_passable(c.x, c.y)
		min_d = minf(min_d, p.distance_to(q))
	_check("los huevos nacen en una celda libre", ok)
	_check("los huevos nacen al lado de la reina, no debajo", min_d >= cfg.cell_px * 0.5 and min_d <= cfg.cell_px * 2.0, "distancia mínima %.1f px" % min_d)


func _t_brood_drawn_above_overlay() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var main = load("res://main.tscn").instantiate()
	main.world_size_override = Vector2(480, 270)
	root.add_child(main)
	await process_frame
	await process_frame
	_check("la cría se dibuja por encima de la capa de feromonas y cámaras", main.brood_view.get_index() > main.overlay.get_index())
	_check("y debajo de las hormigas", main.brood_view.get_index() < main.ant_renderer.get_index())
	main.queue_free()
	await process_frame


func _t_drones_in_normal_game() -> void:
	var cfg := _cfg()
	var sim := Simulation.new(cfg, 3)
	sim.spawn_incremental_start()
	sim.colony.food = 1.0e9
	var drones := 0
	for k in 80:
		sim.cmd_buy_egg()
		if sim.brood.caste[sim.brood.caste.size() - 1] == CasteDefs.Caste.DRONE:
			drones += 1
	_check("en Juego normal también nacen zánganos", drones > 0, "%d de 80 huevos" % drones)


func _t_drones_guard_queen() -> void:
	var cfg := _cfg()
	var sim := Simulation.new(cfg, 5)
	sim.spawn_incremental_start()
	var q := sim.ants.pos[sim.queen_id]
	var d := sim.ants.add_ant_at(Vector2i(cfg.nest_x, cfg.surface_y + cfg.shaft_depth + 1), CasteDefs.Caste.DRONE)
	sim.cmd_force_spider()
	sim.spider.pos = q + Vector2(cfg.cell_px * 3.0, 0.0)
	var hp0 := sim.spider.hp
	var attacked := false
	for t in 6 * cfg.tick_rate:
		sim.spider.pos = q + Vector2(cfg.cell_px * 3.0, 0.0)  # la araña se queda junto a la reina
		sim.tick()
		attacked = attacked or sim.ants.state[d] == AntSystem.State.ATTACK
	_check("el zángano sale a defender a la reina cuando una amenaza se le acerca", attacked)
	_check("y la daña", sim.spider.hp < hp0, "vida %.1f -> %.1f" % [hp0, sim.spider.hp])
	# Lejos de la reina y de los huevos, no persigue.
	var sim2 := Simulation.new(cfg, 5)
	sim2.spawn_incremental_start()
	var d2 := sim2.ants.add_ant_at(Vector2i(cfg.nest_x, cfg.surface_y + cfg.shaft_depth + 1), CasteDefs.Caste.DRONE)
	sim2.cmd_force_spider()
	var far_ok := true
	for t in 4 * cfg.tick_rate:
		sim2.spider.pos = Vector2((cfg.nest_x + 40) * cfg.cell_px, (cfg.surface_y - 1) * cfg.cell_px)
		sim2.tick()
		far_ok = far_ok and sim2.ants.state[d2] != AntSystem.State.ATTACK
	_check("una amenaza lejos de la reina no lo saca de su puesto", far_ok)


func _t_drones_escort_queen() -> void:
	var cfg := _cfg()
	var sim := Simulation.new(cfg, 9)
	sim.spawn_incremental_start()
	var d := sim.ants.add_ant_at(Vector2i(cfg.nest_x + 4, cfg.surface_y - 1), CasteDefs.Caste.DRONE)
	var q := sim.ants.pos[sim.queen_id]
	var d0 := sim.ants.pos[d].distance_to(q)
	for t in 30 * cfg.tick_rate:
		sim.tick()
	var d1 := sim.ants.pos[d].distance_to(sim.ants.pos[sim.queen_id])
	_check("sin tareas, el zángano vuelve a escoltar a la reina", d1 < d0 and d1 <= cfg.cell_px * 4.0, "%.0f px -> %.0f px" % [d0, d1])


func _t_save_keeps_patrol() -> void:
	var cfg := _cfg()
	var sim := Simulation.new(cfg, 2)
	sim.spawn_incremental_start()
	for t in 200:
		sim.tick()
	var copy := SaveSystem.from_dict(SaveSystem.to_dict(sim), cfg)
	_check("guardar/cargar conserva los puntos de patrulla", copy.ants.patrol_x == sim.ants.patrol_x)
	var d := SaveSystem.to_dict(sim)
	(d["ants"] as Dictionary).erase("patrol_x")
	var old := SaveSystem.from_dict(d, cfg)
	_check("un guardado viejo (sin patrulla) carga igual", old.ants.patrol_x.size() == old.ants.count)
