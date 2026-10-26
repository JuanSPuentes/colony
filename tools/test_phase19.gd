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
		ok_giants = ok_giants and giants.size() >= sim.cfg.giant_count_min and giants.size() <= sim.cfg.giant_count_max
		for g in giants:
			ok_giants = ok_giants and absi(g.cell.x - sim.cfg.nest_x) >= sim.cfg.giant_min_dist and g.max_leaves > sim.cfg.leaves_per_plant * 3
		ok_pockets = ok_pockets and mush.size() >= sim.cfg.mushroom_pockets_min and mush.size() <= sim.cfg.mushroom_pockets_max
		for m in mush:
			ok_closed = ok_closed and sim.fields.nest_dist[m.cell.y * sim.world.w + m.cell.x] >= NestDistanceField.FAR
			ok_layer = ok_layer and m.cell.y > sim.cfg.surface_y and m.cell.y < sim.cfg.surface_y + 18 and not m.pocket.is_empty()
	_check("hay 1-2 árboles gigantes, lejos del nido y con muchas más hojas", ok_giants)
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
	var g := _of_kind(sim, Plant.Kind.GIANT)[0]
	var t: Plant = _of_kind(sim, Plant.Kind.TREE)[0]
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
