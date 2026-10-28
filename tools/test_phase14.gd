extends SceneTree
## Pruebas de la Fase 14: controles nuevos de cámara (clic izquierdo arrastra el mapa, clic derecho
## usa la herramienta, WASD/flechas con Shift) y la guía contextual (`CoachView`). Fase 35: el
## tutorial (colonia ya armada, sin araña ni lluvia ni estaciones, tarjetas por capítulo con
## Siguiente/Omitir/Omitir todo), las hormigas de verdad dañan a la reina rival, guardar/cargar
## conserva el modo.
## Uso: godot --headless --path . --script tools/test_phase14.gd      (código de salida 1 si algo falla)

var _pass := 0
var _fail := 0
var _main: Node


func _initialize() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(480, 270)
	_run()


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("[%s] %s %s" % ["OK " if ok else "FALLA", label, detail])


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## Espera cuadros hasta que `cond` se cumpla (o se agote `max_frames`): en headless un cuadro puede
## durar menos que un tick de simulación, así que contar cuadros fijos da resultados al azar.
func _until(cond: Callable, max_frames := 300) -> void:
	for i in max_frames:
		if cond.call():
			return
		await process_frame


func _cfg() -> SimConfig:
	var c := SimConfig.new()
	return c


func _screen(cell: Vector2i) -> Vector2:
	var world_point := (Vector2(cell) + Vector2(0.5, 0.5)) * 8.0
	return _main.world_vp.get_canvas_transform() * world_point


func _drag(from: Vector2i, to: Vector2i, button: int, shift := false) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = button
	down.shift_pressed = shift
	down.pressed = true
	down.position = _screen(from)
	root.push_input(down)
	await process_frame
	var last := down.position
	for i in range(1, 7):
		var m := InputEventMouseMotion.new()
		# Mientras se arrastra la cámara, la celda bajo el mouse cambia: se calcula en píxeles de
		# pantalla desde el punto de partida, no re-proyectando celdas.
		m.position = down.position.lerp(_screen(to) if button == MOUSE_BUTTON_RIGHT else down.position + Vector2(to - from) * 8.0, i / 6.0)
		m.relative = m.position - last
		last = m.position
		root.push_input(m)
		await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = button
	up.pressed = false
	up.position = last
	root.push_input(up)
	await process_frame


