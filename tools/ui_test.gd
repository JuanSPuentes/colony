extends SceneTree
## Prueba la escena real con eventos de teclado y mouse inyectados: herramientas, cámara, pausa,
## velocidades, lluvia, capas, prueba de carga, reinicio y semilla.
## Uso: godot --headless --path . --script tools/ui_test.gd

var _pass := 0
var _fail := 0
var _main: Node


func _initialize() -> void:
	# Las ventanas headless son diminutas: damos un tamaño real y sin escalado para que las
	# posiciones del mouse inyectadas signifiquen lo mismo que en pantalla.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(480, 270)
	_main = load("res://main.tscn").instantiate()
	# En --headless, root.size de arriba no tiene efecto real (la ventana no existe): main.gd
	# necesita que se lo forcemos así para que sus clics de mouse simulados caigan donde deben.
	_main.world_size_override = Vector2(480, 270)
	root.add_child(_main)
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


func _key(code: int, shift := false, hold_frames := 1) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.shift_pressed = shift
	ev.pressed = true
	root.push_input(ev)
	await _frames(hold_frames)
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	root.push_input(up)
	await process_frame


## La cámara vive dentro del SubViewport del mundo (`main.gd`), no en el de `_main`: hay que pasar
## por la transformación de ESE viewport (world -> píxel de pantalla), no por la de `_main`.
func _screen(cell: Vector2i) -> Vector2:
	var world_point := (Vector2(cell) + Vector2(0.5, 0.5)) * 8.0
	return _main.world_vp.get_canvas_transform() * world_point


func _drag(from: Vector2i, to: Vector2i, button := MOUSE_BUTTON_LEFT) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = button
	down.pressed = true
	down.position = _screen(from)
	root.push_input(down)
	await process_frame
	for i in range(1, 7):
		var m := InputEventMouseMotion.new()
		m.position = _screen(Vector2i(roundi(lerpf(from.x, to.x, i / 6.0)), roundi(lerpf(from.y, to.y, i / 6.0))))
		root.push_input(m)
		await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = button
	up.pressed = false
	up.position = _screen(to)
	root.push_input(up)
	await process_frame


