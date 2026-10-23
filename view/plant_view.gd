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
## Igual que antes: con pocas hojas la planta se ve más chica, nunca por debajo de este piso para
## que siga siendo reconocible como árbol y no un brote.
const MIN_SCALE := 0.45
## Fase 16: cuánto se hunde la base en la tierra, como fracción del alto del árbol. El sprite casi
## no tiene margen abajo (1-2 px de 96); el problema era que la punta de las raíces quedaba
## exactamente sobre la línea del pasto y se veía apoyado encima, flotando. Así las raíces entran.
const SINK_FRACTION := 0.1
## Fase 16: tonos de follaje (multiplican el gris del sprite en `tree_color.gdshader`). Cada árbol
## toma uno por su celda, como el tamaño y la rotación: verdes distintos y algún otoñal.
const LEAF_TINTS: Array[Color] = [
	Color(0.36, 0.72, 0.30), Color(0.25, 0.58, 0.26), Color(0.48, 0.78, 0.28),
	Color(0.20, 0.48, 0.30), Color(0.62, 0.74, 0.26), Color(0.86, 0.56, 0.20),
]
const TREE_SHADER := preload("res://view/tree_color.gdshader")

var sim: Simulation


func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = TREE_SHADER
	material = mat


func setup(s: Simulation) -> void:
	sim = s
	queue_redraw()


static func _tint_for_cell(cell: Vector2i) -> Color:
	return LEAF_TINTS[absi(cell.x * 1103515245 + cell.y * 12345 + 7) % LEAF_TINTS.size()]


func _process(_delta: float) -> void:
	queue_redraw()


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


func _draw() -> void:
	if sim == null:
		return
	var cpx := sim.cfg.cell_px
	for p in sim.plants:
		var frac := float(p.leaves) / float(p.max_leaves)
		var scale := maxf(frac, MIN_SCALE)
		var size := TREE_SIZE * scale * _size_for_cell(p.cell)
		var base := Vector2((p.cell.x + 0.5) * cpx, (p.cell.y + 1) * cpx)
		var tex := DIR_TEXTURES[_dir_for_cell(p.cell)]
		base.y += size.y * SINK_FRACTION
		draw_texture_rect(tex, Rect2(base - Vector2(size.x * 0.5, size.y), size), false, _tint_for_cell(p.cell))
