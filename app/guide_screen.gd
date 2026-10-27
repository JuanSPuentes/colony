class_name GuideScreen
extends CanvasLayer
## Fase 12: guía rápida de "Juego normal", a pedido del jugador ("que le permita ver la guía con
## explicaciones del juego, cómo las hormigas, sus funciones, sus amenazas, la mecánica del
## juego... algo simple y sencillo"). Se muestra una sola vez al entrar a Juego normal desde el
## menú (`app.gd._start_game`), con la partida pausada detrás, y se cierra con un botón que
## despausa. No es el tutorial contextual (`TutorialView`, burbujas paso a paso mientras juegas) —
## esto es la referencia de una sola vez al arrancar, mismo espíritu que el manual de instrucciones
## de una caja de juego de mesa. Mismo estilo visual que `OptionsScreen` (tarjetas doradas sobre
## fondo oscuro) para que se sienta parte de la misma interfaz, no una pantalla aparte.

signal closed

const BG := Color(0.05, 0.04, 0.04, 1.0)
const GOLD := Color("ffd43c")
const CREAM := Color("f4ecd8")
const PANEL_BG := Color(0.07, 0.06, 0.08, 0.92)

## Cada entrada: [título de la tarjeta, líneas de texto corto]. Deliberadamente breve (pedido
## explícito "algo simple y sencillo"): una idea por línea, sin explicar mecánicas de detalle que
## ya se cubren sobre la marcha con `TutorialView`.
const SECTIONS := [
	["Tu colonia", [
		"La reina pone huevos; tú los compras con comida (botón [7]).",
		"Cada huevo nace Obrera, Soldado o Zángano al azar — no se elige.",
		"Obreras: cavan y traen hojas. Soldados: patrullan y defienden la colonia.",
		"Zánganos: escoltan a la reina, la defienden a ella y a los huevos, y llevan los huevos a la Guardería.",
		"El nido arranca con tres cámaras: Real (la reina), Guardería (los huevos) y Almacén (ahí dejan la comida).",
	]],
	["Comida", [
		"Pinta un rastro con la feromona de Comida [2] hacia una planta.",
		"Las obreras la siguen, cortan hojas y las traen al nido.",
		"Cada hormiga viva consume comida sola; sin reservas, mueren de hambre.",
	]],
	["Amenazas", [
		"Araña, ciempiés y mantis aparecen solas con el tiempo.",
		"Toda la colonia defiende si una se acerca, no solo los soldados.",
	]],
	["Estaciones", [
		"4 estaciones; al final de cada una ataca una colonia rival de verdad.",
		"No se avanza a la siguiente hasta derrotar a su reina.",
		"Tus soldados se juntan en la salida del nido y salen juntos: ¡el nido tiene que estar abierto!",
		"Ganar las 4 batallas es la victoria del modo.",
	]],
	["Mejoras", [
		"Con comida sobrante, compra mejoras de colonia (sección Mejoras del panel).",
		"Son progresivas: suben el daño/vida/velocidad/trabajo de toda la colonia, no solo de las hormigas nuevas.",
	]],
]


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 20.0
	scroll.offset_bottom = -76.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	center.add_child(content)

	var title := Label.new()
	title.text = "Cómo jugar"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Guías la colonia con feromonas y el diseño del nido; las hormigas hacen el trabajo."
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.75, 0.75, 0.78))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(subtitle)

	for section in SECTIONS:
		content.add_child(_card(section[0], section[1]))

	var play_btn := Button.new()
	play_btn.text = "¡Entendido, a jugar!"
	play_btn.custom_minimum_size = Vector2(220, 44)
	play_btn.add_theme_font_size_override("font_size", 18)
	play_btn.add_theme_color_override("font_color", CREAM)
	play_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	play_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	play_btn.position = Vector2(-110, -58)
	play_btn.pressed.connect(func() -> void: closed.emit())
	root.add_child(play_btn)


## Mismo estilo de tarjeta que `OptionsScreen._card`; se repite acá chico (una sola llamada propia)
## en vez de compartirla: `OptionsScreen` arma la suya con `get_meta("body")` para los sliders, que
## esta pantalla no necesita, así que copiarla sería más código para menos reuso real.
func _card(header_text: String, lines: Array) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(460, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = GOLD
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	card.add_theme_stylebox_override("panel", style)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	card.add_child(body)

	var header := Label.new()
	header.text = header_text
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", Color("7fd0ff"))
	body.add_child(header)

	# Viñeta aparte: el texto de la línea queda solo, así Godot lo traduce entero (Fase 27).
	for line_text in lines:
		var row := HBoxContainer.new()
		var bullet := Label.new()
		bullet.text = "•"
		bullet.add_theme_color_override("font_color", CREAM)
		row.add_child(bullet)
		var line := Label.new()
		line.text = line_text
		line.add_theme_font_size_override("font_size", 14)
		line.add_theme_color_override("font_color", CREAM)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(line)
		body.add_child(row)

	return card
