class_name Hud
extends CanvasLayer
## HUD en español. Fase 1: dibuja directo a la resolución real de la ventana (ver nota en
## main.gd sobre el SubViewport del mundo), así que el texto se ve nítido en vez de
## borroso/bloqueado. `S` escala el layout, pensado originalmente para 480x270, a la ventana real
## (1440x810 por defecto: factor 3). `_top`/`_tools`/`_help`/`_legend` se conservan con los mismos
## nombres que en la Fase 0 porque `tools/ui_test.gd` los lee directamente.
##
## Un solo panel con fondo opaco arriba a la izquierda agrupa TODO el estado del mundo: tres
## secciones cortas (Colonia / Clima / Amenazas) y, debajo, las notificaciones. Antes eran dos
## cajas separadas (una sin fondo, chocando con el texto de atrás, y el aviso amarillo aparte);
## ahora es una sola, con margen, letra más chica y descripciones breves.

const ERA_NAMES: Array[String] = ["Fundación", "Colonia joven", "Colonia madura"]
const HEADER_COLOR := Color("7fd0ff")
## Factor de escala del layout: ventana real / 480. Con la ventana por defecto (1440x810) da 3.
const S := 3.0
const FONT := 8.0 * S
## El panel de estado usa letra más chica que el resto del HUD para caber en menos espacio.
const PANEL_FONT := 6.0 * S
const OUTLINE := 3
const PANEL_W := 230.0
## Margen interno de los paneles (en las mismas unidades de 8px que el resto del layout).
const MARGIN_X := 5.0
const MARGIN_Y := 4.0
const CONTENT_W := PANEL_W - MARGIN_X * 2.0

var _top: Label
var _weather: Label
var _tools: Label
var _legend: RichTextLabel
var _colony: RichTextLabel
var _resources: Label
var _threats: Label
var _ratio: Label
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

	# Estado del mundo (arriba) y controles del jugador (debajo) van en dos recuadros iguales:
	# mismo fondo, mismo borde, mismo margen, para que se lean como una sola familia de paneles.
	var panel := _make_panel(root, Vector2(3, 1), Vector2(PANEL_W, 108))
	var y := 0.0
	_top = _panel_label(panel, y)
	y += 8.0
	_header(panel, y, "COLONIA")
	y += 7.0
	_colony = _panel_rich(panel, y)
	y += 7.0
	_resources = _panel_label(panel, y)
	y += 9.0
	_header(panel, y, "CLIMA")
	y += 7.0
	_weather = _panel_label(panel, y)
	y += 9.0
	_header(panel, y, "AMENAZAS")
	y += 7.0
	_threats = _panel_label(panel, y)
	y += 10.0
	_log = _panel_rich(panel, y, 28.0)

	# Segundo recuadro, mismo estilo, recortado al ancho del texto (no al ancho del primero).
	const CTRL_W := PANEL_W + 14.0
	const CTRL_CONTENT_W := CTRL_W - MARGIN_X * 2.0
	var ctrl := _make_panel(root, Vector2(3, 113), Vector2(CTRL_W, 29))
	var cy := 0.0
	_tools = _panel_label(ctrl, cy, CTRL_CONTENT_W)
	cy += 7.0
	_ratio = _panel_label(ctrl, cy, CTRL_CONTENT_W)
	cy += 9.0
	_legend = _panel_rich(ctrl, cy, 8.0, CTRL_CONTENT_W)

	_defeat = Label.new()
	_defeat.add_theme_font_size_override("font_size", FONT * 2.0)
	_defeat.add_theme_color_override("font_color", Color("ff6a6a"))
	_defeat.add_theme_color_override("font_outline_color", Color.BLACK)
	_defeat.add_theme_constant_override("outline_size", OUTLINE + 1)
	_defeat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_defeat.visible = false
	root.add_child(_defeat)


## Un recuadro con el mismo fondo/borde en toda la interfaz, para que se lea como una sola familia
## de paneles (no uno con fondo y el resto suelto encima del mundo).
func _make_panel(parent: Control, pos: Vector2, size: Vector2) -> Panel:
	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.08, 0.92)
	style.border_color = Color("ffd43c")
	style.set_border_width_all(1)
	style.set_corner_radius_all(int(3 * S))
	panel.add_theme_stylebox_override("panel", style)
	panel.position = pos * S
	panel.size = size * S
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	return panel


