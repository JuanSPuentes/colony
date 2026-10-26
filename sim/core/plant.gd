class_name Plant
extends RefCounted
## Fuente de hojas de la superficie. En las Fases 0-2 las hojas son finitas y no rebrotan; en el
## modo incremental (Fase 3) rebrotan de día (`IncrementalEconomy.regrow_plants`).
##
## Fase 19: además del árbol de siempre, un árbol gigante (más hojas, rebrota más rápido) y bolsones
## de hongos bajo tierra (rebrotan también de noche; las obreras llegan por túnel). Para no duplicar
## la recolección, todos son `Plant`: "hojas" son también los hongos que se llevan.

enum Kind { TREE, GIANT, MUSHROOM }

var cell := Vector2i.ZERO
var leaves := 0
var max_leaves := 0
## Fracción de hoja acumulada hacia el próximo rebrote (solo modo incremental).
var regrow_acc := 0.0
var kind := Kind.TREE
## Hongos: color del bolsón (0 verde, 1 morado, 2 azul), solo estético.
var hue := 0
## Hongos: celdas abiertas de su cueva (para dibujar el brillo). No se guardan: salen del terreno.
var pocket: Array[Vector2i] = []
## Hongos: distancia por túnel hasta el bolsón y con qué terreno se calculó (ver `AntSystem`).
var route := PackedInt32Array()
var route_version := -1
var route_water := -1


func _init(c: Vector2i, n: int) -> void:
	cell = c
	leaves = n
	max_leaves = n


func is_mushroom() -> bool:
	return kind == Kind.MUSHROOM
