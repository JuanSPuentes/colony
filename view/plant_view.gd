class_name PlantView
extends Node2D
## Plantas con hojas finitas: cuantas menos hojas quedan, más pequeña se dibuja la planta.
## Fase 11: usa el pack de 8 rotaciones de árbol que pasó el jugador ("Create a high-quality 2D
## pixel art tree, Idle, 8 direcciones") en vez de una sola imagen fija. La planta no se mueve y no
## tiene "dirección" real (no hay reina/amenaza a la que mirar), así que la rotación no sigue nada:
## cada planta usa una rotación fija, elegida por su propia celda (`DIR_FOR_CELL`), para que el
## bosque no se vea como el mismo árbol clonado en cada posición. Determinista y sin estado propio
## (no hace falta guardarla en el guardado ni en `Plant`, se recalcula igual cada vez desde `cell`).

## Mismo orden que `SpriteDir` (`AntRenderer`/`ThreatSpriteView`): crece con `Vector2.angle()`
## (0 = este, Y+ = hacia abajo/"sur").
const DIR_TEXTURES: Array[Texture2D] = [
	preload("res://view/sprites/plant/east.png"),
	preload("res://view/sprites/plant/south-east.png"),
	preload("res://view/sprites/plant/south.png"),
	preload("res://view/sprites/plant/south-west.png"),
	preload("res://view/sprites/plant/west.png"),
	preload("res://view/sprites/plant/north-west.png"),
	preload("res://view/sprites/plant/north.png"),
	preload("res://view/sprites/plant/north-east.png"),
]
## Fase 15: más grandes (antes 32) y cada árbol de un tamaño distinto (`_size_for_cell`), a pedido
## del jugador — antes todos medían exactamente lo mismo.
const TREE_SIZE := Vector2(46.0, 46.0)
const SIZE_VARIATION_MIN := 0.7
const SIZE_VARIATION_MAX := 1.35
## Fase 19: árbol gigante — mucho más grande que el más grande de los normales, verde profundo.
const GIANT_SCALE := 2.3
## Fase 19: colores de los bolsones de hongos (verde, morado, azul): brillan para que se noten.
const MUSHROOM_HUES: Array[Color] = [Color(0.45, 1.0, 0.4), Color(0.78, 0.42, 1.0), Color(0.35, 0.75, 1.0)]
## Igual que antes: con pocas hojas la planta se ve más chica, nunca por debajo de este piso para
## que siga siendo reconocible como árbol y no un brote.
const MIN_SCALE := 0.45
## Fase 16: cuánto se hunde la base en la tierra, como fracción del alto del árbol. El sprite casi
## no tiene margen abajo (1-2 px de 96); el problema era que la punta de las raíces quedaba
## exactamente sobre la línea del pasto y se veía apoyado encima, flotando. Así las raíces entran.
const SINK_FRACTION := 0.1
## Los tonos de follaje (multiplican el gris del sprite en `tree_color.gdshader`) dependen de la
## estación: ver `SeasonStyle.LEAF_TINTS`. Cada árbol toma uno por su celda.
const TREE_SHADER := preload("res://view/tree_color.gdshader")
## Fase 19: sprites del árbol gigante (8 vistas, mismo orden que `DIR_TEXTURES`).
const GIANT_TEXTURES: Array[Texture2D] = [
	preload("res://view/sprites/giant_tree/east.png"), preload("res://view/sprites/giant_tree/south-east.png"),
	preload("res://view/sprites/giant_tree/south.png"), preload("res://view/sprites/giant_tree/south-west.png"),
	preload("res://view/sprites/giant_tree/west.png"), preload("res://view/sprites/giant_tree/north-west.png"),
	preload("res://view/sprites/giant_tree/north.png"), preload("res://view/sprites/giant_tree/north-east.png"),
]
## Fase 19: hongos — hongo grande y racimo, 8 vistas de cada uno (16 variantes), en escala de
## grises: el color lo pone el bolsón al dibujarlos.
const MUSHROOM_TEXTURES: Array[Texture2D] = [
	preload("res://view/sprites/mushroom_big/east.png"), preload("res://view/sprites/mushroom_big/south-east.png"),
	preload("res://view/sprites/mushroom_big/south.png"), preload("res://view/sprites/mushroom_big/south-west.png"),
	preload("res://view/sprites/mushroom_big/west.png"), preload("res://view/sprites/mushroom_big/north-west.png"),
	preload("res://view/sprites/mushroom_big/north.png"), preload("res://view/sprites/mushroom_big/north-east.png"),
	preload("res://view/sprites/mushroom_cluster/east.png"), preload("res://view/sprites/mushroom_cluster/south-east.png"),
	preload("res://view/sprites/mushroom_cluster/south.png"), preload("res://view/sprites/mushroom_cluster/south-west.png"),
	preload("res://view/sprites/mushroom_cluster/west.png"), preload("res://view/sprites/mushroom_cluster/north-west.png"),
	preload("res://view/sprites/mushroom_cluster/north.png"), preload("res://view/sprites/mushroom_cluster/north-east.png"),
]
## Tamaño de cada hongo en celdas (la cueva mide 2 de alto): varía entre estos dos.
const MUSHROOM_SIZE_MIN := 1.2
const MUSHROOM_SIZE_MAX := 2.6
const MUSHROOM_SHADER := preload("res://view/mushroom_color.gdshader")

