class_name CorpseView
extends Node2D
## Restos recolectables (Punto 4): una mancha oscura chica con un par de líneas finas (huesitos),
## nada elaborado — son un recurso de paso, no un elemento central del arte del juego.

var sim: Simulation

const BODY_COLOR := Color("4a2a1f")
const BONE_COLOR := Color("d8cdb8")


func setup(s: Simulation) -> void:
	sim = s
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if sim == null:
		return
	for c in sim.corpses:
		if c.food_value <= 0.0:
			continue
		draw_circle(c.pos, 2.4, BODY_COLOR)
		draw_line(c.pos + Vector2(-2.2, 0.0), c.pos + Vector2(2.2, 0.0), BONE_COLOR, 0.8)
		draw_line(c.pos + Vector2(0.0, -2.2), c.pos + Vector2(0.0, 2.2), BONE_COLOR, 0.8)
