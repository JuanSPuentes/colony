extends SceneTree
## Pruebas de la Fase 14: controles nuevos de cámara (clic izquierdo arrastra el mapa, clic derecho
## usa la herramienta, WASD/flechas con Shift), la guía contextual (`CoachView`) y el Nivel 0
## (`sim/colony/tutorial_level.gd`): orden de las lecciones, sin araña ni lluvia ni estaciones
## automáticas, batalla final pedida por la guía, las hormigas de verdad dañan a la reina rival,
## victoria al matarla, guardar/cargar conserva el modo.
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
	_check("el Nivel 0 es modo incremental con su bandera propia", sim.incremental and sim.tutorial_level and not sim.test_mode)
	_check("arranca con la comida del Nivel 0", is_equal_approx(sim.colony.food, cfg.tut_start_food))
	_check("sin lluvia automática", sim.rain_start_tick == -1)
	sim.cmd_add_ants(cfg.inc_spider_first_population + 10)
	# Saltar al último día de la primera estación: en Juego normal aquí empezaría la batalla.
	sim.tick_count = int(cfg.day_length_s * (cfg.season_days[0] - 1) / sim.dt) + 10
	for i in 120:
		sim.tick()
	_check("sin araña aunque la población pase el umbral", sim.spiders_spawned == 0)
	_check("sin batalla de estación automática", not sim.rival_colony.battle_active)

	var normal := Simulation.new(cfg, 3)
	normal.spawn_incremental_start()
	normal.tick_count = sim.tick_count
	normal.tick()
	_check("Juego normal sigue con su batalla de fin de estación", normal.rival_colony.battle_active and not normal.tutorial_level)
	_check("cmd_start_tutorial_battle no hace nada fuera del Nivel 0", not normal.cmd_start_tutorial_battle())

	var before := sim.ants.alive_count
	_check("la guía puede pedir la batalla final", sim.cmd_start_tutorial_battle() and sim.rival_colony.battle_active)
	_check("llegan los refuerzos y el ejército rival chico", sim.ants.alive_count == before + cfg.tut_bonus_soldiers + cfg.tut_rival_ants,
		"%d -> %d" % [before, sim.ants.alive_count])
	_check("la batalla final no se puede pedir dos veces", not sim.cmd_start_tutorial_battle())

	var copy := SaveSystem.from_dict(SaveSystem.to_dict(sim), cfg)
	_check("guardar/cargar conserva el Nivel 0 y su batalla", copy.tutorial_level and copy.tutorial_battle_started and copy.rival_colony.battle_active)

	# Las hormigas del jugador dañan a la reina rival (antes nadie podía: solo moría a mano).
	var q := sim.rival_colony.queen
	var hp0 := q.hp
	for i in sim.ants.count:
		if sim.ants.alive[i] == 1 and sim.ants.faction[i] == 0 and sim.ants.caste[i] == CasteDefs.Caste.SOLDIER:
			sim.ants.pos[i] = q.pos
	for i in 40:
		sim.tick()
	_check("los soldados del jugador dañan a la reina rival", q.hp < hp0, "vida %.1f -> %.1f" % [hp0, q.hp])
	var guard := 0
	while not sim.game_over and guard < 3000:
		for i in sim.ants.count:
			if sim.ants.alive[i] == 1 and sim.ants.faction[i] == 0 and sim.ants.caste[i] == CasteDefs.Caste.SOLDIER:
				sim.ants.pos[i] = q.pos
		sim.tick()
		guard += 1
	_check("matar a la reina rival gana el Nivel 0", sim.game_over and sim.victory and not q.alive, sim.game_over_reason)


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

	_main.coach_enabled = true
	_main.start(_main.cfg.world_seed, null, "tutorial")
	await _frames(3)
	var coach: CoachView = _main.coach
	_check("el Nivel 0 arranca con la primera tarjeta, sin pausar el juego", coach.is_showing() and not _main.paused and coach._title.text == "Nivel 0")
	var wr := Rect2(_main.world_container.position, _main.world_container.size)
	_check("la tarjeta va pegada al costado derecho del mapa", coach._card.position.x + coach._card.size.x > wr.end.x - 30.0 and coach._card.position.x > wr.position.x + wr.size.x * 0.4,
		"tarjeta x=%.0f ancho=%.0f mapa=%s" % [coach._card.position.x, coach._card.size.x, wr])
	_main._zoom_t = 0.999999
	await _frames(2)
	_check("la tarjeta acerca la cámara a lo que explica", _main.zoom_index == CoachView.Z_WIDE)
	var order := []
	for i in 4:
		coach.close_card()
		await _frames(2)
		order.append(coach.lessons[coach.step - 1]["id"])
	_check("las lecciones siguen el orden de importancia", order == ["queen", "food", "castes", "camera"], str(order))
	_check("la lección de cámara muestra su objetivo y no tiene botón", coach.is_showing() and coach._goal_label.visible and not coach._ok.visible)
	# Desde el lado izquierdo del mapa: en esta ventana de prueba (480x270) la tarjeta tapa la mitad
	# derecha, y un clic sobre ella es de la tarjeta, no del mapa.
	await _pixel_drag(Vector2(60, 200), Vector2(20, 200))
	await _until(func() -> bool: return coach.lessons[coach.step - 1]["id"] == "phero")
	_check("cumplir el objetivo pasa sola a la siguiente lección", coach.is_showing() and coach.lessons[coach.step - 1]["id"] == "phero")
	_main.sim.cmd_paint_food(_main.cfg.nest_x, _main.cfg.surface_y - 1, 0.5)
	await _until(func() -> bool: return not coach.is_showing())
	await _frames(3)
	_check("una lección con condición espera a que se cumpla (cosecha)", not coach.is_showing() and coach.lessons[coach.step]["id"] == "harvest")
	_main.sim.delivered = 1
	await _until(func() -> bool: return coach.is_showing())
	_check("la cosecha se explica en cuanto llega la primera hoja", coach.is_showing() and coach._title.text == "Cosecha")
	# Recorrer el resto hasta la batalla, cumpliendo cada objetivo a mano.
	var guard := 0
	while not _main.sim.rival_colony.battle_active and guard < 400:
		guard += 1
		if coach.is_showing() and coach._ok.visible:
			coach.close_card()
		_main.sim.dug = 1
		_main.sim.eggs_bought = 1
		_main.sim.colony.food = 500.0
		await _frames(2)
	_check("la última lección pide la batalla final", _main.sim.tutorial_battle_started and _main.sim.rival_colony.battle_active)
	await _until(func() -> bool: return coach.is_showing())
	_check("la cámara va a la reina rival", coach.is_showing() and coach._title.text == "La reina rival")
	_main.sim.rival_colony.queen.take_damage(9999.0)
	await _until(func() -> bool: return _main.sim.game_over)
	_check("matarla termina el Nivel 0 con victoria", _main.sim.game_over and _main.sim.victory)
	var loaded := SaveSystem.from_dict(SaveSystem.to_dict(_main.sim), _main.cfg)
	_main.start(1, loaded)
	_check("cargar una partida del Nivel 0 vuelve al modo tutorial", _main.game_mode == "tutorial")

	# Barra de arriba: símbolos y números de la colonia.
	_main.start(12345, null, "incremental")
	await _frames(3)
	var bar_text := ""
	for l in _main.hud._topbar_row.get_children():
		if (l as Label).visible:
			bar_text += (l as Label).text + " | "
	_check("la barra de arriba muestra hormigas, comida, día y la próxima batalla", bar_text.contains("🐜") and bar_text.contains("🍃") and bar_text.contains("Día 1") and bar_text.contains("⚔ en %d días" % (_main.cfg.season_days[0] - 1)), bar_text)


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
	_main.sim.game_over_reason = "Derrotaste a la reina rival y superaste el Nivel 0.\nEn Juego normal, así termina cada estación."
	await _frames(3)
	var p: PanelContainer = _main.hud._end_panel
	var wr := Rect2(_main.world_container.position, _main.world_container.size)
	_check("el cartel de fin de partida entra entero en el mapa", p.visible and wr.encloses(Rect2(p.position, p.size)), "cartel=%s mapa=%s" % [Rect2(p.position, p.size), wr])
