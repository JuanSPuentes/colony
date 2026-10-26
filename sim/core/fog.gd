class_name Fog
extends RefCounted
## Fase 24: niebla bajo tierra ("Juego normal" con mapa al azar). El subsuelo no se conoce hasta
## que la colonia llega: una celda se descubre si está a `RADIUS` celdas o menos de un hueco
## al que las hormigas pueden llegar (conectado al nido o a la superficie). Lo descubierto queda
## descubierto aunque después se tape algo. Una cueva cerrada (un bolsón de hongos sin túnel) no se
## descubre a sí misma: hay que cavar hasta cerca de ella.
##
## Se deduce del terreno, así que no hace falta guardarla: al cargar una partida se recalcula.

## Fase 24: 0 = solo se ven los huecos mismos (túneles y cámaras conectados), no la tierra de
## alrededor; pedido del jugador: "nada de la tierra alrededor debería verse".
const RADIUS := 0
## Filas de tierra desde la superficie que siempre se ven: solo la del pasto.
const SURFACE_ROWS := 1

var revealed := PackedByteArray()
var version := 0  # sube cada vez que se descubre algo (para que la vista sepa cuándo repintar)


func _init(cells: int) -> void:
	revealed.resize(cells)


func is_revealed(i: int) -> bool:
	return revealed[i] == 1


## Recalcula qué se ve. Se llama cuando cambia el terreno (después de `fields.recompute_terrain`).
func update(world: WorldGrid, fields: NestDistanceField, surface_y: int) -> void:
	var w := world.w
	var changed := false
	for y in world.h:
		for x in w:
			var i := y * w + x
			if revealed[i] == 1:
				continue
			if y < surface_y + SURFACE_ROWS:
				revealed[i] = 1
				changed = true
	# Solo bajo tierra: el aire de arriba ya se ve siempre y es la mayor parte de lo pasable.
	for i in range(surface_y * w, world.cells.size()):
		if not world.is_passable(i % w, i / w):
			continue
		if fields.nest_dist[i] >= NestDistanceField.FAR and fields.surface_dist[i] >= NestDistanceField.FAR:
			continue
		var cx := i % w
		var cy := i / w
		for dy in range(-RADIUS, RADIUS + 1):
			for dx in range(-RADIUS, RADIUS + 1):
				var nx := cx + dx
				var ny := cy + dy
				if world.in_bounds(nx, ny) and revealed[ny * w + nx] == 0:
					revealed[ny * w + nx] = 1
					changed = true
	if changed:
		version += 1


## ¿Se ve alguna celda de esta lista? (un bolsón está descubierto si se ve alguna celda de su cueva)
func any_revealed(cells: Array[Vector2i], w: int) -> bool:
	for c in cells:
		if revealed[c.y * w + c.x] == 1:
			return true
	return false
