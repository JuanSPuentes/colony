class_name Hud
extends CanvasLayer
## HUD en español. Fase 1: dibuja directo a la resolución real de la ventana (ver nota en
## main.gd sobre el SubViewport del mundo), así que el texto se ve nítido en vez de
## borroso/bloqueado. `S` escala el layout, pensado originalmente para 480x270, a la ventana real
## (1440x810 por defecto). `_tools`/`_legend` se conservan con los mismos nombres que en la
## Fase 0 porque `tools/ui_test.gd` los lee directamente.
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
const HEADER_COLOR := PixelUI.HEADER
## Fase 28: ícono de cada mejora, en el orden de `Upgrades.Stat` (daño, vida, velocidad, trabajo).
const UPGRADE_ICONS: Array[String] = ["damage", "health", "speed", "work"]
## Fase 30: la barra de arriba cuenta las hormigas con el sprite de hormiga del juego, de costado.
const ANT_ICON := preload("res://view/sprites/ant/east.png")
const TOP_ICON_PX := 36
## Fase 30: nombre en plural de cada casta para la tabla de Colonia (clave: `CasteDefs.Caste`).
const CASTE_PLURALS := {CasteDefs.Caste.WORKER: "Obreras", CasteDefs.Caste.SOLDIER: "Soldados", CasteDefs.Caste.DRONE: "Zánganos"}
## Factor de escala del layout: ventana real / 480, reducido para que los paneles ocupen menos
## pantalla (antes 3.0 daba paneles casi a media ventana con la barra de abajo todavía puesta).
const S := 2.3
const FONT := 22.0  # Fase 28: tamaños enteros: la fuente pixel se rompe en tamaños intermedios
## El panel lateral usa letra más chica que el resto del HUD para caber en menos espacio.
const PANEL_FONT := 18
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
const TOPBAR_H := 52.0  # Fase 30: más alta, para que los íconos se lean (pedido del jugador)
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

var _tools: Label
var _legend: RichTextLabel
var _colony: RichTextLabel
var _resources: Label
var _threats: Label
## Fase 30: tarjeta de amenazas, solo en el modo con reina (en Juego normal no se muestra).
var _threats_card: PanelContainer
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
## Fase 9 (antes sin interfaz): mejoras de colonia, solo modo incremental.
var _upgrade_section: Control
var _upgrade_btns: Array[Button] = []
## Fase 14: estadísticas reales por casta (vida/velocidad/daño) + cavar, a pedido del jugador —
## antes solo se podía ver el % de vida de una hormiga al pasar el mouse por encima (ver
## `_process`), no los números base ni cómo los mueven las mejoras compradas.
var _stats_label: RichTextLabel
## Fase 14: piezas del panel en columna (ver `_ready`).
const SIDE_PAD := 3.0 * S
var _scroll: ScrollContainer
var _log_card: PanelContainer
## Fase 14: barra de arriba del mapa: símbolos y números de lo más importante, de un vistazo.
var _topbar: PanelContainer
var _topbar_row: HBoxContainer


func _ready() -> void:
	var root := Control.new()
	root.theme = PixelUI.theme(int(FONT))  # Fase 28: fuente pixel en todo el HUD
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_sidebar = Panel.new()
	_sidebar.add_theme_stylebox_override("panel", _panel_style())
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

	# Fase 30 (pedido del jugador): sin tarjetas de día, clima ni estación — eso ya está en la barra
	# de arriba — y la cría en camino va dentro de Colonia, no en una tarjeta aparte.
	var colony := _section(col, "COLONIA")
	_colony = _rich(colony)
	_resources = _line(colony)

	# Amenazas: solo en el modo con reina (Modo infinito, Test); en Juego normal se oculta.
	_threats_card = _section_card(col, "AMENAZAS")
	_threats = _line(_threats_card.get_child(0) as VBoxContainer)

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
	# Fase 28: el botón de huevo lleva el mismo sprite de huevos que se ve en el nido.
	_buy_btns[0].icon = BroodView.EGG_TEXTURE
	_buy_btns[0].add_theme_constant_override("icon_max_width", 26)
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
		ub.icon = HudIcons.get_icon(UPGRADE_ICONS[stat], 2)  # Fase 28
		grid.add_child(ub)
		_upgrade_btns.append(ub)
		ub.pressed.connect(func() -> void: _m.sim.cmd_buy_upgrade(stat))
	var stats := _section(up_box, "ESTADÍSTICAS")
	_stats_label = _rich(stats)

	_log_card = _section_card(col, "AVISOS")
	_log = _rich(_log_card.get_child(0) as VBoxContainer)

	_build_top_bar(root)
	_build_gear_button(root)
	_build_phero_badge(root)

	# Fase 14: el final de partida era un `Label` suelto de tamaño fijo con todo el texto en letra
	# gigante: un motivo largo (el del Nivel 0) se salía de la pantalla por los costados. Ahora es
	# una tarjeta: título grande, el motivo en letra normal con salto de línea y cómo seguir.
	_end_panel = PanelContainer.new()
	var end_style := _panel_style()
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
	var st := _panel_style()
	st.content_margin_top = 0.0
	st.content_margin_bottom = 0.0
	_topbar.add_theme_stylebox_override("panel", st)
	_topbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_topbar)
	_topbar_row = HBoxContainer.new()
	_topbar_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_topbar_row.add_theme_constant_override("separation", 30)
	_topbar.add_child(_topbar_row)


