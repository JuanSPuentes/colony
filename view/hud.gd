class_name Hud
extends CanvasLayer
## HUD en español. Fase 1: dibuja directo a la resolución real de la ventana (ver nota en
## main.gd sobre el SubViewport del mundo), así que el texto se ve nítido en vez de
## borroso/bloqueado. `S` escala el layout, pensado originalmente para 480x270, a la ventana real
## (1440x810 por defecto: factor 3). `_top`/`_tools`/`_help`/`_legend` se conservan con los mismos
## nombres que en la Fase 0 porque `tools/ui_test.gd` los lee directamente.
##
## Tres secciones, cada una con su encabezado, para leer el estado de un vistazo:
##  1. COLONIA: población (con el mismo color de cada casta), cría y recursos.
##  2. CLIMA: despejado, lluvia o aviso de lluvia (la sequía queda para una fase futura).
##  3. AMENAZAS: la araña si anda cerca, o "ninguna a la vista" si no hay nada.
## Las notificaciones (texto amarillo) viven en su propio panel con fondo opaco a la derecha,
## separado de las líneas de estado (texto blanco) a la izquierda, para que nunca se superpongan.

const ERA_NAMES: Array[String] = ["Fundación", "Colonia joven", "Colonia madura"]
const HEADER_COLOR := Color("7fd0ff")
## Factor de escala del layout: ventana real / 480. Con la ventana por defecto (1440x810) da 3.
const S := 3.0
const FONT := 8.0 * S
const OUTLINE := 3
## Ancho del panel de notificaciones y dónde termina la columna de texto blanco de la izquierda.
const LOG_W := 150.0
const LEFT_W := 480.0 - LOG_W - 4.0

var _top: Label
var _weather: Label
var _tools: Label
var _legend: RichTextLabel
var _colony: RichTextLabel
var _brood: Label
var _resources: Label
var _threats: Label
var _ratio: Label
var _help: RichTextLabel
var _log: RichTextLabel
var _defeat: Label


func _ready() -> void:
	var theme := Theme.new()
	theme.set_default_font_size(FONT)
	var root := Control.new()
	root.theme = theme
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Panel de notificaciones: fondo opaco propio, a la derecha, separado del texto blanco.
	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.08, 0.92)
	style.border_color = Color("ffd43c")
	style.set_border_width_all(1)
	style.set_corner_radius_all(int(3 * S))
	style.content_margin_left = 5 * S
	style.content_margin_top = 3 * S
	style.content_margin_right = 5 * S
	style.content_margin_bottom = 3 * S
	panel.add_theme_stylebox_override("panel", style)
	panel.position = Vector2(480.0 - LOG_W, 1) * S
	panel.size = Vector2(LOG_W, 70) * S
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.fit_content = true
	_log.scroll_active = false
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.set_anchors_preset(Control.PRESET_FULL_RECT)
	_log.add_theme_font_size_override("normal_font_size", FONT * 0.85)
	panel.add_child(_log)

	# Columna izquierda, en tres secciones con encabezado: Colonia, Clima, Amenazas.
	_top = _label(root, Vector2(3, 1) * S)

	_header(root, Vector2(3, 12) * S, "— COLONIA —")
	_colony = _rich(root, Vector2(3, 20) * S, Vector2(LEFT_W, 12) * S)
	_brood = _label(root, Vector2(3, 28) * S)
	_resources = _label(root, Vector2(3, 36) * S)

	_header(root, Vector2(3, 48) * S, "— CLIMA —")
	_weather = _label(root, Vector2(3, 56) * S)

	_header(root, Vector2(3, 68) * S, "— AMENAZAS —")
	_threats = _label(root, Vector2(3, 76) * S)

	_tools = _label(root, Vector2(3, 90) * S)
	_ratio = _label(root, Vector2(3, 100) * S)
	_legend = _rich(root, Vector2(3, 110) * S, Vector2(LEFT_W, 12) * S)
	_help = _rich(root, Vector2(3, 247) * S, Vector2(474, 22) * S)
	_help.text = "[color=#cccccc]1 cavar · 2 feromona (Q/E tipo) · 3 cámara (Q/E tipo) · 4 borrar · 7/8/9 más obreras/nodrizas/soldados · clic izq/der: pintar/borrar
