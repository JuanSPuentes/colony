class_name CoachView
extends CanvasLayer
## Fase 14: guía contextual. La cámara se acerca a lo que se explica y aparece una tarjeta chica al
## costado derecho del mapa. La partida NO se pausa (pedido del jugador): se lee mientras se hace.
## Si la lección pide algo, la tarjeta muestra el objetivo y pasa sola a la siguiente cuando se
## cumple; si solo informa, tiene un botón "Siguiente" (o Enter).
##
## Dos listas:
## - Tutorial (`sim.tutorial_level`, Fase 35): tarjetas en orden fijo sobre una colonia ya armada,
##   por capítulos (la colonia, las castas, el bioma, cómo se juega). Cada una con "Siguiente",
##   "Omitir" (salta el resto del capítulo) y "Omitir todo"; al terminar avisa a `main`
##   (`tutorial_finished`) y `app.gd` arranca la partida normal.
## - Juego normal (`sim.incremental`): consejos cortos, solo si el jugador los pidió ("Mostrar
##   consejos" en Opciones). Cada uno salta solo, en cualquier orden, la primera vez que pasa lo que
##   explica (primera noche, primera araña, primera vez que alcanza para un huevo...).
## Modo infinito y Test no la usan. Solo se activa si `main.coach_enabled` (lo pone `app.gd`): así
## `main.tscn` abierto directo, como lo usan las pruebas viejas, se comporta como siempre.

const GOLD := Color("ffd43c")
const CREAM := Color("f4ecd8")
const GREEN := Color("7fe08a")
## Ancho de la tarjeta, en píxeles reales de ventana. Chica a propósito: solo lo mínimo. Las del
## tutorial, más anchas: explican más y llevan tres botones.
const CARD_W := 270.0
const TUTORIAL_CARD_W := 380.0
const MARGIN := 12.0

## Índices de `main.ZOOM_LEVELS` ([0.5, 1, 2, 3, 4]).
const Z_WIDE := 1
const Z_NEAR := 2
const Z_CLOSE := 3

var lessons: Array[Dictionary] = []
## Índice de la próxima tarjeta del tutorial (en Juego normal no se usa: van por `_seen`).
var step := 0
var _seen := {}
var _current: Dictionary = {}
var _mode := ""
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
## Fase 35: "Omitir" (el resto del capítulo) y "Omitir todo" (termina el tutorial).
var _skip: Button
var _skip_all: Button


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
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 6)
	box.add_child(buttons)
	_skip_all = _card_button(buttons, "Omitir todo", skip_all)
	_skip = _card_button(buttons, "Omitir", skip_chapter)
	_ok = _card_button(buttons, "Siguiente  ⏎", close_card)
	_card.visible = false


func _card_button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 18)
	PixelUI.style_button(b)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func is_showing() -> bool:
	return _card.visible


## Llamado por `main.start()` en cada partida nueva (también al reiniciar con F5).
func reset(sim: Simulation) -> void:
	step = 0
	_start_tick = sim.tick_count
	_last_close_tick = -1000000
	_seen.clear()
	_current = {}
	_card.visible = false
	if sim.tutorial_level:
		_mode = "tutorial"
		lessons = _tutorial_lessons()
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
	if _mode == "tutorial":
		if step < lessons.size():
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
	# La del tutorial nunca más ancha que medio mapa (ventanas chicas).
	var w := minf(TUTORIAL_CARD_W, r.size.x * 0.55) if _mode == "tutorial" else CARD_W
	_card.custom_minimum_size = Vector2(w, 0)
	_body.custom_minimum_size = Vector2(w - 24.0, 0)
	_card.size = Vector2(w, 0)  # que la altura salga del contenido
	_card.position = Vector2(r.end.x - w - MARGIN, r.position.y + Hud.TOPBAR_H + MARGIN)


func _open(main, lesson: Dictionary) -> void:
	_current = lesson
	_title.text = lesson["title"]
	_body.text = lesson["text"]
	var tutorial := _mode == "tutorial"
	# Tutorial: "Capítulo  n/m" dentro del capítulo. Armado: no se traduce solo (Fase 27).
	_count.text = "%s  %d/%d" % [tr(String(lesson["chapter"])), _chapter_pos(step), _chapter_size(step)] if tutorial else ""
	var has_goal: bool = lesson.has("goal")
	_goal_label.visible = has_goal
	_goal_label.text = "▶ " + tr(String(lesson.get("goal", "")))
	_ok.visible = not has_goal
	_ok.text = String(lesson.get("button", "Siguiente  ⏎" if tutorial else "Entendido  ⏎"))
	var last := step >= lessons.size() - 1
	_skip.visible = tutorial and not last
	_skip_all.visible = tutorial and not last
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
	_current = {}
	if _mode == "tutorial" and step >= lessons.size():
		main.tutorial_finished.emit()


