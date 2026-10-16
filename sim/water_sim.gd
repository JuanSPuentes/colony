class_name WaterSim
extends RefCounted
## Autómata celular de agua. La lluvia entra por el aire de la superficie; el agua cae por
## gravedad, se extiende hacia los lados nivelándose y, cuando una celda se llena, sube.
## Llena primero lo más bajo. Cuando no llueve, se evapora poco a poco.

const CAP := 1.0

var world: WorldGrid
var cfg: SimConfig
var level := PackedFloat32Array()
var wet := {}  # int idx -> true (solo se recorren las celdas mojadas)
var raining := false
var max_level := 0.0
var volume := 0.0
var _flip := false
var _top_row := 0


func _init(g: WorldGrid) -> void:
	world = g
	cfg = g.cfg
	level.resize(g.w * g.h)
	_top_row = cfg.surface_y - cfg.walk_band


func _holds(x: int, y: int) -> bool:
	return y >= _top_row and world.is_open(x, y)


func add(i: int, v: float) -> void:
	level[i] += v
	wet[i] = true


func clear() -> void:
	level.fill(0.0)
	wet.clear()
	max_level = 0.0
	volume = 0.0


## `dt` es el tiempo simulado que cubre este paso.
func step(dt: float) -> void:
	var w := world.w
	if raining:
		# La lluvia entra por las celdas abiertas a la superficie; el resto del suelo la absorbe.
		var gain := cfg.rain_rate * float(2 * cfg.rain_funnel + 1) * dt
		for x in w:
			if world.cells[cfg.surface_y * w + x] == WorldGrid.Cell.TUNNEL and world.is_open(x, cfg.surface_y - 1):
				var i0 := cfg.surface_y * w + x
				var room := maxf(CAP - level[i0], 0.0)
				if room > 0.0:
					add(i0, minf(gain, room))
	if wet.is_empty():
		max_level = 0.0
		volume = 0.0
		return
	_flip = not _flip
	var keys: Array = wet.keys()
	keys.sort_custom(func(a: int, b: int) -> bool: return a / w > b / w)
	for i: int in keys:
		var x := i % w
		var y := i / w
		var amount := level[i]
		if amount <= 0.0005 or not _holds(x, y):
			continue
		# Caída.
		if _holds(x, y + 1):
			var bi := i + w
			var move := minf(amount, maxf(CAP - level[bi], 0.0))
			if move > 0.0:
				level[i] -= move
				level[bi] += move
				wet[bi] = true
				amount = level[i]
		# Extensión lateral hasta nivelar.
		if amount > 0.01:
			var dirs := [-1, 1] if _flip else [1, -1]
			for dx in dirs:
				var nx: int = x + dx
				if not _holds(nx, y):
					continue
				var ni: int = i + dx
				var diff := level[i] - level[ni]
				if diff > 0.02:
					var m2 := minf(diff * 0.33, maxf(CAP - level[ni], 0.0))
					if m2 > 0.0:
						level[i] -= m2
						level[ni] += m2
						wet[ni] = true
		# Rebose hacia arriba cuando la celda está llena.
		var over := level[i] - CAP
		if over > 0.0 and _holds(x, y - 1):
			var ai := i - w
			var m3 := minf(over, maxf(CAP - level[ai], 0.0))
			if m3 > 0.0:
				level[i] -= m3
				level[ai] += m3
				wet[ai] = true
	# Evaporación (solo cuando no llueve) y limpieza de celdas secas.
	max_level = 0.0
	volume = 0.0
	var dry: Array[int] = []
	var loss := 0.0 if raining else cfg.evap_per_s * dt
	for i: int in wet:
		var v := maxf(0.0, level[i] - loss)
		level[i] = v
		if v <= 0.002:
			level[i] = 0.0
			dry.append(i)
		else:
			max_level = maxf(max_level, v)
			volume += v
	for i in dry:
		wet.erase(i)