var sim: Simulation


func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = TREE_SHADER
	material = mat
	# Fase 18: contador de hojas encima de cada árbol. Nodo hijo aparte porque el shader de los
	# árboles (`material`) también teñiría el texto; el hijo no lo hereda (`use_parent_material`
	# es false por defecto) y va por encima de las hormigas para que siempre se lea.
	_counters = Node2D.new()
	_counters.z_index = 3
	add_child(_counters)
	_counters.draw.connect(_draw_counters)
	_mushrooms = Node2D.new()
	add_child(_mushrooms)
	_mushrooms.draw.connect(_draw_mushrooms)
	# Los sprites de hongo van en otro hijo con su propio shader (el brillo y la cueva no lo llevan).
	_mushroom_sprites = Node2D.new()
	var mmat := ShaderMaterial.new()
	mmat.shader = MUSHROOM_SHADER
	_mushroom_sprites.material = mmat
	add_child(_mushroom_sprites)
	_mushroom_sprites.draw.connect(_draw_mushroom_sprites)
	_home_trunk = Node2D.new()
	_home_trunk.show_behind_parent = true
	add_child(_home_trunk)
	_home_trunk.draw.connect(_draw_home_trunk)
	_home_canopy = Node2D.new()
	var cmat := ShaderMaterial.new()
	cmat.shader = TREE_SHADER
	cmat.set_shader_parameter("leaf_cut", HOME_CANOPY_CUT)
	_home_canopy.material = cmat
	add_child(_home_canopy)
	_home_canopy.draw.connect(_draw_home_canopy)


var _counters: Node2D
var _mushrooms: Node2D
var _mushroom_sprites: Node2D
## Fase 29: tronco del árbol madre, detrás de la copa y sin el shader de los árboles.
var _home_trunk: Node2D
var _home_canopy: Node2D
const COUNTER_FONT_VP := 9  # tamaño en píxeles del viewport del mundo (constante con cualquier zoom)
const COUNTER_FULL := Color(0.92, 1.0, 0.86)
const COUNTER_EMPTY := Color(1.0, 0.55, 0.45)
const COUNTER_GROW := Color(0.55, 1.0, 0.5)


## Fase 18: "hojas que quedan / máximo" sobre cada árbol, con ▲ cuando está rebrotando (de día y
## sin llegar a su máximo, solo en el modo incremental, que es donde rebrotan).
func _draw_counters() -> void:
	if sim == null:
		return
	# Se dibuja en píxeles del viewport (no del mundo): con zoom el texto no se agranda borroso, se
	# dibuja nítido y siempre del mismo tamaño en pantalla.
	var cs := get_canvas_transform().get_scale().x
	_counters.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0 / cs, 1.0 / cs))
	var font := ThemeDB.fallback_font
	var fs := COUNTER_FONT_VP
	var cpx := sim.cfg.cell_px
	var growing_now := sim.incremental and not DayNight.is_night(sim.time_s(), sim.cfg)
	for p in sim.plants:
		var top := _top_of(p)
		var grows_now := sim.incremental and (p.is_mushroom() or growing_now)
		var growing := grows_now and p.leaves < p.max_leaves
		var text := "%d/%d%s" % [p.leaves, p.max_leaves, " ▲" if growing else ""]
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := top * cs + Vector2(-w * 0.5, -4.0)
		var col := COUNTER_EMPTY if p.leaves == 0 else (COUNTER_GROW if growing else COUNTER_FULL)
		draw_string_outline_on(_counters, font, pos, text, fs, 3, Color(0, 0, 0, 0.85))
		_counters.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


