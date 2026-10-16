class_name Plant
extends RefCounted
## Fuente de hojas de la superficie. En las Fases 0-2 las hojas son finitas y no rebrotan; en el
## modo incremental (Fase 3) rebrotan de día (`IncrementalEconomy.regrow_plants`).

var cell := Vector2i.ZERO
var leaves := 0
var max_leaves := 0
## Fracción de hoja acumulada hacia el próximo rebrote (solo modo incremental).
var regrow_acc := 0.0


func _init(c: Vector2i, n: int) -> void:
	cell = c
	leaves = n
	max_leaves = n