## Cada dato: [ícono, texto, tooltip]. Fase 28: el ícono es un nombre de `HudIcons` (antes un
## emoji). Rehace las piezas solo si cambió cuántas hay.
func _set_top_items(items: Array) -> void:
	while _topbar_row.get_child_count() < items.size():
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 6)
		item.mouse_filter = Control.MOUSE_FILTER_PASS
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(TOP_ICON_PX, TOP_ICON_PX)
		icon.mouse_filter = Control.MOUSE_FILTER_PASS
		item.add_child(icon)
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 30)
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		item.add_child(l)
		_topbar_row.add_child(item)
	for i in _topbar_row.get_child_count():
		var item := _topbar_row.get_child(i) as HBoxContainer
		item.visible = i < items.size()
		if item.visible:
			(item.get_child(0) as TextureRect).texture = ANT_ICON if items[i][0] == "ant" else HudIcons.get_icon(items[i][0], 3)
			(item.get_child(1) as Label).text = items[i][1]
			item.tooltip_text = items[i][2]  # ya viene con tr()


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
	items.append(["ant", str(mine), tr("Hormigas de tu colonia")])
	items.append(["leaf", "%.0f" % sim.colony.food, tr("Comida")])
	if sim.queen_id >= 0:
		var q_max := sim.ants.max_hp(sim.queen_id)
		var q_hp := sim.ants.hp[sim.queen_id] if sim.ants.alive[sim.queen_id] == 1 else 0.0
		items.append(["crown", "%d%%" % int(100.0 * q_hp / maxf(q_max, 0.01)), tr("Vida de la reina")])
	if sim.incremental or sim.test_mode:
		var night := sim.is_night()
		items.append(["moon" if night else "sun", _fmt_time(DayNight.seconds_to_change(sim.time_s(), cfg)),
			tr("Falta para que amanezca") if night else tr("Falta para que anochezca")])
		items.append(["calendar", tr("Día %d") % sim.day_number(), tr("Día actual")])
	else:
		items.append(["water", "%.0f" % sim.colony.water, tr("Agua")])
		items.append(["era", tr(ERA_NAMES[sim.era]), tr("Era de la colonia")])
	if sim.incremental and not sim.tutorial_level and sim.season_index < SeasonSystem.SEASON_COUNT:
		var icons := ["spring", "sun", "autumn", "winter"]
		items.append([icons[sim.season_index], "%s %d/%d" % [tr(SeasonSystem.SEASON_NAMES[sim.season_index]), sim.season_index + 1, SeasonSystem.SEASON_COUNT], tr("Estación")])
	var rival := sim.rival_colony
	if sim.incremental and rival.battle_active:
		items.append(["swords", tr("¡Batalla! %d%%") % int(100.0 * rival.queen.hp / maxf(rival.queen.max_hp, 0.01)), tr("Vida de la reina rival")])
	elif sim.incremental and not sim.tutorial_level and sim.season_index < SeasonSystem.SEASON_COUNT:
		# La batalla empieza al llegar al último día de la estación (`SeasonSystem.update`).
		var left := SeasonSystem.season_length(sim) - 1 - SeasonSystem.day_in_season(sim)
		items.append(["swords", tr("Hoy") if left <= 0 else (tr("en %d %s") % [left, tr("día") if left == 1 else tr("días")]), tr("Próxima batalla de fin de estación")])
	if sim.weather != Simulation.Weather.CLEAR:
		items.append(["snow" if SeasonStyle.snows(sim) else "rain", tr("¡%ds!") % ceili(sim.rain_eta_s()) if sim.weather == Simulation.Weather.WARNING else _rain_word(sim), tr("Lluvia")])
	if m.paused:
		items.append(["pause", tr("Pausa"), tr("Espacio para seguir")])
	elif m.speed > 1:
		items.append(["fast", "x%d" % m.speed, tr("Velocidad")])
	_set_top_items(items)
	var r := _world_rect(m)
	var gear_w := TOPBAR_H + 8.0  # la tuerca (Fase 28) es un cuadrado del alto de la barra
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
	b.icon = HudIcons.get_icon("gear", 2)  # Fase 28: ícono pixel en vez del carácter ⚙
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	b.position = Vector2(-TOPBAR_H - 8.0, 6.0)
	b.custom_minimum_size = Vector2(TOPBAR_H, TOPBAR_H)
	b.size = b.custom_minimum_size
	PixelUI.style_button(b)
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
	var style := _panel_style()
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
	# Fase 26: para revisar el ambiente de cada estación sin jugar una estación entera. `start` con
	# la misma simulación vuelve a preparar las vistas (el pasto y la nieve de los árboles se pintan ahí).
	_test_btn(box, "Siguiente estación", func() -> void:
		_m.sim.cmd_next_season()
		_m.start(_m.seed_value, _m.sim))
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
	PixelUI.style_button(b)  # Fase 28: tablita de madera
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


