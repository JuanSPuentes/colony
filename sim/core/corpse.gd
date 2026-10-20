class_name Corpse
extends RefCounted
## Restos de una hormiga o una amenaza al morir (araña, y lo que se sume después). Una obrera los
## recoge igual que recoge una hoja (mismo pickup, mismo viaje a casa) y se vuelven comida al
## llegar, pero valen más que una hoja. Se agotan de un viaje (no hay "varias partes" por cadáver,
## simplificación deliberada) y desaparecen solos si nadie los recoge a tiempo.

var pos: Vector2
var food_value: float
var age := 0.0


func _init(p: Vector2, value: float) -> void:
	pos = p
	food_value = value