## Fase 35: "Omitir": salta el resto del capítulo de la tarjeta abierta (`step` ya apunta a la
## siguiente); nunca se salta la última tarjeta, la de despedida.
func skip_chapter() -> void:
	if _mode != "tutorial" or not _card.visible:
		return
	var chapter: String = lessons[step - 1]["chapter"]
	while step < lessons.size() - 1 and lessons[step]["chapter"] == chapter:
		step += 1
	close_card()


## Fase 35: "Omitir todo": termina el tutorial ya.
func skip_all() -> void:
	if _mode != "tutorial" or not _card.visible:
		return
	step = lessons.size()
	close_card()


## Posición (desde 1) de la tarjeta `i` dentro de su capítulo, y cuántas tiene ese capítulo.
func _chapter_pos(i: int) -> int:
	var n := 1
	while i - n >= 0 and lessons[i - n]["chapter"] == lessons[i]["chapter"]:
		n += 1
	return n


func _chapter_size(i: int) -> int:
	var n := 0
	for l in lessons:
		if l["chapter"] == lessons[i]["chapter"]:
			n += 1
	return n


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
# Cada lección: title, text y, en Juego normal, id + when(sim) -> bool; en el tutorial, chapter.
# Opcionales: focus(sim) -> Vector2, zoom, goal (texto) + done(sim) -> bool, button. Textos cortos:
# solo lo mínimo para entender la idea; el detalle sale jugando.

## Fase 15: antes cada feromona se mencionaba suelta en lecciones distintas, sin decir nunca quién
## sigue cuál — el jugador reportó que era confuso. Una sola tarjeta con las cinco, en el mismo
## orden en que se recorren con Q/E (`main.PHERO_FIELDS`).
const PHEROMONES_TEXT := "Tecla 2, luego Q/E para elegir:\nComida → obreras a la planta\nHogar → «ya explorado»: buscan más lejos\nPeligro → todas se alejan\nAtaque → los soldados van ahí\nEvacuar → huyen de la zona"


## Fase 15: ¿la colonia ya tiene salida a la superficie? El aire de arriba está conectado entre sí,
## así que basta mirar una celda de aire: si `nest_dist` la alcanza, hay algún túnel abierto.
static func _nest_open(sim: Simulation) -> bool:
	var i := (sim.cfg.surface_y - 1) * sim.world.w + sim.cfg.nest_x
	return sim.fields.nest_dist[i] < NestDistanceField.FAR


## Fase 35: centro de las celdas de una cámara (`WorldGrid.Room`), o el nido si no hay ninguna.
static func _room(sim: Simulation, room_type: int) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for i in sim.world.room.size():
		if sim.world.room[i] == room_type:
			sum += _px(sim, Vector2i(i % sim.world.w, i / sim.world.w))
			n += 1
	return sum / n if n > 0 else _nest(sim)


static func _tree(sim: Simulation) -> Vector2:
	if sim.home_tree == null:
		return _nest(sim)
	return _px(sim, Vector2i(sim.home_tree.x, sim.cfg.surface_y - 4))


static func _mushroom(sim: Simulation) -> Vector2:
	for p in sim.plants:
		if p.is_mushroom():
			return _px(sim, p.cell)
	return _nest(sim)


