extends RefCounted
## Decisiones (`_think_*`) específicas de una casta, separadas de `AntSystem` para que ese
## archivo no siga creciendo con cada casta nueva. Sigue siendo el mismo comportamiento de
## siempre: estas funciones operan sobre los arrays de `AntSystem` igual que antes, solo que
## ahora viven en su propio archivo (ver sección 1 de ARCHITECTURE.md: nada cambia de carpeta,
## `colony/` sigue siendo el único dueño de estos datos).
##
## `ants` no se tipa como `AntSystem` a propósito: este archivo lo carga `AntSystem` con
## `preload`, y tipar el parámetro crearía un ciclo de resolución (`AntSystem` necesitaría
## resolver `AntCasteAI`, que a su vez necesitaría resolver `AntSystem`, que todavía se está
## cargando). Por la misma razón, cada valor que sale de `ants.algo` se tipa a mano en vez de
## usar `:=` (que con `ants` como Variant no puede inferir nada): `AntSystem.State`/`Mode`/etc.
## sí se resuelven bien porque son accesos en tiempo de ejecución, no al cargar el script.

const FAR := NestDistanceField.FAR


## El zángano no pasa por `AntSystem._think()` (no pelea activo, no explora): lleva su propia
## cuenta de cuándo le toca pensar, igual que hacía antes dentro de `AntSystem`.
static func think_drone(ants, i: int, cx: int, cy: int, ci: int) -> void:
	var sim: Simulation = ants.sim
	var now := sim.tick_count
	ants.last_think[i] = now
	ants.next_think[i] = now + sim.rng.randi_range(sim.cfg.think_ticks_min, sim.cfg.think_ticks_max)
	var brood := sim.brood
	var idx: int = ants.carry_egg[i]
	if idx >= 0:
		if not brood.alive[idx] or brood.stage[idx] != BroodSystem.Stage.EGG:
			# Ya nació, murió, o avanzó a larva por su cuenta mientras lo cargaba: lo suelta donde esté.
			ants.carry_egg[i] = -1
			ants.state[i] = AntSystem.State.IDLE
			ants.target[i] = ants.pos[i]
			return
		var nursery_cell: int = sim.rooms.nursery_cell
		if nursery_cell < 0:
			# No hay Guardería (todavía): se queda esperando junto al huevo, no insiste con nada.
			ants.state[i] = AntSystem.State.CARRY_EGG
			ants.target[i] = ants.pos[i]
			return
		var dest: Vector2 = ants._center(nursery_cell % sim.world.w, nursery_cell / sim.world.w)
		ants.state[i] = AntSystem.State.CARRY_EGG
		if ants.pos[i].distance_to(dest) <= sim.cfg.soldier_melee_range_px:
			brood.pos[idx] = dest
			brood.claimed[idx] = -1
			ants.carry_egg[i] = -1
			ants.target[i] = ants.pos[i]
		else:
			ants.target[i] = dest
		return
	# Sin huevo en upa: busca el más cercano que nadie esté cargando y que no esté ya en una
	# Guardería (si ya llegó, no hace falta tocarlo de nuevo).
	var best := -1
	var best_d := INF
	for b in brood.stage.size():
		if not brood.alive[b] or brood.stage[b] != BroodSystem.Stage.EGG or brood.claimed[b] >= 0:
			continue
		if sim.rooms.nursery_cell >= 0 and ants._cell_index(brood.pos[b]) == sim.rooms.nursery_cell:
			continue  # ya está en la Guardería (o en la celda que hoy representa a la Guardería)
		var d: float = ants.pos[i].distance_to(brood.pos[b])
		if d < best_d:
			best_d = d
			best = b
	if best < 0:
		ants.state[i] = AntSystem.State.IDLE
		ants.target[i] = ants.pos[i]
		return
	brood.claimed[best] = i
	ants.carry_egg[i] = best
	ants.state[i] = AntSystem.State.CARRY_EGG
	ants.target[i] = brood.pos[best]


static func think_nurse(ants, i: int, cx: int, cy: int, ci: int) -> void:
	var sim: Simulation = ants.sim
	var cfg := sim.cfg
	var nd: int = sim.fields.nest_dist[ci]
	if nd > cfg.nurse_range and nd < FAR:
		ants.state[i] = AntSystem.State.NURSE
		ants._step(i, cx, cy, ci, AntSystem.Mode.NEST, null)
	else:
		ants.state[i] = AntSystem.State.NURSE
		ants.target[i] = ants.pos[i]  # se queda cuidando la cría cerca del nido


