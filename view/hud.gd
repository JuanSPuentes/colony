class_name Hud
extends CanvasLayer
## HUD en español. Fase 1: dibuja directo a la resolución real de la ventana (ver nota en
## main.gd sobre el SubViewport del mundo), así que el texto se ve nítido en vez de
## borroso/bloqueado. `S` escala el layout, pensado originalmente para 480x270, a la ventana real
## (1440x810 por defecto). `_top`/`_tools`/`_help`/`_legend` se conservan con los mismos
## nombres que en la Fase 0 porque `tools/ui_test.gd` los lee directamente.
##
## Fase 10: panel lateral único, fijo y estático a la izquierda, AFUERA del mundo (`main.gd` reduce
## el `SubViewport` del mundo para dejarle sitio en vez de dibujar el panel encima, ver
## `main._resize_world_container()`). Reemplaza los dos paneles flotantes que había antes (estado +
## herramientas): ahora es un solo `Panel` que ocupa todo el alto de la ventana, con una sección por
## tema (Colonia/Clima/Cría-Amenazas/Herramienta/Reparto-Compra/Mejoras/Estación/Notificaciones).
## Los overlays que sí siguen flotando sobre el mundo (insignia de feromona, panel de pausa, panel
## de Test, pantalla de derrota, tooltip) se posicionan contra el rectángulo real del mundo
## (`main.world_container`), no contra toda la ventana, para seguir centrados en el mapa visible.

## `season_system.gd` no tiene `class_name` (lo carga `Simulation` con `preload`, ver ese archivo);
## se preloadea igual acá para leer `SEASON_NAMES`/`SEASON_COUNT` sin duplicarlos.
const SeasonSystem = preload("res://sim/colony/season_system.gd")

const ERA_NAMES: Array[String] = ["Fundación", "Colonia joven", "Colonia madura"]
const HEADER_COLOR := Color("7fd0ff")
## Factor de escala del layout: ventana real / 480, reducido para que los paneles ocupen menos
## pantalla (antes 3.0 daba paneles casi a media ventana con la barra de abajo todavía puesta).
const S := 2.3
const FONT := 8.0 * S
## El panel lateral usa letra más chica que el resto del HUD para caber en menos espacio.
const PANEL_FONT := 6.0 * S
const OUTLINE := 3
## Ancho del panel lateral en píxeles reales de ventana. Debe coincidir con `Main.SIDEBAR_W` (ese
## archivo reserva exactamente este ancho al achicar el `SubViewport` del mundo); documentado en
## los dos lados para que quede claro por qué tienen que ir de la mano.
const SIDEBAR_W_PX := 300.0
## Ancho del panel expresado en las mismas unidades "baseline" (8px) que usa el resto del layout,
## para que `PANEL_W * S` dé
## siempre `SIDEBAR_W_PX` exacto.
const PANEL_W := SIDEBAR_W_PX / S
## Margen interno de los paneles (en las mismas unidades de 8px que el resto del layout).
const MARGIN_X := 4.0
const MARGIN_Y := 3.0
const CONTENT_W := PANEL_W - MARGIN_X * 2.0
## Fase 14: alto de la barra de estadísticas de arriba del mapa (píxeles reales de ventana). La
## guía (`CoachView`) y la insignia de feromona se ubican debajo de ella.
const TOPBAR_H := 36.0
## Columnas de la barra de controles: encabezado y pares [tecla, qué hace]. Si se agrega una tecla
## nueva en main.gd, se agrega aquí también para que el jugador la vea.
## Fase 5: COLONIA (comprar/ir a la reina) y PARTIDA (guardar/reiniciar) se quitaron de esta lista
## a propósito: son acciones de juego, no "opciones" — la pantalla de Opciones (que reusa esta
## lista) terminó mostrando más de lo que su nombre promete. Las teclas 7/8/9/H/F5/F6/F7/Shift+F5
## siguen funcionando igual en `main.gd`; solo se dejaron de documentar aquí.
const CONTROLS := [
	["HERRAMIENTAS", [["1", "Cavar túneles"], ["2 / 3", "Feromona / Cámara"], ["4", "Borrar todo bajo el pincel"],
		["5", "Mover reina (Shift + clic der. cancela)"],
		["Q / E", "Cambiar subtipo"], ["Clic derecho", "Usar la herramienta"], ["Shift + clic der.", "Borrar / quitar"]]],
	["CÁMARA Y TIEMPO", [["Clic izq. y arrastrar", "Mover la cámara"], ["WASD / flechas", "Mover la cámara (Shift: rápido)"], ["Rueda", "Zoom"], ["Espacio", "Pausa"],
		["F1 / F2 / F3", "Velocidad x1 / x2 / x4"], ["I", "Plegar / desplegar panel"]]],
]

## Estado de plegado del panel lateral. `main.gd` lo lee en `_resize_world_container()` para
## devolverle el ancho completo al mundo quien lo pliega; la tecla I y el botón lo cambian.
var sidebar_open := true

## Fase 3 (menú): `main.gd` la reenvía como `menu_requested` para que `app.gd` abra Opciones.
signal gear_pressed
## `main.gd` la escucha para recalcular `_resize_world_container()`: el panel lateral reserva/
## libera sitio real del mundo, así que cambiar `sidebar_open` sin avisarle a `main` deja el
## `SubViewport` con el tamaño viejo (clics mapeando contra la franja equivocada).
signal sidebar_toggled

var _sidebar: Panel
## Todo lo que cuelga del panel salvo la línea superior (`_top`), para no usarse hoy pero se deja
## documentado: con un solo panel ya no hace falta plegar por partes, se pliega entero
## (`_sidebar.visible`).
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
var _end_panel: PanelContainer
var _end_reason: Label
## Fase 5: tooltip al pasar el mouse sobre una hormiga (casta, vida) o una cámara (tipo, válida).
var _tooltip: Label
## Fase 5: panel visible mientras el juego está en pausa (Espacio), para que una persona nueva
## pueda reiniciar o salir sin saber que Shift+F5/la tuerca existen.
var _pause_panel: PanelContainer
## Recuadro arriba al centro con la feromona activa (muestra de color + nombre), visible solo con
## la herramienta Feromona [2]. Sigue siendo un overlay sobre el mundo (no una sección del panel):
## es información espacial que se mira mientras se pinta, no mientras se lee el panel.
var _phero_badge: PanelContainer
var _phero_swatch: ColorRect
var _phero_label: Label
## Fase 6: panel del modo Test (sandbox), visible solo con `sim.test_mode`.
var _test_panel: PanelContainer