func _wheel(up: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	e.pressed = true
	e.position = Vector2(240, 135)
	root.push_input(e)
	await process_frame


func _ticks_per_second(frames: int) -> float:
	var t0 := Time.get_ticks_msec()
	var k0: int = _main.sim.tick_count
	await _frames(frames)
	return float(_main.sim.tick_count - k0) / ((Time.get_ticks_msec() - t0) / 1000.0)


func _run() -> void:
	await _frames(5)
	var sim: Simulation = _main.sim
	var cfg: SimConfig = _main.cfg
	var sy := cfg.surface_y
	# Fase 3: la escena real arranca en modo incremental (spawn_incremental_start, llamado por
	# main.gd.start()): reina + obreras + soldados iniciales, ya no las 100 obreras de la Fase 1.
	var expected_total := 1 + cfg.inc_start_workers + cfg.inc_start_soldiers
	_check("la escena principal arranca con la colonia inicial y todas las vistas", sim.incremental and sim.ants.alive_count == expected_total and _main.terrain_view != null and _main.ant_renderer != null and _main.overlay != null and _main.hud != null and _main.day_night_view != null, "esperado=%d real=%d" % [expected_total, sim.ants.alive_count])
	# Fase 3: la semilla ya no se muestra; en su lugar va el día (y si es de día o de noche).
	_check("el HUD muestra los datos en español", _main.hud._top.text.contains("Hormigas: %d" % expected_total) and _main.hud._top.text.contains("Día 1") and not _main.hud._top.text.contains("Semilla") and _main.hud._top.text.contains("FPS:") and _main.hud._top.text.contains("Vel:") and _main.hud._weather.text.length() > 0, _main.hud._top.text + " | " + _main.hud._weather.text)

	# Fase 3: comprar con 7/8 y la auto-compra con 9 (y con los botones del panel).
	_main.sim.colony.food = 200.0
	var eggs0: int = _main.sim.brood.total_alive()
	await _key(KEY_7)
	await _key(KEY_8)
	_check("7 y 8 compran una obrera y un soldado", _main.sim.econ.bought[CasteDefs.Caste.WORKER] == 1 and _main.sim.econ.bought[CasteDefs.Caste.SOLDIER] == 1 and _main.sim.brood.total_alive() == eggs0 + 2)
	_main.hud._buy_btns[0].pressed.emit()
	_check("el botón de obrera también compra", _main.sim.econ.bought[CasteDefs.Caste.WORKER] == 2)
	await _key(KEY_9)
	_check("9 cambia la auto-compra", _main.sim.econ.auto_mode == IncrementalEconomy.Auto.WORKER and _main.hud._buy_btns[2].text.contains("obreras"))
	await _key(KEY_9)
	await _key(KEY_9)

	# Panel plegable: I pliega el estado (la línea de arriba sigue visible). La barra de controles
	# de abajo se quitó del HUD (Fase 3): esa misma lista vive ahora en Opciones (`Hud.CONTROLS`).
	var hud: Hud = _main.hud
	var status_h: float = hud._status_panel.size.y
	await _key(KEY_I)
	_check("I pliega el panel de estado y deja la línea de arriba", not hud.status_open and hud._status_panel.size.y < status_h and hud._top.visible and not hud._weather.visible and hud._ctrl_panel.position.y < status_h)
	await _key(KEY_I)
	_check("I lo vuelve a desplegar", hud.status_open and hud._status_panel.size.y == status_h and hud._weather.visible)

	# Pausa y velocidades.
	await _key(KEY_SPACE)
	_check("Espacio pausa", _main.paused)
	var k0: int = _main.sim.tick_count
	await _frames(20)
	_check("en pausa no avanzan los ticks", _main.sim.tick_count == k0)
	await _key(KEY_SPACE)
	_check("Espacio reanuda", not _main.paused)
	await _key(KEY_F1)
	var r1 := await _ticks_per_second(40)
	await _key(KEY_F3)
	var r4 := await _ticks_per_second(40)
	await _key(KEY_F2)
	var r2 := await _ticks_per_second(40)
	_check("F1/F2/F3 dan velocidad x1/x2/x4 (más ticks por segundo, mismo tick fijo)", _main.speed == 2 and r4 > r2 * 1.5 and r2 > r1 * 1.4, "ticks/s: x1=%.0f x2=%.0f x4=%.0f" % [r1, r2, r4])
	await _key(KEY_F1)

	# Herramientas del mouse.
	await _key(KEY_1)
	var cells: Array[Vector2i] = [Vector2i(cfg.nest_x + 1, sy + 2), Vector2i(cfg.nest_x + 2, sy + 2), Vector2i(cfg.nest_x + 3, sy + 2)]
	await _drag(cells[0], cells[2])
	_check("clic izquierdo y arrastrar con Cavar marca celdas", _main.sim.world.marked_count == 3, "marcadas=%d" % _main.sim.world.marked_count)
	await _drag(Vector2i(30, sy + 10), Vector2i(32, sy + 10))
	_check("no se marcan celdas sin espacio abierto al lado", _main.sim.world.type_at(31, sy + 10) == WorldGrid.Cell.DIRT)
	await _drag(cells[1], cells[2], MOUSE_BUTTON_RIGHT)
	_check("clic derecho desmarca", _main.sim.world.marked_count == 1)
	await _key(KEY_2)
	await _drag(Vector2i(cfg.nest_x, sy - 1), Vector2i(cfg.nest_x - 20, sy - 1))
	var near: float = _main.sim.food.get_v(cfg.nest_x - 3, sy - 1)
	var far: float = _main.sim.food.get_v(cfg.nest_x - 18, sy - 1)
	_check("la herramienta Feromona pinta un rastro con dirección (más fuerte al final)", far > near and near > 0.0, "cerca=%.2f lejos=%.2f" % [near, far])
	await _drag(Vector2i(cfg.nest_x - 12, sy - 1), Vector2i(cfg.nest_x - 12, sy - 1), MOUSE_BUTTON_RIGHT)
	_check("clic derecho con Feromona borra", _main.sim.food.get_v(cfg.nest_x - 12, sy - 1) == 0.0)

	# Cámara.
	var cam: Camera2D = _main.camera
	var x0 := cam.position.x
	await _key(KEY_D, false, 20)
	_check("WASD mueve la cámara", cam.position.x > x0 + 2.0, "x %.0f -> %.0f" % [x0, cam.position.x])
	var z0: float = cam.zoom.x
	await _wheel(true)
	_check("la rueda hace zoom en pasos fijos", cam.zoom.x > z0 and [0.5, 1.0, 2.0, 3.0, 4.0].has(cam.zoom.x), "zoom %.1f -> %.1f" % [z0, cam.zoom.x])
	for i in 8:
		await _wheel(false)
	_check("el zoom tiene un mínimo", cam.zoom.x == 0.5)
	await _wheel(true)

	# Lluvia, capas y prueba de carga.
	await _key(KEY_L)
	_check("L fuerza la lluvia", _main.sim.weather == Simulation.Weather.RAINING)
	var layer0: int = _main.overlay.layer
	await _key(KEY_TAB)
	_check("Tab cambia de capa de depuración", _main.overlay.layer != layer0, OverlayView.LAYER_NAMES[_main.overlay.layer])
	var seen := {}
	for i in 5:
		seen[_main.overlay.layer] = true
		await _key(KEY_TAB)
	_check("Tab recorre las 5 capas (ninguna, comida, hogar, agua, estados)", seen.size() == 5)
	var before: int = _main.sim.ants.alive_count
	await _key(KEY_F9)
	_check("F9 agrega 400 hormigas", _main.sim.ants.alive_count == before + 400, "%d -> %d" % [before, _main.sim.ants.alive_count])

	# Reinicio y semilla.
	var seed0: int = _main.seed_value
	var sim_before: Simulation = _main.sim
	await _frames(30)
	await _key(KEY_F5)
	_check("F5 reinicia con la misma semilla", _main.sim != sim_before and _main.sim.rng.seed == seed0 and _main.sim.tick_count < 5 and _main.sim.ants.alive_count == expected_total, "semilla %d" % _main.sim.rng.seed)
	var a: Simulation = Simulation.new(cfg, seed0)
	a.spawn_incremental_start()
	for i in 100:
		a.tick()
	var b: Simulation = _main.sim
	while b.tick_count < 100:
		b.tick()
	_check("tras reiniciar, la misma semilla reproduce exactamente la partida", a.checksum() == b.checksum(), "huellas %d / %d" % [a.checksum(), b.checksum()])
	await _key(KEY_F5, true)
	_check("Shift+F5 reinicia con una semilla nueva", _main.seed_value != seed0 and _main.sim.rng.seed == _main.seed_value, "semilla %d" % _main.seed_value)
	print("RESULTADO: %d correctas, %d fallidas" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
