class_name ProtoNest
extends RefCounted
## PROTOTIPO: el nido visto de lado, como un CORTE vertical bajo la franja del exterior
## (y = ProtoSurface.CUT_Y). La columna x del nido es la misma x del exterior: un túnel que llega
## a la fila 0 es un orificio en el exterior en esa misma x.
##
## Arranca cerrado: una cámara y un túnel corto que no llega arriba. El jugador marca qué cavar y
## las hormigas lo cavan. Tres campos de distancia (BFS por túneles) guían a las hormigas:
## a la cámara, a la salida más cercana y al frente de excavación más cercano.

const W := 240               # igual que ProtoSurface.W: misma x
const H := 60                # 240 px de profundidad
const CELL := 4.0

var open := PackedByteArray()     # 1 = túnel
var mark := PackedByteArray()     # 1 = marcado para cavar
var chamber := Rect2i()
var to_chamber := PackedInt32Array()
var to_exit := PackedInt32Array()
var to_dig := PackedInt32Array()
var version := 0                  # sube al cambiar túneles o marcas (para repintar)


func _init(cx: int) -> void:
	open.resize(W * H)
	mark.resize(W * H)
	chamber = Rect2i(cx - 7, 24, 14, 5)
	for y in range(chamber.position.y, chamber.end.y):
		for x in range(chamber.position.x, chamber.end.x):
			open[y * W + x] = 1
	for y in range(14, chamber.position.y):
		open[y * W + cx] = 1
	recompute()


func idx(x: int, y: int) -> int:
	return y * W + x


func in_chamber(i: int) -> bool:
	return chamber.has_point(Vector2i(i % W, i / W))


func cell_center(i: int) -> Vector2:
	return Vector2((i % W + 0.5) * CELL, (i / W + 0.5) * CELL)


func cell_at(p: Vector2) -> int:
	return clampi(int(p.y / CELL), 0, H - 1) * W + clampi(int(p.x / CELL), 0, W - 1)


## Columnas centrales de cada salida (tramos seguidos de túnel en la fila 0 = una salida).
func entrances() -> PackedInt32Array:
	var out := PackedInt32Array()
	var x := 0
	while x < W:
		if open[x] == 1:
			var x0 := x
			while x < W and open[x] == 1:
				x += 1
			out.append((x0 + x - 1) / 2)
		else:
			x += 1
	return out


func set_mark(i: int, v: bool) -> void:
	if open[i] == 1:
		return
	var nv := 1 if v else 0
	if mark[i] != nv:
		mark[i] = nv
		version += 1
		to_dig = _bfs(_dig_sources())


func has_marks() -> bool:
	return mark.has(1)


func dig(i: int) -> void:
	open[i] = 1
	mark[i] = 0
	version += 1
	recompute()


## Una celda marcada al lado de `i` (la que se cava desde ahí), o -1.
func dig_target_near(i: int) -> int:
	for n in _neighbors(i):
		if mark[n] == 1:
			return n
	return -1


func recompute() -> void:
	var cham := PackedInt32Array()
	var exits := PackedInt32Array()
	for i in open.size():
		if open[i] == 1:
			if in_chamber(i):
				cham.append(i)
			if i < W:
				exits.append(i)
	to_chamber = _bfs(cham)
	to_exit = _bfs(exits)
	to_dig = _bfs(_dig_sources())


## Siguiente celda bajando por el campo; la misma celda si ya llegó (o si no hay camino).
func step_down(field: PackedInt32Array, i: int) -> int:
	var d := field[i]
	if d <= 0:
		return i
	for n in _neighbors(i):
		if open[n] == 1 and field[n] >= 0 and field[n] < d:
			return n
	return i


func _dig_sources() -> PackedInt32Array:
	var src := PackedInt32Array()
	for i in open.size():
		if open[i] == 1 and dig_target_near(i) >= 0:
			src.append(i)
	return src


func _neighbors(i: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var x := i % W
	var y := i / W
	if x > 0: out.append(i - 1)
	if x < W - 1: out.append(i + 1)
	if y > 0: out.append(i - W)
	if y < H - 1: out.append(i + W)
	return out


func _bfs(sources: PackedInt32Array) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(W * H)
	dist.fill(-1)
	var q := PackedInt32Array()
	for s in sources:
		dist[s] = 0
		q.append(s)
	var head := 0
	while head < q.size():
		var c := q[head]
		head += 1
		for n in _neighbors(c):
			if open[n] == 1 and dist[n] < 0:
				dist[n] = dist[c] + 1
				q.append(n)
	return dist