static func draw_string_outline_on(ci: CanvasItem, font: Font, pos: Vector2, text: String, fs: int, size: int, col: Color) -> void:
	ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, size, col)


func setup(s: Simulation) -> void:
	sim = s
	(material as ShaderMaterial).set_shader_parameter("snow", SeasonStyle.SNOW_ON_TREES[SeasonStyle.of(sim)])
	(_home_canopy.material as ShaderMaterial).set_shader_parameter("snow", SeasonStyle.SNOW_ON_TREES[SeasonStyle.of(sim)])
	queue_redraw()
	# El árbol madre no cambia solo: se redibuja al preparar la partida (mapa nuevo, estación).
	_home_trunk.queue_redraw()
	_home_canopy.queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()
	if _counters != null:
		_counters.queue_redraw()
		_mushrooms.queue_redraw()
		_mushroom_sprites.queue_redraw()


## Rotación fija por celda (hash simple, sin estado): dos plantas en la misma celda siempre eligen
## la misma, y no depende de cuántas plantas hay ni del orden en que se crearon (a diferencia de un
## índice por posición en `sim.plants`, que cambiaría si una planta desaparece).
static func _dir_for_cell(cell: Vector2i) -> int:
	return absi(cell.x * 374761393 + cell.y * 668265263) % DIR_TEXTURES.size()


## Fase 15: tamaño propio de cada árbol, mismo truco que `_dir_for_cell` (hash de la celda, sin
## estado): se ve igual tras guardar/cargar porque la celda se guarda, sin tocar `Plant` ni el
## formato de guardado.
static func _size_for_cell(cell: Vector2i) -> float:
	var h := absi(cell.x * 2654435761 + cell.y * 40503) % 1000
	return lerpf(SIZE_VARIATION_MIN, SIZE_VARIATION_MAX, float(h) / 999.0)


## Fase 19: tamaño en el mundo de un árbol (normal o gigante) según sus hojas.
func _tree_size(p: Plant) -> Vector2:
	var frac := float(p.leaves) / float(p.max_leaves)
	var s := TREE_SIZE * maxf(frac, MIN_SCALE)
	if p.kind == Plant.Kind.GIANT:
		return s * GIANT_SCALE
	return s * _size_for_cell(p.cell)


## Fase 19: punto de arriba de cada fuente (donde va su contador).
func _top_of(p: Plant) -> Vector2:
	var cpx := sim.cfg.cell_px
	if p.is_mushroom():
		var min_y := p.cell.y
		for c in p.pocket:
			min_y = mini(min_y, c.y)
		return Vector2((p.cell.x + 0.5) * cpx, min_y * cpx - 2.0)
	var size := _tree_size(p)
	return Vector2((p.cell.x + 0.5) * cpx, (p.cell.y + 1) * cpx + size.y * SINK_FRACTION - size.y)


func _draw() -> void:
	if sim == null:
		return
	var cpx := sim.cfg.cell_px
	for p in sim.plants:
		if p.is_mushroom():
			continue  # los dibuja `_mushrooms` (sin el shader de los árboles)
		var size := _tree_size(p)
		var base := Vector2((p.cell.x + 0.5) * cpx, (p.cell.y + 1) * cpx)
		var tex: Texture2D = GIANT_TEXTURES[_dir_for_cell(p.cell)] if p.kind == Plant.Kind.GIANT else DIR_TEXTURES[_dir_for_cell(p.cell)]
		base.y += size.y * SINK_FRACTION
		var tint := SeasonStyle.GIANT_TINT[SeasonStyle.of(sim)] if p.kind == Plant.Kind.GIANT else SeasonStyle.leaf_tint(sim, p.cell)
		draw_texture_rect(tex, Rect2(base - Vector2(size.x * 0.5, size.y), size), false, tint)