## Fase 3: botones de compra (huevo, auto-compra) del modo incremental.
var _buy_row: HBoxContainer
var _buy_btns: Array[Button] = []
## Fase 5: sliders de reparto de castas (modo clásico). Mismo lugar que `_buy_row`: nunca se
## muestran a la vez (uno es del modo incremental, el otro de la colonia con reina).
var _caste_row: VBoxContainer
var _caste_sliders: Array[HSlider] = []
var _threat_header: Label
## Fase 9 (antes sin interfaz): mejoras de colonia, solo modo incremental.
var _upgrade_section: Control
var _upgrade_btns: Array[Button] = []
## Fase 14: estadísticas reales por casta (vida/velocidad/daño) + cavar, a pedido del jugador —
## antes solo se podía ver el % de vida de una hormiga al pasar el mouse por encima (ver
## `_process`), no los números base ni cómo los mueven las mejoras compradas.
var _stats_label: RichTextLabel
## Fase 9 (antes sin interfaz): estación actual + estado de la colonia rival, solo incremental.
var _season_section: Control
var _season_label: Label
var _rival_label: Label
## Fase 14: piezas del panel en columna (ver `_ready`).
const SIDE_PAD := 3.0 * S
var _scroll: ScrollContainer
var _log_card: PanelContainer
var _last_header: Label
## Fase 14: barra de arriba del mapa: símbolos y números de lo más importante, de un vistazo.
var _topbar: PanelContainer
var _topbar_row: HBoxContainer


func _ready() -> void:
	var theme := Theme.new()
	theme.set_default_font_size(FONT)
	var root := Control.new()
	root.theme = theme
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_sidebar = Panel.new()
	_sidebar.add_theme_stylebox_override("panel", _panel_style(1.0))
	_sidebar.position = Vector2.ZERO
	_sidebar.size = Vector2(PANEL_W, 270.0) * S  # alto real lo fija `_layout()` cada frame.
	_sidebar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_sidebar)

	# El botón de plegar vive FUERA del panel (hijo de `root`, no de `_sidebar`): si colgara del
	# panel, se escondería con él al plegarlo y ya no habría forma de volver a abrirlo con el mouse.
	_build_fold_button(root)

	# Fase 14 (orden del panel, a pedido del jugador: "todo está pegado"): antes cada línea iba en
	# una `y` fija, así que el texto largo se cortaba o se encimaba con la sección de abajo. Ahora
	# cada sección es una tarjeta dentro de una columna con scroll: las alturas salen del contenido
	# (sin `clip_text`, que era lo que hacía colapsar las filas dentro de un contenedor) y siempre
	# queda aire entre secciones.
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(0.0, (MARGIN_Y + 9.0) * S)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sidebar.add_child(_scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_left", int(SIDE_PAD))
	pad.add_theme_constant_override("margin_right", int(SIDE_PAD))
	pad.add_theme_constant_override("margin_bottom", int(SIDE_PAD))
	_scroll.add_child(pad)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(PANEL_W * S - 2.0 * SIDE_PAD, 0.0)
	col.add_theme_constant_override("separation", int(3 * S))
	pad.add_child(col)

	var top_card := _card(col)
	_top = _line(top_card)

	var colony := _section(col, "COLONIA")
	_colony = _rich(colony)
	_resources = _line(colony)

	var weather := _section(col, "CLIMA")
	_weather = _line(weather)

	var threats := _section(col, "AMENAZAS")
	_threat_header = _last_header
	_threats = _line(threats)

	var tools := _section(col, "HERRAMIENTA")
	_tools = _line(tools)
	_legend = _rich(tools)

	var buy := _section(col, "REPARTO / COMPRA")
	_ratio = _line(buy)
	_buy_row = HBoxContainer.new()
	_buy_row.add_theme_constant_override("separation", int(2 * S))
	buy.add_child(_buy_row)
	for k in 2:
		var b := _buy_button()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0.0, 9.0 * S)
		_buy_row.add_child(b)
		_buy_btns.append(b)
	_buy_btns[0].pressed.connect(func() -> void: _m.sim.cmd_buy_egg())
	_buy_btns[1].pressed.connect(func() -> void: _m.sim.cmd_cycle_auto_buy())

	_caste_row = VBoxContainer.new()
	_caste_row.add_theme_constant_override("separation", int(2 * S))
	buy.add_child(_caste_row)
	var castes := [CasteDefs.Caste.WORKER, CasteDefs.Caste.NURSE, CasteDefs.Caste.SOLDIER, CasteDefs.Caste.DRONE]
	for c in castes:
		var s := HSlider.new()
		s.min_value = 0.05
		s.max_value = 0.9
		s.step = 0.01
		s.custom_minimum_size = Vector2(0.0, 8.0) * S
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.modulate = CasteDefs.COLORS[c]
		_caste_row.add_child(s)
		_caste_sliders.append(s)
		s.value_changed.connect(func(v: float) -> void: _m.sim.cmd_set_caste_target(c, v))

	# Fase 9: mejoras de colonia, un botón por stat. Solo existen en el modo incremental
	# (`Upgrades`/`cmd_buy_upgrade` atados a `sim.incremental`); se ocultan enteras en los demás
	# modos (`update_info`), junto con las estadísticas que esas mejoras mueven.
	var up_box := VBoxContainer.new()
	up_box.add_theme_constant_override("separation", int(3 * S))
	col.add_child(up_box)
	_upgrade_section = up_box
	var upgrades := _section(up_box, "MEJORAS")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", int(2 * S))
	grid.add_theme_constant_override("v_separation", int(2 * S))
	upgrades.add_child(grid)
	for stat in Upgrades.STAT_COUNT:
		var ub := _buy_button()
		ub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ub.custom_minimum_size = Vector2(0.0, 13.0 * S)
		grid.add_child(ub)
		_upgrade_btns.append(ub)
		ub.pressed.connect(func() -> void: _m.sim.cmd_buy_upgrade(stat))
	var stats := _section(up_box, "ESTADÍSTICAS")
	_stats_label = _rich(stats)

	# Fase 9: estación actual + estado de la colonia rival, solo incremental (mismo motivo).
	_season_section = _section_card(col, "ESTACIÓN")
	var season := _season_section.get_child(0) as VBoxContainer
	_season_label = _line(season)
	_rival_label = _line(season)

	_log_card = _section_card(col, "AVISOS")
	_log = _rich(_log_card.get_child(0) as VBoxContainer)

	_build_top_bar(root)
	_build_gear_button(root)
	_build_phero_badge(root)

	# Fase 14: el final de partida era un `Label` suelto de tamaño fijo con todo el texto en letra
	# gigante: un motivo largo (el del Nivel 0) se salía de la pantalla por los costados. Ahora es
	# una tarjeta: título grande, el motivo en letra normal con salto de línea y cómo seguir.
	_end_panel = PanelContainer.new()
	var end_style := _panel_style(0.94)
	end_style.content_margin_left = 28.0
	end_style.content_margin_right = 28.0
	end_style.content_margin_top = 18.0
	end_style.content_margin_bottom = 18.0
	_end_panel.add_theme_stylebox_override("panel", end_style)
	_end_panel.visible = false
	root.add_child(_end_panel)
	var end_box := VBoxContainer.new()
	end_box.add_theme_constant_override("separation", 10)
	_end_panel.add_child(end_box)
	_defeat = Label.new()
	_defeat.add_theme_font_size_override("font_size", 34)
	_defeat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_box.add_child(_defeat)
	_end_reason = Label.new()
	_end_reason.add_theme_font_size_override("font_size", 17)
	_end_reason.add_theme_color_override("font_color", Color("f4ecd8"))
	_end_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_end_reason.custom_minimum_size = Vector2(440, 0)
	end_box.add_child(_end_reason)
	var end_hint := Label.new()
	end_hint.text = "F5: jugar de nuevo   ·   ⚙: salir al menú"
	end_hint.add_theme_font_size_override("font_size", 14)
	end_hint.add_theme_color_override("font_color", Color(0.75, 0.72, 0.68))
	end_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_box.add_child(end_hint)

	_build_pause_panel(root)
	_build_test_panel(root)

	_tooltip = Label.new()
	_tooltip.add_theme_font_size_override("font_size", PANEL_FONT)
	_tooltip.add_theme_color_override("font_color", Color("f4ecd8"))
	_tooltip.add_theme_color_override("font_outline_color", Color.BLACK)
	_tooltip.add_theme_constant_override("outline_size", OUTLINE)
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.visible = false
	root.add_child(_tooltip)


