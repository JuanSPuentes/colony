class_name Plant
extends RefCounted
## Fuente de hojas de la superficie. Las hojas son finitas y no rebrotan.

var cell := Vector2i.ZERO
var leaves := 0
var max_leaves := 0


func _init(c: Vector2i, n: int) -> void:
	cell = c
	leaves = n
	max_leaves = n
