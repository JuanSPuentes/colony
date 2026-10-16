extends Node2D
## Punto de entrada real del juego (ver `project.godot`, `run/main_scene`). Decide qué pantalla se
## ve: menú, opciones o la partida. `main.tscn` sigue arrancando solo (modo Infinito) cuando se
## abre directo, para que las pruebas (`ui_test.gd`, `screenshot.gd`) no cambien: aquí lo
## instanciamos con `auto_start = false` y lo arrancamos nosotros en el modo que haya elegido el
## jugador.

const MAIN_SCENE := "res://main.tscn"

var settings: AppSettings
var menu: MainMenu
var options: OptionsScreen
var quit_dialog: ConfirmationDialog
var game: Node2D
## A dónde vuelve la flecha de Opciones: "menu" (se abrió desde el menú) o "game" (desde la tuerca).
var _return_to := "menu"


func _ready() -> void:
	settings = AppSettings.load_settings()
	settings.apply_volume()

	menu = MainMenu.new()
	add_child(menu)
	menu.play_normal.connect(func() -> void: _start_game(false))
	menu.play_infinite.connect(func() -> void: _start_game(true))
	menu.open_options.connect(func() -> void: _open_options("menu"))
	menu.quit_requested.connect(_ask_quit)

	options = OptionsScreen.new()
	options.visible = false
	add_child(options)
	options.back_pressed.connect(_on_options_back)
	options.volume_changed.connect(_on_volume_changed)
	options.brightness_changed.connect(_on_brightness_changed)
	options.quit_requested.connect(_ask_quit)

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
	game.start(game.cfg.world_seed, null, "incremental" if incremental else "historia")


func _open_options(return_to: String) -> void:
	_return_to = return_to
	if game != null and return_to == "game":
		game.paused = true
	options.set_values(settings.volume, settings.brightness)
	options.visible = true
	menu.visible = false


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