func _build_top_bar(root: Control) -> void:
	_topbar = PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.07, 0.06, 0.08, 0.78)
	st.set_corner_radius_all(4)
	st.content_margin_left = 10.0
	st.content_margin_right = 10.0
	_topbar.add_theme_stylebox_override("panel", st)
	_topbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_topbar)
	_topbar_row = HBoxContainer.new()
	_topbar_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_topbar_row.add_theme_constant_override("separation", 22)
	_topbar.add_child(_topbar_row)


## Cada dato: [símbolo, texto, tooltip]. Rehace las etiquetas solo si cambió cuántas hay.
func _set_top_items(items: Array) -> void:
	while _topbar_row.get_child_count() < items.size():
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 17)
		l.add_theme_color_override("font_color", Color("f4ecd8"))
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		_topbar_row.add_child(l)
	for i in _topbar_row.get_child_count():
		var l := _topbar_row.get_child(i) as Label
		l.visible = i < items.size()
		if l.visible:
			l.text = "%s %s" % [items[i][0], items[i][1]]
			l.tooltip_text = items[i][2]


func _fmt_time(sec: float) -> String:
	var t := maxi(0, ceili(sec))
	return "%d:%02d" % [t / 60, t % 60]


func _update_top_bar(m: Node, sim: Simulation) -> void:
	var cfg := sim.cfg
	var items := []
	var mine := 0
	for i in sim.ants.count:
		if sim.ants.alive[i] == 1 and sim.ants.faction[i] == 0:
			mine += 1
	items.append(["🐜", str(mine), "Hormigas de tu colonia"])
	items.append(["🍃", "%.0f" % sim.colony.food, "Comida"])
	if sim.queen_id >= 0:
		var q_max := cfg.queen_hp_base * CasteDefs.HP_MULT[CasteDefs.Caste.QUEEN]
		var q_hp := sim.ants.hp[sim.queen_id] if sim.ants.alive[sim.queen_id] == 1 else 0.0
		items.append(["👑", "%d%%" % int(100.0 * q_hp / maxf(q_max, 0.01)), "Vida de la reina"])
	if sim.incremental or sim.test_mode:
		var night := sim.is_night()
		items.append(["🌙" if night else "☀", _fmt_time(DayNight.seconds_to_change(sim.time_s(), cfg)),
			"Falta para que amanezca" if night else "Falta para que anochezca"])
		items.append(["📅", "Día %d" % sim.day_number(), "Día actual"])
	else:
		items.append(["💧", "%.0f" % sim.colony.water, "Agua"])
		items.append(["🏛", ERA_NAMES[sim.era], "Era de la colonia"])
	if sim.incremental and not sim.tutorial_level and sim.season_index < SeasonSystem.SEASON_COUNT:
		var icons := ["🌱", "☀", "🍂", "❄"]
		items.append([icons[sim.season_index], "%s %d/%d" % [SeasonSystem.SEASON_NAMES[sim.season_index], sim.season_index + 1, SeasonSystem.SEASON_COUNT], "Estación"])
	var rival := sim.rival_colony
	if sim.incremental and rival.battle_active:
		items.append(["⚔", "¡Batalla! %d%%" % int(100.0 * rival.queen.hp / maxf(rival.queen.max_hp, 0.01)), "Vida de la reina rival"])
	elif sim.incremental and not sim.tutorial_level and sim.season_index < SeasonSystem.SEASON_COUNT:
		# La batalla empieza al llegar al último día de la estación (`SeasonSystem.update`).
		var day_in := (sim.day_number() - 1) % cfg.season_length_days
		var left := cfg.season_length_days - 1 - day_in
		items.append(["⚔", "Hoy" if left <= 0 else ("en %d %s" % [left, "día" if left == 1 else "días"]), "Próxima batalla de fin de estación"])
	if sim.weather != Simulation.Weather.CLEAR:
		items.append(["🌧", "¡%ds!" % ceili(sim.rain_eta_s()) if sim.weather == Simulation.Weather.WARNING else "Lloviendo", "Lluvia"])
	if m.paused:
		items.append(["⏸", "Pausa", "Espacio para seguir"])
	elif m.speed > 1:
		items.append(["⏩", "x%d" % m.speed, "Velocidad"])
	_set_top_items(items)
	var r := _world_rect(m)
	var gear_w := 15.0 * S
	_topbar.position = r.position + Vector2(8.0, 6.0)
	_topbar.size = Vector2(r.size.x - 16.0 - gear_w, TOPBAR_H)


