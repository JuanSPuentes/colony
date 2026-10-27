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
	# Fase 14: zángano guardián. Si una amenaza llega cerca de la reina o de un huevo, suelta lo
	# que cargue y va a pelear ahí (antes solo devolvía el golpe si lo alcanzaban donde estaba).
	var guard = guard_threat(ants)
	if guard != null:
		var held: int = ants.carry_egg[i]
		if held >= 0:
			brood.claimed[held] = -1
			ants.carry_egg[i] = -1
		ants.state[i] = AntSystem.State.ATTACK
		if ants.pos[i].distance_to(guard.pos) > sim.cfg.soldier_melee_range_px:
			ants.step_along(i, cx, cy, ci, ants.path_field(ants._cell_index(guard.pos)))
		else:
			ants.target[i] = ants.pos[i]  # el golpe lo da `AntSystem.tick()` cada tick, como siempre
		return
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
			# Fase 17: por los túneles. Antes el destino era el punto final y caminaba en línea recta,
			# atravesando la tierra.
			ants.step_along(i, cx, cy, ci, ants.path_field(nursery_cell))
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
		# Fase 14: sin huevos que mover, escolta a la reina en vez de quedarse donde esté.
		ants.state[i] = AntSystem.State.IDLE
		escort_queen(ants, i, cx, cy, ci)
		return
	# Fase 17: lo recoge recién al llegar a su lado. Antes lo "cargaba" apenas lo elegía, y como el
	# huevo sigue al zángano que lo carga, saltaba de golpe hasta él; y además iba en línea recta.
	ants.state[i] = AntSystem.State.CARRY_EGG
	if ants.pos[i].distance_to(brood.pos[best]) <= sim.cfg.soldier_melee_range_px:
		brood.claimed[best] = i
		ants.carry_egg[i] = best
		ants.target[i] = ants.pos[i]
	else:
		ants.step_along(i, cx, cy, ci, ants.path_field(ants._cell_index(brood.pos[best])))


## La amenaza cerca de la reina contra la que salen los zánganos, o null. Fase 17: "cerca" se mide
## por los túneles (`AntSystem.queen_field`), no en línea recta. Antes una rival caminando por la
## superficie, justo encima de la cámara, contaba como cerca: los zánganos soltaban los huevos que
## llevaban a la Guardería e intentaban ir hacia ella a través de la tierra, pegados a la pared.
## Los huevos nacen al lado de la reina y la Guardería queda junto a la Real, así que este radio
## (`cfg.drone_guard_cells` por los túneles) también los cubre a ellos.
static func guard_threat(ants):
	var sim: Simulation = ants.sim
	if sim.queen_id < 0 or ants.alive[sim.queen_id] == 0:
		return null
	var t = ants._nearest_threat(ants.pos[sim.queen_id], sim.cfg.drone_guard_px)
	if t == null:
		return null
	var dist: PackedInt32Array = ants.queen_field()
	var tc: int = ants._cell_index(t.pos)
	if tc < 0 or tc >= dist.size() or dist[tc] > sim.cfg.drone_guard_cells:
		return null
	return t


## Fase 14: se queda a unas celdas de la reina; si se aleja, vuelve (por el nido si está lejos).
static func escort_queen(ants, i: int, cx: int, cy: int, ci: int) -> void:
	var sim: Simulation = ants.sim
	if sim.queen_id < 0 or ants.alive[sim.queen_id] == 0:
		ants.target[i] = ants.pos[i]
		return
	var q: Vector2 = ants.pos[sim.queen_id]
	if ants.pos[i].distance_to(q) <= 3.0 * sim.cfg.cell_px:
		ants.target[i] = ants.pos[i]
		return
	# Por los túneles, no en línea recta (en línea recta se trababa contra la tierra).
	ants.step_along(i, cx, cy, ci, ants.queen_field())


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
	if sim.rival_colony.fighting() and battle_formation(ants, i, cx, cy, ci):
		return
	ants.state[i] = AntSystem.State.GUARD
	patrol(ants, i, cx, cy, ci, think_dt)


