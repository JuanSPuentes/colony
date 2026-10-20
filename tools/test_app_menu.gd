extends SceneTree
## Prueba el flujo del menú (app/app.gd): arranca en el menú, cada botón lleva a donde debe,
## la tuerca durante la partida abre Opciones y la flecha vuelve al lugar correcto, y el volumen
## y el brillo se guardan entre sesiones. No usa clics de mouse reales (no hace falta: son
## Controls comunes, sin cámara ni SubViewport de por medio): llama directo a sus señales, que es
## exactamente lo que un clic real dispara.
## Uso: godot --headless --path . --script tools/test_app_menu.gd

var _pass := 0
var _fail := 0
var _app: Node


func _initialize() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1440, 810)
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


func _run() -> void:
	# Ambiente limpio: si hay preferencias guardadas de una sesión real, las respaldamos y
	# las restauramos al final para no dejar nada distinto a como estaba.
	var backup := ""
	var had_backup := FileAccess.file_exists(AppSettings.PATH)
	if had_backup:
		var f := FileAccess.open(AppSettings.PATH, FileAccess.READ)
		backup = f.get_as_text()
		f.close()

	_app = load("res://app/app.tscn").instantiate()
	root.add_child(_app)
	await _frames(3)

	_check("arranca mostrando el menú", _app.menu.visible and not _app.options.visible and _app.game == null)

	# Opciones desde el menú: la flecha debe volver al menú.
	_app.menu.open_options.emit()
	await _frames(1)
	_check("Opciones desde el menú se abre y oculta el menú", _app.options.visible and not _app.menu.visible)
	_app.options.volume_changed.emit(0.4)
	_app.options.brightness_changed.emit(1.2)
	_check("el volumen y el brillo quedan en las preferencias", absf(_app.settings.volume - 0.4) < 0.001 and absf(_app.settings.brightness - 1.2) < 0.001)
	_app.options.back_pressed.emit()
	await _frames(1)
	_check("la flecha desde el menú vuelve al menú", _app.menu.visible and not _app.options.visible)

	# Papeles invertidos a propósito (ver main_menu.gd): "Juego normal" es la economía de
	# comida/compra (incremental) y "Modo infinito" es la colonia con reina/castas/araña (Historia).
	_app.menu.play_normal.emit()
	await _frames(3)
	_check("Juego normal arranca en modo incremental (comida/compra)", _app.game != null and _app.game.sim.incremental, "" if _app.game == null else "incremental=%s" % _app.game.sim.incremental)

	# La tuerca durante la partida: abre Opciones y pausa; la flecha debe volver al juego, no al menú.
	_app.game.menu_requested.emit()
	await _frames(1)
	_check("la tuerca durante la partida abre Opciones y pausa", _app.options.visible and _app.game.paused)
	_app.options.back_pressed.emit()
	await _frames(1)
	_check("la flecha desde la tuerca vuelve al juego (no al menú) y lo despausa", not _app.options.visible and not _app.menu.visible and not _app.game.paused)

	# Reiniciar (F5-equivalente) en modo incremental debe conservar el modo, no volver a Historia.
	var seed0: int = _app.game.seed_value
	_app.game.start(seed0)
	_check("reiniciar conserva el modo de juego (incremental)", _app.game.sim.incremental)

	# Modo Infinito (Historia): se descarta la partida de comida/compra y se arranca una nueva.
	_app.game.queue_free()
	await _frames(1)
	_app = load("res://app/app.tscn").instantiate()
	root.add_child(_app)
	await _frames(2)
	_app.menu.play_infinite.emit()
	await _frames(3)
	_check("Modo infinito arranca en modo Historia (con reina y nodrizas)", not _app.game.sim.incremental and _app.game.sim.queen_id >= 0)
	var expected_historia: int = _app.game.cfg.initial_ants + 1 + _app.game.cfg.initial_nurses
	_check("la colonia de Historia arranca con obreras+reina+nodrizas", _app.game.sim.ants.alive_count == expected_historia, "esperado=%d real=%d" % [expected_historia, _app.game.sim.ants.alive_count])

	# Fase 6: Test arranca el sandbox con la composición fija (50 hormigas), nunca con victoria/derrota.
	_app.game.queue_free()
	await _frames(1)
	_app = load("res://app/app.tscn").instantiate()
	root.add_child(_app)
	await _frames(2)
	_app.menu.play_test.emit()
	await _frames(3)
	_check("Test arranca el modo sandbox (sim.test_mode)", _app.game.sim.test_mode)
	_check("la colonia de Test arranca con 50 hormigas", _app.game.sim.ants.alive_count == 50, "real=%d" % _app.game.sim.ants.alive_count)

	# Salir: el botón debe pedir confirmación, no cerrar directo.
	var closed := false
	auto_accept_quit = false
	_app.quit_dialog.confirmed.connect(func() -> void: closed = true)
	_app.menu.visible = true
	_app.options.visible = false
	_app.menu.quit_requested.emit()
	await _frames(1)
	_check("Salir pide confirmación en vez de cerrar directo", _app.quit_dialog.visible and not closed)

	# Limpieza: dejamos las preferencias como estaban (o las borramos si no existían).
	if had_backup:
		var f2 := FileAccess.open(AppSettings.PATH, FileAccess.WRITE)
		f2.store_string(backup)
		f2.close()
	elif FileAccess.file_exists(AppSettings.PATH):
		DirAccess.remove_absolute(AppSettings.PATH)

	print("RESULTADO: %d correctas, %d fallidas" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
