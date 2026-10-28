extends Node2D
## Punto de entrada real del juego (ver `project.godot`, `run/main_scene`). Decide qué pantalla se
## ve: menú, opciones, la guía rápida de Juego normal o la partida. `main.tscn` sigue arrancando
## solo (modo Infinito) cuando se abre directo, para que las pruebas (`ui_test.gd`,
## `screenshot.gd`) no cambien: aquí lo instanciamos con `auto_start = false` y lo arrancamos
## nosotros en el modo que haya elegido el jugador.

const MAIN_SCENE := "res://main.tscn"

var settings: AppSettings
var menu: MainMenu
var options: OptionsScreen
var guide: GuideScreen
var quit_dialog: ConfirmationDialog
var game: Node2D
## A dónde vuelve la flecha de Opciones: "menu" (se abrió desde el menú) o "game" (desde la tuerca).
var _return_to := "menu"
var confirm_dialog: ConfirmationDialog
## Fase 35: el tutorial se empezó desde "Nueva partida": al terminarlo arranca la partida normal
## (si se pidió desde Opciones, vuelve al menú).
var _chain_to_normal := false
var _guide_from_options := false
var _pending: Callable


func _ready() -> void:
	settings = AppSettings.load_settings()
	settings.apply_volume()
	settings.apply_language()

	menu = MainMenu.new()
	add_child(menu)
	# Papeles invertidos a propósito (ver nota en main_menu.gd): "Juego normal" es ahora la
	# economía de comida/compra (antes "Modo infinito") y "Modo infinito" es la colonia con reina,
	# castas y araña (antes "Juego normal"). `_start_game(incremental)` no cambió de significado.
	menu.play_normal.connect(func() -> void: _start_game(true))
	menu.play_infinite.connect(func() -> void: _start_game(false))
	menu.play_test.connect(_start_test_game)
	menu.open_options.connect(func() -> void: _open_options("menu"))
	menu.quit_requested.connect(_ask_quit)

	options = OptionsScreen.new()
	options.visible = false
	add_child(options)
	options.back_pressed.connect(_on_options_back)
	options.volume_changed.connect(_on_volume_changed)
	options.brightness_changed.connect(_on_brightness_changed)
	options.language_changed.connect(_on_language_changed)
	options.quit_requested.connect(_ask_quit)
	options.tips_changed.connect(_on_tips_changed)
	options.tutorial_requested.connect(_on_tutorial_requested)

	guide = GuideScreen.new()
	guide.visible = false
	add_child(guide)
	guide.closed.connect(_on_guide_closed)

	quit_dialog = ConfirmationDialog.new()
	quit_dialog.title = "Salir"
	quit_dialog.dialog_text = "¿Seguro que quieres cerrar el juego?"
	quit_dialog.ok_button_text = "Salir"
	quit_dialog.cancel_button_text = "Cancelar"
	add_child(quit_dialog)
	quit_dialog.confirmed.connect(func() -> void: get_tree().quit())

	# Fase 17: guardar / nueva partida / volver al menú desde las opciones de la partida.
	options.save_requested.connect(_on_save_requested)
	options.new_game_requested.connect(func() -> void: _confirm(
		"¿Empezar una partida nueva? Se pierde lo que no hayas guardado.", "Nueva partida", _restart_same_mode))
	options.main_menu_requested.connect(func() -> void: _confirm(
		"¿Volver al menú principal? Se pierde lo que no hayas guardado.", "Menú principal", _back_to_main_menu))
	menu.play_continue.connect(_continue_game)

	# Fase 35: "Nueva partida" arranca el tutorial la primera vez (obligatorio); después, directo.
	# "Cómo jugar" se abre desde las opciones de la partida.
	menu.play_new.connect(_on_new_game)
	options.how_to_play_requested.connect(func() -> void:
		_guide_from_options = true
		guide.visible = true)
	confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.title = "Confirmar"
	confirm_dialog.cancel_button_text = "Cancelar"
	add_child(confirm_dialog)
	confirm_dialog.confirmed.connect(func() -> void:
		if _pending.is_valid():
			_pending.call())


## Crea la escena de partida (sin arrancarla: cada modo llama a `game.start()` a su manera) y
## esconde el menú. Antes estas líneas estaban repetidas en cada función que arranca una partida.
func _new_game_scene() -> void:
	menu.visible = false
	game = load(MAIN_SCENE).instantiate()
	game.auto_start = false
	add_child(game)
	game.set_brightness(settings.brightness)
	game.menu_requested.connect(func() -> void: _open_options("game"))


func _start_game(incremental: bool) -> void:
	_new_game_scene()
	# "Juego normal" sortea una semilla nueva en cada partida (mapa distinto cada vez, a pedido
	# del jugador); "Modo infinito" sigue arrancando siempre con `cfg.world_seed` fijo, como desde
	# el principio del proyecto — acá no se pidió cambiarlo, y el seed fijo sigue siendo útil para
	# depurar ese modo con un mapa reproducible. F5 dentro de una partida sigue reiniciando con la
	# MISMA semilla que ya estaba (ver `main.gd::start`); solo Shift+F5 sortea una nueva a mano.
	var seed_value: int = randi() if incremental else game.cfg.world_seed
	# Fase 35: los consejos de Juego normal (`CoachView`) solo si el jugador los pidió en Opciones;
	# el tutorial ya explicó todo.
	game.coach_enabled = incremental and settings.show_tips
	# Fase 15: "Juego normal" arranca con el nido cerrado y árboles al azar (ver `main.gd`).
	game.fresh_layout_enabled = incremental
	game.start(seed_value, null, "incremental" if incremental else "historia")