## Obrera y Zángano (en combate activo; el Zángano además pelea pasivo si lo alcanzan, ver
## `AntSystem.tick()`) defendiendo la colmena: igual de simple que el Soldado (acercarse y pegar),
## pero con el daño de su propia casta (`CasteDefs.DAMAGE_PER_S`), bastante menor.
## `threat` no se tipa: puede ser `Spider` o `Centipede` (ver `AntSystem._nearest_threat`), que no
## comparten clase base, solo la misma forma (`.pos`, `.take_damage()`).
static func think_defend(ants, i: int, cx: int, cy: int, ci: int, threat, think_dt: float) -> void:
	var sim: Simulation = ants.sim
	var cfg := sim.cfg
	var d: float = ants.pos[i].distance_to(threat.pos)
	ants.state[i] = AntSystem.State.ATTACK
	if d <= cfg.soldier_melee_range_px:
		ants.target[i] = ants.pos[i]
		# Fase 9: mejora de daño del bando jugador (esta función solo la llaman hormigas de ese
		# bando; las rivales pelean con su propio código en AntSystem._tick_rival).
		threat.take_damage(CasteDefs.DAMAGE_PER_S[ants.caste[i]] * think_dt * sim.upgrades.damage_mult)
	else:
		ants._step(i, cx, cy, ci, AntSystem.Mode.PLANT, threat.pos)


static func think_soldier(ants, i: int, cx: int, cy: int, ci: int, think_dt: float) -> void:
	var sim: Simulation = ants.sim
	var cfg := sim.cfg
	var threat = ants._nearest_threat(ants.pos[i], cfg.soldier_sight_px)
	if threat != null and not ants.can_reach(ants.pos[i], threat.pos):
		threat = null  # Fase 16: la ve a través de la tierra pero no puede llegar
	if threat != null:
		var d: float = ants.pos[i].distance_to(threat.pos)
		if d <= cfg.soldier_melee_range_px:
			ants.state[i] = AntSystem.State.ATTACK
			ants.target[i] = ants.pos[i]
			threat.take_damage(CasteDefs.DAMAGE_PER_S[CasteDefs.Caste.SOLDIER] * think_dt * sim.upgrades.damage_mult)
			return
		ants.state[i] = AntSystem.State.ATTACK
		ants._step(i, cx, cy, ci, AntSystem.Mode.PLANT, threat.pos)
		return
	# Fase 15: antes un soldado sin enemigo a la vista subía el rastro de Ataque hasta la punta y se
	# quedaba ahí (o dando vueltas por el rastro mientras se desvanecía) más de un minuto, sin nadie
	# a quien pegarle — el jugador lo vio como soldados "bugueados" amontonados. Ahora, al llegar a la
	# punta sin amenaza, "da por cumplida" la orden: ignora ese rastro un rato (mismo `ignore_until`
	# que usan las obreras con el de Comida; los soldados no lo usaban para nada más) y patrulla.
	if sim.tick_count >= ants.ignore_until[i]:
		var here: float = sim.attack.data[ci]
		var best := here
		for k in 8:
			best = maxf(best, sim.attack.get_v(cx + AntSystem.DX[k], cy + AntSystem.DY[k]))
		if best > 0.02:
			if best <= here + 0.001:
				ants.ignore_until[i] = sim.tick_count + int(cfg.ignore_trail_seconds * cfg.tick_rate)
			else:
				ants.state[i] = AntSystem.State.ATTACK
				ants._step(i, cx, cy, ci, AntSystem.Mode.TOWARD, sim.attack)
				return
	# Sin amenaza, el soldado patrulla libre en vez de volver a pararse junto al nido: se mueve
	# igual que una obrera explorando (misma puntuación de `Mode.EXPLORE`), solo que sin cortar
	# hojas ni cavar. Pedido explícito: antes quedaba plantado cerca de la entrada.
	ants.state[i] = AntSystem.State.GUARD
	ants._step(i, cx, cy, ci, AntSystem.Mode.EXPLORE, null)


## Sigue la BFS de `sim.queen_goal_dist` (calculada una sola vez en `cmd_move_queen`) celda a
## celda, igual de greedy que `Mode.NEST` con `nest_dist`. Se llama todo tick mientras haya una
## orden en curso (no solo cada `next_think`): es una sola hormiga, no vale la pena esperar a que
## le toque pensar para que la orden del jugador se sienta inmediata.
static func think_queen(ants, i: int, cx: int, cy: int, ci: int) -> void:
	var sim: Simulation = ants.sim
	if ci == sim.queen_goal_cell:
		sim.queen_goal_cell = -1
		ants.target[i] = ants.pos[i]
		return
	var world := sim.world
	var w: int = world.w
	var dist: PackedInt32Array = sim.queen_goal_dist
	var best_k := -1
	var best_d: int = NestDistanceField.FAR
	for k in 8:
		var nx := cx + AntSystem.DX[k]
		var ny := cy + AntSystem.DY[k]
		if not world.is_passable(nx, ny):
			continue
		if AntSystem.DX[k] != 0 and AntSystem.DY[k] != 0:
			if not world.is_passable(cx + AntSystem.DX[k], cy) or not world.is_passable(cx, cy + AntSystem.DY[k]):
				continue  # nada de cortar esquinas de tierra, igual que `_step`
		var nd: int = dist[ny * w + nx]
		if nd < best_d:
			best_d = nd
			best_k = k
	if best_k < 0 or best_d >= NestDistanceField.FAR:
		sim.queen_goal_cell = -1  # sin camino posible (p.ej. alguien tapó el túnel): cancela la orden
		ants.target[i] = ants.pos[i]
		return
	ants.target[i] = ants._center(cx + AntSystem.DX[best_k], cy + AntSystem.DY[best_k])
