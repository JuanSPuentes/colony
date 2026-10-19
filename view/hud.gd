class_name Hud
extends CanvasLayer
## HUD en español. Fase 1: dibuja directo a la resolución real de la ventana (ver nota en
## main.gd sobre el SubViewport del mundo), así que el texto se ve nítido en vez de
## borroso/bloqueado. `S` escala el layout, pensado originalmente para 480x270, a la ventana real
## (1440x810 por defecto). `_top`/`_tools`/`_help`/`_legend` se conservan con los mismos
## nombres que en la Fase 0 porque `tools/ui_test.gd` los lee directamente.
##
## Un solo panel con fondo opaco arriba a la izquierda agrupa TODO el estado del mundo: tres
## secciones cortas (Colonia / Clima / Amenazas) y, debajo, las notificaciones. Antes eran dos
## cajas separadas (una sin fondo, chocando con el texto de atrás, y el aviso amarillo aparte);
## ahora es una sola, con margen, letra más chica y descripciones breves.
##
## Fase 3 (menú): la barra de abajo con todas las teclas se quitó de aquí (ocupaba media
## pantalla); esa misma lista (`CONTROLS`) ahora vive en la sección "Controles" de
## `OptionsScreen`, detrás de la tuerca, en vez de estar siempre encima del mundo.

const ERA_NAMES: Array[String] = ["Fundación", "Colonia joven", "Colonia madura"]
const HEADER_COLOR := Color("7fd0ff")
## Factor de escala del layout: ventana real / 480, reducido para que los paneles ocupen menos
## pantalla (antes 3.0 daba paneles casi a media ventana con la barra de abajo todavía puesta).
const S := 2.3
const FONT := 8.0 * S
## El panel de estado usa letra más chica que el resto del HUD para caber en menos espacio.
const PANEL_FONT := 6.0 * S
const OUTLINE := 3
const PANEL_W := 200.0
## Margen interno de los paneles (en las mismas unidades de 8px que el resto del layout).
const MARGIN_X := 4.0
const MARGIN_Y := 3.0
const CONTENT_W := PANEL_W - MARGIN_X * 2.0
## Alto del panel de estado desplegado y plegado (solo la línea de `_top`).
const STATUS_H := 100.0
const STATUS_FOLDED_H := 7.0 + MARGIN_Y * 2.0
const KEY_COLOR := "ffd43c"
## Columnas de la barra de controles: encabezado y pares [tecla, qué hace]. Si se agrega una tecla
## nueva en main.gd, se agrega aquí también para que el jugador la vea.
const CONTROLS := [
	["HERRAMIENTAS", [["1", "Cavar túneles"], ["2 / 3", "Feromona / Cámara"], ["4", "Borrar todo bajo el pincel"],
		["Q / E", "Cambiar subtipo"], ["Clic izq / der", "Pintar / quitar"]]],
	["COLONIA", [["7", "Comprar obrera (comida)"], ["8", "Comprar soldado (comida)"], ["9", "Cambiar auto-compra"],
		["H", "Ir a la reina"]]],
	["CÁMARA Y TIEMPO", [["WASD / clic medio", "Mover la cámara"], ["Rueda", "Zoom"], ["Espacio", "Pausa"],
		["F1 / F2 / F3", "Velocidad x1 / x2 / x4"], ["I", "Plegar / desplegar estado"]]],
	["PARTIDA", [["F6 / F7", "Guardar / cargar"], ["F5", "Reiniciar (mismo mapa)"], ["Shift+F5", "Reiniciar con mapa nuevo"]]],
]

## Estado de plegado del panel de estado. `main.gd` lo cambia con I; el botón, con clic.
var status_open := true

## Fase 3 (menú): `main.gd` la reenvía como `menu_requested` para que `app.gd` abra Opciones.
signal gear_pressed