## Mismo marco en todos los recuadros que flotan (panel lateral, tuerca, insignia de feromona,
## pausa, Test, fin de partida), para que se lean como una sola familia. Fase 28: marco pixel de
## madera con fondo de tierra (`PixelUI.frame`); se copia porque cada uno ajusta sus márgenes.
func _panel_style() -> StyleBox:
	return PixelUI.frame().duplicate()


## Fase 14: piezas del panel lateral en columna (ver `_ready`). Cada sección es una tarjeta con
## fondo un poco más claro que el panel, encabezado en `HEADER_COLOR` y su contenido debajo.
func _card_style() -> StyleBox:
	return PixelUI.card(3)  # Fase 28: tarjeta de tierra con borde de madera


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
	h.add_theme_font_override("font", PixelUI.title_font())
	h.add_theme_font_size_override("font_size", 14)
	h.add_theme_color_override("font_color", HEADER_COLOR)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(h)
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


## Rectángulo real del mundo en la ventana (posición y tamaño del `SubViewportContainer` de
## `main.gd`), para que los overlays que flotan sobre el mapa (insignia de feromona, pausa, panel
## de Test, derrota) se centren en el mapa visible y no en el hueco que deja el panel lateral.
func _world_rect(m: Node) -> Rect2:
	if m.world_container == null:
		return Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	return Rect2(m.world_container.position, m.world_container.size)


