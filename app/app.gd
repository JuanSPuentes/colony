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


func _ready() -> void:
	settings = AppSettings.load_settings()
	settings.apply_volume()

	menu = MainMenu.new()
	add_child(menu)
	# Papeles invertidos a propósito (ver nota en main_menu.gd): "Juego normal" es ahora la
	# economía de comida/compra (antes "Modo infinito") y "Modo infinito" es la colonia con reina,
	# castas y araña (antes "Juego normal"). `_start_game(incremental)` no cambió de significado.
	menu.play_tutorial.connect(_start_tutorial)
	menu.play_normal.connect(func() -> void: _start_game(true))
	menu.play_infinite.connect(func() -> void: _start_game(false))
	menu.play_test.connect(_start_test_game)
	menu.open_options.connect(func() -> void: _open_options("menu"))
	menu.open_guide.connect(_open_guide)
	menu.quit_requested.connect(_ask_quit)

	options = OptionsScreen.new()
	options.visible = false
	add_child(options)
	options.back_pressed.connect(_on_options_back)
	options.volume_changed.connect(_on_volume_changed)
	options.brightness_changed.connect(_on_brightness_changed)
	options.quit_requested.connect(_ask_quit)

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


func _start_game(incremental: bool) -> void:
	menu.visible = false
	game = load(MAIN_SCENE).instantiate()
	game.auto_start = false
	add_child(game)
	game.set_brightness(settings.brightness)
	game.menu_requested.connect(func() -> void: _open_options("game"))
	# "Juego normal" sortea una semilla nueva en cada partida (mapa distinto cada vez, a pedido
	# del jugador); "Modo infinito" sigue arrancando siempre con `cfg.world_seed` fijo, como desde
	# el principio del proyecto — acá no se pidió cambiarlo, y el seed fijo sigue siendo útil para
	# depurar ese modo con un mapa reproducible. F5 dentro de una partida sigue reiniciando con la
	# MISMA semilla que ya estaba (ver `main.gd::start`); solo Shift+F5 sortea una nueva a mano.
	var seed_value: int = randi() if incremental else game.cfg.world_seed
	# Fase 14: en vez de la guía de una pantalla al empezar (Fase 12), "Juego normal" explica
	# cada cosa la primera vez que aparece (`CoachView`). La guía sigue en el menú ("Cómo jugar").
	game.coach_enabled = incremental
	# Fase 15: "Juego normal" arranca con el nido cerrado y árboles al azar (ver `main.gd`).
	game.fresh_layout_enabled = incremental
	game.start(seed_value, null, "incremental" if incremental else "historia")


## Fase 14: Nivel 0. Mapa fijo (`cfg.world_seed`), para que la explicación sea la misma siempre.
func _start_tutorial() -> void:
	menu.visible = false
	game = load(MAIN_SCENE).instantiate()
	game.auto_start = false
	add_child(game)
	game.set_brightness(settings.brightness)
	game.menu_requested.connect(func() -> void: _open_options("game"))
	game.coach_enabled = true
	game.start(game.cfg.world_seed, null, "tutorial")


func _open_guide() -> void:
	menu.visible = false
	guide.visible = true


## Fase 6: igual que `_start_game`, pero en el modo Test (sandbox, sin victoria/derrota). Función
## hermana en vez de un tercer caso en `_start_game` para no arriesgar el flujo ya probado de
## "Juego normal"/"Modo infinito" (ver tools/test_app_menu.gd).
func _start_test_game() -> void:
	menu.visible = false
	game = load(MAIN_SCENE).instantiate()
	game.auto_start = false
	add_child(game)
	game.set_brightness(settings.brightness)
	game.menu_requested.connect(func() -> void: _open_options("game"))
	game.start(game.cfg.world_seed, null, "test")


func _open_options(return_to: String) -> void:
	_return_to = return_to
	if game != null and return_to == "game":
		game.paused = true
	options.set_values(settings.volume, settings.brightness)
	options.visible = true
	menu.visible = false


func _on_guide_closed() -> void:
	guide.visible = false
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


func _ask_quit() -> void:
	quit_dialog.popup_centered()
