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

	# Fase 14: la guía de una pantalla (Fase 12) ya no sale sola; en su lugar, la guía contextual
	# (`CoachView`) abre su primera tarjeta con la partida pausada detrás. Nunca en los otros modos
	# (se comprueba más abajo, al arrancar Historia y Test).
	_check("Juego normal ya no abre la guía de una pantalla", not _app.guide.visible)
	_check("la guía contextual abre su primera tarjeta sin pausar la partida", _app.game.coach.is_showing() and not _app.game.paused)
	_app.game.coach.close_card()
	await _frames(1)
	_check("la tarjeta se cierra", not _app.game.coach.is_showing() and not _app.game.paused)

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
	_check("Modo infinito sigue arrancando con la semilla fija de siempre (cfg.world_seed)",
		_app.game.seed_value == _app.game.cfg.world_seed)
	_check("Modo infinito no muestra la guía de Juego normal", not _app.guide.visible and not _app.game.paused)

	# Fase 11: "Juego normal" sortea un mapa nuevo cada vez (a pedido del jugador), a diferencia
	# de Modo infinito. Dos partidas sucesivas de Juego normal deben caer en semillas distintas
	# (y, con ellas, mapas distintos); no se compara un número exacto de semillas porque `randi()`
	# podría repetir por pura casualidad una vez en un millón, pero dos partidas seguidas con
	# exactamente la misma huella de mundo sería sospechoso de verdad. `_app` (Modo infinito, de
	# más arriba) no se toca ni se libera acá: sigue vivo para la sección de Test de más abajo,
	# que es quien lo libera.
	var app_a: Node = load("res://app/app.tscn").instantiate()
	root.add_child(app_a)
	await _frames(2)
	app_a.menu.play_normal.emit()
	await _frames(3)
	var seed_a: int = app_a.game.seed_value
	app_a.queue_free()
	await _frames(1)
	var app_b: Node = load("res://app/app.tscn").instantiate()
	root.add_child(app_b)
	await _frames(2)
	app_b.menu.play_normal.emit()
	await _frames(3)
	var seed_b: int = app_b.game.seed_value
	_check("Juego normal sortea una semilla distinta en cada partida nueva", seed_a != seed_b,
		"a=%d b=%d" % [seed_a, seed_b])
	app_b.queue_free()
	await _frames(1)
	# `_app` sigue siendo la instancia de Modo infinito de más arriba (con su partida corriendo):
	# `app_a`/`app_b` fueron instancias propias solo para este chequeo, no la tocaron.

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
	_check("Test no muestra la guía de Juego normal", not _app.guide.visible and not _app.game.paused)

	await _t_game_actions()

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


## Fase 17: guardar / nueva partida / volver al menú desde las opciones de la partida, y
## "Continuar partida" en el menú. Respalda la partida guardada real (si existe) y la restaura.
func _t_game_actions() -> void:
	var save_path := "user://save1.json"
	var had_save := FileAccess.file_exists(save_path)
	var save_backup := ""
	if had_save:
		save_backup = FileAccess.get_file_as_string(save_path)
		DirAccess.remove_absolute(save_path)

	_app.game.queue_free()
	await _frames(1)
	_app = load("res://app/app.tscn").instantiate()
	root.add_child(_app)
	await _frames(2)
	_check("sin partida guardada, el menú no muestra \"Continuar partida\"", not _app.menu._continue_btn.visible)
	_app.menu.open_options.emit()
	await _frames(1)
	_check("Opciones desde el menú no muestra las acciones de la partida", not _app.options._game_card.visible)
	_app.options.back_pressed.emit()
	await _frames(1)

	_app.menu.play_normal.emit()
	await _frames(3)
	var day_food: float = _app.game.sim.colony.food
	_app.game.menu_requested.emit()
	await _frames(1)
	_check("Opciones desde la partida muestra Guardar / Nueva partida / Menú principal", _app.options._game_card.visible)
	_app.options.save_requested.emit()
	await _frames(1)
	_check("Guardar partida escribe el archivo y lo confirma", FileAccess.file_exists(save_path)
		and _app.options._save_status.text == "Partida guardada.", _app.options._save_status.text)

	_app.options.new_game_requested.emit()
	await _frames(1)
	_check("Nueva partida pide confirmación", _app.confirm_dialog.visible)
	var old_seed: int = _app.game.seed_value
	_app.confirm_dialog.confirmed.emit()
	_app.confirm_dialog.hide()
	await _frames(3)
	_check("Nueva partida repite el modo (Juego normal) con un mapa nuevo",
		_app.game != null and _app.game.sim.incremental and _app.game.seed_value != old_seed and not _app.options.visible)

	_app.game.menu_requested.emit()
	await _frames(1)
	_app.options.main_menu_requested.emit()
	await _frames(1)
	_app.confirm_dialog.confirmed.emit()
	_app.confirm_dialog.hide()
	await _frames(2)
	_check("Menú principal cierra la partida y vuelve al menú", _app.game == null and _app.menu.visible)
	_check("con una partida guardada, el menú muestra \"Continuar partida\"", _app.menu._continue_btn.visible)

	_app.menu.play_continue.emit()
	await _frames(3)
	_check("Continuar partida carga la guardada (Juego normal)", _app.game != null and _app.game.sim != null
		and _app.game.sim.incremental and absf(_app.game.sim.colony.food - day_food) < 5.0,
		"" if _app.game == null or _app.game.sim == null else "comida %.1f (guardada ~%.1f)" % [_app.game.sim.colony.food, day_food])

	if had_save:
		var f := FileAccess.open(save_path, FileAccess.WRITE)
		f.store_string(save_backup)
		f.close()
	elif FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
