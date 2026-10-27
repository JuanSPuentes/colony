class_name CorpseView
extends Node2D
## Restos recolectables (Punto 4): una mancha oscura chica con un par de líneas finas (huesitos),
## nada elaborado — son un recurso de paso, no un elemento central del arte del juego.
## Fase 29: también lo que cae del árbol madre (hoja, semilla, fruta), cada cosa con su forma.

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
		if c.is_tree_drop():
			_draw_drop(c)
			continue
		draw_circle(c.pos, 2.4, BODY_COLOR)
		draw_line(c.pos + Vector2(-2.2, 0.0), c.pos + Vector2(2.2, 0.0), BONE_COLOR, 0.8)
		draw_line(c.pos + Vector2(0.0, -2.2), c.pos + Vector2(0.0, 2.2), BONE_COLOR, 0.8)


const DROP_LEAF := Color("5fb04a")
const DROP_LEAF_DARK := Color("3a7a2c")
const DROP_SEED := Color("a8743a")
const DROP_SEED_DARK := Color("6b4226")
const DROP_FRUIT := Color("d8402f")
const DROP_FRUIT_HI := Color("ff8a70")


## Fase 29: hoja (óvalo verde con nervio), semilla (grano marrón) o fruta (bola roja con brillo).
## Lo que lleva mucho tiempo en el suelo se oscurece un poco: está por pudrirse.
func _draw_drop(c: Corpse) -> void:
	var rot := clampf(c.age / sim.cfg.drop_decay_s, 0.0, 1.0)
	var dim := 1.0 - 0.45 * rot
	var p := c.pos
	match c.kind:
		Corpse.Kind.LEAF:
			draw_set_transform(p, 0.35, Vector2(1.0, 0.5))
			draw_circle(Vector2.ZERO, 2.4, DROP_LEAF.darkened(1.0 - dim))
			draw_set_transform(Vector2.ZERO)
			draw_line(p + Vector2(-2.0, -0.6), p + Vector2(2.0, 0.6), DROP_LEAF_DARK, 0.5)
		Corpse.Kind.SEED:
			draw_set_transform(p, -0.3, Vector2(1.0, 0.7))
			draw_circle(Vector2.ZERO, 1.5, DROP_SEED.darkened(1.0 - dim))
			draw_set_transform(Vector2.ZERO)
			draw_circle(p + Vector2(0.5, 0.3), 0.6, DROP_SEED_DARK)
		Corpse.Kind.FRUIT:
			draw_circle(p + Vector2(0, -1.2), 2.6, DROP_FRUIT.darkened(1.0 - dim))
			draw_circle(p + Vector2(-0.8, -2.0), 0.8, DROP_FRUIT_HI)
			draw_line(p + Vector2(0, -3.8), p + Vector2(0.6, -4.8), DROP_SEED_DARK, 0.6)
