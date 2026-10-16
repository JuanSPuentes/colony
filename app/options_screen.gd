class_name OptionsScreen
extends CanvasLayer
## Controles, volumen y brillo, con una flecha para volver. Se abre desde el menú principal o,
## durante la partida, desde la tuerca del HUD (`Hud.gear_pressed` -> `main.gd.menu_requested`);
## `back_pressed` le dice a `app.gd` a dónde volver en cada caso, no lo decide esta pantalla.
## Reusa `Hud.CONTROLS` para la lista de teclas, en vez de mantener una copia aparte que se
## desactualice. El contenido va en tarjetas centradas (mismo estilo de panel que usa `hud.gd`:
## fondo oscuro, borde dorado), agrupadas como en la barra de controles del HUD.

signal back_pressed
signal volume_changed(v: float)
signal brightness_changed(b: float)
signal quit_requested

const BG := Color(0.05, 0.04, 0.04, 1.0)
const GOLD := Color("ffd43c")
const CREAM := Color("f4ecd8")
const PANEL_BG := Color(0.07, 0.06, 0.08, 0.92)
const CONTENT_W := 760.0

var _volume_slider: HSlider
var _volume_value: Label
var _brightness_slider: HSlider
var _brightness_value: Label


func _ready() -> void:
	# Capa explícita por encima del HUD de la partida (CanvasLayer, capa 0): `game` se agrega al
	# árbol después de esta pantalla (ver `app.gd._start_game`), así que sin esto su HUD dibuja
	# encima y los paneles de la partida se ven mezclados con los de Opciones.
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var back := Button.new()
	back.text = "←  Volver"
	back.custom_minimum_size = Vector2(110, 40)
	back.add_theme_font_size_override("font_size", 18)
	back.add_theme_color_override("font_color", CREAM)
	back.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back.position = Vector2(20, 20)
	back.pressed.connect(func() -> void: back_pressed.emit())
	root.add_child(back)

	# Todo lo demás vive centrado dentro de un scroll (por si la ventana es baja y no entra todo).
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 76.0
	scroll.offset_bottom = -70.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)

	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(CONTENT_W, 0)
	content.add_theme_constant_override("separation", 20)
	center.add_child(content)

	var title := Label.new()
	title.text = "Opciones"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)

	var settings_card := _card("Ajustes")
	content.add_child(settings_card)
	var settings_body := settings_card.get_meta("body") as VBoxContainer
	_slider_row(settings_body, "Volumen", 0.0, 1.0, 0.01,
		func(v: float) -> String: return "%d%%" % int(v * 100.0),
		func(v: float) -> void: volume_changed.emit(v))
	_volume_slider = _last_slider
	_volume_value = _last_value_label
	_slider_row(settings_body, "Brillo", AppSettings.BRIGHTNESS_MIN, AppSettings.BRIGHTNESS_MAX, 0.02,
		func(v: float) -> String: return "%d%%" % int(v * 100.0),
		func(v: float) -> void: brightness_changed.emit(v))
	_brightness_slider = _last_slider
	_brightness_value = _last_value_label

	var controls_card := _card("Controles")
	content.add_child(controls_card)
	var controls_body := controls_card.get_meta("body") as VBoxContainer
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	controls_body.add_child(cols)
	for group in Hud.CONTROLS:
		cols.add_child(_controls_column(group[0], group[1]))

	var quit_btn := Button.new()
	quit_btn.text = "Salir del juego"
	quit_btn.custom_minimum_size = Vector2(180, 40)
	quit_btn.add_theme_font_size_override("font_size", 16)
	quit_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	quit_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	quit_btn.position = Vector2(-200, -60)
	quit_btn.pressed.connect(func() -> void: quit_requested.emit())
	root.add_child(quit_btn)


## Tarjeta con el mismo look que los paneles del HUD (`hud.gd._build_gear_button`/`_make_panel`):
## fondo oscuro translúcido y borde dorado. El cuerpo (un VBoxContainer) queda en metadata "body"
## porque GDScript no deja devolver dos nodos a la vez sin una clase aparte solo para eso.
func _card(header_text: String) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = GOLD
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.content_margin_top = 18.0
	style.content_margin_bottom = 18.0
	card.add_theme_stylebox_override("panel", style)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	card.add_child(body)
	card.set_meta("body", body)

	var header := Label.new()
	header.text = header_text
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", GOLD)
	body.add_child(header)
	return card


func _controls_column(header_text: String, rows: Array) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(160, 0)
	col.add_theme_constant_override("separation", 4)
	var header := Label.new()
	header.text = header_text
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color("7fd0ff"))
	col.add_child(header)
	for row in rows:
		var line := RichTextLabel.new()
		line.bbcode_enabled = true
		line.fit_content = true
		line.scroll_active = false
		line.add_theme_font_size_override("normal_font_size", 13)
		line.text = "[color=#ffd43c]%s[/color]  %s" % [row[0], row[1]]
		col.add_child(line)
	return col


## Último slider/label creados por `_slider_row` (GDScript no permite devolver dos valores a la
## vez sin un struct; esto evita crear una clase diminuta solo para eso).
var _last_slider: HSlider
var _last_value_label: Label


func _slider_row(parent: VBoxContainer, label_text: String, lo: float, hi: float, step: float,
		fmt: Callable, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(80, 0)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", CREAM)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.custom_minimum_size = Vector2(400, 20)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	_last_slider = slider

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(56, 0)
	value_label.add_theme_font_size_override("font_size", 14)
	value_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.78))
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	_last_value_label = value_label

	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = fmt.call(v)
		on_change.call(v))


## `app.gd` llama esto cada vez que abre la pantalla, para que los sliders reflejen el valor
## guardado (no el último que quedó de una sesión anterior de esta misma instancia).
func set_values(volume: float, brightness: float) -> void:
	_volume_slider.set_value_no_signal(volume)
	_volume_value.text = "%d%%" % int(volume * 100.0)
	_brightness_slider.set_value_no_signal(brightness)
	_brightness_value.text = "%d%%" % int(brightness * 100.0)