## Como `_label`, pero en letra chica, con el margen del panel ya aplicado, y en coordenadas
## internas de un panel (en unidades de 8px, para no tener que recalcular todo si cambia `S`).
## `w` es el ancho útil en esas mismas unidades (ya descontado el margen).
func _panel_label(parent: Control, y: float, w: float = CONTENT_W) -> Label:
	var l := Label.new()
	l.position = Vector2(MARGIN_X, MARGIN_Y + y) * S
	l.add_theme_font_size_override("font_size", PANEL_FONT)
	l.add_theme_color_override("font_color", Color("f4ecd8"))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.clip_text = true
	l.custom_minimum_size = Vector2(w, 0) * S
	l.size = Vector2(w, 7) * S
	parent.add_child(l)
	return l


func _panel_rich(parent: Control, y: float, h: float = 7.0, w: float = CONTENT_W) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = Vector2(MARGIN_X, MARGIN_Y + y) * S
	l.size = Vector2(w, h) * S
	l.add_theme_font_size_override("normal_font_size", PANEL_FONT)
	l.add_theme_constant_override("outline_size", 2)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	parent.add_child(l)
	return l


## Encabezado de sección corto, en un color distinto para que se note sin necesitar negrita.
func _header(parent: Control, y: float, text: String) -> Label:
	var l := _panel_label(parent, y)
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
	_top.text = "Hormigas: %d   Vel: %s   Semilla: %d   FPS: %d" % [
		sim.ants.alive_count, "PAUSA" if m.paused else "x%d" % m.speed, sim.rng.seed, Engine.get_frames_per_second()]

	# --- Clima: despejado, aviso de lluvia o lluvia. (La sequía llega en una fase futura.)
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
	_weather.text = weather

	# --- Amenazas: quién anda rondando la colonia (hoy solo la araña).
	if sim.queen_id >= 0 and sim.spider.alive:
		var state_names := {Spider.State.SEARCH: "buscando presas", Spider.State.ATTACK: "atacando",
			Spider.State.SIEGE: "en la entrada", Spider.State.RETREAT: "huyendo"}
		_threats.text = "Araña %s (%d%%)" % [state_names.get(sim.spider.state, "cerca"), int(100.0 * sim.spider.hp / maxf(sim.spider.max_hp, 0.01))]
	else:
		_threats.text = "Ninguna a la vista"

	if sim.queen_id >= 0:
		var c := {CasteDefs.Caste.WORKER: 0, CasteDefs.Caste.NURSE: 0, CasteDefs.Caste.SOLDIER: 0}
		for i in sim.ants.count:
			if sim.ants.alive[i] == 1 and sim.ants.caste[i] != CasteDefs.Caste.QUEEN:
				c[sim.ants.caste[i]] += 1
		var queen_alive := sim.ants.alive[sim.queen_id] == 1
		var queen_hp := sim.ants.hp[sim.queen_id] if queen_alive else 0.0
		var queen_hp_max := sim.cfg.queen_hp_base * CasteDefs.HP_MULT[CasteDefs.Caste.QUEEN]
		# El bullet de cada casta usa el mismo color con el que se ve en el mundo.
		_colony.text = "[color=#%s]●[/color]%d [color=#%s]●[/color]%d [color=#%s]●[/color]%d [color=#%s]●[/color]%d%%   %s" % [
			CasteDefs.COLORS[CasteDefs.Caste.WORKER].to_html(false), c[CasteDefs.Caste.WORKER],
			CasteDefs.COLORS[CasteDefs.Caste.NURSE].to_html(false), c[CasteDefs.Caste.NURSE],
			CasteDefs.COLORS[CasteDefs.Caste.SOLDIER].to_html(false), c[CasteDefs.Caste.SOLDIER],
			CasteDefs.COLORS[CasteDefs.Caste.QUEEN].to_html(false), int(100.0 * queen_hp / maxf(queen_hp_max, 0.01)),
			ERA_NAMES[sim.era]]
		_resources.text = "Cría %d/%d/%d   Comida %.0f%s  Agua %.0f%s" % [
			sim.brood.counts_by_stage[BroodSystem.Stage.EGG], sim.brood.counts_by_stage[BroodSystem.Stage.LARVA], sim.brood.counts_by_stage[BroodSystem.Stage.PUPA],
			sim.colony.food, _trend_arrow(sim.colony.food_trend), sim.colony.water, _trend_arrow(sim.colony.water_trend)]
		var t := sim.colony.target_pct
		_ratio.text = "Reparto → Obreras %d%%  Nodrizas %d%%  Soldados %d%%  (7/8/9)" % [
			int(t[CasteDefs.Caste.WORKER] * 100), int(t[CasteDefs.Caste.NURSE] * 100), int(t[CasteDefs.Caste.SOLDIER] * 100)]
		var lines := ""
		for n in sim.notifications:
			lines += "[color=#ffd43c]• %s[/color]\n" % n
		_log.text = lines
	else:
		_colony.text = ""
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
