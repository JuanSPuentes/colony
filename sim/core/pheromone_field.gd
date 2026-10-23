class_name PheromoneField
extends RefCounted
## Un campo de feromona: un valor decimal (0..1) por celda, con decaimiento exponencial.

var w := 0
var h := 0
var data := PackedFloat32Array()
var decay_per_s := 0.01
var active := 0  # celdas con valor > 0 tras el último decaimiento
## Fase 14: piso que no decae, puesto por el pincel del jugador (`paint`). Vacío hasta que se pinta
## algo: un campo que nadie pinta (o que las pruebas llenan escribiendo `data` directo) decae
## exactamente igual que antes. Lo que depositan las hormigas va encima y sí se desgasta.
var floor_v := PackedFloat32Array()


func _init(width: int, height: int, decay: float) -> void:
	w = width
	h = height
	decay_per_s = decay
	data.resize(w * h)


func get_v(x: int, y: int) -> float:
	if x < 0 or y < 0 or x >= w or y >= h:
		return 0.0
	return data[y * w + x]


func deposit(i: int, amount: float) -> void:
	data[i] = minf(1.0, data[i] + amount)


func set_max(i: int, value: float) -> void:
	if value > data[i]:
		data[i] = minf(1.0, value)


## Fase 14: pintar fija además un piso que no se desgasta (el rastro del jugador dura hasta que lo
## borre); el valor visible nunca baja de ese piso.
func paint(i: int, value: float) -> void:
	if floor_v.is_empty():
		floor_v.resize(w * h)
	floor_v[i] = maxf(floor_v[i], minf(1.0, value))
	set_max(i, value)


## Borra una celda entera: lo depositado y lo pintado.
func clear_cell(i: int) -> void:
	data[i] = 0.0
	if not floor_v.is_empty():
		floor_v[i] = 0.0


## Fase 16: borra solo lo depositado por las hormigas; lo pintado por el jugador (el piso) queda.
func clear_deposit(i: int) -> void:
	data[i] = 0.0 if floor_v.is_empty() else floor_v[i]


## `mult` > 1 acelera el decaimiento (lluvia).
func decay(dt: float, mult: float) -> void:
	var f := exp(-decay_per_s * mult * dt)
	var n := 0
	var has_floor := not floor_v.is_empty()
	for i in data.size():
		var v := data[i]
		if v > 0.0:
			v *= f
			if v < 0.02:
				v = 0.0
			if has_floor and v < floor_v[i]:
				v = floor_v[i]
			if v > 0.0:
				n += 1
			data[i] = v
	active = n


func clear() -> void:
	data.fill(0.0)
	floor_v.fill(0.0)
	active = 0
