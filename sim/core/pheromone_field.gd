class_name PheromoneField
extends RefCounted
## Un campo de feromona: un valor decimal (0..1) por celda, con decaimiento exponencial.

var w := 0
var h := 0
var data := PackedFloat32Array()
var decay_per_s := 0.01
var active := 0  # celdas con valor > 0 tras el último decaimiento


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


## `mult` > 1 acelera el decaimiento (lluvia).
func decay(dt: float, mult: float) -> void:
	var f := exp(-decay_per_s * mult * dt)
	var n := 0
	for i in data.size():
		var v := data[i]
		if v > 0.0:
			v *= f
			if v < 0.02:
				v = 0.0
			else:
				n += 1
			data[i] = v
	active = n


func clear() -> void:
	data.fill(0.0)
	active = 0
