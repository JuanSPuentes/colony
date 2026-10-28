class_name Migration
extends RefCounted
## Fase 25: al ganar la batalla de una estación la colonia se muda a un territorio nuevo. El mapa
## (terreno, túneles, cámaras, árboles, hongos, niebla) se genera de cero con otra semilla; lo que
## la colonia ganó se conserva: comida, hormigas por casta, mejoras, precio del huevo, estación y
## estadísticas. La cría que estaba en camino llega ya nacida.
##
## No toca la `Simulation` vieja: arma una nueva con `spawn_incremental_start(true)` (el mismo
## arranque de "Juego normal") y le copia el estado que se lleva. `main.gd` la cambia por la vieja
## igual que al cargar una partida.

const CARRIED_CASTES: Array[int] = [CasteDefs.Caste.WORKER, CasteDefs.Caste.SOLDIER, CasteDefs.Caste.DRONE]


static func migrate(old: Simulation, seed_value: int) -> Simulation:
	var sim := Simulation.new(old.cfg, seed_value)
	# Fase 31: la estación va antes del arranque: la reina rival nace con la fuerza de esta estación.
	sim.season_index = old.season_index
	sim.spawn_incremental_start(true)
	# Mejoras primero: `add_ant_at` aplica `hp_mult` a las hormigas que se crean después.
	sim.upgrades.set_bought(old.upgrades.bought)
	_carry_ants(old, sim)
	sim.colony.food = old.colony.food
	sim.econ.bought_eggs = old.econ.bought_eggs
	sim.econ.auto_mode = old.econ.auto_mode
	sim.econ.food_earned = old.econ.food_earned
	# El reloj sigue: mismo día y hora, la estación nueva arranca cuando ya estaba previsto.
	sim.tick_count = old.tick_count
	sim.season_start_day = old.season_start_day
	sim.era = old.era
	sim.spiders_spawned = old.spiders_spawned
	sim.spider_next_s = old.spider_next_s
	sim.centipedes_spawned = old.centipedes_spawned
	sim.centipede_next_s = old.centipede_next_s
	sim.mantises_spawned = old.mantises_spawned
	sim.mantis_next_s = old.mantis_next_s
	sim.eggs_bought = old.eggs_bought
	sim.upgrades_bought = old.upgrades_bought
	sim.delivered = old.delivered
	sim.deaths = old.deaths
	sim.dug = old.dug
	if sim.cfg.rain_auto:
		sim.rain_start_tick = sim.tick_count + int(sim.cfg.inc_rain_first_s * sim.cfg.tick_rate)
	sim.notify("Tu colonia migró a un territorio nuevo.")
	return sim


## Reemplaza la colonia mínima del arranque por la de antes: misma cantidad por casta (más la cría
## viva, ya nacida) repartida por el nido y sus cámaras, y la reina con la misma fracción de vida.
static func _carry_ants(old: Simulation, sim: Simulation) -> void:
	var counts := old.ants.count_by_caste(CARRIED_CASTES)
	for i in old.brood.caste.size():
		if old.brood.alive[i] and counts.has(old.brood.caste[i]):
			counts[old.brood.caste[i]] += 1
	var queen_frac := 1.0
	if old.queen_id >= 0 and old.ants.alive[old.queen_id] == 1:
		queen_frac = clampf(old.ants.hp[old.queen_id] / old.ants.max_hp(old.queen_id), 0.05, 1.0)
	# Fuera las hormigas y la cría del arranque del jugador (la reina se queda: es la misma colonia;
	# las de la rival nueva, también).
	for i in sim.ants.count:
		if i != sim.queen_id and sim.ants.alive[i] == 1 and sim.ants.faction[i] == 0:  # la rival se queda
			sim.ants.alive[i] = 0
			sim.ants.alive_count -= 1  # sin `_kill`: no son muertes (ni cadáveres), solo no viajan
	sim.ants._members_dirty = true
	sim.brood = BroodSystem.new(sim)
	sim.ants.hp[sim.queen_id] = sim.ants.max_hp(sim.queen_id) * queen_frac
	var spots := _nest_spots(sim)
	var k := 0
	for c in CARRIED_CASTES:
		for n in int(counts[c]):
			sim.ants.add_ant_at(spots[k % spots.size()], c)
			k += 1
	sim.ants._recount()


## Celdas abiertas del nido inicial (cámara Real, Guardería, Almacén y sus pasillos).
static func _nest_spots(sim: Simulation) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var w := sim.world.w
	for i in range(sim.cfg.surface_y * w, sim.world.cells.size()):
		if sim.world.is_passable(i % w, i / w) and sim.fields.nest_dist[i] < NestDistanceField.FAR:
			out.append(Vector2i(i % w, i / w))
	# Mezcla con el rng de la simulación (no el global): misma semilla, misma mudanza.
	for i in range(out.size() - 1, 0, -1):
		var j := sim.rng.randi_range(0, i)
		var t := out[i]
		out[i] = out[j]
		out[j] = t
	return out
