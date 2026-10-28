class_name CoachView
extends CanvasLayer
## Fase 14: guía contextual. En vez de una sola pantalla de instrucciones al empezar, cada cosa se
## explica la primera vez que se vuelve relevante: la cámara se acerca a lo que se explica y
## aparece una tarjeta chica al costado derecho del mapa. La partida NO se pausa (pedido del
## jugador): se lee mientras se hace. Si la lección pide algo, la tarjeta muestra el objetivo y
## pasa sola a la siguiente cuando se cumple; si solo informa, tiene un botón "Siguiente" (o Enter).
##
## Dos listas:
## - Nivel 0 (`sim.tutorial_level`): lecciones en orden fijo, de lo más importante a lo menos. La
##   penúltima pide la batalla final (`sim.cmd_start_tutorial_battle`).
## - Juego normal (`sim.incremental`): cada consejo salta solo, en cualquier orden, la primera vez
##   que pasa lo que explica (primera noche, primera araña, primera vez que alcanza para un huevo...).
## Modo infinito y Test no la usan. Solo se activa si `main.coach_enabled` (lo pone `app.gd`): así
## `main.tscn` abierto directo, como lo usan las pruebas viejas, se comporta como siempre.

const GOLD := Color("ffd43c")
const CREAM := Color("f4ecd8")
const GREEN := Color("7fe08a")
## Ancho de la tarjeta, en píxeles reales de ventana. Chica a propósito: solo lo mínimo.
const CARD_W := 270.0
const MARGIN := 12.0

## Índices de `main.ZOOM_LEVELS` ([0.5, 1, 2, 3, 4]).
const Z_WIDE := 1
const Z_NEAR := 2
const Z_CLOSE := 3

var lessons: Array[Dictionary] = []
## Índice de la próxima lección del Nivel 0 (en Juego normal no se usa: van por `_seen`).
var step := 0
var _seen := {}
var _current: Dictionary = {}
var _mode := ""
## Lo marca `main.gd` cuando el jugador mueve la cámara (arrastre o teclado): la lección de cámara
## del Nivel 0 no tiene un contador en `sim` porque la cámara es pura presentación.
var camera_moved := false
## Tick en que arrancó la partida: algunos consejos de Juego normal esperan unos segundos de juego
## (`_played_s`) para no encadenarse con la bienvenida.
var _start_tick := 0
## Juego normal: segundos de juego mínimos entre un consejo y el siguiente, para que no se encadenen.
const NORMAL_GAP_S := 8.0
var _last_close_tick := -1000000
var _main_ref = null

var _card: PanelContainer
var _title: Label
var _body: Label
var _count: Label
var _goal_label: Label
var _ok: Button


func _ready() -> void:
	layer = 5
	_card = PanelContainer.new()
	# Fase 28: mismo marco de madera y fuente pixel que el HUD.
	_card.theme = PixelUI.theme(18)
	_card.add_theme_stylebox_override("panel", PixelUI.frame(5))
	_card.custom_minimum_size = Vector2(CARD_W, 0)
	add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	_card.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_title = Label.new()
	_title.add_theme_font_override("font", PixelUI.title_font())
	_title.add_theme_font_size_override("font_size", 18)
	_title.add_theme_color_override("font_color", GOLD)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(_title)
	_count = Label.new()
	_count.add_theme_font_size_override("font_size", 16)
	_count.add_theme_color_override("font_color", Color(CREAM, 0.55))
	head.add_child(_count)
	_body = Label.new()
	_body.add_theme_font_size_override("font_size", 19)
	_body.add_theme_color_override("font_color", CREAM)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(CARD_W - 24.0, 0)
	box.add_child(_body)
	_goal_label = Label.new()
	_goal_label.add_theme_font_size_override("font_size", 19)
	_goal_label.add_theme_color_override("font_color", GOLD)
	_goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_goal_label.custom_minimum_size = Vector2(CARD_W - 24.0, 0)
	box.add_child(_goal_label)
	_ok = Button.new()
	_ok.text = "Siguiente  ⏎"
	_ok.focus_mode = Control.FOCUS_NONE
	_ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	_ok.add_theme_font_size_override("font_size", 18)
	PixelUI.style_button(_ok)
	_ok.pressed.connect(close_card)
	box.add_child(_ok)
	_card.visible = false