## Modo incremental (Fase 3). Fase 30: el panel solo muestra lo que no está en la barra de arriba —
## la colonia (cuántas de cada casta y cuántas vienen en camino), la comida con su ritmo, y si hay
## araña — más compras, mejoras y estadísticas. Día, clima y estación están en la barra.
func _update_incremental(sim: Simulation) -> void:
	var cfg := sim.cfg
	# Cría en camino por casta: la casta de cada huevo ya se sorteó al comprarlo
	# (`IncrementalEconomy.buy_egg`), así que no es una previsión, es lo que va a nacer.
	var coming := {CasteDefs.Caste.WORKER: 0, CasteDefs.Caste.SOLDIER: 0, CasteDefs.Caste.DRONE: 0}
	for i in sim.brood.stage.size():
		if sim.brood.alive[i] and coming.has(sim.brood.caste[i]):
			coming[sim.brood.caste[i]] += 1
	var c := sim.ants.count_by_caste([CasteDefs.Caste.WORKER, CasteDefs.Caste.SOLDIER, CasteDefs.Caste.DRONE])
	var rows := ""
	for caste in [CasteDefs.Caste.WORKER, CasteDefs.Caste.SOLDIER, CasteDefs.Caste.DRONE]:
		var more := "[color=#a8d672]+%d[/color]" % coming[caste] if coming[caste] > 0 else ""
		rows += "[cell][color=#%s]%s[/color]  [/cell][cell]%d  [/cell][cell]%s[/cell]" % [
			CasteDefs.COLORS[caste].to_html(false), tr(CASTE_PLURALS[caste]), c[caste], more]
	var queen_hp := sim.ants.hp[sim.queen_id] if sim.ants.alive[sim.queen_id] == 1 else 0.0
	rows += "[cell][color=#%s]%s[/color]  [/cell][cell]%d%%[/cell][cell][/cell]" % [
		CasteDefs.COLORS[CasteDefs.Caste.QUEEN].to_html(false), tr("Reina"),
		int(100.0 * queen_hp / maxf(sim.ants.max_hp(sim.queen_id), 0.01))]
	_colony.text = "[table=3]%s[/table]" % rows
	var food := tr("Comida: %.0f / %.0f") % [sim.colony.food, sim.colony.food_cap]
	food += "\n" + tr("+%.0f/min · −%.0f/min") % [sim.econ.income_per_min, sim.econ.upkeep_per_min]
	if sim.colony.starving:
		food += tr("\n¡HAMBRE!")
	if sim.spider.alive:
		var state_names := {Spider.State.SEARCH: tr("buscando presas"), Spider.State.ATTACK: tr("atacando"),
			Spider.State.SIEGE: tr("en la entrada"), Spider.State.RETREAT: tr("huyendo")}
		food += "\n" + tr("¡Araña %s! (%d%%)") % [
			state_names.get(sim.spider.state, tr("cerca")), int(100.0 * sim.spider.hp / maxf(sim.spider.max_hp, 0.01))]
	_resources.text = food
	var econ := sim.econ
	_buy_btns[0].text = tr("[7] Huevo: %.0f") % econ.egg_cost()
	_buy_btns[0].disabled = not econ.can_buy_egg()
	_buy_btns[1].text = tr("[9] Auto: %s") % tr(IncrementalEconomy.AUTO_NAMES[econ.auto_mode])

	# Fase 9 (antes sin interfaz): mejoras de colonia.
	var up := sim.upgrades
	for stat in Upgrades.STAT_COUNT:
		var b := _upgrade_btns[stat]
		# Fase 28: sin "comida" (el precio siempre es comida): con el ícono no entraba en el botón.
		b.text = tr("%s\nNv.%d · %.0f") % [tr(Upgrades.STAT_NAMES[stat]), up.levels[stat], up.cost(stat)]
		b.disabled = not up.can_buy(stat)

	# Fase 14: estadísticas reales por casta, con las mejoras ya aplicadas — vida/velocidad/daño
	# salen de CasteDefs * cfg, multiplicados por el stat de Upgrades correspondiente (mismo
	# cálculo que usa AntSystem al nacer/moverse/atacar, ver sim/colony/upgrades.gd). "Cavar" es
	# por colonia, no por casta: cfg.dig_seconds / work_mult es lo que tarda cualquier hormiga
	# cavando una celda marcada, sin importar quién sea.
	# Tabla: la casta a la izquierda y una columna por número, para leerlos de un vistazo.
	var dim := "[color=#9a94a0]%s[/color]"
	var stats_text := "[table=4][cell][/cell][cell]%s  [/cell][cell]%s  [/cell][cell]%s[/cell]" % [dim % tr("Vida"), dim % tr("Vel."), dim % tr("Daño/s")]
	for stat_caste in [CasteDefs.Caste.QUEEN, CasteDefs.Caste.WORKER, CasteDefs.Caste.SOLDIER, CasteDefs.Caste.DRONE]:
		var base_hp: float = cfg.queen_hp_base if stat_caste == CasteDefs.Caste.QUEEN else cfg.ant_hp
		var hp_val := base_hp * CasteDefs.HP_MULT[stat_caste] * up.hp_mult
		var speed_val := cfg.ant_speed * CasteDefs.SPEED_MULT[stat_caste] * up.speed_mult
		var dmg_val := CasteDefs.DAMAGE_PER_S[stat_caste] * up.damage_mult
		stats_text += "[cell][color=#%s]%s[/color]  [/cell][cell]%.0f[/cell][cell]%.1f[/cell][cell]%.1f[/cell]" % [
			CasteDefs.COLORS[stat_caste].to_html(false), tr(CasteDefs.NAMES[stat_caste]), hp_val, speed_val, dmg_val]
	stats_text += "[/table]\n" + dim % (tr("Cavar una celda: %.1f s") % (cfg.dig_seconds / up.work_mult))
	_stats_label.text = stats_text


