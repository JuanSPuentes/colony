class_name NestDistanceField
extends RefCounted
## Campos de distancia por BFS sobre las celdas pasables. Se recalculan solo cuando cambia el terreno.
##  - nest_dist: pasos hasta la cámara del nido (lo usan CARRY_HOME, IDLE y la recuperación).
##  - surface_dist: pasos hasta el suelo exterior (para que las hormigas del nido salgan a explorar).
##  - dig_dist: pasos hasta una celda desde la que se puede cavar un trabajo libre.

const FAR := 1 << 20

var world: WorldGrid
var nest_dist := PackedInt32Array()
var surface_dist := PackedInt32Array()
var dig_dist := PackedInt32Array()
## Fase 14: celdas marcadas que se pueden cavar YA (tienen al lado una celda pasable), tomadas o
## no. Un túnel largo marcado solo se cava por la punta: mandar más excavadoras que esto las hace ir
## y volver sin nada que hacer (ver `AntSystem._think_idle`).
var dig_frontier := 0
var _queue := PackedInt32Array()
var recomputes := 0
## Fase 17: pasos hasta la cámara Almacén (sus celdas pasables), para que en Juego normal las
## obreras dejen la comida ahí y no en la primera celda del nido. FAR en todo el mapa si no hay
## Almacén. Lo recalcula `Simulation.tick()` cuando cambian las cámaras o el terreno.
var storage_dist := PackedInt32Array()
## Fase 21: agua para `dig_dist`. Las obreras no cruzan agua profunda (solo huyendo, ver
## `AntSystem._step`), así que el camino hasta lo que hay que cavar la trata como pared: si la
## lluvia corta el único camino, la obrera ve que no llega y se va a buscar comida en vez de
## quedarse trabada. La pone `Simulation`; sin ella (`null`) todo funciona como antes.
var water: WaterSim
var water_block := 1.0e9


func _init(g: WorldGrid) -> void:
	world = g
	var n := g.w * g.h
	nest_dist.resize(n)
	surface_dist.resize(n)
	dig_dist.resize(n)
	storage_dist.resize(n)
	storage_dist.fill(FAR)
	_queue.resize(n)
	nest_dist.fill(FAR)
	surface_dist.fill(FAR)
	dig_dist.fill(FAR)


func recompute_terrain() -> void:
	recomputes += 1
	_bfs(world.nest_cells, nest_dist)
	var ground: Array[int] = []
	var gy := world.cfg.surface_y - 1
	for x in world.w:
		if world.is_passable(x, gy):
			ground.append(gy * world.w + x)
	_bfs(ground, surface_dist)


## Fuentes: celdas pasables vecinas (4) de cada celda marcada y libre.
func recompute_dig() -> void:
	var sources: Array[int] = []
	var seen := {}
	var w := world.w
	dig_frontier = 0
	for y in range(world.cfg.surface_y - 1, world.h):
		for x in w:
			var i := y * w + x
			if world.cells[i] == WorldGrid.Cell.MARKED:
				var open := false
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: int = x + d.x
					var ny: int = y + d.y
					if world.is_passable(nx, ny):
						open = true
						if world.job_claim[i] != -1:
							continue
						var ni: int = ny * w + nx
						if not seen.has(ni):
							seen[ni] = true
							sources.append(ni)
				if open:
					dig_frontier += 1
	_bfs(sources, dig_dist, true)


func recompute_storage() -> void:
	var sources: Array[int] = []
	for i in world.room.size():
		if world.room[i] == WorldGrid.Room.STORAGE and world.is_passable(i % world.w, i / world.w):
			sources.append(i)
	_bfs(sources, storage_dist)


## BFS puntual contra celdas pasables, para un destino que no es el nido ni la superficie (hoy lo
## usa `cmd_move_queen`: distancia de cada celda hasta la celda elegida por el jugador). A
## diferencia de `nest_dist`/`surface_dist`/`dig_dist`, no se guarda ni se recalcula solo: cada
## llamado es una BFS nueva de principio a fin.
func bfs_from(sources: Array[int], avoid_water := false) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(world.w * world.h)
	_bfs(sources, out, avoid_water)
	return out


func _bfs(sources: Array[int], out: PackedInt32Array, avoid_water := false) -> void:
	out.fill(FAR)
	var wl := water.level if avoid_water and water != null else PackedFloat32Array()
	var wet := not wl.is_empty() and water.volume > 0.0
	var w := world.w
	var h := world.h
	var head := 0
	var tail := 0
	for s in sources:
		if world.is_passable(s % w, s / w) and not (wet and wl[s] >= water_block):
			out[s] = 0
			_queue[tail] = s
			tail += 1
	while head < tail:
		var cur := _queue[head]
		head += 1
		var cx := cur % w
		var cy := cur / w
		var nd := out[cur] + 1
		if cx > 0 and out[cur - 1] > nd and world.is_passable(cx - 1, cy) and not (wet and wl[cur - 1] >= water_block):
			out[cur - 1] = nd
			_queue[tail] = cur - 1
			tail += 1
		if cx < w - 1 and out[cur + 1] > nd and world.is_passable(cx + 1, cy) and not (wet and wl[cur + 1] >= water_block):
			out[cur + 1] = nd
			_queue[tail] = cur + 1
			tail += 1
		if cy > 0 and out[cur - w] > nd and world.is_passable(cx, cy - 1) and not (wet and wl[cur - w] >= water_block):
			out[cur - w] = nd
			_queue[tail] = cur - w
			tail += 1
		if cy < h - 1 and out[cur + w] > nd and world.is_passable(cx, cy + 1) and not (wet and wl[cur + w] >= water_block):
			out[cur + w] = nd
			_queue[tail] = cur + w
			tail += 1