var _status_panel: Panel
var _status_body: Array[Control] = []
var _status_btn: Button
var _ctrl_panel: Panel
## Fase 3: botones de compra (obrera, soldado, auto-compra) en el panel de herramientas.
var _buy_row: HBoxContainer
var _buy_btns: Array[Button] = []
var _threat_header: Label
var _m: Node

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
	var panel := _make_panel(root, Vector2(3, 1), Vector2(PANEL_W, STATUS_H))
	_status_panel = panel
	var y := 0.0
	# `_top` queda visible aunque el panel esté plegado; le dejamos sitio al botón a la derecha.
	_top = _panel_label(panel, y, CONTENT_W - 42.0)
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
	_threat_header = _header(panel, y, "AMENAZAS")
	y += 7.0
	_threats = _panel_label(panel, y)
	y += 10.0
	_log = _panel_rich(panel, y, 28.0)
	for c in panel.get_children():
		if c != _top:
			_status_body.append(c)
	_status_btn = _fold_button(panel, PANEL_W, toggle_status)

	# Segundo recuadro, mismo estilo, recortado al ancho del texto (no al ancho del primero).
	# Su posición vertical la fija `_layout()`: va justo debajo del panel de estado, plegado o no.
	const CTRL_W := PANEL_W + 14.0
	const CTRL_CONTENT_W := CTRL_W - MARGIN_X * 2.0
	_ctrl_panel = _make_panel(root, Vector2(3, 113), Vector2(CTRL_W, 31))
	var cy := 0.0
	_tools = _panel_label(_ctrl_panel, cy, CTRL_CONTENT_W)
	cy += 7.0
	_ratio = _panel_label(_ctrl_panel, cy, CTRL_CONTENT_W)
	_buy_row = HBoxContainer.new()
	_buy_row.position = Vector2(MARGIN_X, MARGIN_Y + cy + 1.0) * S
	_buy_row.size = Vector2(CTRL_CONTENT_W, 8.0) * S
	_buy_row.add_theme_constant_override("separation", int(3 * S))
	_buy_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ctrl_panel.add_child(_buy_row)
	for k in 3:
		var b := _buy_button()
		_buy_row.add_child(b)
		_buy_btns.append(b)
	_buy_btns[0].pressed.connect(func() -> void: _m.sim.cmd_buy(CasteDefs.Caste.WORKER))
	_buy_btns[1].pressed.connect(func() -> void: _m.sim.cmd_buy(CasteDefs.Caste.SOLDIER))
	_buy_btns[2].pressed.connect(func() -> void: _m.sim.cmd_cycle_auto_buy())
	cy += 11.0
	_legend = _panel_rich(_ctrl_panel, cy, 8.0, CTRL_CONTENT_W)

	_build_gear_button(root)
	_layout()

	_defeat = Label.new()
	_defeat.add_theme_font_size_override("font_size", FONT * 2.0)
	_defeat.add_theme_color_override("font_outline_color", Color.BLACK)
	_defeat.add_theme_constant_override("outline_size", OUTLINE + 1)
	_defeat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_defeat.visible = false
	root.add_child(_defeat)


## Botón "ocultar / mostrar" en la esquina superior derecha de un panel. Sin foco de teclado: si lo
## tuviera, Espacio (pausa) lo activaría en vez de pausar.
func _fold_button(parent: Panel, panel_w: float, on_press: Callable) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	b.add_theme_font_size_override("font_size", PANEL_FONT)
	b.add_theme_color_override("font_color", HEADER_COLOR)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.position = Vector2(panel_w - MARGIN_X - 40.0, MARGIN_Y - 1.0) * S
	b.custom_minimum_size = Vector2(40.0, 8.0) * S
	b.size = b.custom_minimum_size
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


## Fase 3 (menú): tuerca en la esquina superior derecha de la ventana real (no del panel: usa
## anclas propias para quedar fija ahí sin importar el tamaño de la ventana), para abrir Opciones
## o salir en cualquier momento de la partida.
func _build_gear_button(root: Control) -> void:
	var b := Button.new()
	b.text = "⚙"
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", PANEL_FONT)
	b.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	b.position = Vector2(-13.0, 2.0) * S
	b.custom_minimum_size = Vector2(11.0, 8.0) * S
	b.size = b.custom_minimum_size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.08, 0.92)
	style.border_color = Color("ffd43c")
	style.set_border_width_all(1)
	style.set_corner_radius_all(int(3 * S))
	for s in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(s, style)
	b.pressed.connect(func() -> void: gear_pressed.emit())
	root.add_child(b)