## Fase 17: durante la batalla de fin de estación los soldados no patrullan sueltos: primero se
## reúnen en la entrada del nido y después marchan juntos hacia la reina rival (ver
## `RivalColony.marching`). Pelean con lo que se crucen igual que siempre: eso lo decide
## `think_soldier` antes de llegar acá. Devuelve false si no hay a dónde ir (nido cerrado).
static func battle_formation(ants, i: int, cx: int, cy: int, ci: int) -> bool:
	var sim: Simulation = ants.sim
	var cfg := sim.cfg
	var rival := sim.rival_colony
	var rc: int = ants.rally_cell()
	if rc < 0:
		return false  # el nido no tiene salida: no hay forma de salir a pelear
	var on_surface := cy < cfg.surface_y
	ants.state[i] = AntSystem.State.ATTACK
	if not on_surface:
		# Salir primero, por los túneles (misma tendencia hacia afuera que una obrera explorando).
		ants._step(i, cx, cy, ci, AntSystem.Mode.EXPLORE, null)
		return true
	if rival.marching and rival.queen.alive:
		ants._step(i, cx, cy, ci, AntSystem.Mode.PLANT, rival.queen.pos)
		return true
	var rp: Vector2 = ants._center(rc % sim.world.w, rc / sim.world.w)
	if ants.pos[i].distance_to(rp) <= cfg.cell_px:
		ants.target[i] = ants.pos[i]
	else:
		ants._step(i, cx, cy, ci, AntSystem.Mode.PLANT, rp)
	return true

## Fase 14: patrulla de verdad. Antes el soldado "exploraba" con la misma puntuación que una obrera
## (atraído por la feromona de comida, repelido por la de hogar) y terminaba yendo y viniendo por
## la misma franja junto al rastro. Ahora elige un punto al azar a lo ancho del mapa (Fase 31: de su
## mitad, si la rival vive en el mapa), camina por la superficie hasta llegar, y elige otro; de vez
## en cuando vuelve a revisar el nido.
static func patrol(ants, i: int, cx: int, cy: int, ci: int, think_dt: float) -> void:
	var sim: Simulation = ants.sim
	var cfg := sim.cfg
	ants.timer[i] -= think_dt
	var px: int = ants.patrol_x[i]
	if px == -2:
		# Revisando el nido: entra, se queda un rato y vuelve a salir.
		if sim.fields.nest_dist[ci] > 0 and sim.fields.nest_dist[ci] < FAR and ants.timer[i] > 0.0:
			ants._step(i, cx, cy, ci, AntSystem.Mode.NEST, null)
			return
		if ants.timer[i] > 0.0:
			ants.target[i] = ants.pos[i]
			return
		px = -1
	var on_surface := cy < cfg.surface_y
	if px < 0 or ants.timer[i] <= 0.0 or (on_surface and absi(cx - px) <= 1):
		if sim.rng.randf() < cfg.soldier_nest_check_chance:
			ants.patrol_x[i] = -2
			ants.timer[i] = cfg.soldier_nest_check_s
			ants._step(i, cx, cy, ci, AntSystem.Mode.NEST, null)
			return
		# Fase 31: con la rival en el mapa, solo su mitad (hasta el árbol) mientras no haya ataque.
		var span: Vector2i = sim.rival_colony.player_patrol_range()
		px = sim.rng.randi_range(span.x, span.y)
		ants.patrol_x[i] = px
		ants.timer[i] = cfg.soldier_patrol_timeout_s
	if not on_surface:
		# Bajo tierra, salir primero (misma tendencia hacia afuera que una obrera explorando).
		ants._step(i, cx, cy, ci, AntSystem.Mode.EXPLORE, null)
		return
	ants._step(i, cx, cy, ci, AntSystem.Mode.PLANT, ants._center(px, cfg.surface_y - 1))


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