func is_showing() -> bool:
	return _card.visible


## Llamado por `main.start()` en cada partida nueva (también al reiniciar con F5).
func reset(sim: Simulation) -> void:
	step = 0
	camera_moved = false
	_start_tick = sim.tick_count
	_last_close_tick = -1000000
	_seen.clear()
	_current = {}
	_card.visible = false
	if sim.tutorial_level:
		_mode = "level0"
		lessons = _level0_lessons()
	elif sim.incremental and not sim.test_mode:
		_mode = "normal"
		lessons = _normal_lessons()
	else:
		_mode = ""
		lessons = []


## Una vez por frame desde `main.gd._process`.
func update(main) -> void:
	_main_ref = main
	var sim: Simulation = main.sim
	if _mode == "" or sim == null:
		return
	_place(main)
	if sim.game_over:
		_card.visible = false
		return
	if _card.visible:
		# Una lección con objetivo se cierra sola en cuanto se cumple.
		if _current.has("done") and (_current["done"] as Callable).call(sim):
			close_card()
		return
	if _mode == "level0":
		if step < lessons.size() and (lessons[step]["when"] as Callable).call(sim):
			_open(main, lessons[step])
			step += 1
	else:
		if (sim.tick_count - _last_close_tick) * sim.dt < NORMAL_GAP_S:
			return
		for l in lessons:
			if not _seen.has(l["id"]) and (l["when"] as Callable).call(sim):
				_seen[l["id"]] = true
				_open(main, l)
				break


## Pegada al borde derecho del mapa, justo debajo de la barra de arriba del HUD.
func _place(main) -> void:
	var r := Rect2(main.world_container.position, main.world_container.size)
	_card.size = Vector2(CARD_W, 0)  # que la altura salga del contenido
	_card.position = Vector2(r.end.x - CARD_W - MARGIN, r.position.y + Hud.TOPBAR_H + MARGIN)


func _open(main, lesson: Dictionary) -> void:
	_current = lesson
	_title.text = lesson["title"]
	_body.text = lesson["text"]
	_count.text = "%d/%d" % [step + 1, lessons.size()] if _mode == "level0" else ""
	var has_goal: bool = lesson.has("goal")
	_goal_label.visible = has_goal
	_goal_label.text = "▶ " + tr(String(lesson.get("goal", "")))  # armado: no se traduce solo (Fase 27)
	_ok.visible = not has_goal
	_ok.text = String(lesson.get("button", "Siguiente  ⏎" if _mode == "level0" else "Entendido  ⏎"))
	_card.visible = true
	var focus: Callable = lesson.get("focus", Callable())
	if focus.is_valid():
		var p: Vector2 = focus.call(main.sim)
		if is_finite(p.x):
			main.focus_on(p, int(lesson.get("zoom", Z_WIDE)))


func close_card() -> void:
	if not _card.visible:
		return
	_card.visible = false
	var main = _main_ref
	if main == null:
		return
	_last_close_tick = main.sim.tick_count
	var on_close: Callable = _current.get("on_close", Callable())
	if on_close.is_valid():
		on_close.call(main.sim)
	_current = {}


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and _card.visible and _ok.visible and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER):
		close_card()
		get_viewport().set_input_as_handled()


# --- Dónde mirar --------------------------------------------------------------------------------

