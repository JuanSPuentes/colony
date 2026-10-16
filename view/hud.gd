class_name Hud
extends CanvasLayer
## HUD mínimo de depuración, en español. Texto pequeño (8 px) porque la resolución base es 480x270.

var _top: Label
var _tools: Label
var _help: RichTextLabel
var _legend: RichTextLabel


func _ready() -> void:
	var theme := Theme.new()
	theme.set_default_font_size(8)
	var root := Control.new()
	root.theme = theme
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_top = _label(root, Vector2(3, 1))
	_tools = _label(root, Vector2(3, 11))
	_help = RichTextLabel.new()
	_help.bbcode_enabled = true
	_help.fit_content = true
	_help.scroll_active = false
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help.position = Vector2(3, 249)
	_help.size = Vector2(474, 20)
	_help.add_theme_font_size_override("normal_font_size", 8)
	_help.add_theme_constant_override("outline_size", 3)
	_help.add_theme_color_override("font_outline_color", Color.BLACK)
	_help.text = "[color=#cccccc]1 cavar · 2 feromona · clic izq arrastrar: marcar/pintar · clic der: borrar · WASD o botón central: cámara · rueda: zoom
Espacio: pausa · F1/F2/F3: velocidad · L: lluvia · Tab: capas · F9: +400 hormigas · F5: reiniciar · Shift+F5: nueva semilla[/color]"
	root.add_child(_help)
	_legend = RichTextLabel.new()
	_legend.bbcode_enabled = true
	_legend.fit_content = true
	_legend.scroll_active = false
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend.position = Vector2(3, 21)
	_legend.size = Vector2(300, 12)
	_legend.add_theme_font_size_override("normal_font_size", 8)
	_legend.add_theme_constant_override("outline_size", 3)
	_legend.add_theme_color_override("font_outline_color", Color.BLACK)
	root.add_child(_legend)


func _label(parent: Control, p: Vector2) -> Label:
	var l := Label.new()
	l.position = p
	l.add_theme_font_size_override("font_size", 8)
	l.add_theme_color_override("font_color", Color("f4ecd8"))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func update_info(sim: Simulation, speed: int, paused: bool, tool: int, layer: int, zoom: float) -> void:
	var weather := "Despejado"
	match sim.weather:
		Simulation.Weather.WARNING:
			weather = "¡Lluvia en %d s!" % ceili(sim.rain_eta_s())
		Simulation.Weather.RAINING:
			weather = "Lloviendo"
		_:
			var eta := sim.rain_eta_s()
			if eta >= 0.0:
				weather = "Despejado (lluvia en %d s)" % int(eta)
	_top.text = "Hormigas: %d   Hojas: %d   Clima: %s   Vel: %s   Semilla: %d   FPS: %d" % [
		sim.ants.alive_count, sim.leaves_stored, weather, "PAUSA" if paused else "x%d" % speed, sim.rng.seed, Engine.get_frames_per_second()]
	_tools.text = "Herramienta: %s   Capa: %s   Zoom: %sx   Marcadas: %d" % [
		"Cavar [1]" if tool == 1 else "Feromona de comida [2]", OverlayView.LAYER_NAMES[layer], str(zoom), sim.world.marked_count]
	if layer == OverlayView.Layer.STATES:
		var parts := ""
		for k in 6:
			var c: Color = AntSystem.STATE_COLORS[k]
			parts += "[color=#%s]■ %s[/color]  " % [c.to_html(false), AntSystem.STATE_NAMES[k]]
		_legend.text = parts
	else:
		_legend.text = ""