## Botón "ocultar / mostrar" el panel lateral, fijo en la esquina superior izquierda de la ventana
## (no del panel: así sigue visible y clicable aunque el panel esté oculto).
func _build_fold_button(root: Control) -> void:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", PANEL_FONT)
	b.add_theme_color_override("font_color", HEADER_COLOR)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.position = Vector2(MARGIN_X, MARGIN_Y) * S
	b.custom_minimum_size = Vector2(PANEL_W - MARGIN_X * 2.0, 7.0) * S
	b.size = b.custom_minimum_size
	b.pressed.connect(toggle_sidebar)
	root.add_child(b)
	_sidebar_btn = b


var _sidebar_btn: Button


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
	var style := _panel_style()
	for s in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(s, style)
	b.pressed.connect(func() -> void: gear_pressed.emit())
	root.add_child(b)


## Recuadro con la feromona activa: una muestra de color (mismo color que la capa de depuración,
## `OverlayView.PHERO_COLORS`) y su nombre. Solo visible con la herramienta Feromona [2]; su
## posición se recalcula cada frame contra el rectángulo del mundo (`update_info`), no contra toda
## la ventana, para seguir centrado sobre el mapa visible aunque el panel lateral le quite sitio.
func _build_phero_badge(root: Control) -> void:
	var panel := PanelContainer.new()
	var style := _panel_style()
	style.content_margin_left = 6.0 * S
	style.content_margin_right = 6.0 * S
	style.content_margin_top = 3.0 * S
	style.content_margin_bottom = 3.0 * S
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	root.add_child(panel)
	_phero_badge = panel

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(3 * S))
	panel.add_child(row)

	_phero_swatch = ColorRect.new()
	_phero_swatch.custom_minimum_size = Vector2(7.0, 7.0) * S
	row.add_child(_phero_swatch)

	_phero_label = Label.new()
	_phero_label.add_theme_font_size_override("font_size", PANEL_FONT)
	_phero_label.add_theme_color_override("font_color", Color("f4ecd8"))
	row.add_child(_phero_label)


## Fase 5: panel centrado con Reiniciar/Salir, visible solo en pausa manual (Espacio), para que una
## persona nueva no dependa de saber que Shift+F5 o la tuerca existen (prompt_fase3_godot.md 4.4).
func _build_pause_panel(root: Control) -> void:
	var panel := PanelContainer.new()
	var style := _panel_style(0.95)
	style.content_margin_left = 16.0 * S
	style.content_margin_right = 16.0 * S
	style.content_margin_top = 10.0 * S
	style.content_margin_bottom = 10.0 * S
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.visible = false
	root.add_child(panel)
	_pause_panel = panel

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(4 * S))
	panel.add_child(box)

	var title := Label.new()
	title.text = "Pausa"
	title.add_theme_font_size_override("font_size", PANEL_FONT)
	title.add_theme_color_override("font_color", HEADER_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var restart := _buy_button()
	restart.text = "Reiniciar"
	restart.pressed.connect(func() -> void: _m.start(_m.seed_value))
	box.add_child(restart)

	var quit := _buy_button()
	quit.text = "Salir"
	quit.pressed.connect(func() -> void: gear_pressed.emit())
	box.add_child(quit)


## Fase 6: panel del modo Test (sandbox) — reiniciar, poner/quitar amenazas, agregar hormigas de
## cualquier casta. Su posición la fija `update_info` cada frame contra la esquina superior derecha
## del rectángulo del mundo (no de toda la ventana), y solo lo deja visible con `sim.test_mode`.
func _build_test_panel(root: Control) -> void:
	var panel := PanelContainer.new()
	var style := _panel_style()
	style.content_margin_left = 6.0 * S
	style.content_margin_right = 6.0 * S
	style.content_margin_top = 5.0 * S
	style.content_margin_bottom = 5.0 * S
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.visible = false
	root.add_child(panel)
	_test_panel = panel

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(3 * S))
	box.custom_minimum_size = Vector2(90.0, 0) * S
	panel.add_child(box)

	var title := Label.new()
	title.text = "PRUEBAS"
	title.add_theme_font_size_override("font_size", PANEL_FONT)
	title.add_theme_color_override("font_color", HEADER_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_test_btn(box, "Reiniciar prueba", func() -> void:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		_m.start(rng.randi() % 1000000))
	_test_btn(box, "Lluvia ahora", func() -> void: _m.sim.cmd_force_rain())
	_test_btn(box, "Detener lluvia", func() -> void: _m.sim.cmd_stop_rain())
	_test_btn(box, "Aparecer araña", func() -> void: _m.sim.cmd_force_spider())
	_test_btn(box, "Quitar araña", func() -> void: _m.sim.cmd_remove_spider())
	_test_btn(box, "Aparecer ciempiés", func() -> void: _m.sim.cmd_force_centipede())
	_test_btn(box, "Quitar ciempiés", func() -> void: _m.sim.cmd_remove_centipede())
	_test_btn(box, "Aparecer mantis", func() -> void: _m.sim.cmd_force_mantis())
	_test_btn(box, "Quitar mantis", func() -> void: _m.sim.cmd_remove_mantis())
	_test_btn(box, "+5 Obreras", func() -> void: _m.sim.cmd_add_caste_ants(CasteDefs.Caste.WORKER, 5))
	_test_btn(box, "+5 Guerreras", func() -> void: _m.sim.cmd_add_caste_ants(CasteDefs.Caste.SOLDIER, 5))
	_test_btn(box, "+5 Zánganos", func() -> void: _m.sim.cmd_add_caste_ants(CasteDefs.Caste.DRONE, 5))
	_test_btn(box, "+5 Nodrizas", func() -> void: _m.sim.cmd_add_caste_ants(CasteDefs.Caste.NURSE, 5))


func _test_btn(parent: Control, text: String, cb: Callable) -> void:
	var b := _buy_button()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)


