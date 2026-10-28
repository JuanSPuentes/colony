extends SceneTree
## Pruebas de la Fase 25: al ganar una estación la colonia se muda a un mapa nuevo y conserva lo ganado.
## Uso: godot --headless --path . --script tools/test_phase25.gd      (código de salida 1 si algo falla)

const SeasonSystem := preload("res://sim/colony/season_system.gd")

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_t_migration()
	_t_classic_map_stays()
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


const CASTES: Array = [CasteDefs.Caste.WORKER, CasteDefs.Caste.SOLDIER, CasteDefs.Caste.DRONE]


func _t_migration() -> void:
	var sim := Simulation.new(_cfg(), 3)
	sim.spawn_incremental_start(true)
	sim.cmd_add_caste_ants(CasteDefs.Caste.SOLDIER, 5)
	sim.cmd_add_caste_ants(CasteDefs.Caste.DRONE, 2)
	sim.colony.food = 900.0
	sim.cmd_buy_upgrade(Upgrades.Id.SHELL)
	sim.cmd_buy_upgrade(Upgrades.Id.MANDIBLES)
	sim.cmd_buy_egg()
	for k in 200:
		sim.tick()
	var before := sim.ants.count_by_caste(CASTES)
	for i in sim.brood.caste.size():
		if sim.brood.alive[i]:
			before[sim.brood.caste[i]] += 1
	var food := sim.colony.food
	var day := sim.day_number()
	var old_cells := sim.world.cells.duplicate()

	SeasonSystem._advance_season(sim)
	_check("ganar la estación pide la mudanza", sim.migration_pending)
	var moved := Migration.migrate(sim, 99)
	var after := moved.ants.count_by_caste(CASTES)
	_check("se conservan las hormigas por casta (la cría llega nacida)", after == before, "%s -> %s" % [before, after])
	# Fase 31: el mapa nuevo trae también las guardias de la rival nueva (bando 1).
	var rivals := moved.cfg.rival_start_ants
	_check("el total de vivas cuadra (reina + las que viajan + guardias rivales)", moved.ants.alive_count == 1 + rivals + after.values().reduce(func(a, b): return a + b, 0), "alive_count=%d" % moved.ants.alive_count)
	_check("se conserva la comida", is_equal_approx(moved.colony.food, food))
	_check("se conservan las mejoras", moved.upgrades.bought == sim.upgrades.bought and is_equal_approx(moved.upgrades.hp_mult, sim.upgrades.hp_mult))
	_check("se conserva el precio del huevo", moved.econ.egg_cost() == sim.econ.egg_cost())
	_check("misma estación y mismo día", moved.season_index == 1 and moved.day_number() == day and moved.season_start_day == sim.season_start_day)
	_check("el mapa es otro", moved.world.cells != old_cells)
	_check("los árboles vuelven llenos", moved.plants.all(func(p: Plant) -> bool: return p.leaves == p.max_leaves))
	_check("la niebla empieza de nuevo", moved.fog != null and not moved.migration_pending)
	_check("la vida de las hormigas lleva la mejora", moved.ants.hp[_first_worker(moved)] > moved.cfg.ant_hp * CasteDefs.HP_MULT[CasteDefs.Caste.WORKER])
	var ok := true
	for i in moved.ants.count:
		if moved.ants.alive[i] == 1 and moved.ants.faction[i] == 0:  # las rivales están en su montículo
			var c := moved.ants._cell_index(moved.ants.pos[i])
			if moved.fields.nest_dist[c] >= NestDistanceField.FAR:
				ok = false
	_check("todas las tuyas aparecen dentro del nido", ok)
	for k in 200:
		moved.tick()
	_check("el mapa nuevo sigue andando", moved.ants.alive[moved.queen_id] == 1 and not moved.game_over)


func _first_worker(sim: Simulation) -> int:
	for i in sim.ants.count:
		if sim.ants.alive[i] == 1 and sim.ants.caste[i] == CasteDefs.Caste.WORKER:
			return i
	return -1


func _t_classic_map_stays() -> void:
	var sim := Simulation.new(_cfg(), 3)
	sim.spawn_incremental_start()
	SeasonSystem._advance_season(sim)
	_check("el mapa fijo (sin niebla) no se muda", not sim.migration_pending and sim.season_index == 1)
