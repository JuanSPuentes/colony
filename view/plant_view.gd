class_name PlantView
extends Node2D
## Plantas con hojas finitas: cuantas menos hojas quedan, más pequeña se dibuja la planta.
## Fase 11: usa el sprite real de árbol que pasó el jugador ("Árbol frondoso pixelado en escala de
## grises", 1254x1254) en vez de las formas procedurales que había antes (dos rectángulos verdes
## diminutos, ~7px de alto). Una sola imagen, sin direcciones (la planta no se mueve ni tiene
## frente/espalda). Tamaño pensado para que un árbol se note de verdad junto al nido, no como un
## matorral (`TREE_SIZE`, ~4 celdas de alto).

const TREE_TEX: Texture2D = preload("res://view/sprites/plant/tree.png")
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


func _draw() -> void:
	if sim == null:
		return
	var cpx := sim.cfg.cell_px
	for p in sim.plants:
		var frac := float(p.leaves) / float(p.max_leaves)
		var scale := maxf(frac, MIN_SCALE)
		var size := TREE_SIZE * scale
		var base := Vector2((p.cell.x + 0.5) * cpx, (p.cell.y + 1) * cpx)
		draw_texture_rect(TREE_TEX, Rect2(base - Vector2(size.x * 0.5, size.y), size), false)