## Botón de compra: recuadro con borde (a diferencia de los de plegar, que son solo texto) para que
## se lea como algo que se pulsa. Sin foco de teclado, por el mismo motivo que el botón de plegar.
func _buy_button() -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(CONTENT_W, 8.0) * S
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


func toggle_sidebar() -> void:
	sidebar_open = not sidebar_open
	_layout()
	sidebar_toggled.emit()


## Aplica el estado de plegado (todo el panel, de una) y lo estira al alto real de la ventana.
func _layout() -> void:
	_sidebar.visible = sidebar_open
	_sidebar_btn.text = "ocultar panel (I)" if sidebar_open else "mostrar panel (I)"
	var h := get_viewport().get_visible_rect().size.y if get_viewport() != null else 270.0 * S
	_sidebar.size.y = maxf(h, 270.0 * S)
	if _scroll != null:
		_scroll.size = Vector2(PANEL_W * S, _sidebar.size.y - _scroll.position.y)


## Mismo fondo oscuro y borde dorado en todos los recuadros de la interfaz (paneles, botones de
## compra, tuerca, insignia de feromona, panel de pausa), para que se lean como una sola familia
## en vez de cada uno inventando su propio estilo.
func _panel_style(bg_alpha: float = 0.92) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.08, bg_alpha)
	style.border_color = Color("ffd43c")
	style.set_border_width_all(1)
	style.set_corner_radius_all(int(3 * S))
	return style


## Fase 14: piezas del panel lateral en columna (ver `_ready`). Cada sección es una tarjeta con
## fondo un poco más claro que el panel, encabezado en `HEADER_COLOR` y su contenido debajo.
func _card_style() -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.12, 0.11, 0.13, 1.0)
	st.set_corner_radius_all(int(2 * S))
	st.content_margin_left = 3.0 * S
	st.content_margin_right = 3.0 * S
	st.content_margin_top = 2.0 * S
	st.content_margin_bottom = 2.5 * S
	return st


## Tarjeta sin encabezado; devuelve la columna donde van sus líneas.
func _card(parent: Control) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _card_style())
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(pc)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(1.5 * S))
	pc.add_child(box)
	return box


## Tarjeta con encabezado; devuelve la tarjeta entera (para poder ocultarla de una).
func _section_card(parent: Control, title: String) -> PanelContainer:
	var box := _card(parent)
	var h := Label.new()
	h.text = title
	h.add_theme_font_size_override("font_size", int(PANEL_FONT * 0.85))
	h.add_theme_color_override("font_color", HEADER_COLOR)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(h)
	_last_header = h
	return box.get_parent() as PanelContainer


## Tarjeta con encabezado; devuelve la columna del contenido.
func _section(parent: Control, title: String) -> VBoxContainer:
	return _section_card(parent, title).get_child(0) as VBoxContainer


func _line(parent: Control) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", PANEL_FONT)
	l.add_theme_color_override("font_color", Color("f4ecd8"))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(l)
	return l


func _rich(parent: Control) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("normal_font_size", PANEL_FONT)
	l.add_theme_font_size_override("bold_font_size", PANEL_FONT)
	l.add_theme_color_override("default_color", Color("f4ecd8"))
	parent.add_child(l)
	return l


func _trend_arrow(v: float) -> String:
	if v > 0.5:
		return "↑"
	if v < -0.5:
		return "↓"
	return "→"


