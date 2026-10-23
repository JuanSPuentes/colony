class_name MainMenu
extends CanvasLayer
## Menú principal: Juego normal, Modo infinito, Opciones y Salir. Dibuja directo a la resolución
## real, con el mismo estilo de paneles que el resto de la interfaz (`Hud._make_panel`), para que
## se sienta parte del mismo juego.
##
## Papeles invertidos a propósito: "Juego normal" lanza la economía de comida/compra (la Fase 3,
## sin reina ni final) y "Modo infinito" lanza la colonia con reina/castas/araña (la Fase 1, que
## sí puede ganarse o perderse). `play_normal`/`play_infinite` conservan sus nombres de señal
## porque son la posición en el menú, no el modo; `app.gd._ready()` decide a qué modo de
## `_start_game()` apunta cada una.

## Fase 14: Nivel 0, el tutorial jugable (ver `sim/colony/tutorial_level.gd`).
## Fase 17: retoma la partida guardada (`main.SAVE_PATH`). Solo se ve si hay una guardada.
signal play_continue
signal play_tutorial
signal play_normal
signal play_infinite
## Fase 6: sandbox para probar amenazas y castas sin que una partida real se corte.
signal play_test
signal open_options
## Fase 14: la guía de una pantalla (`GuideScreen`) ya no sale sola al empezar; queda aquí.
signal open_guide
signal quit_requested
## Fase 18: "Nueva partida" — `app.gd` pregunta si se quiere hacer el tutorial antes.
signal play_new

const GOLD := Color("ffd43c")
const CREAM := Color("f4ecd8")


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var bg := MenuBackground.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	# Oscurece un poco la escena animada para que el título y los botones sigan leyéndose nítidos
	# encima de un cielo claro.
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.2)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)

	var title := Label.new()
	title.text = "Colony: Under the Earth"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-320, 70)
	title.size = Vector2(640, 56)
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Guías la colonia con feromonas y el diseño del nido; las hormigas hacen el trabajo."
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.85, 0.85, 0.88))
	subtitle.add_theme_color_override("font_outline_color", Color.BLACK)
	subtitle.add_theme_constant_override("outline_size", 3)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.set_anchors_preset(Control.PRESET_CENTER_TOP)
	subtitle.position = Vector2(-320, 128)
	subtitle.size = Vector2(640, 24)
	root.add_child(subtitle)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-140, -110)
	box.custom_minimum_size = Vector2(280, 0)
	box.add_theme_constant_override("separation", 16)
	root.add_child(box)

	# Fase 18: menú final pedido por el jugador — Continuar (si hay guardada) / Nueva partida /
	# Opciones / Salir. El tutorial se ofrece al pulsar Nueva partida y "Cómo jugar" pasó a las
	# opciones de la partida. Modo infinito y Test son herramientas de desarrollo: solo se ven
	# corriendo desde el editor de Godot, nunca en una build exportada.
	_continue_btn = _option(box, "Continuar partida", "Retoma la última partida guardada.", play_continue.emit)
	refresh_continue()
	_option(box, "Nueva partida", "Empieza una colonia nueva (con tutorial si quieres).", play_new.emit)
	if OS.has_feature("editor"):
		_option(box, "Modo infinito", "(desarrollo) Colonia completa con reina y castas.", play_infinite.emit)
		_option(box, "Test", "(desarrollo) Hormigas y amenazas a voluntad.", play_test.emit)
	_option(box, "Opciones", "Controles, volumen y brillo.", open_options.emit)
	_option(box, "Salir", "Cierra el juego.", quit_requested.emit)


## `hint` queda sin usarse por ahora (el usuario pidió sacar las descripciones del menú el
## 2026-10-20); se deja el parámetro para no tener que tocar cada `_option(...)` cuando se
## reactiven.
func _option(parent: Control, label: String, _hint: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(280, 46)
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", CREAM)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.1, 0.09, 0.1, 0.92)
	normal.border_color = GOLD
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.16, 0.14, 0.08, 0.95)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.pressed.connect(cb)
	parent.add_child(btn)
	return btn


var _continue_btn: Button


## Fase 17: muestra "Continuar partida" solo si existe una partida guardada. `app.gd` lo llama al
## volver al menú, por si se acaba de guardar desde las opciones de la partida.
func refresh_continue() -> void:
	if _continue_btn != null:
		_continue_btn.visible = FileAccess.file_exists("user://save1.json")
