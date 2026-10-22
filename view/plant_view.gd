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
const TREE_SIZE := Vector2(32.0, 32.0)
## Igual que antes: con pocas hojas la planta se ve más chica, nunca por debajo de este piso para
## que siga siendo reconocible como árbol y no un brote.
const MIN_SCALE := 0.45

var sim: Simulation


func setup(s: Simulation) -> void:
	sim = s
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


## Rotación fija por celda (hash simple, sin estado): dos plantas en la misma celda siempre eligen
## la misma, y no depende de cuántas plantas hay ni del orden en que se crearon (a diferencia de un
## índice por posición en `sim.plants`, que cambiaría si una planta desaparece).
static func _dir_for_cell(cell: Vector2i) -> int:
	return absi(cell.x * 374761393 + cell.y * 668265263) % DIR_TEXTURES.size()


func _draw() -> void:
	if sim == null:
		return
	var cpx := sim.cfg.cell_px
	for p in sim.plants:
		var frac := float(p.leaves) / float(p.max_leaves)
		var scale := maxf(frac, MIN_SCALE)
		var size := TREE_SIZE * scale
		var base := Vector2((p.cell.x + 0.5) * cpx, (p.cell.y + 1) * cpx)
		var tex := DIR_TEXTURES[_dir_for_cell(p.cell)]
		draw_texture_rect(tex, Rect2(base - Vector2(size.x * 0.5, size.y), size), false)