## Botón de compra: recuadro con borde (a diferencia de los de plegar, que son solo texto) para que
## se lea como algo que se pulsa. Sin foco de teclado, por el mismo motivo que `_fold_button`.
func _buy_button() -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 8.0) * S
	b.add_theme_font_size_override("font_size", PANEL_FONT)
	for s in ["normal", "hover", "pressed", "disabled"]:
		var st := StyleBoxFlat.new()
		st.bg_color = {"normal": Color(0.16, 0.14, 0.1), "hover": Color(0.28, 0.24, 0.12),
			"pressed": Color(0.4, 0.33, 0.12), "disabled": Color(0.1, 0.1, 0.11)}[s]
		st.border_color = Color("ffd43c") if s != "disabled" else Color(0.35, 0.35, 0.38)
		st.set_border_width_all(1)
		st.set_corner_radius_all(int(2 * S))
		st.content_margin_left = 2.0 * S
		st.content_margin_right = 2.0 * S
		b.add_theme_stylebox_override(s, st)
	b.add_theme_color_override("font_color", Color("f4ecd8"))
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.55, 0.58))
	return b


## Alto del panel de estado desplegado: crece con los avisos en vez de dejar siempre un hueco fijo
## para ellos (`STATUS_H` es el alto con la lista de avisos llena a 4 líneas).
func _status_open_h() -> float:
	var lines := _log.text.count("\n") if _log != null else 0
	return minf(STATUS_H, STATUS_H - 32.0 + 8.0 * lines)


func toggle_status() -> void:
	status_open = not status_open
	_layout()


## Aplica el estado de plegado: tamaño, visibilidad y el panel de herramientas pegado debajo del
## de estado.
func _layout() -> void:
	for c in _status_body:
		c.visible = status_open
	_status_btn.text = "ocultar (I)" if status_open else "mostrar (I)"
	_status_panel.size.y = (_status_open_h() if status_open else STATUS_FOLDED_H) * S
	_ctrl_panel.position.y = _status_panel.position.y + _status_panel.size.y + 4.0 * S


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


func _trend_arrow(v: float) -> String:
	if v > 0.5:
		return "↑"
	if v < -0.5:
		return "↓"
	return "→"


