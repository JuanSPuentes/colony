class_name WorldGrid
extends RefCounted
## Terreno en una cuadrícula, excavación y conectividad. Una hormiga puede estar en una celda
## "pasable": túnel, o aire dentro de la franja baja sobre el suelo.

enum Cell { AIR, DIRT, ROCK, TUNNEL, MARKED }
## Cámaras que el jugador designa sobre túneles ya excavados (Fase 1). Simplificación del MVP:
## una cámara es "todas las celdas de túnel con esa etiqueta conectadas al nido", no exige una
## forma contigua concreta; lo que importa para el efecto es el tamaño total y la conexión.
enum Room { NONE, ROYAL, NURSERY, STORAGE, FUNGUS, DRAIN }
const ROOM_NAMES: Array[String] = ["(ninguna)", "Real", "Guardería", "Almacén", "Jardín de hongos", "Drenaje"]

var cfg: SimConfig
var w := 0
var h := 0
var cells := PackedByteArray()
## Celdas cuyo aspecto cambió desde la última vez que la vista las leyó.
var changed: PackedInt32Array = PackedInt32Array()
## Sube cada vez que cambia lo que es pasable (la vista y los campos de distancia lo usan).
var passable_version := 0
## Para cada celda marcada: id de la hormiga que la cava (-1 libre) y progreso.
var job_claim := PackedInt32Array()
var job_progress := PackedFloat32Array()
var marked_count := 0
var jobs_version := 0
var nest_cells: Array[int] = []

## Etiqueta de cámara por celda (Fase 1). Solo tiene sentido sobre Cell.TUNNEL.
var room := PackedByteArray()
var rooms_version := 0


func _init(config: SimConfig) -> void:
	cfg = config
	w = cfg.grid_w
	h = cfg.grid_h
	cells.resize(w * h)
	job_claim.resize(w * h)
	job_claim.fill(-1)
	job_progress.resize(w * h)
	room.resize(w * h)


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h


func type_at(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return Cell.ROCK
	return cells[y * w + x]


func is_passable(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= w or y >= h:
		return false
	var t := cells[y * w + x]
	if t == Cell.TUNNEL:
		return true
	return t == Cell.AIR and y >= cfg.surface_y - cfg.walk_band


## Aire o túnel: el agua puede estar ahí y se puede marcar tierra junto a ello.
func is_open(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= w or y >= h:
		return false
	var t := cells[y * w + x]
	return t == Cell.TUNNEL or t == Cell.AIR


func generate(rng: RandomNumberGenerator) -> void:
	for y in h:
		for x in w:
			var t := Cell.DIRT
			if y < cfg.surface_y:
				t = Cell.AIR
			elif y >= h - 1:
				t = Cell.ROCK
			cells[y * w + x] = t
	# Rocas sueltas, lejos del nido inicial.
	for i in cfg.rock_clusters:
		var cx := rng.randi_range(3, w - 4)
		var cy := rng.randi_range(cfg.surface_y + 5, h - 3)
		if absi(cx - cfg.nest_x) < 16 and cy < cfg.surface_y + 18:
			continue
		var r := rng.randi_range(1, 3)
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if dx * dx + dy * dy <= r * r + 1 and rng.randf() < 0.9:
					var x := cx + dx
					var y := cy + dy
					if in_bounds(x, y) and cells[y * w + x] == Cell.DIRT:
						cells[y * w + x] = Cell.ROCK
	# Entrada, túnel inicial y cámara.
	var sy := cfg.surface_y
	for y in range(sy, sy + cfg.shaft_depth):
		cells[y * w + cfg.nest_x] = Cell.TUNNEL
	var cy0 := sy + cfg.shaft_depth
	var half := cfg.chamber_w / 2
	nest_cells.clear()
	for y in range(cy0, cy0 + cfg.chamber_h):
		for x in range(cfg.nest_x - half, cfg.nest_x - half + cfg.chamber_w):
			cells[y * w + x] = Cell.TUNNEL
			nest_cells.append(y * w + x)
	# La cámara inicial ya es la Real: la colonia arranca con la reina alojada (Fase 1).
	for c in nest_cells:
		room[c] = Room.ROYAL
	rooms_version += 1
	changed.clear()
	passable_version += 1


# --- Excavación -----------------------------------------------------------------------------

func can_mark(x: int, y: int) -> bool:
	if not in_bounds(x, y) or cells[y * w + x] != Cell.DIRT:
		return false
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = x + d.x
		var ny: int = y + d.y
		if is_open(nx, ny) or type_at(nx, ny) == Cell.MARKED:
			return true
	return false


func mark(x: int, y: int) -> bool:
	if not can_mark(x, y):
		return false
	var i := y * w + x
	cells[i] = Cell.MARKED
	job_claim[i] = -1
	job_progress[i] = 0.0
	marked_count += 1
	jobs_version += 1
	changed.append(i)
	return true


func unmark(x: int, y: int) -> bool:
	if not in_bounds(x, y) or cells[y * w + x] != Cell.MARKED:
		return false
	var i := y * w + x
	cells[i] = Cell.DIRT
	job_claim[i] = -1
	job_progress[i] = 0.0
	marked_count -= 1
	jobs_version += 1
	changed.append(i)
	return true


func complete_dig(i: int) -> void:
	cells[i] = Cell.TUNNEL
	job_claim[i] = -1
	job_progress[i] = 0.0
	marked_count -= 1
	jobs_version += 1
	passable_version += 1
	changed.append(i)


func take_changed() -> PackedInt32Array:
	var out := changed
	changed = PackedInt32Array()
	return out


# --- Cámaras (Fase 1) ---------------------------------------------------------------------------

func can_assign_room(x: int, y: int) -> bool:
	return in_bounds(x, y) and cells[y * w + x] == Cell.TUNNEL


func assign_room(x: int, y: int, room_type: int) -> bool:
	if not can_assign_room(x, y):
		return false
	var i := y * w + x
	if room[i] == room_type:
		return false
	room[i] = room_type
	rooms_version += 1
	changed.append(i)
	return true


func clear_room(x: int, y: int) -> bool:
	if not in_bounds(x, y) or room[y * w + x] == Room.NONE:
		return false
	var i := y * w + x
	room[i] = Room.NONE
	rooms_version += 1
	changed.append(i)
	return true
