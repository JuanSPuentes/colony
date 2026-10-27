extends SceneTree
## Pruebas de la Fase 17: los soldados ganan la batalla de fin de estación en formación (antes
## llegaban de a uno y morían sin tocar a la reina rival), los zánganos no salen por una rival que
## camina encima de la cámara a través de la tierra, y Juego normal arranca con Real, Guardería y
## Almacén, con la comida entregada en el Almacén.
## Uso: godot --headless --path . --script tools/test_phase17.gd      (código de salida 1 si algo falla)

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_t_battle_won_in_formation()
	_t_closed_nest_warns()
	_t_drones_ignore_rival_through_dirt()
	_t_drones_defend_inside_the_nest()
	_t_starting_chambers()
	_t_food_goes_to_storage()
	_t_classic_still_delivers_to_nest()
	_t_save_keeps_formation()
	_t_closed_nest_workers_dig_late_marks()
	_t_drones_stay_in_tunnels()
	_t_seasons_last_full_length()
	_t_season_lengths()
	_t_spider_stays_on_surface()
	_t_hp_percent_counts_upgrade()
	print("RESULTADO: %d correctas, %d fallidas" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("[%s] %s %s" % ["OK " if ok else "FALLA", label, detail])


func _cfg() -> SimConfig:
	var c: SimConfig = load("res://sim/core/default_config.tres")
	c = c.duplicate()
	c.rain_auto = false
	# Fase 29: el juego ya no pone árboles chicos; estas pruebas pintan un rastro hasta uno.
	c.home_tree_other_trees = 4
	return c


## Juego normal con el nido cerrado al empezar y el pozo ya abierto por el jugador.
func _opened(seed_v: int) -> Simulation:
	var cfg := _cfg()
	var sim := Simulation.new(cfg, seed_v)
	sim.spawn_incremental_start(true)
	var y := cfg.surface_y + cfg.shaft_depth - 1
	while y >= cfg.surface_y:
		var i := y * sim.world.w + cfg.nest_x
		sim.world.cells[i] = WorldGrid.Cell.MARKED
		sim.world.marked_count += 1
		sim.world.complete_dig(i)
		y -= 1
	sim.tick()
	return sim


func _t_battle_won_in_formation() -> void:
	var sim := _opened(12345)
	sim.cmd_add_caste_ants(CasteDefs.Caste.SOLDIER, 8)
	sim.rival_colony.start_battle(6, 1.0)
	var start_soldiers := _my_soldiers(sim)
	var t := 0
	while sim.rival_colony.battle_active and t < 120 * sim.cfg.tick_rate:
		sim.tick()
		t += 1
	var left := _my_soldiers(sim)
	_check("los soldados en formación matan a la reina rival", sim.rival_colony.battle_won, "en %.0f s" % (t * sim.dt))
	_check("y la mayoría sobrevive (antes morían todos sin tocarla)", left * 2 >= start_soldiers, "%d de %d" % [left, start_soldiers])
	_check("salieron juntos (la formación pasó a marchar)", sim.rival_colony.marching)


## Solo los del jugador (`count_by_caste` cuenta también a las rivales, que son soldados).
func _my_soldiers(sim: Simulation) -> int:
	var n := 0
	for i in sim.ants.count:
		if sim.ants.alive[i] == 1 and sim.ants.faction[i] == 0 and sim.ants.caste[i] == CasteDefs.Caste.SOLDIER:
			n += 1
	return n


func _t_closed_nest_warns() -> void:
	var cfg := _cfg()
	var sim := Simulation.new(cfg, 3)
	sim.spawn_incremental_start(true)
	sim.rival_colony.start_battle(3, 1.0)
	var warned := false
	for n in sim.notifications:
		warned = warned or n.contains("Abre el nido")
	_check("con el nido cerrado, la batalla avisa que hay que abrirlo", warned)


func _t_drones_ignore_rival_through_dirt() -> void:
	var sim := _opened(7)
	var cfg := sim.cfg
	var q := sim.ants.pos[sim.queen_id]
	var d := sim.ants.add_ant_at(Vector2i(int(q.x / cfg.cell_px) - 1, int(q.y / cfg.cell_px)), CasteDefs.Caste.DRONE)
	sim.rival_colony.start_battle(1, 1.0)
	var r := sim.ants.count - 1
	# La rival camina por la superficie justo encima de la reina: en línea recta está cerca, pero por
	# los túneles hay que salir por el pozo y bajar.
	var above := Vector2(q.x + cfg.cell_px * 3.0, (cfg.surface_y - 0.5) * cfg.cell_px)
	var left_post := false
	for t in 6 * cfg.tick_rate:
		sim.ants.pos[r] = above
		sim.ants.target[r] = above
		sim.tick()
		left_post = left_post or sim.ants.state[d] == AntSystem.State.ATTACK
	_check("una rival encima de la cámara (a través de la tierra) no saca al zángano", not left_post,
		"distancia en línea recta %.0f px" % q.distance_to(above))


func _t_drones_defend_inside_the_nest() -> void:
	var sim := _opened(8)
	var cfg := sim.cfg
	var q := sim.ants.pos[sim.queen_id]
	var d := sim.ants.add_ant_at(Vector2i(int(q.x / cfg.cell_px) - 2, int(q.y / cfg.cell_px)), CasteDefs.Caste.DRONE)
	sim.rival_colony.start_battle(1, 1.0)
	var r := sim.ants.count - 1
	var inside := q + Vector2(cfg.cell_px * 2.0, 0.0)
	var defended := false
	for t in 6 * cfg.tick_rate:
		sim.ants.pos[r] = inside
		sim.ants.target[r] = inside
		sim.ants.hp[r] = 999.0
		sim.tick()
		defended = defended or sim.ants.state[d] == AntSystem.State.ATTACK
	_check("una rival dentro del nido, junto a la reina, sí lo hace salir a defender", defended)


func _t_starting_chambers() -> void:
	var cfg := _cfg()
	var sim := Simulation.new(cfg, 11)
	sim.spawn_incremental_start(true)
	sim.tick()
	var v := sim.rooms.valid
	_check("Juego normal arranca con Real, Guardería y Almacén válidas",
		v[WorldGrid.Room.ROYAL] and v[WorldGrid.Room.NURSERY] and v[WorldGrid.Room.STORAGE])
	var plain := Simulation.new(cfg, 11)
	plain.spawn_incremental_start()
	plain.tick()
	_check("el mapa de siempre (pruebas, Nivel 0) sigue solo con la Real",
		plain.rooms.valid[WorldGrid.Room.ROYAL] and not plain.rooms.valid[WorldGrid.Room.NURSERY] and not plain.rooms.valid[WorldGrid.Room.STORAGE])


func _deliveries_by_room(sim: Simulation, seconds: float) -> Dictionary:
	var cfg := sim.cfg
	var plant: Plant = sim.plants[0]
	for p in sim.plants:
		if absi(p.cell.x - cfg.nest_x) < absi(plant.cell.x - cfg.nest_x):
			plant = p
	var dir := signi(plant.cell.x - cfg.nest_x)
	for k in range(0, absi(plant.cell.x - cfg.nest_x) + 1):
		sim.cmd_paint_phero(sim.food, cfg.nest_x + dir * k, cfg.surface_y - 1, minf(1.0, cfg.paint_start + cfg.paint_ramp * k))
	var by_room := {}
	for t in int(seconds * cfg.tick_rate):
		var was := sim.ants.carry.duplicate()
		sim.tick()
		for i in sim.ants.count:
			if i < was.size() and was[i] == 1 and sim.ants.carry[i] == 0 and sim.ants.alive[i] == 1:
				var r: int = sim.world.room[sim.ants._cell_index(sim.ants.pos[i])]
				by_room[r] = by_room.get(r, 0) + 1
	return by_room


func _t_food_goes_to_storage() -> void:
	var sim := _opened(12345)
	sim.cmd_add_caste_ants(CasteDefs.Caste.WORKER, 8)
	var by_room := _deliveries_by_room(sim, 120.0)
	var to_storage: int = by_room.get(WorldGrid.Room.STORAGE, 0)
	var total := 0
	for k in by_room:
		total += by_room[k]
	_check("en Juego normal la comida se entrega en el Almacén", total > 10 and to_storage == total, "%d de %d" % [to_storage, total])


func _t_classic_still_delivers_to_nest() -> void:
	var cfg := _cfg()
	var sim := Simulation.new(cfg, 12345)
	sim.spawn_colony_court()
	# Un Almacén designado en el modo con reina NO cambia dónde se entrega (solo sube el tope).
	var cy := cfg.surface_y + cfg.shaft_depth + 1
	sim.cmd_assign_room(cfg.nest_x + 3, cy, WorldGrid.Room.STORAGE)
	var by_room := _deliveries_by_room(sim, 60.0)
	_check("en Modo infinito la comida se sigue entregando en el nido", by_room.get(WorldGrid.Room.ROYAL, 0) > 0, str(by_room))


func _t_save_keeps_formation() -> void:
	var sim := _opened(5)
	sim.cmd_add_caste_ants(CasteDefs.Caste.SOLDIER, 3)
	sim.rival_colony.start_battle(2, 1.0)
	for t in 40:
		sim.tick()
	sim.rival_colony.marching = true
	var copy := SaveSystem.from_dict(SaveSystem.to_dict(sim), sim.cfg)
	_check("guardar/cargar conserva la formación de batalla", copy.rival_colony.marching and is_equal_approx(copy.rival_colony.rally_s, sim.rival_colony.rally_s))


## Con el nido cerrado, las obreras iniciales se iban a "explorar" (sin salida, dando vueltas para
## siempre) antes de que el jugador marcara nada, y después no cavaban lo que se marcaba: solo
## cavaban las que nacían de un huevo nuevo.
func _t_closed_nest_workers_dig_late_marks() -> void:
	var cfg := _cfg()
	var sim := Simulation.new(cfg, 4242)
	sim.spawn_incremental_start(true)
	for t in 20 * cfg.tick_rate:
		sim.tick()
	var exploring := 0
	for i in sim.ants.count:
		if sim.ants.alive[i] == 1 and sim.ants.state[i] == AntSystem.State.EXPLORE:
			exploring += 1
	_check("sin salida a la superficie nadie se queda explorando", exploring == 0, "explorando: %d" % exploring)
	var half := cfg.chamber_w / 2
	var mid := cfg.surface_y + cfg.shaft_depth + cfg.chamber_h / 2
	for side in [-1, 1]:
		for dy in range(1, 12):
			for y in [mid - dy, mid + dy]:
				if y >= cfg.surface_y:
					sim.cmd_mark(cfg.nest_x + side * (half + 1), y)
	var initial: int = sim.ants.count_by_caste([CasteDefs.Caste.WORKER])[CasteDefs.Caste.WORKER]
	var most := 0
	for t in 10 * cfg.tick_rate:
		sim.tick()
		most = maxi(most, sim.ants.state_counts[AntSystem.State.DIG])
	_check("las obreras iniciales cavan lo que se marca después", sim.dug >= 5, "cavadas en 10 s: %d" % sim.dug)
	_check("con el nido cerrado cavan todas, no solo el 35 %", most >= initial, "a la vez: %d de %d" % [most, initial])


## Los zánganos iban a la Guardería y a buscar huevos en línea recta, atravesando la tierra, y el
## huevo "saltaba" hasta el zángano apenas lo elegía (lo cargaba desde lejos).
func _t_drones_stay_in_tunnels() -> void:
	var sim := _opened(4242)
	var cfg := sim.cfg
	sim.cmd_add_caste_ants(CasteDefs.Caste.DRONE, 4)
	sim.colony.food = 2000.0
	var bad := 0
	var jumps := 0
	for t in 60 * cfg.tick_rate:
		if t % (6 * cfg.tick_rate) == 0:
			sim.cmd_buy_egg()
		var before := sim.brood.pos.duplicate()
		sim.tick()
		for b in mini(before.size(), sim.brood.pos.size()):
			if sim.brood.pos[b].distance_to(before[b]) > cfg.cell_px * 1.5:
				jumps += 1
		for i in sim.ants.count:
			if sim.ants.alive[i] == 1 and sim.ants.caste[i] == CasteDefs.Caste.DRONE:
				var c := Vector2i(sim.ants.pos[i] / cfg.cell_px)
				if not sim.world.is_passable(c.x, c.y):
					bad += 1
	_check("los zánganos nunca pisan la tierra (van por los túneles)", bad == 0, "muestras dentro de la tierra: %d" % bad)
	_check("los huevos no saltan hasta el zángano: lo recoge al llegar", jumps == 0, "saltos: %d" % jumps)


## La estación se contaba con `(día - 1) % largo`: ganar la batalla en el último día hacía que la
## siguiente estación empezara YA en su último día (otra oleada con otra reina al instante: "la reina
## revive"), y una batalla larga le acortaba los días a la siguiente.
func _t_seasons_last_full_length() -> void:
	var cfg := _cfg()
	cfg.season_days = [3, 4, 3, 3]  # cortas, para que la prueba no tarde (lo que importa es la cuenta)
	var sim := Simulation.new(cfg, 21)
	sim.spawn_incremental_start()
	var per_day := int(cfg.day_length_s / sim.dt)
	var guard := 0
	while not sim.rival_colony.battle_active and guard < per_day * (cfg.season_days[0] + 1):
		sim.tick()
		guard += 1
	var battle_day := sim.day_number()
	_check("la primera batalla llega el último día de la estación", sim.rival_colony.battle_active and battle_day == cfg.season_days[0], "día %d" % battle_day)
	sim.rival_colony.queen.take_damage(9999.0)
	var new_battle := false
	for t in 40:
		sim.tick()
		new_battle = new_battle or sim.rival_colony.battle_active
	_check("ganarla el último día no trae otra oleada al instante", not new_battle and sim.season_index == 1)
	_check("la reina rival no revive", not sim.rival_colony.queen.alive)
	guard = 0
	while not sim.rival_colony.battle_active and guard < per_day * (cfg.season_days[1] + 3):
		sim.tick()
		guard += 1
	_check("la estación siguiente dura sus %d días completos (cada una tiene su propia duración)" % cfg.season_days[1],
		sim.rival_colony.battle_active and sim.day_number() - battle_day == cfg.season_days[1],
		"batalla 1 el día %d, batalla 2 el día %d" % [battle_day, sim.day_number()])
	var copy := SaveSystem.from_dict(SaveSystem.to_dict(sim), cfg)
	_check("guardar/cargar conserva el inicio de la estación", copy.season_start_day == sim.season_start_day)


func _t_season_lengths() -> void:
	var cfg := _cfg()
	_check("las estaciones duran 20, 15, 25 y 15 días", cfg.season_days == [20, 15, 25, 15], str(cfg.season_days))


## La araña seguía a su presa en línea recta cuando se metía por el pozo: entraba al nido a
## través de la tierra. Caso forzado: la araña elige una obrera en la superficie, junto a la entrada,
## y esa obrera baja por el pozo.
func _t_spider_stays_on_surface() -> void:
	var cfg := _cfg()
	var sim := Simulation.new(cfg, 33)
	sim.spawn_incremental_start()  # la araña actúa siempre en este modo; un solo soldado, no huye
	sim.cmd_force_spider()
	var surface_px := float(cfg.surface_y * cfg.cell_px)
	var px := float(cfg.cell_px)
	sim.spider.pos = Vector2((cfg.nest_x - 6 + 0.5) * px, (cfg.surface_y - 0.5) * px)
	var bait := sim.ants.add_ant_at(Vector2i(cfg.nest_x, cfg.surface_y - 1))
	sim.ants.hp[bait] = 1.0e6  # que no muera: lo que importa es a dónde la sigue la araña
	var top := Vector2((cfg.nest_x + 0.5) * px, (cfg.surface_y - 0.5) * px)
	# Arriba, junto a la entrada, hasta que la araña la elige como presa.
	var guard := 0
	while sim.spider.target_ant != bait and guard < 200:
		sim.ants.pos[bait] = top
		sim.ants.target[bait] = top
		sim.tick()
		guard += 1
	var chosen := sim.spider.target_ant == bait
	var lowest := 0.0
	for t in 30 * cfg.tick_rate:
		# Después baja por el pozo del nido y se queda adentro.
		var depth := minf(float(cfg.shaft_depth), 0.5 + t / 10.0)
		sim.ants.pos[bait] = Vector2(top.x, (cfg.surface_y + depth) * px)
		sim.ants.target[bait] = sim.ants.pos[bait]
		sim.tick()
		if sim.spider.alive:
			lowest = maxf(lowest, sim.spider.pos.y)
	_check("la araña llegó a elegir a la obrera como presa (si no, la prueba no prueba nada)", chosen)
	_check("la araña no sigue a su presa por el pozo (no entra al nido)", lowest < surface_px,
		"y más baja %.0f px, superficie en %.0f px" % [lowest, surface_px])


## Con la mejora de Vida comprada, una hormiga sana figuraba con 115 % (se medía contra la vida base).
func _t_hp_percent_counts_upgrade() -> void:
	var cfg := _cfg()
	var sim := Simulation.new(cfg, 34)
	sim.spawn_incremental_start()
	sim.colony.food = 1.0e6
	sim.cmd_buy_upgrade(Upgrades.Stat.HP)
	sim.cmd_buy_upgrade(Upgrades.Stat.HP)
	var w := sim.ants.add_ant_at(Vector2i(cfg.nest_x, cfg.surface_y + cfg.shaft_depth + 1))
	var pct_new := 100.0 * sim.ants.hp[w] / sim.ants.max_hp(w)
	var q := sim.queen_id
	var pct_queen := 100.0 * sim.ants.hp[q] / sim.ants.max_hp(q)
	_check("una hormiga sana con la mejora de Vida se ve al 100 %", is_equal_approx(pct_new, 100.0) and is_equal_approx(pct_queen, 100.0),
		"nueva %.0f %%, reina %.0f %%" % [pct_new, pct_queen])