## Fase 19: bolsones de hongos. Un brillo de color (verde, morado o azul) que se ve a través de la
## tierra alrededor de la cueva — la pista de que ahí hay algo antes de cavar — y hongos con
## sombrero de ese color que se van achicando en cantidad a medida que se cosechan (los hongos en
## sí los dibuja `_draw_mushroom_sprites`, con su shader).
func _draw_mushrooms() -> void:
	if sim == null:
		return
	var cpx := float(sim.cfg.cell_px)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 600.0)
	for p in sim.plants:
		if not p.is_mushroom() or p.pocket.is_empty():
			continue
		var col: Color = MUSHROOM_HUES[p.hue % MUSHROOM_HUES.size()]
		# Un solo brillo suave centrado en la cueva (se ve a través de la tierra: la pista de que ahí
		# hay algo) y un tinte leve adentro, sobre la pared de fondo que ya dibuja `TerrainView`.
		var box := Rect2(Vector2(p.pocket[0]) * cpx, Vector2.ZERO)
		for c in p.pocket:
			box = box.expand(Vector2(c) * cpx).expand(Vector2(c + Vector2i.ONE) * cpx)
		var center := box.get_center()
		var r := maxf(box.size.x, box.size.y) * 0.5
		for k in 3:
			_mushrooms.draw_circle(center, r * (1.6 - 0.25 * k), Color(col, (0.035 + 0.025 * pulse) * (k + 1) * 0.6))
		for c in p.pocket:
			_mushrooms.draw_rect(Rect2(Vector2(c) * cpx, Vector2(cpx, cpx)), Color(col, 0.13))


## Fase 19: sprites de hongo (grande y racimo) sobre el piso de cada bolsón: tantos como le queden
## (uno por celda del piso como máximo). Cada uno elige sprite, vista, tamaño y una variación del
## color del bolsón por su celda (hash sin estado, se ve igual tras guardar/cargar). El color lo
## aplica `mushroom_color.gdshader` sobre el gris del sprite.
func _draw_mushroom_sprites() -> void:
	if sim == null:
		return
	var cpx := float(sim.cfg.cell_px)
	for p in sim.plants:
		if not p.is_mushroom():
			continue
		var col: Color = MUSHROOM_HUES[p.hue % MUSHROOM_HUES.size()]
		var in_pocket := {}
		for c in p.pocket:
			in_pocket[c] = true
		# Piso: celdas de la cueva con tierra debajo. Cuántos hongos se ven depende de cuántos quedan.
		var floor_cells: Array[Vector2i] = []
		for c in p.pocket:
			if not in_pocket.has(c + Vector2i(0, 1)):
				floor_cells.append(c)
		floor_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
		var shown := int(ceil(float(floor_cells.size()) * float(p.leaves) / float(p.max_leaves)))
		for k in mini(shown, floor_cells.size()):
			var c := floor_cells[k]
			# Alto libre sobre esta celda del piso: el hongo nunca pasa del techo de la cueva.
			var clear := 1
			while in_pocket.has(c - Vector2i(0, clear)):
				clear += 1
			var h := absi(c.x * 73856093 + c.y * 19349663 + k * 83492791)
			var tex: Texture2D = MUSHROOM_TEXTURES[h % MUSHROOM_TEXTURES.size()]
			var s := cpx * lerpf(MUSHROOM_SIZE_MIN, MUSHROOM_SIZE_MAX, float((h / 7) % 100) / 99.0)
			s = minf(s, clear * cpx - 1.0)
			# Variación dentro de la misma familia de color: un poco de corrimiento de tono, más o menos
			# saturado y más claro u oscuro (mezclar con el color de otro bolsón daba grises).
			var hue_shift := (float((h / 11) % 100) / 99.0 - 0.5) * 0.12
			var mcol := Color.from_hsv(fposmod(col.h + hue_shift, 1.0), clampf(col.s * (0.85 + 0.3 * float((h / 13) % 3) / 2.0), 0.0, 1.0), col.v)
			mcol = mcol.lightened(0.1) if (h / 17) % 2 == 0 else mcol.darkened(0.15)
			var bx := (c.x + 0.5) * cpx
			var by := (c.y + 1) * cpx
			_mushroom_sprites.draw_texture_rect(tex, Rect2(bx - s * 0.5, by - s, s, s), false, mcol)


