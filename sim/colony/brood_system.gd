class_name BroodSystem
extends RefCounted
## Cría: huevo -> larva -> pupa -> adulta (Fase 1).
## El huevo sí tiene posición física (`pos`, `claimed`): nace donde esté parada la reina y el
## Zángano lo puede cargar hasta una celda de Guardería (ver `AntSystem._think_drone`). Larva y
## pupa no se mueven solas una vez que el huevo llegó a destino (o no): la velocidad de desarrollo
## sigue siendo la misma de siempre, por colonia, no por posición individual — eso no cambió, para
## no reabrir el balance ya ajustado. Lo que sí importa de verdad para el jugador:
##  - sin nodrizas vivas la larva se desarrolla mucho más despacio;
##  - sin Guardería válida se desarrolla más despacio y puede morir si el nido se inunda a fondo;
##  - sin comida, la larva se detiene (no muere de hambre en este MVP, solo se estanca).

enum Stage { EGG, LARVA, PUPA }

var sim: Simulation
var stage: Array[int] = []
var timer: Array[float] = []
var caste: Array[int] = []
var alive: Array[bool] = []
var pos := PackedVector2Array()
## Índice de la hormiga (zángano) que está cargando este huevo ahora mismo, -1 si ninguna. Solo
## tiene sentido mientras `stage[i] == Stage.EGG`; una vez que pasa a larva, si seguía cargado
## queda suelto donde estuviera (ver `AntSystem._think_drone`).
var claimed: Array[int] = []
var counts_by_stage: Array[int] = [0, 0, 0]
var hatched := 0
var died := 0


func _init(s: Simulation) -> void:
	sim = s


func lay_egg(target_caste: int, p: Vector2) -> void:
	stage.append(Stage.EGG)
	timer.append(sim.cfg.egg_time_s)
	caste.append(target_caste)
	alive.append(true)
	pos.append(p)
	claimed.append(-1)


func total_alive() -> int:
	var n := 0
	for a in alive:
		if a:
			n += 1
	return n


func tick(dt: float) -> void:
	var cfg := sim.cfg
	var nurses_alive := 0
	var fields := sim.fields
	for i in sim.ants.count:
		if sim.ants.alive[i] == 1 and sim.ants.caste[i] == CasteDefs.Caste.NURSE:
			var ci := sim.ants._cell_index(sim.ants.pos[i])
			if fields.nest_dist[ci] <= cfg.nurse_range:
				nurses_alive += 1
	var nursery_ok := sim.rooms.valid[WorldGrid.Room.NURSERY]
	var dev_mult := 1.0
	if nurses_alive == 0:
		dev_mult = 0.4
	elif not nursery_ok:
		dev_mult = 0.65
	# Fase 3: en el modo incremental no se compran nodrizas, así que la cría no depende de ellas;
	# toda la cría (no solo la larva) avanza `inc_brood_speed` veces más rápido.
	var speed := 1.0
	if sim.incremental:
		dev_mult = 1.0
		speed = cfg.inc_brood_speed
	var flooded := sim.rooms.counts[WorldGrid.Room.NURSERY] == 0 and _nest_is_deep_flooded()
	var starved := sim.colony.food <= 0.0
	for k in 3:
		counts_by_stage[k] = 0
	for i in stage.size():
		if not alive[i]:
			continue
		if flooded and sim.rng.randf() < cfg.brood_flood_death_chance * dt:
			alive[i] = false
			died += 1
			continue
		counts_by_stage[stage[i]] += 1
		if starved and stage[i] == Stage.LARVA:
			continue  # sin comida la larva no avanza (se estanca, no muere, en este MVP)
		timer[i] -= dt * speed * (dev_mult if stage[i] == Stage.LARVA else 1.0) * maxf(CasteDefs.DEV_SPEED_MULT[caste[i]], 0.01)
		if timer[i] <= 0.0:
			_advance(i)


func _nest_is_deep_flooded() -> bool:
	var w := sim.world
	var lvl := sim.water.level
	for c in w.nest_cells:
		if lvl[c] > sim.cfg.deep_level:
			return true
	return false


func _advance(i: int) -> void:
	match stage[i]:
		Stage.EGG:
			stage[i] = Stage.LARVA
			timer[i] = sim.cfg.larva_time_s
			claimed[i] = -1  # si un zángano lo tenía en upa, lo suelta donde esté (ver _think_drone)
		Stage.LARVA:
			stage[i] = Stage.PUPA
			timer[i] = sim.cfg.pupa_time_s
		Stage.PUPA:
			alive[i] = false
			hatched += 1
			var nest := sim.world.nest_cells
			var c: int = nest[sim.rng.randi() % nest.size()]
			sim.ants.add_ant_at(Vector2i(c % sim.world.w, c / sim.world.w), caste[i])
