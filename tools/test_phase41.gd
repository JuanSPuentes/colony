extends SceneTree
## Pruebas de la Fase 41 (auditoría UX, punto 1): menú de pausa único. Continuar, Guardar partida,
## Opciones y Menú principal; ya no hay «Reiniciar» (borraba la partida sin preguntar) y salir al
## menú pide confirmación. «Guardar» escribe el guardado real: se respalda y se restaura.
## Uso: godot --headless --path . --script tools/test_phase41.gd      (código de salida 1 si algo falla)

const MAIN_SCRIPT := preload("res://main.gd")

var _pass := 0
var _fail := 0
var _app: Node
var _backups := {}


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


func _backup() -> void:
	for p in [MAIN_SCRIPT.SAVE_PATH, MAIN_SCRIPT.SAVE_PATH + SaveSystem.BACKUP_SUFFIX, AppSettings.PATH, AppSettings.PATH + SaveSystem.BACKUP_SUFFIX]:
		_backups[p] = FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else null


func _restore() -> void:
	for p in _backups:
		if _backups[p] == null:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(p)
		else:
			var f := FileAccess.open(p, FileAccess.WRITE)
			f.store_string(_backups[p])
			f.close()


func _pause_buttons() -> Array:
	var out := []
	for b in _app.game.hud._pause_panel.find_children("*", "Button", true, false):
		out.append((b as Button).text)
	return out


func _press(text: String) -> void:
	for b in _app.game.hud._pause_panel.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			(b as Button).pressed.emit()
			return
	_check("existe el botón «%s»" % text, false)


func _run() -> void:
	_backup()
	_app = load("res://app/app.tscn").instantiate()
	root.add_child(_app)
	await _frames(3)
	_app.settings.tutorial_done = true
	_app._start_game(true)
	await _frames(3)
	_app.game.paused = true  # Espacio: pausa rápida
	await _frames(2)
	var hud: Hud = _app.game.hud
	_check("la pausa rápida (Espacio) no tapa la pantalla con el menú", not hud._pause_panel.visible)
	_app.game.open_pause_menu()  # Esc / P
	await _frames(2)
	_check("Esc / P abre el menú de pausa y pausa", hud._pause_panel.visible and _app.game.paused)
	var labels := _pause_buttons()
	_check("tiene Continuar, Guardar partida, Opciones y Menú principal",
		labels == ["Continuar", "Guardar partida", "Opciones", "Menú principal"], str(labels))
	_check("ya no tiene «Reiniciar» (borraba la partida sin preguntar)", not "Reiniciar" in labels)

	_press("Guardar partida")
	_check("Guardar partida guarda y lo avisa", FileAccess.file_exists(MAIN_SCRIPT.SAVE_PATH) and hud._pause_status.visible
		and hud._pause_status.text == "Partida guardada.", hud._pause_status.text)

	_press("Continuar")
	await _frames(2)
	_check("Continuar reanuda el juego y cierra el menú", not _app.game.paused and not hud._pause_panel.visible)
	_app.game.open_pause_menu()
	await _frames(2)
	_check("al volver a abrirlo, el aviso de la vez anterior no queda", not hud._pause_status.visible)

	_press("Opciones")
	await _frames(1)
	_check("Opciones abre la pantalla de Opciones", _app.options.visible)
	_app.options.back_pressed.emit()
	await _frames(1)

	var sim_before: Simulation = _app.game.sim
	_press("Menú principal")
	await _frames(1)
	_check("Menú principal pide confirmación y no sale todavía", _app.confirm_dialog.visible and _app.game != null and _app.game.sim == sim_before)
	_app.confirm_dialog.hide()

	# Punto 2 de la auditoría: la barra superior entra entera, sin meterse bajo la tuerca, aun a
	# 1280x800 (Steam Deck) y con todos los datos a la vista (lluvia y velocidad incluidas).
	_app.game.close_pause_menu()
	_app.game.sim.weather = Simulation.Weather.RAINING
	_app.game.sim.rain_end_tick = _app.game.sim.tick_count + 100000
	_app.game.speed = 4
	for res in [Vector2i(1280, 800), Vector2i(1440, 810), Vector2i(1920, 1080)]:
		root.size = res
		await _frames(4)
		var bar: Control = hud._topbar
		var row_w: float = hud._topbar_row.get_combined_minimum_size().x
		_check("a %dx%d la barra superior entra entera" % [res.x, res.y], row_w <= bar.size.x and bar.position.x + bar.size.x <= res.x - Hud.TOPBAR_H - 8.0 + 0.5,
			"contenido %.0f px en %.0f px, letra %d" % [row_w, bar.size.x, hud._top_font])
	root.size = Vector2i(1440, 810)
	_app.game.speed = 1
	await _frames(2)

	# Fin de partida: botones en vez de "F5: jugar de nuevo" (F5 ya no existe fuera del editor).
	_check("F5 y las amenazas forzadas son solo del editor", _app.game.dev_keys == OS.has_feature("editor"))
	_app.game.sim.game_over = true
	await _frames(2)
	var end_buttons := []
	for b in hud._end_panel.find_children("*", "Button", true, false):
		end_buttons.append((b as Button).text)
	_check("el fin de partida ofrece Jugar de nuevo y Menú principal", end_buttons == ["Jugar de nuevo", "Menú principal"], str(end_buttons))
	var old_game: Node = _app.game
	for b in hud._end_panel.find_children("*", "Button", true, false):
		if (b as Button).text == "Jugar de nuevo":
			(b as Button).pressed.emit()
	await _frames(3)
	_check("Jugar de nuevo arranca otra partida del mismo modo", _app.game != null and _app.game != old_game and _app.game.game_mode == "incremental")
	_app.game.sim.game_over = true
	await _frames(1)
	for b in _app.game.hud._end_panel.find_children("*", "Button", true, false):
		if (b as Button).text == "Menú principal":
			(b as Button).pressed.emit()
	await _frames(2)
	_check("con la partida terminada, Menú principal sale sin preguntar", _app.game == null and _app.menu.visible and not _app.confirm_dialog.visible)
	_restore()
	print("RESULTADO: %d correctas, %d fallidas" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