Espacio: pausa · F1/F2/F3: velocidad · L: lluvia · F10: araña · Tab: capas · H: ir a la reina · F9: +400 hormigas · F5: reiniciar · Shift+F5: nueva semilla[/color]"
	_defeat = Label.new()
	_defeat.add_theme_font_size_override("font_size", FONT * 2.0)
	_defeat.add_theme_color_override("font_color", Color("ff6a6a"))
	_defeat.add_theme_color_override("font_outline_color", Color.BLACK)
	_defeat.add_theme_constant_override("outline_size", OUTLINE + 1)
	_defeat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_defeat.visible = false
	root.add_child(_defeat)


func _label(parent: Control, p: Vector2) -> Label:
	var l := Label.new()
	l.position = p
	l.add_theme_font_size_override("font_size", FONT)
	l.add_theme_color_override("font_color", Color("f4ecd8"))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", OUTLINE)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.clip_text = true
	l.custom_minimum_size = Vector2(LEFT_W, 0) * S
	l.size = Vector2(LEFT_W, 10) * S
	parent.add_child(l)
	return l


## Encabezado de sección: mismo tamaño que el resto (pensado para una resolución base de 8 px),
## pero en un color distinto para que se note como título sin necesitar una fuente en negrita.
func _header(parent: Control, p: Vector2, text: String) -> Label:
	var l := _label(parent, p)
	l.text = text
	l.add_theme_color_override("font_color", HEADER_COLOR)
	return l


func _rich(parent: Control, p: Vector2, sz: Vector2) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = p
	l.size = sz
	l.add_theme_font_size_override("normal_font_size", FONT)
	l.add_theme_constant_override("outline_size", OUTLINE)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	parent.add_child(l)
	return l


func _trend_arrow(v: float) -> String:
	if v > 0.5:
		return "↑"
	if v < -0.5:
		return "↓"
	return "→"


