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

signal play_normal
signal play_infinite
signal open_options
signal quit_requested

const BG := Color(0.05, 0.04, 0.04, 1.0)
const GOLD := Color("ffd43c")
const CREAM := Color("f4ecd8")


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

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
	subtitle.add_theme_color_override("font_color", Color(0.75, 0.75, 0.78))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.set_anchors_preset(Control.PRESET_CENTER_TOP)
	subtitle.position = Vector2(-320, 128)
	subtitle.size = Vector2(640, 24)
	root.add_child(subtitle)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-140, -60)
	box.custom_minimum_size = Vector2(280, 0)
	box.add_theme_constant_override("separation", 16)
	root.add_child(box)

	_option(box, "Juego normal", "Crece sin límite: compra obreras y soldados con comida.", play_normal.emit)
	_option(box, "Modo infinito", "Reina, cámaras, araña: la colonia completa de la Fase 1.", play_infinite.emit)
	_option(box, "Opciones", "Controles, volumen y brillo.", open_options.emit)
	_option(box, "Salir", "Cierra el juego.", quit_requested.emit)


func _option(parent: Control, label: String, hint: String, cb: Callable) -> void:
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

	var hint_label := Label.new()
	hint_label.text = hint
	hint_label.add_theme_font_size_override("font_size", 12)
	hint_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.63))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	parent.add_child(hint_label)
