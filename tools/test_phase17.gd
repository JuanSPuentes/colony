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