func _plural(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


## Rectángulo real del mundo en la ventana (posición y tamaño del `SubViewportContainer` de
## `main.gd`), para que los overlays que flotan sobre el mapa (insignia de feromona, pausa, panel
## de Test, derrota) se centren en el mapa visible y no en el hueco que deja el panel lateral.
func _world_rect(m: Node) -> Rect2:
	if m.world_container == null:
		return Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	return Rect2(m.world_container.position, m.world_container.size)


## Modo incremental (Fase 3): sin semilla, sin agua, sin araña ni eras. Muestra el día, la comida
## como único recurso, la cría que viene en camino y el precio de cada compra.
func _update_incremental(m: Node, sim: Simulation) -> void:
	var cfg := sim.cfg
	var t := sim.time_s()
	var night := sim.is_night()
	_top.text = "Día %d · %s\nHormigas: %d   ·   %s   ·   %d FPS" % [
		sim.day_number(), "de noche" if night else "de día", sim.ants.alive_count,
		"En pausa" if m.paused else "Velocidad x%d" % m.speed, Engine.get_frames_per_second()]

	var c := sim.ants.count_by_caste([CasteDefs.Caste.WORKER, CasteDefs.Caste.SOLDIER])
	var queen_alive := sim.ants.alive[sim.queen_id] == 1
	var queen_hp := sim.ants.hp[sim.queen_id] if queen_alive else 0.0
	var queen_hp_max := cfg.queen_hp_base * CasteDefs.HP_MULT[CasteDefs.Caste.QUEEN]
	_colony.text = "[color=#%s]●[/color] %s   [color=#%s]●[/color] %s   [color=#%s]●[/color] Reina %d%%" % [
		CasteDefs.COLORS[CasteDefs.Caste.WORKER].to_html(false), _plural(c[CasteDefs.Caste.WORKER], "obrera", "obreras"),
		CasteDefs.COLORS[CasteDefs.Caste.SOLDIER].to_html(false), _plural(c[CasteDefs.Caste.SOLDIER], "soldado", "soldados"),
		CasteDefs.COLORS[CasteDefs.Caste.QUEEN].to_html(false), int(100.0 * queen_hp / maxf(queen_hp_max, 0.01))]
	_resources.text = "Comida: %.0f / %.0f\n+%.0f/min por hojas · −%.0f/min de consumo%s" % [
		sim.colony.food, sim.colony.food_cap, sim.econ.income_per_min, sim.econ.upkeep_per_min,
		"\n¡HAMBRE!" if sim.colony.starving else ""]

	var change := ceili(DayNight.seconds_to_change(t, cfg))
	var weather := ("De noche: amanece en %d s" if night else "De día: anochece en %d s") % change
	match sim.weather:
		Simulation.Weather.WARNING:
			weather += "\n¡Lluvia en %d s!" % ceili(sim.rain_eta_s())
		Simulation.Weather.RAINING:
			weather += "\nLloviendo"
	_weather.text = weather

	# Cría en camino, por casta (lo que el jugador compró y aún no nació). La casta de cada huevo
	# ya se sorteó al comprarlo (`IncrementalEconomy.buy_egg`), así que esto no es una previsión:
	# es lo que de verdad va a nacer. Un punto de color por huevo (no por larva/pupa, para no
	# amontonar la línea) adelanta el resultado antes de que se vea la hormiga.
	var coming := {CasteDefs.Caste.WORKER: 0, CasteDefs.Caste.SOLDIER: 0}
	var egg_dots := ""
	for i in sim.brood.stage.size():
		if not sim.brood.alive[i] or not coming.has(sim.brood.caste[i]):
			continue
		coming[sim.brood.caste[i]] += 1
		if sim.brood.stage[i] == BroodSystem.Stage.EGG:
			egg_dots += "[color=#%s]●[/color]" % CasteDefs.COLORS[sim.brood.caste[i]].to_html(false)
	var st := sim.brood.counts_by_stage
	if coming[CasteDefs.Caste.WORKER] + coming[CasteDefs.Caste.SOLDIER] == 0:
		_threats.text = "Nada en camino: compra un huevo abajo"
	else:
		_threats.text = "En camino: %s y %s\nLarvas: %d   ·   Pupas: %d" % [
			_plural(coming[CasteDefs.Caste.WORKER], "obrera", "obreras"),
			_plural(coming[CasteDefs.Caste.SOLDIER], "soldado", "soldados"),
			st[BroodSystem.Stage.LARVA], st[BroodSystem.Stage.PUPA]]
	if egg_dots != "":
		_colony.text += "   Huevos: " + egg_dots
	# La araña también aparece en este modo (por población, sin eras: ver
	# cfg.inc_spider_first_population). Reusa la línea de "en camino" en vez de sumar una línea
	# nueva: el panel tiene la altura de siempre calculada para una sola línea acá, y agregar una
	# de más (como se probó primero) tapaba la línea de comida de abajo.
	if sim.spider.alive:
		var state_names := {Spider.State.SEARCH: "buscando presas", Spider.State.ATTACK: "atacando",
			Spider.State.SIEGE: "en la entrada", Spider.State.RETREAT: "huyendo"}
		_threats.text = "¡Araña %s! (%d%%)" % [
			state_names.get(sim.spider.state, "cerca"), int(100.0 * sim.spider.hp / maxf(sim.spider.max_hp, 0.01))]

	var econ := sim.econ
	_buy_btns[0].text = "[7] Huevo: %.0f" % econ.egg_cost()
	_buy_btns[0].disabled = not econ.can_buy_egg()
	_buy_btns[1].text = "[9] Auto: %s" % IncrementalEconomy.AUTO_NAMES[econ.auto_mode]

	# Fase 9 (antes sin interfaz): mejoras de colonia.
	var up := sim.upgrades
	for stat in Upgrades.STAT_COUNT:
		var b := _upgrade_btns[stat]
		b.text = "%s\nNv.%d · %.0f comida" % [Upgrades.STAT_NAMES[stat], up.levels[stat], up.cost(stat)]
		b.disabled = not up.can_buy(stat)

	# Fase 14: estadísticas reales por casta, con las mejoras ya aplicadas — vida/velocidad/daño
	# salen de CasteDefs * cfg, multiplicados por el stat de Upgrades correspondiente (mismo
	# cálculo que usa AntSystem al nacer/moverse/atacar, ver sim/colony/upgrades.gd). "Cavar" es
	# por colonia, no por casta: cfg.dig_seconds / work_mult es lo que tarda cualquier hormiga
	# cavando una celda marcada, sin importar quién sea.
	# Tabla: la casta a la izquierda y una columna por número, para leerlos de un vistazo.
	var dim := "[color=#9a94a0]%s[/color]"
	var stats_text := "[table=4][cell][/cell][cell]%s  [/cell][cell]%s  [/cell][cell]%s[/cell]" % [dim % "Vida", dim % "Vel.", dim % "Daño/s"]
	for stat_caste in [CasteDefs.Caste.QUEEN, CasteDefs.Caste.WORKER, CasteDefs.Caste.SOLDIER]:
		var base_hp: float = cfg.queen_hp_base if stat_caste == CasteDefs.Caste.QUEEN else cfg.ant_hp
		var hp_val := base_hp * CasteDefs.HP_MULT[stat_caste] * up.hp_mult
		var speed_val := cfg.ant_speed * CasteDefs.SPEED_MULT[stat_caste] * up.speed_mult
		var dmg_val := CasteDefs.DAMAGE_PER_S[stat_caste] * up.damage_mult
		stats_text += "[cell][color=#%s]●[/color] %s  [/cell][cell]%.0f[/cell][cell]%.1f[/cell][cell]%.1f[/cell]" % [
			CasteDefs.COLORS[stat_caste].to_html(false), CasteDefs.NAMES[stat_caste], hp_val, speed_val, dmg_val]
	stats_text += "[/table]\n" + dim % ("Cavar una celda: %.1f s" % (cfg.dig_seconds / up.work_mult))
	_stats_label.text = stats_text

	# Fase 9 (antes sin interfaz): estación actual + colonia rival.
	_season_label.text = "%s (día %d/%d)" % [
		SeasonSystem.SEASON_NAMES[sim.season_index], (sim.day_number() - 1) % sim.cfg.season_length_days + 1,
		sim.cfg.season_length_days] if sim.season_index < SeasonSystem.SEASON_COUNT else "¡Las 4 estaciones superadas!"
	var rival := sim.rival_colony
	if rival.battle_active:
		_rival_label.text = "¡Batalla! Reina rival %d%%" % int(100.0 * rival.queen.hp / maxf(rival.queen.max_hp, 0.01))
	else:
		_rival_label.text = "Sin ataque en curso"


## Fase 5: tooltip al pasar el mouse. Se recalcula cada frame (barato: una hormiga cercana y una
## celda), no cada tick de simulación, así que vive en `_process`, no en `update_info`.
func _process(_delta: float) -> void:
	if _m == null or _m.sim == null or _defeat.visible:
		_tooltip.visible = false
		return
	var screen_pos := get_viewport().get_mouse_position()
	var world_pos: Vector2 = _m._to_world(screen_pos)
	var cell: Vector2i = _m._world_cell(world_pos)
	var sim: Simulation = _m.sim
	var text := ""
	if sim.queen_id >= 0:
		var nearest := -1
		var nearest_d := 6.0  # px: el radio de "estás señalando esta hormiga".
		for i in sim.ants.count:
			if sim.ants.alive[i] == 0:
				continue
			var d: float = sim.ants.pos[i].distance_to(world_pos)
			if d < nearest_d:
				nearest_d = d
				nearest = i
		if nearest >= 0:
			var nc: int = sim.ants.caste[nearest]
			var base_hp: float = sim.cfg.queen_hp_base if nc == CasteDefs.Caste.QUEEN else sim.cfg.ant_hp
			text = "%s   %d%% vida" % [CasteDefs.NAMES[nc],
				int(100.0 * sim.ants.hp[nearest] / maxf(base_hp * CasteDefs.HP_MULT[nc], 0.01))]
	if text == "" and sim.world.in_bounds(cell.x, cell.y):
		var room_type: int = sim.world.room[cell.y * sim.world.w + cell.x]
		if room_type != WorldGrid.Room.NONE:
			var valid: bool = sim.rooms.valid[room_type]
			text = "%s — %s" % [WorldGrid.ROOM_NAMES[room_type], "válida" if valid else "inválida (falta espacio)"]
	_tooltip.text = text
	_tooltip.visible = text != ""
	if text != "":
		_tooltip.position = screen_pos + Vector2(14, 14)


## `m` es el nodo main.gd: lee todo lo que necesita de él y de `m.sim`.
func update_info(m: Node) -> void:
	var sim: Simulation = m.sim
	_layout()  # barato; sigue el alto real de la ventana si cambia de tamaño
	_top.text = "Hormigas: %d   ·   %s   ·   %d FPS\nSemilla: %d" % [
		sim.ants.alive_count, "En pausa" if m.paused else "Velocidad x%d" % m.speed, Engine.get_frames_per_second(), sim.rng.seed]

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

	# --- Amenazas: quién anda rondando la colonia. Fase 5: ya puede haber dos a la vez (araña y
	# ciempiés), se listan juntas en la misma línea en vez de sumar una línea por amenaza (mismo
	# espíritu que la nota de arriba sobre no concatenar secciones nuevas sin pensar el layout).
	if sim.queen_id >= 0:
		var threat_parts: Array[String] = []
		if sim.spider.alive:
			var spider_states := {Spider.State.SEARCH: "buscando presas", Spider.State.ATTACK: "atacando",
				Spider.State.SIEGE: "en la entrada", Spider.State.RETREAT: "huyendo"}
			threat_parts.append("Araña %s (%d%%)" % [spider_states.get(sim.spider.state, "cerca"),
				int(100.0 * sim.spider.hp / maxf(sim.spider.max_hp, 0.01))])
		if sim.centipede.alive:
			var cent_states := {Centipede.State.SEARCH: "buscando presas", Centipede.State.CHASE: "persiguiendo",
				Centipede.State.ATTACK: "atacando", Centipede.State.RETREAT: "huyendo"}
			threat_parts.append("Ciempiés %s (%d%%)" % [cent_states.get(sim.centipede.state, "cerca"),
				int(100.0 * sim.centipede.hp / maxf(sim.centipede.max_hp, 0.01))])
		if sim.mantis.alive:
			var mantis_states := {Mantis.State.HIDDEN: "camuflada", Mantis.State.ATTACK: "atacando",
				Mantis.State.RETREAT: "huyendo"}
			threat_parts.append("Mantis %s (%d%%)" % [mantis_states.get(sim.mantis.state, "cerca"),
				int(100.0 * sim.mantis.hp / maxf(sim.mantis.max_hp, 0.01))])
		_threats.text = " · ".join(threat_parts) if not threat_parts.is_empty() else "Ninguna a la vista"

	if sim.queen_id >= 0:
		var c := sim.ants.count_by_caste([CasteDefs.Caste.WORKER, CasteDefs.Caste.NURSE, CasteDefs.Caste.SOLDIER, CasteDefs.Caste.DRONE])
		var queen_alive := sim.ants.alive[sim.queen_id] == 1
		var queen_hp := sim.ants.hp[sim.queen_id] if queen_alive else 0.0
		var queen_hp_max := sim.cfg.queen_hp_base * CasteDefs.HP_MULT[CasteDefs.Caste.QUEEN]
		# El bullet de cada casta usa el mismo color con el que se ve en el mundo.
		_colony.text = "[color=#%s]●[/color]%d [color=#%s]●[/color]%d [color=#%s]●[/color]%d [color=#%s]●[/color]%d [color=#%s]●[/color]%d%%   %s" % [
			CasteDefs.COLORS[CasteDefs.Caste.WORKER].to_html(false), c[CasteDefs.Caste.WORKER],
			CasteDefs.COLORS[CasteDefs.Caste.NURSE].to_html(false), c[CasteDefs.Caste.NURSE],
			CasteDefs.COLORS[CasteDefs.Caste.SOLDIER].to_html(false), c[CasteDefs.Caste.SOLDIER],
			CasteDefs.COLORS[CasteDefs.Caste.DRONE].to_html(false), c[CasteDefs.Caste.DRONE],
			CasteDefs.COLORS[CasteDefs.Caste.QUEEN].to_html(false), int(100.0 * queen_hp / maxf(queen_hp_max, 0.01)),
			ERA_NAMES[sim.era]]
		_resources.text = "Cría %d/%d/%d   Comida %.0f%s  Agua %.0f%s" % [
			sim.brood.counts_by_stage[BroodSystem.Stage.EGG], sim.brood.counts_by_stage[BroodSystem.Stage.LARVA], sim.brood.counts_by_stage[BroodSystem.Stage.PUPA],
			sim.colony.food, _trend_arrow(sim.colony.food_trend), sim.colony.water, _trend_arrow(sim.colony.water_trend)]
		var t := sim.colony.target_pct
		_ratio.text = "Reparto → Obreras %d%%  Nodrizas %d%%  Soldados %d%%  Zánganos %d%%" % [
			int(t[CasteDefs.Caste.WORKER] * 100), int(t[CasteDefs.Caste.NURSE] * 100), int(t[CasteDefs.Caste.SOLDIER] * 100), int(t[CasteDefs.Caste.DRONE] * 100)]
		var castes := [CasteDefs.Caste.WORKER, CasteDefs.Caste.NURSE, CasteDefs.Caste.SOLDIER, CasteDefs.Caste.DRONE]
		for i in castes.size():
			_caste_sliders[i].set_value_no_signal(t[castes[i]])
		var lines := ""
		for n in sim.notifications:
			lines += "[color=#ffd43c]• %s[/color]\n" % n
		_log.text = lines
	else:
		_colony.text = ""
		_resources.text = ""
		_ratio.text = ""
		_log.text = ""
	_log_card.visible = _log.text != ""

	# Fase 3: en el modo incremental el mismo panel cuenta otra cosa (pisa los textos de arriba).
	_m = m
	_buy_row.visible = sim.incremental
	_ratio.visible = not sim.incremental
	_caste_row.visible = not sim.incremental
	# Fase 9: Mejoras y Estación solo existen de verdad en el modo incremental (`Upgrades`/
	# `SeasonSystem` atados a `sim.incremental`, ver sim/colony/upgrades.gd y season_system.gd).
	_upgrade_section.visible = sim.incremental
	_season_section.visible = sim.incremental

	var world_rect := _world_rect(m)
	_pause_panel.visible = m.paused and not sim.game_over
	if _pause_panel.visible:
		_pause_panel.position = world_rect.position + (world_rect.size - _pause_panel.size) * 0.5
	_test_panel.visible = sim.test_mode
	if _test_panel.visible:
		_test_panel.position = world_rect.position + Vector2(world_rect.size.x - _test_panel.size.x - 10.0 * S, 10.0 * S)
	_threat_header.text = "CRÍA" if sim.incremental else "AMENAZAS"
	if sim.incremental:
		_update_incremental(m, sim)

	var tool_names := ["", "Cavar [1]", "Feromona [2]", "Cámara [3]", "Borrar [4]", "Mover reina [5]"]
	var sub := ""
	if m.tool == 2:
		sub = " · %s (Q/E)" % OverlayView.LAYER_NAMES[m.phero_index + 1]
	elif m.tool == 3:
		sub = " · %s (Q/E)" % WorldGrid.ROOM_NAMES[m.ROOM_TYPES[m.room_index]]
	_tools.text = "%s%s\nCapa: %s\nZoom %sx   ·   Marcadas: %d" % [
		tool_names[m.tool], sub, OverlayView.LAYER_NAMES[m.overlay.layer], "%.2f" % m.camera.zoom.x, sim.world.marked_count]

	_phero_badge.visible = m.tool == 2
	if _phero_badge.visible:
		_phero_swatch.color = OverlayView.PHERO_COLORS[m.phero_index]
		var name: String = OverlayView.LAYER_NAMES[m.phero_index + 1]
		_phero_label.text = name[0].to_upper() + name.substr(1)
		_phero_badge.position = world_rect.position + Vector2((world_rect.size.x - _phero_badge.size.x) * 0.5, TOPBAR_H + 12.0)

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

	_update_top_bar(m, sim)

	_defeat.visible = sim.game_over
	_end_panel.visible = sim.game_over
	if sim.game_over:
		var won := sim.victory
		_defeat.text = ("¡VICTORIA!" if sim.tutorial_level else "¡LA COLONIA PROSPERÓ!") if won else "LA COLONIA CAYÓ"
		_defeat.add_theme_color_override("font_color", Color("7fe08a") if won else Color("ff6a6a"))
		_end_reason.text = sim.game_over_reason
		_end_reason.custom_minimum_size.x = clampf(world_rect.size.x - 160.0, 280.0, 520.0)
		_end_panel.reset_size()
		_end_panel.position = world_rect.position + (world_rect.size - _end_panel.size) * 0.5