## Fase 5: tooltip al pasar el mouse. Se recalcula cada frame (barato: una hormiga cercana y una
## celda), no cada tick de simulación, así que vive en `_process`, no en `update_info`.
func _process(_delta: float) -> void:
	if _m == null or _m.sim == null or _defeat.visible:
		_tooltip.visible = false
		return
	var screen_pos := get_viewport().get_mouse_position()
	# Fuera del mapa (sobre el panel lateral) no hay nada que señalar: antes igual se recorrían todas
	# las hormigas cada cuadro, y podía salir el tooltip de una hormiga escondida debajo del panel.
	if not _world_rect(_m).has_point(screen_pos):
		_tooltip.visible = false
		return
	var world_pos: Vector2 = _m._to_world(screen_pos)
	var cell: Vector2i = _m._world_cell(world_pos)
	var sim: Simulation = _m.sim
	var text := ""
	if sim.queen_id >= 0:
		var nearest := -1
		var nearest_d := 6.0 * 6.0  # px²: el radio de "estás señalando esta hormiga" (6 px).
		for i in sim.ants.count:
			if sim.ants.alive[i] == 0:
				continue
			var d: float = sim.ants.pos[i].distance_squared_to(world_pos)
			if d < nearest_d:
				nearest_d = d
				nearest = i
		if nearest >= 0:
			var nc: int = sim.ants.caste[nearest]
			text = tr("%s   %d%% vida") % [tr(CasteDefs.NAMES[nc]),
				int(100.0 * sim.ants.hp[nearest] / maxf(sim.ants.max_hp(nearest), 0.01))]
	if text == "" and sim.world.in_bounds(cell.x, cell.y):
		var room_type: int = sim.world.room[cell.y * sim.world.w + cell.x]
		if room_type != WorldGrid.Room.NONE:
			var valid: bool = sim.rooms.valid[room_type]
			text = "%s — %s" % [tr(WorldGrid.ROOM_NAMES[room_type]), tr("válida") if valid else tr("inválida (falta espacio)")]
	_tooltip.text = text
	_tooltip.visible = text != ""
	if text != "":
		_tooltip.position = screen_pos + Vector2(14, 14)


