extends SceneTree
## Pruebas de la Fase 19: árbol gigante y bolsones de hongos bajo tierra ("Juego normal").
## Uso: godot --headless --path . --script tools/test_phase19.gd      (código de salida 1 si algo falla)

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_t_generation()
	_t_classic_layout_unchanged()
	_t_unreachable_pocket_is_ignored()
	_t_connected_pocket_is_harvested()
	_t_regrow_rules()
	_t_save_load_keeps_kinds()
	_t_flooded_pocket_is_skipped()
	_t_fog()
	_t_trees_first()
	_t_egg_rebalance()
	print("RESULTADO: %d correctas, %d fallidas" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("[%s] %s %s" % ["OK " if ok else "FALLA", label, detail])


func _cfg() -> SimConfig:
	var c := SimConfig.new()
	c.rain_auto = false
	return c


func _fresh(seed_value: int) -> Simulation:
	var sim := Simulation.new(_cfg(), seed_value)
	sim.spawn_incremental_start(true)
	return sim


func _of_kind(sim: Simulation, kind: int) -> Array[Plant]:
	var out: Array[Plant] = []
	for p in sim.plants:
		if p.kind == kind:
			out.append(p)
	return out


func _t_generation() -> void:
	var ok_giants := true
	var ok_pockets := true
	var ok_closed := true
	var ok_layer := true
	for s in [1, 2, 3, 4, 5]:
		var sim := _fresh(s)
		var giants := _of_kind(sim, Plant.Kind.GIANT)
		var mush := _of_kind(sim, Plant.Kind.MUSHROOM)
		# Fase 29 (cambio intencional): los gigantes sueltos se reemplazaron por un solo árbol madre
		# encima del nido (ver tools/test_phase29.gd).
		ok_giants = ok_giants and giants.is_empty() and sim.home_tree != null
		ok_pockets = ok_pockets and mush.size() >= sim.cfg.mushroom_pockets_min and mush.size() <= sim.cfg.mushroom_pockets_max
		for m in mush:
			ok_closed = ok_closed and sim.fields.nest_dist[m.cell.y * sim.world.w + m.cell.x] >= NestDistanceField.FAR
			ok_layer = ok_layer and m.cell.y > sim.cfg.surface_y and m.cell.y < sim.cfg.surface_y + 18 and not m.pocket.is_empty()
	_check("en vez de gigantes sueltos, un solo árbol madre sobre el nido (Fase 29)", ok_giants)
	_check("hay 3-5 bolsones de hongos", ok_pockets)
	_check("los bolsones arrancan cerrados (sin camino desde el nido)", ok_closed)
	_check("los bolsones están en la primera capa de tierra", ok_layer)


func _t_classic_layout_unchanged() -> void:
	var sim := Simulation.new(_cfg(), 1)
	sim.spawn_incremental_start()
	_check("sin mapa al azar (pruebas, Nivel 0) no hay gigantes ni hongos",
		_of_kind(sim, Plant.Kind.GIANT).is_empty() and _of_kind(sim, Plant.Kind.MUSHROOM).is_empty())


## Cava a mano un túnel de la cámara del nido hasta el bolsón: primero en horizontal por la fila de
## la cámara y después en vertical hasta el piso del bolsón.
func _connect(sim: Simulation, m: Plant) -> void:
	var w := sim.world
	var y0 := sim.cfg.surface_y + sim.cfg.shaft_depth + 1
	var x := sim.cfg.nest_x
	var step := signi(m.cell.x - x)
	while x != m.cell.x:
		x += step
		w.cells[y0 * w.w + x] = WorldGrid.Cell.TUNNEL
	var y := y0
	var ystep := signi(m.cell.y - y0)
	while y != m.cell.y:
		y += ystep
		w.cells[y * w.w + x] = WorldGrid.Cell.TUNNEL
	w.passable_version += 1
	sim.fields.recompute_terrain()
	sim.fields.recompute_dig()


func _nearest_pocket(sim: Simulation) -> Plant:
	var best: Plant = null
	for m in _of_kind(sim, Plant.Kind.MUSHROOM):
		if best == null or absi(m.cell.x - sim.cfg.nest_x) < absi(best.cell.x - sim.cfg.nest_x):
			best = m
	return best


func _t_unreachable_pocket_is_ignored() -> void:
	var sim := _fresh(7)
	for i in int(40.0 * sim.cfg.tick_rate):
		sim.tick()
	var taken := 0
	for m in _of_kind(sim, Plant.Kind.MUSHROOM):
		taken += m.max_leaves - m.leaves
	_check("sin túnel hasta los hongos nadie los toca", taken == 0, "hongos tomados=%d" % taken)


func _t_connected_pocket_is_harvested() -> void:
	var sim := _fresh(7)
	var m := _nearest_pocket(sim)
	_connect(sim, m)
	_check("el bolsón ya tiene camino desde el nido", sim.fields.nest_dist[m.cell.y * sim.world.w + m.cell.x] < NestDistanceField.FAR)
	var d0 := sim.delivered
	for i in int(90.0 * sim.cfg.tick_rate):
		sim.tick()
	_check("con el nido todavía cerrado arriba, las obreras cosechan el bolsón conectado",
		m.leaves < m.max_leaves and sim.delivered > d0, "hongos tomados=%d, entregas=%d" % [m.max_leaves - m.leaves, sim.delivered - d0])


func _t_regrow_rules() -> void:
	var sim := _fresh(8)
	var m := _of_kind(sim, Plant.Kind.MUSHROOM)[0]
	# Desde la Fase 29 el mapa al azar no trae otros árboles (`home_tree_other_trees = 0`): se
	# plantan a mano un árbol normal y un gigante para comparar cómo rebrotan.
	var t := Plant.new(Vector2i(10, sim.cfg.surface_y - 1), 20)
	var g := Plant.new(Vector2i(20, sim.cfg.surface_y - 1), 20)
	g.kind = Plant.Kind.GIANT
	sim.plants.append_array([t, g])
	m.leaves = 0
	t.leaves = 0
	# De noche: el hongo rebrota, el árbol no.
	sim.tick_count = int(0.8 * sim.cfg.day_length_s / sim.dt)
	sim.econ.regrow_plants(60.0)
	_check("de noche los hongos rebrotan y los árboles no", m.leaves > 0 and t.leaves == 0, "hongo=%d árbol=%d" % [m.leaves, t.leaves])
	# De día: el gigante rebrota más rápido que un árbol normal.
	sim.tick_count = int(0.25 * sim.cfg.day_length_s / sim.dt)
	g.leaves = 0
	t.leaves = 0
	g.regrow_acc = 0.0
	t.regrow_acc = 0.0
	for k in 100:
		sim.econ.regrow_plants(1.0)
	_check("el gigante rebrota más rápido que un árbol normal", g.leaves > t.leaves, "gigante=%d normal=%d" % [g.leaves, t.leaves])


func _t_save_load_keeps_kinds() -> void:
	var sim := _fresh(9)
	var data := SaveSystem.to_dict(sim)
	var back := SaveSystem.from_dict(data, sim.cfg)
	var same := back != null and back.plants.size() == sim.plants.size()
	if same:
		for k in sim.plants.size():
			same = same and back.plants[k].kind == sim.plants[k].kind and back.plants[k].hue == sim.plants[k].hue \
				and back.plants[k].pocket.size() == sim.plants[k].pocket.size()
	_check("guardar/cargar conserva gigantes y bolsones (tipo, color y cueva)", same)


## Fase 22: con la cueva inundada, las obreras no se quedan dando vueltas intentando llegar a los
## hongos (el camino esquiva el agua: el bolsón queda inalcanzable); cuando baja, vuelven a cosechar.
func _t_flooded_pocket_is_skipped() -> void:
	var sim := _fresh(7)
	# Sin árbol ni comida en el suelo: esta prueba cuenta obreras que van a comer, y lo que cae del
	# árbol madre es un destino legítimo (Fase 32) que no tiene que ver con la cueva inundada.
	sim.home_tree = null
	sim.corpses.clear()
	var m := _nearest_pocket(sim)
	_connect(sim, m)
	var w := sim.world
	var heading_there := 0
	for t in int(25.0 * sim.cfg.tick_rate):
		for c in m.pocket:
			var i := c.y * w.w + c.x
			if sim.water.level[i] < 0.9:
				sim.water.add(i, 0.95 - sim.water.level[i])
		sim.tick()
	for a in sim.ants.count:
		if sim.ants.alive[a] == 1 and sim.ants.state[a] == AntSystem.State.GO_TO_FOOD:
			heading_there += 1
	var nest_i := (sim.cfg.surface_y + sim.cfg.shaft_depth + 1) * w.w + sim.cfg.nest_x
	_check("con la cueva inundada, el bolsón figura inalcanzable", sim.ants.mushroom_route(m)[nest_i] >= NestDistanceField.FAR)
	_check("con la cueva inundada, ninguna obrera se queda intentando ir", heading_there == 0, "yendo a comer=%d" % heading_there)
	sim.water.clear()
	var taken0 := m.max_leaves - m.leaves
	for t in int(60.0 * sim.cfg.tick_rate):
		sim.tick()
	_check("cuando baja el agua, vuelven a cosechar el bolsón", m.max_leaves - m.leaves > taken0, "tomados antes=%d después=%d" % [taken0, m.max_leaves - m.leaves])


## Fase 24: niebla bajo tierra. Los bolsones arrancan sin descubrir y se descubren al cavar cerca.
func _t_fog() -> void:
	var sim := _fresh(7)
	var w := sim.world
	_check("hay niebla en Juego normal con mapa al azar", sim.fog != null)
	var hidden := true
	for m in _of_kind(sim, Plant.Kind.MUSHROOM):
		hidden = hidden and not sim.is_discovered(m)
	_check("los bolsones arrancan ocultos", hidden)
	var nest_i: int = (sim.cfg.surface_y + sim.cfg.shaft_depth + 1) * w.w + sim.cfg.nest_x
	_check("el nido y la superficie se ven", sim.fog.is_revealed(nest_i) and sim.fog.is_revealed((sim.cfg.surface_y - 1) * w.w + 3))
	var m := _nearest_pocket(sim)
	_connect(sim, m)
	sim.tick()
	_check("al cavar hasta el bolsón, se descubre", sim.is_discovered(m))
	var back := SaveSystem.from_dict(SaveSystem.to_dict(sim), sim.cfg)
	_check("guardar/cargar conserva la niebla", back.fog != null and back.is_discovered(back.plants[sim.plants.find(m)]))
	var classic := Simulation.new(_cfg(), 7)
	classic.spawn_incremental_start()
	_check("sin mapa al azar no hay niebla (se ve todo)", classic.fog == null)


## Fase 24: primero lo de arriba. Con árboles con hojas, de día y con salida a la superficie, las
## obreras no van a los hongos aunque estén más cerca; de noche sí.
func _t_trees_first() -> void:
	var sim := _fresh(7)
	var m := _nearest_pocket(sim)
	_connect(sim, m)
	# Abrir el pozo hacia la superficie (el nido arranca cerrado en este modo).
	var w := sim.world
	for y in range(sim.cfg.surface_y, sim.cfg.surface_y + sim.cfg.shaft_depth):
		w.cells[y * w.w + sim.cfg.nest_x] = WorldGrid.Cell.TUNNEL
	w.passable_version += 1
	sim.tick_count = int(0.1 * sim.cfg.day_length_s / sim.dt)
	for i in int(60.0 * sim.cfg.tick_rate):
		sim.tick()
	_check("de día y con árboles con hojas, no se comen los hongos", m.leaves == m.max_leaves, "hongos tomados=%d" % (m.max_leaves - m.leaves))
	sim.tick_count = int(0.65 * sim.cfg.day_length_s / sim.dt)
	for i in int(60.0 * sim.cfg.tick_rate):
		sim.tick()
	_check("de noche (los árboles no rebrotan) sí van a los hongos", m.leaves < m.max_leaves, "hongos tomados=%d" % (m.max_leaves - m.leaves))


## Pocas obreras (muchos soldados) -> los huevos salen casi siempre obrera; y el HUD no cuenta rivales.
func _t_egg_rebalance() -> void:
	var sim := _fresh(11)
	sim.cmd_add_caste_ants(CasteDefs.Caste.SOLDIER, 12)
	var before := sim.econ.worker_share()
	var workers := 0
	for k in 20:
		sim.colony.food = 1000.0
		sim.econ.bought_eggs = 0
		var n := sim.brood.caste.size()
		if not sim.econ.buy_egg():
			_check("se pudo comprar el huevo", false, "queen=%s food=%.0f" % [sim.econ._queen_alive(), sim.colony.food])
			return
		if sim.brood.caste[n] == CasteDefs.Caste.WORKER:
			workers += 1
	_check("con pocas obreras los huevos salen mayormente obrera", before < 0.6 and workers >= 14, "share %.2f, obreras %d/20" % [before, workers])
	var mine: int = sim.ants.count_by_caste([CasteDefs.Caste.SOLDIER])[CasteDefs.Caste.SOLDIER]
	sim.ants.add_ant_at(Vector2i(2, sim.cfg.surface_y - 1), CasteDefs.Caste.SOLDIER, 1)
	_check("los soldados rivales no se cuentan como propios", sim.ants.count_by_caste([CasteDefs.Caste.SOLDIER])[CasteDefs.Caste.SOLDIER] == mine)