## Fase 35: el tutorial. Mapa fijo (`cfg.world_seed`), para que la explicación sea la misma
## siempre. Al terminarlo (última tarjeta u "Omitir todo") `main` avisa con `tutorial_finished`.
func _start_tutorial() -> void:
	_new_game_scene()
	game.coach_enabled = true
	game.tutorial_finished.connect(_on_tutorial_finished)
	game.start(game.cfg.world_seed, null, "tutorial")


func _on_new_game() -> void:
	if settings.tutorial_done:
		_start_game(true)
	else:
		_chain_to_normal = true
		_start_tutorial()


func _on_tutorial_finished() -> void:
	settings.tutorial_done = true
	settings.save()
	var chain := _chain_to_normal
	_close_game()
	if chain:
		_start_game(true)
	else:
		menu.refresh_continue()
		menu.visible = true


## Opciones → "Ver el tutorial". Con una partida abierta se pierde lo no guardado: se confirma.
func _on_tutorial_requested() -> void:
	var go := func() -> void:
		_close_game()
		_start_tutorial()
	if game != null:
		_confirm("¿Ver el tutorial? Se pierde lo que no hayas guardado.", "Ver el tutorial", go)
	else:
		options.visible = false
		go.call()


func _on_tips_changed(on: bool) -> void:
	settings.show_tips = on
	settings.save()
	if game != null and game.game_mode == "incremental":
		game.coach_enabled = on


## Fase 6: igual que `_start_game`, pero en el modo Test (sandbox, sin victoria/derrota). Función
## hermana en vez de un tercer caso en `_start_game` para no arriesgar el flujo ya probado de
## "Juego normal"/"Modo infinito" (ver tools/test_app_menu.gd).
func _start_test_game() -> void:
	_new_game_scene()
	game.start(game.cfg.world_seed, null, "test")


func _open_options(return_to: String) -> void:
	_return_to = return_to
	if game != null and return_to == "game":
		game.paused = true
	options.set_values(settings.volume, settings.brightness)
	options.set_language(settings.language)
	options.set_tips(settings.show_tips)
	options.set_in_game(game != null and return_to == "game")
	options.visible = true
	menu.visible = false


func _on_guide_closed() -> void:
	guide.visible = false
	if _guide_from_options:
		_guide_from_options = false  # vuelve a las Opciones, que siguen abiertas debajo
		return
	if game != null:
		game.paused = false
	else:
		menu.visible = true


func _on_options_back() -> void:
	options.visible = false
	if _return_to == "menu":
		menu.visible = true
	elif game != null:
		game.paused = false


func _on_volume_changed(v: float) -> void:
	settings.volume = v
	settings.apply_volume()
	settings.save()


func _on_brightness_changed(b: float) -> void:
	settings.brightness = b
	settings.save()
	if game != null:
		game.set_brightness(b)


func _on_language_changed(code: String) -> void:
	settings.language = code
	settings.apply_language()
	settings.save()


func _ask_quit() -> void:
	quit_dialog.popup_centered()


# --- Fase 17: partida en curso desde Opciones, y "Continuar partida" en el menú ------------------

func _confirm(text: String, ok_text: String, action: Callable) -> void:
	_pending = action
	confirm_dialog.dialog_text = text
	confirm_dialog.ok_button_text = ok_text
	confirm_dialog.popup_centered()


func _on_save_requested() -> void:
	if game == null:
		return
	game.save_game()
	var ok := FileAccess.file_exists(game.SAVE_PATH)
	options.show_save_status(tr("Partida guardada.") if ok else tr("No se pudo guardar."))


## Cierra la partida actual (sin guardar). Deja `game` en null.
func _close_game() -> void:
	_chain_to_normal = false
	if game != null:
		game.queue_free()
		game = null
	options.visible = false


func _back_to_main_menu() -> void:
	_close_game()
	menu.refresh_continue()
	menu.visible = true


## Nueva partida en el mismo modo que se estaba jugando (Juego normal sortea mapa nuevo).
func _restart_same_mode() -> void:
	var mode: String = game.game_mode if game != null else "incremental"
	var chain := _chain_to_normal
	_close_game()
	match mode:
		"historia":
			_start_game(false)
		"tutorial":
			_chain_to_normal = chain
			_start_tutorial()
		"test":
			_start_test_game()
		_:
			_start_game(true)


func _continue_game() -> void:
	_new_game_scene()
	game.coach_enabled = settings.show_tips
	game.load_game()
	if game.sim == null:  # no había partida o el archivo no se pudo leer
		_back_to_main_menu()