## Modo con reina ("Modo infinito", Test y partidas clásicas): castas, cría, comida y agua, reparto.
## Fase 30: sin tarjetas de día ni clima (están en la barra de arriba).
func _update_classic(sim: Simulation) -> void:
	# --- Amenazas: quién anda rondando la colonia. Fase 5: ya puede haber dos a la vez (araña y
	# ciempiés), se listan juntas en la misma línea en vez de sumar una línea por amenaza (mismo
	# espíritu que la nota de arriba sobre no concatenar secciones nuevas sin pensar el layout).
	if sim.queen_id >= 0:
		var threat_parts: Array[String] = []
		if sim.spider.alive:
			var spider_states := {Spider.State.SEARCH: tr("buscando presas"), Spider.State.ATTACK: tr("atacando"),
				Spider.State.SIEGE: tr("en la entrada"), Spider.State.RETREAT: tr("huyendo")}
			threat_parts.append(tr("Araña %s (%d%%)") % [spider_states.get(sim.spider.state, tr("cerca")),
				int(100.0 * sim.spider.hp / maxf(sim.spider.max_hp, 0.01))])
		if sim.centipede.alive:
			var cent_states := {Centipede.State.SEARCH: tr("buscando presas"), Centipede.State.CHASE: tr("persiguiendo"),
				Centipede.State.ATTACK: tr("atacando"), Centipede.State.RETREAT: tr("huyendo")}
			threat_parts.append(tr("Ciempiés %s (%d%%)") % [cent_states.get(sim.centipede.state, tr("cerca")),
				int(100.0 * sim.centipede.hp / maxf(sim.centipede.max_hp, 0.01))])
		if sim.mantis.alive:
			var mantis_states := {Mantis.State.HIDDEN: tr("camuflada"), Mantis.State.ATTACK: tr("atacando"),
				Mantis.State.RETREAT: tr("huyendo")}
			threat_parts.append(tr("Mantis %s (%d%%)") % [mantis_states.get(sim.mantis.state, tr("cerca")),
				int(100.0 * sim.mantis.hp / maxf(sim.mantis.max_hp, 0.01))])
		_threats.text = " · ".join(threat_parts) if not threat_parts.is_empty() else tr("Ninguna a la vista")

	if sim.queen_id >= 0:
		var c := sim.ants.count_by_caste([CasteDefs.Caste.WORKER, CasteDefs.Caste.NURSE, CasteDefs.Caste.SOLDIER, CasteDefs.Caste.DRONE])
		var queen_alive := sim.ants.alive[sim.queen_id] == 1
		var queen_hp := sim.ants.hp[sim.queen_id] if queen_alive else 0.0
		var queen_hp_max := sim.ants.max_hp(sim.queen_id)
		# El bullet de cada casta usa el mismo color con el que se ve en el mundo.
		_colony.text = "[color=#%s]•[/color]%d [color=#%s]•[/color]%d [color=#%s]•[/color]%d [color=#%s]•[/color]%d [color=#%s]•[/color]%d%%   %s" % [
			CasteDefs.COLORS[CasteDefs.Caste.WORKER].to_html(false), c[CasteDefs.Caste.WORKER],
			CasteDefs.COLORS[CasteDefs.Caste.NURSE].to_html(false), c[CasteDefs.Caste.NURSE],
			CasteDefs.COLORS[CasteDefs.Caste.SOLDIER].to_html(false), c[CasteDefs.Caste.SOLDIER],
			CasteDefs.COLORS[CasteDefs.Caste.DRONE].to_html(false), c[CasteDefs.Caste.DRONE],
			CasteDefs.COLORS[CasteDefs.Caste.QUEEN].to_html(false), int(100.0 * queen_hp / maxf(queen_hp_max, 0.01)),
			tr(ERA_NAMES[sim.era])]
		_resources.text = tr("Cría %d/%d/%d   Comida %.0f%s  Agua %.0f%s") % [
			sim.brood.counts_by_stage[BroodSystem.Stage.EGG], sim.brood.counts_by_stage[BroodSystem.Stage.LARVA], sim.brood.counts_by_stage[BroodSystem.Stage.PUPA],
			sim.colony.food, _trend_arrow(sim.colony.food_trend), sim.colony.water, _trend_arrow(sim.colony.water_trend)]
		var t := sim.colony.target_pct
		_ratio.text = tr("Reparto → Obreras %d%%  Nodrizas %d%%  Soldados %d%%  Zánganos %d%%") % [
			int(t[CasteDefs.Caste.WORKER] * 100), int(t[CasteDefs.Caste.NURSE] * 100), int(t[CasteDefs.Caste.SOLDIER] * 100), int(t[CasteDefs.Caste.DRONE] * 100)]
		var castes := [CasteDefs.Caste.WORKER, CasteDefs.Caste.NURSE, CasteDefs.Caste.SOLDIER, CasteDefs.Caste.DRONE]
		for i in castes.size():
			_caste_sliders[i].set_value_no_signal(t[castes[i]])
	else:
		_colony.text = ""
		_resources.text = ""
		_ratio.text = ""


## Avisos de la partida (los mismos en todos los modos con reina); la tarjeta solo se ve si hay.
func _update_log(sim: Simulation) -> void:
	var lines := ""
	if sim.queen_id >= 0:
		for n in sim.notifications:
			lines += "[color=#ffd43c]• %s[/color]\n" % note_text(n)
	_log.text = lines
	_log_card.visible = lines != ""