func _plural(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


## Modo incremental (Fase 3): sin semilla, sin agua, sin araña ni eras. Muestra el día, la comida
## como único recurso, la cría que viene en camino y el precio de cada compra.
func _update_incremental(m: Node, sim: Simulation) -> void:
	var cfg := sim.cfg
	var t := sim.time_s()
	var night := sim.is_night()
	_top.text = "Día %d · %s   Hormigas: %d   Vel: %s   FPS: %d" % [
		sim.day_number(), "Noche" if night else "Día", sim.ants.alive_count,
		"PAUSA" if m.paused else "x%d" % m.speed, Engine.get_frames_per_second()]

	var c := {CasteDefs.Caste.WORKER: 0, CasteDefs.Caste.SOLDIER: 0}
	for i in sim.ants.count:
		if sim.ants.alive[i] == 1 and c.has(sim.ants.caste[i]):
			c[sim.ants.caste[i]] += 1
	var queen_alive := sim.ants.alive[sim.queen_id] == 1
	var queen_hp := sim.ants.hp[sim.queen_id] if queen_alive else 0.0
	var queen_hp_max := cfg.queen_hp_base * CasteDefs.HP_MULT[CasteDefs.Caste.QUEEN]
	_colony.text = "[color=#%s]●[/color] %s   [color=#%s]●[/color] %s   [color=#%s]●[/color] Reina %d%%" % [
		CasteDefs.COLORS[CasteDefs.Caste.WORKER].to_html(false), _plural(c[CasteDefs.Caste.WORKER], "obrera", "obreras"),
		CasteDefs.COLORS[CasteDefs.Caste.SOLDIER].to_html(false), _plural(c[CasteDefs.Caste.SOLDIER], "soldado", "soldados"),
		CasteDefs.COLORS[CasteDefs.Caste.QUEEN].to_html(false), int(100.0 * queen_hp / maxf(queen_hp_max, 0.01))]
	_resources.text = "Comida %.0f / %.0f   +%.0f/min hojas · −%.0f/min consumo%s" % [
		sim.colony.food, sim.colony.food_cap, sim.econ.income_per_min, sim.econ.upkeep_per_min,
		"   ¡HAMBRE!" if sim.colony.starving else ""]

	var change := ceili(DayNight.seconds_to_change(t, cfg))
	var weather := ("De noche: amanece en %d s" if night else "De día: anochece en %d s") % change
	match sim.weather:
		Simulation.Weather.WARNING:
			weather += "   · ¡Lluvia en %d s!" % ceili(sim.rain_eta_s())
		Simulation.Weather.RAINING:
			weather += "   · Lloviendo"
	_weather.text = weather

	# Cría en camino, por casta (lo que el jugador compró y aún no nació).
	var coming := {CasteDefs.Caste.WORKER: 0, CasteDefs.Caste.SOLDIER: 0}
	for i in sim.brood.stage.size():
		if sim.brood.alive[i] and coming.has(sim.brood.caste[i]):
			coming[sim.brood.caste[i]] += 1
	var st := sim.brood.counts_by_stage
	if coming[CasteDefs.Caste.WORKER] + coming[CasteDefs.Caste.SOLDIER] == 0:
		_threats.text = "Nada en camino: compra obreras o soldados abajo"
	else:
		_threats.text = "En camino: %s y %s   (huevo %d · larva %d · pupa %d)" % [
			_plural(coming[CasteDefs.Caste.WORKER], "obrera", "obreras"),
			_plural(coming[CasteDefs.Caste.SOLDIER], "soldado", "soldados"),
			st[BroodSystem.Stage.EGG], st[BroodSystem.Stage.LARVA], st[BroodSystem.Stage.PUPA]]

	var econ := sim.econ
	_buy_btns[0].text = "[7] Obrera: %.0f" % econ.cost(CasteDefs.Caste.WORKER)
	_buy_btns[0].disabled = not econ.can_buy(CasteDefs.Caste.WORKER)
	_buy_btns[1].text = "[8] Soldado: %.0f" % econ.cost(CasteDefs.Caste.SOLDIER)
	_buy_btns[1].disabled = not econ.can_buy(CasteDefs.Caste.SOLDIER)
	_buy_btns[2].text = "[9] Auto: %s" % IncrementalEconomy.AUTO_NAMES[econ.auto_mode]


## `m` es el nodo main.gd: lee todo lo que necesita de él y de `m.sim`.
func update_info(m: Node) -> void:
	var sim: Simulation = m.sim
	_layout()  # barato; sigue el alto real de la ventana si cambia de tamaño
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

	# Fase 3: en el modo incremental el mismo panel cuenta otra cosa (pisa los textos de arriba).
	_m = m
	_buy_row.visible = sim.incremental
	_ratio.visible = not sim.incremental
	_threat_header.text = "CRÍA" if sim.incremental else "AMENAZAS"
	if sim.incremental:
		_update_incremental(m, sim)

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
		if sim.victory:
			_defeat.text = "¡LA COLONIA PROSPERÓ!\n%s\n\nF5 para reiniciar" % sim.game_over_reason
			_defeat.add_theme_color_override("font_color", Color("7fe08a"))
		else:
			_defeat.text = "LA COLONIA CAYÓ\n%s\n\nF5 para reiniciar" % sim.game_over_reason
			_defeat.add_theme_color_override("font_color", Color("ff6a6a"))
		_defeat.size = Vector2(400, 120) * S / 2.0
		_defeat.position = (Vector2(240, 135) * S) - _defeat.size * 0.5