static func _px(sim: Simulation, c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * sim.cfg.cell_px


static func _nest(sim: Simulation) -> Vector2:
	return _px(sim, Vector2i(sim.cfg.nest_x, sim.cfg.surface_y + 2))


static func _queen(sim: Simulation) -> Vector2:
	if sim.queen_id >= 0 and sim.ants.alive[sim.queen_id] == 1:
		return sim.ants.pos[sim.queen_id]
	return _nest(sim)


static func _first_of(sim: Simulation, caste: int) -> Vector2:
	for i in sim.ants.count:
		if sim.ants.alive[i] == 1 and sim.ants.caste[i] == caste and sim.ants.faction[i] == 0:
			return sim.ants.pos[i]
	return _nest(sim)


static func _nearest_plant(sim: Simulation) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	for p in sim.plants:
		var d := absf(p.cell.x - sim.cfg.nest_x)
		if p.leaves > 0 and d < best_d:
			best_d = d
			best = _px(sim, p.cell)
	return best


func _played_s(sim: Simulation) -> float:
	return (sim.tick_count - _start_tick) * sim.dt


# --- Lecciones ----------------------------------------------------------------------------------
# Cada lección: id, title, text, when(sim) -> bool, y opcionales focus(sim) -> Vector2, zoom,
# goal (texto) + done(sim) -> bool, on_close(sim), button. Textos cortos: solo lo mínimo para
# entender la idea; el detalle sale jugando.

## Fase 15: antes cada feromona se mencionaba suelta en lecciones distintas, sin decir nunca quién
## sigue cuál — el jugador reportó que era confuso. Una sola tarjeta con las cinco, en el mismo
## orden en que se recorren con Q/E (`main.PHERO_FIELDS`).
const PHEROMONES_TEXT := "Tecla 2, luego Q/E para elegir:\nComida → obreras a la planta\nHogar → «ya explorado»: buscan más lejos\nPeligro → todas se alejan\nAtaque → los soldados van ahí\nEvacuar → huyen de la zona"


## Fase 15: ¿la colonia ya tiene salida a la superficie? El aire de arriba está conectado entre sí,
## así que basta mirar una celda de aire: si `nest_dist` la alcanza, hay algún túnel abierto.
static func _nest_open(sim: Simulation) -> bool:
	var i := (sim.cfg.surface_y - 1) * sim.world.w + sim.cfg.nest_x
	return sim.fields.nest_dist[i] < NestDistanceField.FAR


func _level0_lessons() -> Array[Dictionary]:
	var always := func(_s: Simulation) -> bool: return true
	return [
		{"id": "welcome", "title": "Nivel 0", "when": always, "focus": _nest, "zoom": Z_WIDE,
			"text": "No controlas a las hormigas: les das señales (feromonas) y diseñas el nido. Termina con una batalla."},
		{"id": "queen", "title": "La reina", "when": always, "focus": _queen, "zoom": Z_CLOSE,
			"text": "La más grande. Pone todos los huevos. Si muere, pierdes."},
		{"id": "food", "title": "Comida", "when": always, "focus": _nest, "zoom": Z_NEAR,
			"text": "Todo cuesta comida y todas comen. Si llega a 0, la reina y los soldados se debilitan."},
		{"id": "castes", "title": "Castas", "when": always, "focus": func(s: Simulation) -> Vector2: return _first_of(s, CasteDefs.Caste.WORKER), "zoom": Z_CLOSE,
			"text": "Obrera: cava y trae hojas.\nSoldado: patrulla y defiende.\nZángano: lleva huevos a la Guardería y defiende a la reina.\nAnte un enemigo pelean todas."},
		{"id": "camera", "title": "Cámara", "when": always,
			"text": "Clic izq. arrastra · WASD/flechas (Shift: rápido) · rueda: zoom · H: la reina.",
			"goal": "Mueve la cámara", "done": func(s: Simulation) -> bool: return camera_moved},
		{"id": "phero", "title": "Feromona de Comida", "when": always, "focus": _nearest_plant, "zoom": Z_WIDE,
			"text": "Las obreras siguen rastros. Empieza en el nido y termina en la planta.",
			"goal": "Pulsa 2 y arrastra con clic derecho", "done": func(s: Simulation) -> bool: return s.food_painted},
		{"id": "harvest", "title": "Cosecha", "when": func(s: Simulation) -> bool: return s.delivered > 0, "focus": _nest, "zoom": Z_NEAR,
			"text": "Cada hoja que llega al nido es comida. Las plantas rebrotan de día."},
		{"id": "pheromones", "title": "Las 5 feromonas", "when": always, "text": PHEROMONES_TEXT},
		{"id": "dig", "title": "Cavar", "when": always, "focus": _nest, "zoom": Z_NEAR,
			"text": "Marca desde un túnel hacia la tierra; las obreras cavan. La roca gris no se cava.",
			"goal": "Pulsa 1 y arrastra con clic derecho", "done": func(s: Simulation) -> bool: return s.dug > 0},
		{"id": "egg", "title": "Huevos", "when": func(s: Simulation) -> bool: return s.econ.can_buy_egg(), "focus": _queen, "zoom": Z_CLOSE,
			"text": "Huevo → larva → pupa → adulta. Sale obrera, soldado o zángano al azar. 9: auto-compra.",
			"goal": "Compra un huevo (tecla 7)", "done": func(s: Simulation) -> bool: return s.eggs_bought > 0},
		{"id": "daynight", "title": "Día y noche", "when": always,
			"text": "De noche no rebrotan las plantas. Arriba ves cuánto falta para que cambie."},
		{"id": "upgrades", "title": "Mejoras", "when": always,
			"text": "Con comida compras mejoras en el árbol (tecla U). Elige una rama: Ataque, Defensa o Recolección; cada mejora abre la siguiente."},
		{"id": "threats", "title": "Amenazas", "when": always,
			"text": "Araña, ciempiés, mantis y lluvia. Feromona de Peligro: alejar. De Ataque: llamar soldados."},
		{"id": "battle", "title": "Fin de estación", "when": always, "button": "¡A la batalla!  ⏎",
			"on_close": func(s: Simulation) -> void: s.cmd_start_tutorial_battle(),
			"text": "Cada estación termina con un ataque rival: gana quien mate a la reina. Te mandamos 3 soldados."},
		{"id": "rival", "title": "La reina rival", "when": func(s: Simulation) -> bool: return s.rival_colony.battle_active,
			"focus": func(s: Simulation) -> Vector2: return s.rival_colony.queen.pos, "zoom": Z_NEAR,
			"text": "Lleva a tu colonia hasta ella con la feromona de Ataque (2, luego Q/E).",
			"goal": "Derrota a la reina rival", "done": func(s: Simulation) -> bool: return s.game_over},
	]


func _normal_lessons() -> Array[Dictionary]:
	return [
		{"id": "welcome", "title": "Juego normal", "when": func(_s: Simulation) -> bool: return true, "focus": _nest, "zoom": Z_WIDE,
			"text": "Sobrevive a 4 estaciones. Tu nido ya tiene Real (reina), Guardería (huevos) y Almacén (comida). Clic izq. arrastra el mapa; clic derecho usa la herramienta."},
		# Fase 15: el nido arranca cerrado; abrirlo es lo primero y lo decide el jugador.
		{"id": "open", "title": "Abre el nido", "when": func(s: Simulation) -> bool: return not _nest_open(s), "focus": _nest, "zoom": Z_NEAR,
			"text": "El nido está cerrado. Marca un túnel desde la cámara hasta la superficie, por donde quieras salir.",
			"goal": "Pulsa 1 y arrastra con clic derecho hasta arriba", "done": func(s: Simulation) -> bool: return _nest_open(s)},
		# Fase 29: la comida de arriba cae del árbol madre y las obreras la recogen solas (antes pedía
		# pintar un rastro hasta una planta, que en este modo ya no hay).
		{"id": "drops", "title": "La comida cae del árbol", "when": func(s: Simulation) -> bool: return _nest_open(s) and _played_s(s) > 20.0, "focus": _nest, "zoom": Z_WIDE,
			"text": "Hojas, semillas y frutas caen bajo la copa. Las obreras las recogen solas: solo necesitan una salida al exterior."},
		# Fase 31: la rival vive en el mapa desde el principio (NUCLEO.md, pilar "la carrera").
		{"id": "rival_home", "title": "La colonia rival", "when": func(s: Simulation) -> bool: return s.rival_colony.home and _played_s(s) > 45.0,
			"focus": func(s: Simulation) -> Vector2: return s.rival_colony.queen.pos, "zoom": Z_NEAR,
			"text": "Del otro lado del árbol vive una colonia rival. Crece sola y te manda incursiones. Mata a su reina para ganar la estación: tecla 8 o «¡Atacar!»"},
		{"id": "harvest", "title": "Cosecha", "when": func(s: Simulation) -> bool: return s.delivered > 0, "focus": _nest, "zoom": Z_NEAR,
			"text": "Hojas, semillas y frutas son comida. Todas las hormigas comen: que no llegue a 0."},
		{"id": "pheromones", "title": "Las 5 feromonas", "when": func(s: Simulation) -> bool: return s.delivered > 0,
			"text": PHEROMONES_TEXT},
		{"id": "egg", "title": "Compra un huevo", "when": func(s: Simulation) -> bool: return s.econ.can_buy_egg() and s.eggs_bought == 0, "focus": _queen, "zoom": Z_CLOSE,
			"text": "Nace obrera, soldado o zángano al azar. 9: auto-compra.",
			"goal": "Tecla 7 o botón del panel", "done": func(s: Simulation) -> bool: return s.eggs_bought > 0},
		{"id": "dig", "title": "Amplía el nido", "when": func(s: Simulation) -> bool: return s.eggs_bought > 0 and s.dug == 0, "focus": _nest, "zoom": Z_NEAR,
			"text": "Desde un túnel hacia la tierra.",
			"goal": "Pulsa 1 y arrastra con clic derecho", "done": func(s: Simulation) -> bool: return s.dug > 0},
		{"id": "drone", "title": "Nació un zángano", "when": func(s: Simulation) -> bool: return s.ants.count_by_caste([CasteDefs.Caste.DRONE])[CasteDefs.Caste.DRONE] > 0,
			"focus": func(s: Simulation) -> Vector2: return _first_of(s, CasteDefs.Caste.DRONE), "zoom": Z_CLOSE,
			"text": "Escolta a la reina y la defiende si algo se acerca a ella o a los huevos. También lleva los huevos a la Guardería."},
		{"id": "night", "title": "Cae la noche", "when": func(s: Simulation) -> bool: return s.is_night(),
			"text": "De noche el árbol suelta la mitad de comida. Los hongos de abajo siguen creciendo: un túnel hasta una cueva ayuda."},
		{"id": "upgrade", "title": "Mejoras", "when": func(s: Simulation) -> bool: return s.upgrades_bought == 0 and s.upgrades.available_count() > 0,
			"text": "Ya te alcanza para una mejora: abre el árbol con la tecla U."},
		{"id": "rain", "title": "Lluvia", "when": func(s: Simulation) -> bool: return s.weather != Simulation.Weather.CLEAR,
			"text": "Inunda los túneles bajos y borra feromonas. El agua se evapora sola."},
		{"id": "spider", "title": "¡Una araña!", "when": func(s: Simulation) -> bool: return s.spider != null and s.spider.alive,
			"focus": func(s: Simulation) -> Vector2: return s.spider.pos, "zoom": Z_NEAR,
			"text": "Caza obreras sueltas. Feromona de Ataque (2, Q/E) manda a los soldados."},
		{"id": "rival", "title": "Fin de estación", "when": func(s: Simulation) -> bool: return s.rival_colony.battle_active,
			"focus": func(s: Simulation) -> Vector2: return s.rival_colony.queen.pos, "zoom": Z_NEAR,
			"text": "Mata a la reina rival para pasar de estación. Tus soldados se juntan en la salida del nido y salen juntos a buscarla."},
	]
