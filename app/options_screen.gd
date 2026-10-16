class_name OptionsScreen
extends CanvasLayer
## Controles, volumen y brillo, con una flecha para volver. Se abre desde el menú principal o,
## durante la partida, desde la tuerca del HUD (`Hud.gear_pressed` -> `main.gd.menu_requested`);
## `back_pressed` le dice a `app.gd` a dónde volver en cada caso, no lo decide esta pantalla.
## Reusa `Hud.CONTROLS` para la lista de teclas, en vez de mantener una copia aparte que se
## desactualice.

signal back_pressed
signal volume_changed(v: float)
signal brightness_changed(b: float)
signal quit_requested

const BG := Color(0.05, 0.04, 0.04, 1.0)
const GOLD := Color("ffd43c")
const CREAM := Color("f4ecd8")

var _volume_slider: HSlider
var _volume_value: Label
var _brightness_slider: HSlider
var _brightness_value: Label


func _ready() -> void:
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

	var title := Label.new()
	title.text = "Opciones"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", GOLD)
	title.position = Vector2(20, 72)
	root.add_child(title)

	var y := 120.0
	y = _slider_row(root, y, "Volumen", 0.0, 1.0, 0.01, func(v: float) -> String: return "%d%%" % int(v * 100.0),
		func(v: float) -> void: volume_changed.emit(v)) + 20.0
	_volume_slider = _last_slider
	_volume_value = _last_value_label
	y = _slider_row(root, y, "Brillo", AppSettings.BRIGHTNESS_MIN, AppSettings.BRIGHTNESS_MAX, 0.02,
		func(v: float) -> String: return "%d%%" % int(v * 100.0),
		func(v: float) -> void: brightness_changed.emit(v)) + 30.0
	_brightness_slider = _last_slider
	_brightness_value = _last_value_label

	var controls_title := Label.new()
	controls_title.text = "Controles"
	controls_title.add_theme_font_size_override("font_size", 20)
	controls_title.add_theme_color_override("font_color", GOLD)
	controls_title.position = Vector2(20, y)
	root.add_child(controls_title)
	y += 34.0

	var controls := RichTextLabel.new()
	controls.bbcode_enabled = true
	controls.fit_content = true
	controls.scroll_active = false
	controls.position = Vector2(20, y)
	controls.size = Vector2(760, 170)
	controls.add_theme_font_size_override("normal_font_size", 15)
	var lines := ""
	for group in Hud.CONTROLS:
		lines += "[color=#7fd0ff]%s[/color]\n" % group[0]
		for row in group[1]:
			lines += "  [color=#ffd43c]%s[/color]  %s\n" % [row[0], row[1]]
	controls.text = lines
	root.add_child(controls)

	var quit_btn := Button.new()
	quit_btn.text = "Salir del juego"
	quit_btn.custom_minimum_size = Vector2(180, 40)
	quit_btn.add_theme_font_size_override("font_size", 16)
	quit_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	quit_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	quit_btn.position = Vector2(-200, -60)
	quit_btn.pressed.connect(func() -> void: quit_requested.emit())
	root.add_child(quit_btn)


## Último slider/label creados por `_slider_row` (GDScript no permite devolver dos valores a la
## vez sin un struct; esto evita crear una clase diminuta solo para eso).
var _last_slider: HSlider
var _last_value_label: Label


func _slider_row(parent: Control, y: float, label_text: String, lo: float, hi: float, step: float,
		fmt: Callable, on_change: Callable) -> float:
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", CREAM)
	label.position = Vector2(20, y)
	parent.add_child(label)

	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.position = Vector2(140, y + 2.0)
	slider.size = Vector2(320, 20)
	parent.add_child(slider)
	_last_slider = slider

	var value_label := Label.new()
	value_label.add_theme_font_size_override("font_size", 14)
	value_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.78))
	value_label.position = Vector2(470, y)
	value_label.size = Vector2(60, 24)
	parent.add_child(value_label)
	_last_value_label = value_label

	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = fmt.call(v)
		on_change.call(v))
	return y + 26.0


## `app.gd` llama esto cada vez que abre la pantalla, para que los sliders reflejen el valor
## guardado (no el último que quedó de una sesión anterior de esta misma instancia).
func set_values(volume: float, brightness: float) -> void:
	_volume_slider.set_value_no_signal(volume)
	_volume_value.text = "%d%%" % int(volume * 100.0)
	_brightness_slider.set_value_no_signal(brightness)
	_brightness_value.text = "%d%%" % int(brightness * 100.0)