## Fase 35: el tutorial. Tarjetas cortas por capítulo, sobre la colonia ya armada
## (`Simulation.spawn_tutorial_start`). Sin objetivos: solo se lee y se mira.
func _tutorial_lessons() -> Array[Dictionary]:
	var surface := func(s: Simulation) -> Vector2: return _px(s, Vector2i(s.cfg.nest_x, s.cfg.surface_y - 3))
	return [
		{"chapter": "Inicio", "title": "Bienvenida", "focus": _nest, "zoom": Z_WIDE,
			"text": "Esta colonia ya está armada para que veas cómo funciona. Después empiezas la tuya desde cero.\nMueve la cámara con clic izq. y arrastrando, o con WASD; la rueda acerca y aleja."},
		{"chapter": "La colonia", "title": "La cámara Real", "focus": func(s: Simulation) -> Vector2: return _room(s, WorldGrid.Room.ROYAL), "zoom": Z_NEAR,
			"text": "Aquí vive la reina. Es el corazón del nido: si la reina muere, pierdes."},
		{"chapter": "La colonia", "title": "La Guardería", "focus": func(s: Simulation) -> Vector2: return _room(s, WorldGrid.Room.NURSERY), "zoom": Z_NEAR,
			"text": "Aquí se cuida la cría hasta que nace: huevo → larva → pupa → adulta."},
		{"chapter": "La colonia", "title": "El Almacén", "focus": func(s: Simulation) -> Vector2: return _room(s, WorldGrid.Room.STORAGE), "zoom": Z_NEAR,
			"text": "Las obreras dejan aquí la comida. Cuanto más grande, más comida puedes guardar."},
		{"chapter": "La colonia", "title": "Los túneles", "focus": _nest, "zoom": Z_NEAR,
			"text": "Unen las cámaras entre sí y con la superficie. Para cavar: tecla 1 y arrastra con clic derecho; las obreras hacen el trabajo. La roca gris no se cava."},
		{"chapter": "Las castas", "title": "La reina", "focus": _queen, "zoom": Z_CLOSE,
			"text": "La más grande. Pone todos los huevos y no pelea: protégela."},
		{"chapter": "Las castas", "title": "Obreras", "focus": func(s: Simulation) -> Vector2: return _first_of(s, CasteDefs.Caste.WORKER), "zoom": Z_CLOSE,
			"text": "Cavan, buscan comida y la traen al nido. Son la mayoría de la colonia."},
		{"chapter": "Las castas", "title": "Soldados", "focus": func(s: Simulation) -> Vector2: return _first_of(s, CasteDefs.Caste.SOLDIER), "zoom": Z_CLOSE,
			"text": "Patrullan tu mitad del mapa y pelean. Con «¡Atacar!» (tecla 8) marchan juntos contra la reina rival."},
		{"chapter": "Las castas", "title": "Zánganos", "focus": func(s: Simulation) -> Vector2: return _first_of(s, CasteDefs.Caste.DRONE), "zoom": Z_CLOSE,
			"text": "Llevan los huevos a la Guardería y escoltan a la reina. Si algo se le acerca, la defienden."},
		{"chapter": "Las castas", "title": "Más hormigas", "focus": _queen, "zoom": Z_NEAR,
			"text": "No eliges la casta: compras un huevo con comida (tecla 7) y nace obrera, soldado o zángano al azar."},
		{"chapter": "El bioma", "title": "El árbol gigante", "focus": _tree, "zoom": Z_WIDE,
			"text": "Está en el medio y es de las dos colonias. Las hojas caen por toda la copa; las semillas y frutas, que valen más, junto al tronco."},
		{"chapter": "El bioma", "title": "La superficie", "focus": surface, "zoom": Z_WIDE,
			"text": "Ahí está la comida, pero es peligrosa: arañas, ciempiés, mantis y las hormigas rivales."},
		{"chapter": "El bioma", "title": "Bajo tierra", "focus": _mushroom, "zoom": Z_NEAR,
			"text": "Tu refugio. La niebla tapa lo que todavía no exploraste. Cavando encuentras cuevas con hongos, que también son comida."},
		{"chapter": "El bioma", "title": "Clima y estaciones", "focus": surface, "zoom": Z_WIDE,
			"text": "De noche cae menos comida. La lluvia inunda los túneles bajos y borra los rastros. Cada estación trae un mapa nuevo y una rival más fuerte."},
		{"chapter": "El bioma", "title": "La colonia rival", "focus": func(s: Simulation) -> Vector2: return s.rival_colony.queen.pos, "zoom": Z_NEAR,
			"text": "Vive del otro lado del árbol. Crece sola, recoge lo que cae en su mitad y te manda incursiones. Ganas la estación si matas a su reina; pierdes si matan a la tuya."},
		{"chapter": "Cómo se juega", "title": "Las 5 feromonas", "focus": _nest, "zoom": Z_WIDE,
			"text": PHEROMONES_TEXT},
		{"chapter": "Cómo se juega", "title": "Árbol de mejoras", "focus": _nest, "zoom": Z_WIDE,
			"text": "Con comida compras mejoras en el árbol (tecla U). Elige una rama: Ataque, Defensa o Recolección; cada mejora abre la siguiente."},
		{"chapter": "Cómo se juega", "title": "¡A jugar!", "focus": _nest, "zoom": Z_WIDE, "button": "Empezar mi colonia  ⏎",
			"text": "Tu colonia empieza chica y con el nido cerrado: ábrelo, junta comida y crece más rápido que la rival."},
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