## Fase 29: el árbol madre. El tronco y las raíces son el sprite propio (`home_tree/trunk.png`,
## 168×168, en grises: se tiñe de madera); de él se repite la franja de arriba hacia el cielo, así
## el tronco sigue subiendo y sale del mapa por arriba — no se ve entero, que es la idea: es
## colosal. De la copa solo cuelga el borde de abajo desde el techo del mapa (la copa del gigante,
## agrandada y con el color de la estación).
const HOME_TRUNK := preload("res://view/sprites/home_tree/trunk.png")
const HOME_TRUNK_TINT := Color("c49a6c")
## Cuántas veces se agranda el sprite del tronco (168 px). Provisorio: con un sprite más grande
## generado a la escala del juego volvería a 1 y se vería igual de nítido que el resto.
const HOME_TREE_ZOOM := 3.0
## Filas de arriba del sprite que se repiten para alargar el tronco (son solo corteza, sin raíces).
const HOME_TRUNK_STRIP := 30
## Fracción de abajo del sprite que se descarta: lo que quedaría bajo la línea del pasto. Nada del
## tronco se dibuja bajo tierra (taparía túneles y hormigas); las raíces de abajo son parte del
## terreno (`TerrainView`, `HomeTree.root_mask`).
const HOME_ROOT_SINK := 0.12
## Copa: el sprite del gigante cortado por el shader (`leaf_cut`) donde terminan las hojas, y su
## tamaño en el mundo.
const HOME_CANOPY_CUT := 0.56
const HOME_CANOPY_SIZE := Vector2(1100, 1100)
## Cuánto de la copa cuelga dentro del mapa, desde el borde de arriba del mundo (px).
const HOME_CANOPY_HANG := 60.0


## Fase 29: copa del árbol madre, en su propio nodo (`_home_canopy`) con una copia del shader de
## los árboles que la corta donde terminan las hojas; el tronco va en `_home_trunk`, detrás, sin
## shader (es todo madera).
func _draw_home_canopy() -> void:
	if sim == null or sim.home_tree == null:
		return
	var cx := (sim.home_tree.x + 0.5) * sim.cfg.cell_px
	var top := HOME_CANOPY_HANG - HOME_CANOPY_SIZE.y * HOME_CANOPY_CUT
	_home_canopy.draw_texture_rect(GIANT_TEXTURES[0], Rect2(Vector2(cx - HOME_CANOPY_SIZE.x * 0.5, top), HOME_CANOPY_SIZE),
		false, SeasonStyle.GIANT_TINT[SeasonStyle.of(sim)])


func _draw_home_trunk() -> void:
	if sim == null or sim.home_tree == null:
		return
	var cpx := sim.cfg.cell_px
	var w := HOME_TRUNK.get_width() * HOME_TREE_ZOOM
	var left := (sim.home_tree.x + 0.5) * cpx - w * 0.5
	var kept := HOME_TRUNK.get_height() * (1.0 - HOME_ROOT_SINK)  # filas del sprite sobre el pasto
	var y := sim.cfg.surface_y * cpx - kept * HOME_TREE_ZOOM
	_home_trunk.draw_texture_rect_region(HOME_TRUNK, Rect2(left, y, w, kept * HOME_TREE_ZOOM),
		Rect2(0, 0, HOME_TRUNK.get_width(), kept), HOME_TRUNK_TINT)
	# Hacia arriba, la franja de corteza repetida hasta pasar el borde del mundo.
	var strip := Rect2(0, 0, HOME_TRUNK.get_width(), HOME_TRUNK_STRIP)
	var strip_h := HOME_TRUNK_STRIP * HOME_TREE_ZOOM
	while y > -strip_h:
		y -= strip_h
		_home_trunk.draw_texture_rect_region(HOME_TRUNK, Rect2(left, y, w, strip_h), strip, HOME_TRUNK_TINT)
