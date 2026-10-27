class_name Corpse
extends RefCounted
## Comida suelta en el suelo. Al principio solo eran restos de una hormiga o una amenaza al morir
## (araña, y lo que se sume después); Fase 29: también lo que cae del árbol madre (hoja, semilla,
## fruta). Una obrera la recoge igual que una hoja de árbol (mismo pickup, mismo viaje a casa) y se
## vuelve comida al llegar. Se agota de un viaje (no hay "varias partes", simplificación deliberada)
## y desaparece sola si nadie la recoge a tiempo.

enum Kind { REMAINS, LEAF, SEED, FRUIT }

var pos: Vector2
var food_value: float
var age := 0.0
var kind := Kind.REMAINS


func _init(p: Vector2, value: float, k: Kind = Kind.REMAINS) -> void:
	pos = p
	food_value = value
	kind = k


func is_tree_drop() -> bool:
	return kind != Kind.REMAINS