## `m` es el nodo main.gd: lee todo lo que necesita de él y de `m.sim`.
func update_info(m: Node) -> void:
	var sim: Simulation = m.sim
	_top.text = "Hormigas: %d   Hojas: %d   Vel: %s   Semilla: %d   FPS: %d" % [
		sim.ants.alive_count, sim.leaves_stored, "PAUSA" if m.paused else "x%d" % m.speed, sim.rng.seed, Engine.get_frames_per_second()]

	# --- Sección Clima: despejado, aviso de lluvia o lluvia. (La sequía llega en una fase futura.)
	var weather := "Sin novedades"
	match sim.weather:
		Simulation.Weather.WARNING:
			weather = "¡Lluvia en %d s!" % ceili(sim.rain_eta_s())
		Simulation.Weather.RAINING:
			weather = "Lloviendo"
		_:
			var eta := sim.rain_eta_s()
			if eta >= 0.0:
				weather = "Sin novedades (lluvia en %d s)" % int(eta)
	_weather.text = "Clima: %s" % weather

	# --- Sección Amenazas: quién anda rondando la colonia (hoy solo la araña).
	if sim.queen_id >= 0 and sim.spider.alive:
		var state_names := {Spider.State.SEARCH: "buscando presas", Spider.State.ATTACK: "atacando",
			Spider.State.SIEGE: "asediando la entrada", Spider.State.RETREAT: "huyendo"}
		_threats.text = "Araña %s — vida %d%%" % [state_names.get(sim.spider.state, "cerca"), int(100.0 * sim.spider.hp / maxf(sim.spider.max_hp, 0.01))]
	else:
		_threats.text = "Ninguna amenaza a la vista"

	if sim.queen_id >= 0:
		var c := {CasteDefs.Caste.WORKER: 0, CasteDefs.Caste.NURSE: 0, CasteDefs.Caste.SOLDIER: 0}
		for i in sim.ants.count:
			if sim.ants.alive[i] == 1 and sim.ants.caste[i] != CasteDefs.Caste.QUEEN:
				c[sim.ants.caste[i]] += 1
		var queen_alive := sim.ants.alive[sim.queen_id] == 1
		var queen_hp := sim.ants.hp[sim.queen_id] if queen_alive else 0.0
		var queen_hp_max := sim.cfg.queen_hp_base * CasteDefs.HP_MULT[CasteDefs.Caste.QUEEN]
		# --- Sección Colonia: el bullet de cada casta usa el mismo color con el que se ve en el mundo.
		_colony.text = "Era: %s   [color=#%s]●[/color] Obreras %d  [color=#%s]●[/color] Nodrizas %d  [color=#%s]●[/color] Soldados %d  [color=#%s]●[/color] Reina %d%%" % [
			ERA_NAMES[sim.era],
			CasteDefs.COLORS[CasteDefs.Caste.WORKER].to_html(false), c[CasteDefs.Caste.WORKER],
			CasteDefs.COLORS[CasteDefs.Caste.NURSE].to_html(false), c[CasteDefs.Caste.NURSE],
			CasteDefs.COLORS[CasteDefs.Caste.SOLDIER].to_html(false), c[CasteDefs.Caste.SOLDIER],
			CasteDefs.COLORS[CasteDefs.Caste.QUEEN].to_html(false), int(100.0 * queen_hp / maxf(queen_hp_max, 0.01))]
		_brood.text = "Cría (huevo/larva/pupa): %d/%d/%d" % [
			sim.brood.counts_by_stage[BroodSystem.Stage.EGG], sim.brood.counts_by_stage[BroodSystem.Stage.LARVA], sim.brood.counts_by_stage[BroodSystem.Stage.PUPA]]
		_resources.text = "Comida: %.0f%s   Agua: %.0f%s" % [
			sim.colony.food, _trend_arrow(sim.colony.food_trend), sim.colony.water, _trend_arrow(sim.colony.water_trend)]
		var t := sim.colony.target_pct
		_ratio.text = "Reparto objetivo → Obreras %d%%  Nodrizas %d%%  Soldados %d%%   (7/8/9 para ajustar)" % [
			int(t[CasteDefs.Caste.WORKER] * 100), int(t[CasteDefs.Caste.NURSE] * 100), int(t[CasteDefs.Caste.SOLDIER] * 100)]
		var lines := ""
		for n in sim.notifications:
			lines += "[color=#ffd43c]• %s[/color]\n" % n
		_log.text = lines
	else:
		_colony.text = ""
		_brood.text = ""
		_resources.text = ""
		_ratio.text = ""
		_log.text = ""

	var tool_names := ["", "Cavar [1]", "Feromona [2]", "Cámara [3]", "Borrar [4]"]
	var sub := ""
	if m.tool == 2:
		sub = " · %s (Q/E)" % OverlayView.LAYER_NAMES[m.phero_index + 1]
	elif m.tool == 3:
		sub = " · %s (Q/E)" % WorldGrid.ROOM_NAMES[m.ROOM_TYPES[m.room_index]]
	_tools.text = "Herramienta: %s%s   Capa: %s   Zoom: %sx   Marcadas: %d" % [
		tool_names[m.tool], sub, OverlayView.LAYER_NAMES[m.overlay.layer], str(m.ZOOM_LEVELS[m.zoom_index]), sim.world.marked_count]

	if m.overlay.layer == OverlayView.Layer.STATES:
		var parts := ""
		for k in AntSystem.State.size():
			var col: Color = AntSystem.STATE_COLORS[k]
			parts += "[color=#%s]■ %s[/color]  " % [col.to_html(false), AntSystem.STATE_NAMES[k]]
		_legend.text = parts
	elif m.overlay.layer == OverlayView.Layer.CASTES:
		var parts2 := ""
		for k in CasteDefs.NAMES.size():
			var col2: Color = CasteDefs.COLORS[k]
			parts2 += "[color=#%s]■ %s[/color]  " % [col2.to_html(false), CasteDefs.NAMES[k]]
		_legend.text = parts2
	else:
		_legend.text = ""

	_defeat.visible = sim.game_over
	if sim.game_over:
		_defeat.text = "LA COLONIA CAYÓ\n%s\n\nF5 para reiniciar" % sim.game_over_reason
		_defeat.size = Vector2(400, 120) * S / 2.0
		_defeat.position = (Vector2(240, 135) * S) - _defeat.size * 0.5
