class_name RoomSystem
extends RefCounted
## Cuenta cuántas celdas válidas tiene cada tipo de cámara: deben ser túnel y estar conectadas
## al nido (nest_dist < FAR). Simplificación de la Fase 1: no exige que formen un bloque
## contiguo con una forma concreta, solo que existan suficientes y que no queden aisladas tras
## un derrumbe de conectividad. El tamaño mínimo decide si la cámara está "activa".

var world: WorldGrid
var fields: NestDistanceField
var cfg: SimConfig
var counts: Array[int] = [0, 0, 0, 0]
var valid: Array[bool] = [false, false, false, false]
var _seen_rooms_version := -1
var _seen_terrain_recomputes := -1


func _init(w: WorldGrid, f: NestDistanceField, c: SimConfig) -> void:
	world = w
	fields = f
	cfg = c


func min_size(room_type: int) -> int:
	match room_type:
		WorldGrid.Room.ROYAL:
			return cfg.room_min_royal
		WorldGrid.Room.NURSERY:
			return cfg.room_min_nursery
		WorldGrid.Room.STORAGE:
			return cfg.room_min_storage
		_:
			return 0


## Capacidad total de una cámara (tamaño x efecto por celda), 0 si no es válida.
func capacity(room_type: int, per_cell: float) -> float:
	return float(counts[room_type]) * per_cell if valid[room_type] else 0.0


## Se llama cada tick; solo recalcula si algo relevante cambió (como `dig_dist`/`nest_dist`).
func maybe_recompute() -> void:
	if world.rooms_version == _seen_rooms_version and fields.recomputes == _seen_terrain_recomputes:
		return
	_seen_rooms_version = world.rooms_version
	_seen_terrain_recomputes = fields.recomputes
	for k in 4:
		counts[k] = 0
	for i in world.room.size():
		var r := world.room[i]
		if r == WorldGrid.Room.NONE:
			continue
		if world.cells[i] != WorldGrid.Cell.TUNNEL:
			continue
		if fields.nest_dist[i] >= NestDistanceField.FAR:
			continue
		counts[r] += 1
	for r in 4:
		valid[r] = counts[r] >= min_size(r)