func _pixel_drag(from: Vector2, to: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = from
	root.push_input(down)
	await process_frame
	var last := from
	for i in range(1, 7):
		var m := InputEventMouseMotion.new()
		m.position = from.lerp(to, i / 6.0)
		m.relative = m.position - last
		last = m.position
		root.push_input(m)
		await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = to
	root.push_input(up)
	await process_frame


func _key(code: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = down
	root.push_input(ev)
	await process_frame


func _run() -> void:
	await _sim_tests()
	_main = load("res://main.tscn").instantiate()
	_main.world_size_override = Vector2(480, 270)
	_main.auto_start = false
	root.add_child(_main)
	await _frames(2)
	await _input_tests()
	await _coach_tests()
	await _zoom_fill_tests()
	_phero_tests()
	await _end_banner_tests()
	print("RESULTADO: %d correctas, %d fallidas" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _sim_tests() -> void:
	var cfg := _cfg()
	var sim := Simulation.new(cfg, 3)
	sim.spawn_tutorial_start()
	_check("el tutorial es modo incremental con su bandera propia", sim.incremental and sim.tutorial_level and not sim.test_mode)
	_check("arranca con la comida del tutorial", is_equal_approx(sim.colony.food, cfg.tut_start_food))
	_check("sin lluvia automática", sim.rain_start_tick == -1)
	# Fase 35: la colonia ya armada — nido abierto, las tres cámaras, todas las castas y cría.
	var top := (cfg.surface_y - 1) * sim.world.w + cfg.nest_x
	_check("el nido ya está abierto a la superficie", sim.fields.nest_dist[top] < NestDistanceField.FAR)
	var rooms := {}
	for r in sim.world.room:
		rooms[r] = true
	_check("tiene Real, Guardería y Almacén", rooms.has(WorldGrid.Room.ROYAL) and rooms.has(WorldGrid.Room.NURSERY) and rooms.has(WorldGrid.Room.STORAGE))
	var castes := sim.ants.count_by_caste([CasteDefs.Caste.WORKER, CasteDefs.Caste.SOLDIER, CasteDefs.Caste.DRONE])
	_check("con obreras, soldados y zánganos", castes[CasteDefs.Caste.WORKER] >= cfg.tut_extra_workers
		and castes[CasteDefs.Caste.SOLDIER] >= cfg.tut_extra_soldiers and castes[CasteDefs.Caste.DRONE] == cfg.tut_drones, str(castes))
	_check("y cría en camino", sim.brood.stage.size() >= cfg.tut_eggs)
	_check("con el árbol gigante y la rival en el mapa", sim.home_tree != null and sim.rival_colony.home and sim.rival_colony.queen.alive)
	var rivals := sim.rival_colony.alive_count()
	sim.cmd_add_ants(cfg.inc_spider_first_population + 10)
	# Saltar al último día de la primera estación: en Juego normal aquí empezaría la batalla.
	sim.tick_count = int(cfg.day_length_s * (cfg.season_days[0] - 1) / sim.dt) + 10
	for i in 120:
		sim.tick()
	_check("sin araña aunque la población pase el umbral", sim.spiders_spawned == 0)
	_check("sin estaciones: la rival no crece ni ataca", not sim.rival_colony.battle_active
		and sim.rival_colony.alive_count() == rivals and not sim.ants.raiding.has(1))

	var normal := Simulation.new(cfg, 3)
	normal.spawn_incremental_start()
	normal.tick_count = sim.tick_count
	normal.tick()
	_check("Juego normal sigue con su batalla de fin de estación", normal.rival_colony.battle_active and not normal.tutorial_level)

	var copy := SaveSystem.from_dict(SaveSystem.to_dict(sim), cfg)
	_check("guardar/cargar conserva el tutorial", copy.tutorial_level)

	# Las hormigas del jugador dañan a la reina rival (antes nadie podía: solo moría a mano).
	var q := sim.rival_colony.queen
	var hp0 := q.hp
	for i in sim.ants.count:
		if sim.ants.alive[i] == 1 and sim.ants.faction[i] == 0 and sim.ants.caste[i] == CasteDefs.Caste.SOLDIER:
			sim.ants.pos[i] = q.pos
	for i in 40:
		sim.tick()
	_check("los soldados del jugador dañan a la reina rival", q.hp < hp0, "vida %.1f -> %.1f" % [hp0, q.hp])


func _input_tests() -> void:
	_main.start(12345, null, "incremental")
	await _frames(3)
	var cfg: SimConfig = _main.cfg
	var sy := cfg.surface_y
	_main._set_zoom(3)
	_main._zoom_t = 0.999999
	await _frames(2)
	await _key(KEY_1, true)
	await _key(KEY_1, false)
	var cam: Camera2D = _main.camera
	var p0 := cam.position
	var marked0: int = _main.sim.world.marked_count
	await _drag(Vector2i(cfg.nest_x + 1, sy + 2), Vector2i(cfg.nest_x - 6, sy + 2), MOUSE_BUTTON_LEFT)
	_check("clic izquierdo y arrastrar mueve el mapa", cam.position.distance_to(p0) > 2.0, "%s -> %s" % [p0, cam.position])
	_check("clic izquierdo ya no cava", _main.sim.world.marked_count == marked0)
	_main._drag_vel = Vector2.ZERO
	await _drag(Vector2i(cfg.nest_x + 1, sy + 2), Vector2i(cfg.nest_x + 3, sy + 2), MOUSE_BUTTON_RIGHT)
	_check("clic derecho usa la herramienta (Cavar)", _main.sim.world.marked_count == marked0 + 3, "marcadas=%d" % _main.sim.world.marked_count)
	await _drag(Vector2i(cfg.nest_x + 2, sy + 2), Vector2i(cfg.nest_x + 3, sy + 2), MOUSE_BUTTON_RIGHT, true)
	_check("Shift + clic derecho borra", _main.sim.world.marked_count == marked0 + 1)
	# Regresión: el objetivo "pinta Comida" del tutorial se quedaba trabado porque el pincel real
	# usa `cmd_paint_phero`, que no marcaba `food_painted` (solo lo hacía `cmd_paint_food`).
	_check("todavía no se pintó Comida", not _main.sim.food_painted)
	await _key(KEY_2, true)
	await _key(KEY_2, false)
	await _drag(Vector2i(cfg.nest_x, sy - 1), Vector2i(cfg.nest_x - 4, sy - 1), MOUSE_BUTTON_RIGHT)
	_check("pintar Comida con el mouse cumple el objetivo del tutorial", _main.sim.food_painted)
	await _key(KEY_1, true)
	await _key(KEY_1, false)

	_main._set_zoom(1)
	_main._zoom_t = 0.999999
	await _frames(2)
	cam.position = Vector2(cfg.nest_x * cfg.cell_px, (sy + 10) * cfg.cell_px)
	var x0 := cam.position.x
	await _key(KEY_RIGHT, true)
	await _frames(15)
	await _key(KEY_RIGHT, false)
	var slow := cam.position.x - x0
	_check("las flechas mueven la cámara", slow > 2.0, "dx=%.1f" % slow)
	await _frames(20)
	_main._pan_vel = Vector2.ZERO
	cam.position.x = x0
	await _key(KEY_SHIFT, true)
	await _key(KEY_RIGHT, true)
	await _frames(15)
	await _key(KEY_RIGHT, false)
	await _key(KEY_SHIFT, false)
	var fast := cam.position.x - x0
	_check("con Shift la cámara va más rápido", fast > slow * 1.5, "normal=%.1f rápido=%.1f" % [slow, fast])
	_main._pan_vel = Vector2.ZERO
	await _key(KEY_D, true)
	await _key(KEY_A, true)
	await _key(KEY_A, false)
	_check("soltar A con D apretada sigue moviendo a la derecha", _main._pan == Vector2.RIGHT)
	await _key(KEY_D, false)
	await _key(KEY_W, true)
	await _key(KEY_D, true)
	_check("la diagonal no va más rápido que un eje", is_equal_approx(_main._pan.length(), 1.0))
	await _key(KEY_W, false)
	await _key(KEY_D, false)


func _coach_tests() -> void:
	_main.coach_enabled = false
	_main.start(12345, null, "incremental")
	await _frames(3)
	_check("sin coach_enabled (main.tscn directo) no aparece ninguna tarjeta", not _main.coach.is_showing())

	# Fase 35: el tutorial — tarjetas por capítulo con Siguiente / Omitir / Omitir todo.
	_main.coach_enabled = true
	_main.start(_main.cfg.world_seed, null, "tutorial")
	await _frames(3)
	var coach: CoachView = _main.coach
	_check("el tutorial arranca con la primera tarjeta, sin pausar el juego", coach.is_showing() and not _main.paused and coach._title.text == "Bienvenida")
	var wr := Rect2(_main.world_container.position, _main.world_container.size)
	_check("la tarjeta va pegada al costado derecho del mapa", coach._card.position.x + coach._card.size.x > wr.end.x - 30.0 and coach._card.position.x > wr.position.x + wr.size.x * 0.4,
		"tarjeta x=%.0f ancho=%.0f mapa=%s" % [coach._card.position.x, coach._card.size.x, wr])
	_check("con Siguiente, Omitir y Omitir todo", coach._ok.visible and coach._skip.visible and coach._skip_all.visible)
	_main._zoom_t = 0.999999
	await _frames(2)
	_check("la tarjeta acerca la cámara a lo que explica", _main.zoom_index == CoachView.Z_WIDE)
	coach.close_card()
	await _frames(2)
	_check("Siguiente pasa al capítulo de la colonia", coach._title.text == "La cámara Real" and coach._count.text.begins_with("La colonia"), coach._count.text)
	coach.skip_chapter()
	await _frames(2)
	_check("Omitir salta el resto del capítulo", coach._title.text == "La reina", coach._title.text)
	var finished := [false]
	_main.tutorial_finished.connect(func() -> void: finished[0] = true)
	while coach.step < coach.lessons.size():
		coach.close_card()
		await _frames(2)
	_check("la última tarjeta no se puede omitir", coach.is_showing() and not coach._skip.visible and not coach._skip_all.visible)
	coach.close_card()
	_check("cerrarla termina el tutorial", finished[0])
	_main.start(_main.cfg.world_seed, null, "tutorial")
	await _frames(3)
	finished[0] = false
	coach.skip_all()
	_check("Omitir todo lo termina en cualquier momento", finished[0])
	var loaded := SaveSystem.from_dict(SaveSystem.to_dict(_main.sim), _main.cfg)
	_main.start(1, loaded)
	_check("cargar una partida del tutorial vuelve al modo tutorial", _main.game_mode == "tutorial")

	# Barra de arriba: símbolos y números de la colonia.
	_main.start(12345, null, "incremental")
	await _frames(3)
	# Fase 28: cada dato es un ícono pixel (`HudIcons`) más su texto, ya no un emoji en el texto.
	var bar_text := ""
	var icons_ok := true
	for item in _main.hud._topbar_row.get_children():
		if (item as Control).visible:
			bar_text += (item.get_child(1) as Label).text + " | "
			icons_ok = icons_ok and (item.get_child(0) as TextureRect).texture != null
	_check("la barra de arriba muestra hormigas, comida, día y la próxima batalla", icons_ok and bar_text.contains("Día 1") and bar_text.contains("en %d días" % (_main.cfg.season_days[0] - 1)), bar_text)


## Mapa a pantalla completa: ningún zoom deja ver más allá del mundo (sin franjas negras).
func _zoom_fill_tests() -> void:
	# Un área más alta que ancha en proporción al mundo: 0.5 dejaría ver de más por arriba/abajo.
	_main.world_size_override = Vector2(480, 400)
	_main._resize_world_container()
	await _frames(3)
	for i in 8:
		_main._set_zoom(_main.zoom_index - 1)
		_main._zoom_t = 0.999999
		await _frames(2)
	var vp: Vector2 = Vector2(_main.world_vp.size) / _main.camera.zoom.x
	var world: Vector2 = Vector2(_main.sim.world.w, _main.sim.world.h) * _main.cfg.cell_px
	_check("al alejar al máximo el mapa llena toda la pantalla", vp.x <= world.x + 0.5 and vp.y <= world.y + 0.5, "visible=%s mundo=%s zoom=%.2f" % [vp, world, _main.camera.zoom.x])
	_main.world_size_override = Vector2(480, 270)
	_main._resize_world_container()
	await _frames(3)


## Rastro pintado por el jugador: no se desgasta (lo depositado por las hormigas sí).
func _phero_tests() -> void:
	var cfg := _cfg()
	cfg.rain_auto = false
	var sim := Simulation.new(cfg, 4)
	var y := cfg.surface_y - 1
	for x in range(cfg.nest_x, cfg.nest_x - 10, -1):
		sim.cmd_paint_phero(sim.food, x, y, 0.3 + 0.01 * (cfg.nest_x - x))
	var i0 := y * sim.world.w + cfg.nest_x - 5
	var painted := sim.food.data[i0]
	var other := y * sim.world.w + cfg.nest_x + 20
	sim.food.deposit(other, 0.3)
	for k in int(300.0 / sim.dt):
		if k % cfg.pheromone_step_ticks == 0:
			sim.food.decay(sim.dt * cfg.pheromone_step_ticks, 1.0)
	_check("el rastro pintado no se desgasta en 5 minutos", is_equal_approx(sim.food.data[i0], painted), "%.3f -> %.3f" % [painted, sim.food.data[i0]])
	_check("lo que dejan las hormigas sí se desgasta", sim.food.data[other] < 0.05, "%.3f" % sim.food.data[other])
	_check("el rastro conserva la pendiente hacia la planta", sim.food.data[i0 - 1] > sim.food.data[i0])
	var copy := SaveSystem.from_dict(SaveSystem.to_dict(sim), cfg)
	_check("guardar/cargar conserva el rastro pintado", not copy.food.floor_v.is_empty() and is_equal_approx(copy.food.floor_v[i0], painted))
	sim.cmd_erase_phero(sim.food, cfg.nest_x - 5, y)
	sim.food.decay(1.0, 1.0)
	_check("borrar con Shift + clic derecho lo quita del todo", sim.food.data[i0] == 0.0)
	sim.cmd_paint_phero(sim.danger, cfg.nest_x, y, 0.5)
	for k in 200:
		sim.danger.decay(1.0, 1.0)
	_check("Peligro sigue siendo un aviso que se apaga solo", sim.danger.data[y * sim.world.w + cfg.nest_x] == 0.0)


func _end_banner_tests() -> void:
	_main.coach_enabled = false
	_main.start(_main.cfg.world_seed, null, "tutorial")
	await _frames(2)
	_main.sim.game_over = true
	_main.sim.victory = true
	_main.sim.game_over_reason = "Un motivo largo de fin de partida, para ver que el cartel entra entero.
Con una segunda línea también larga, como los avisos reales."
	await _frames(3)
	var p: PanelContainer = _main.hud._end_panel
	var wr := Rect2(_main.world_container.position, _main.world_container.size)
	_check("el cartel de fin de partida entra entero en el mapa", p.visible and wr.encloses(Rect2(p.position, p.size)), "cartel=%s mapa=%s" % [Rect2(p.position, p.size), wr])