## `m` es el nodo main.gd: lee todo lo que necesita de él y de `m.sim`.
func update_info(m: Node) -> void:
	var sim: Simulation = m.sim
	_layout()  # barato; sigue el alto real de la ventana si cambia de tamaño
	_m = m
	# El mismo panel cuenta cosas distintas según el modo. Antes se armaban siempre los textos del
	# modo con reina y, en Juego normal, `_update_incremental` los pisaba en el mismo cuadro.
	if sim.incremental:
		_update_incremental(sim)
	else:
		_update_classic(sim)
	_update_log(sim)

	# Fase 3: qué secciones existen depende del modo.
	_buy_row.visible = sim.incremental
	_ratio.visible = not sim.incremental
	_caste_row.visible = not sim.incremental
	# Fase 9: Mejoras solo existen de verdad en el modo incremental (`Upgrades` atado a
	# `sim.incremental`, ver sim/colony/upgrades.gd). Fase 30: amenazas, solo en el modo con reina.
	_upgrade_section.visible = sim.incremental
	_threats_card.visible = not sim.incremental

	var world_rect := _world_rect(m)
	_pause_panel.visible = m.paused and not sim.game_over
	if _pause_panel.visible:
		_pause_panel.position = world_rect.position + (world_rect.size - _pause_panel.size) * 0.5
	_test_panel.visible = sim.test_mode
	if _test_panel.visible:
		_test_panel.position = world_rect.position + Vector2(world_rect.size.x - _test_panel.size.x - 10.0 * S, 10.0 * S)

	var tool_names := ["", tr("Cavar [1]"), tr("Feromona [2]"), tr("Cámara [3]"), tr("Borrar [4]"), tr("Mover reina [5]")]
	var sub := ""
	if m.tool == 2:
		sub = " · %s (Q/E)" % tr(OverlayView.LAYER_NAMES[m.phero_index + 1])
	elif m.tool == 3:
		sub = " · %s (Q/E)" % tr(WorldGrid.ROOM_NAMES[m.ROOM_TYPES[m.room_index]])
	_tools.text = tr("%s%s\nCapa: %s\nZoom %sx   ·   Marcadas: %d") % [
		tool_names[m.tool], sub, tr(OverlayView.LAYER_NAMES[m.overlay.layer]), "%.2f" % m.camera.zoom.x, sim.world.marked_count]

	_phero_badge.visible = m.tool == 2
	if _phero_badge.visible:
		_phero_swatch.color = OverlayView.PHERO_COLORS[m.phero_index]
		var name: String = tr(OverlayView.LAYER_NAMES[m.phero_index + 1])
		_phero_label.text = name[0].to_upper() + name.substr(1)
		_phero_badge.position = world_rect.position + Vector2((world_rect.size.x - _phero_badge.size.x) * 0.5, TOPBAR_H + 12.0)

	if m.overlay.layer == OverlayView.Layer.STATES:
		var parts := ""
		for k in AntSystem.State.size():
			var col: Color = AntSystem.STATE_COLORS[k]
			parts += "[color=#%s]• %s[/color]  " % [col.to_html(false), tr(AntSystem.STATE_NAMES[k])]
		_legend.text = parts
	elif m.overlay.layer == OverlayView.Layer.CASTES:
		var parts2 := ""
		for k in CasteDefs.NAMES.size():
			var col2: Color = CasteDefs.COLORS[k]
			parts2 += "[color=#%s]• %s[/color]  " % [col2.to_html(false), tr(CasteDefs.NAMES[k])]
		_legend.text = parts2
	else:
		_legend.text = ""

	_update_top_bar(m, sim)

	_defeat.visible = sim.game_over
	_end_panel.visible = sim.game_over
	if sim.game_over:
		var won := sim.victory
		_defeat.text = (tr("¡VICTORIA!") if sim.tutorial_level else tr("¡LA COLONIA PROSPERÓ!")) if won else tr("LA COLONIA CAYÓ")
		_defeat.add_theme_color_override("font_color", Color("7fe08a") if won else Color("ff6a6a"))
		_end_reason.text = sim.game_over_reason
		_end_reason.custom_minimum_size.x = clampf(world_rect.size.x - 160.0, 280.0, 520.0)
		_end_panel.reset_size()
		_end_panel.position = world_rect.position + (world_rect.size - _end_panel.size) * 0.5


## Fase 26: en invierno la lluvia se ve como nieve, así que el HUD dice "Nevando".
func _rain_word(sim: Simulation) -> String:
	return tr("Nevando") if SeasonStyle.snows(sim) else tr("Lloviendo")


## Fase 27: un aviso de `Simulation.notify` en el idioma actual. Viene como "clave␟dato␟dato": se
## traduce la clave y cada dato de texto (un número queda igual).
func note_text(note: String) -> String:
	var parts := note.split(Simulation.NOTE_SEP)
	var msg := tr(parts[0])
	if parts.size() == 1:
		return msg
	var args := []
	for k in range(1, parts.size()):
		args.append(tr(parts[k]))
	return msg % args
