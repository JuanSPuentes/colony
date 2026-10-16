extends SceneTree
## Pruebas de la Fase 3: modo incremental (colonia mínima, todo en comida, compra de hormigas,
## auto-compra, plantas que rebrotan, día y noche, sin araña).
## Uso: godot --headless --path . --script tools/test_phase3.gd      (código de salida 1 si algo falla)

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_t_start_colony()
	_t_no_spider_no_eras()
	_t_day_night()
	_t_leaves_become_food()
	_t_buy_costs_food_and_scales()
	_t_bought_egg_hatches_as_that_caste()
	_t_auto_buy_keeps_reserve()
	_t_plants_regrow_only_by_day()
	_t_colony_grows_on_its_own()
	_t_save_load_keeps_incremental()
	_t_deterministic()
	print("RESULTADO: %d correctas, %d fallidas" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("[%s] %s %s" % ["OK " if ok else "FALLA", label, detail])


func _cfg(rain := false) -> SimConfig:
	var c := SimConfig.new()
	c.rain_auto = rain
	return c


func _inc(cfg: SimConfig, seed_value := 7) -> Simulation:
	var sim := Simulation.new(cfg, seed_value)
	sim.spawn_incremental_start()
	return sim


func _run(sim: Simulation, seconds: float) -> void:
	for i in int(seconds * sim.cfg.tick_rate):
		sim.tick()


func _count(sim: Simulation, caste: int) -> int:
	var n := 0
	for i in sim.ants.count:
		if sim.ants.alive[i] == 1 and sim.ants.caste[i] == caste:
			n += 1
	return n


# --- Pruebas ----------------------------------------------------------------------------------

func _t_start_colony() -> void:
	var cfg := _cfg()
	var sim := _inc(cfg)
	var ok := sim.incremental and sim.ants.alive_count == 5 and _count(sim, CasteDefs.Caste.QUEEN) == 1 \
		and _count(sim, CasteDefs.Caste.WORKER) == 3 and _count(sim, CasteDefs.Caste.SOLDIER) == 1 \
		and _count(sim, CasteDefs.Caste.NURSE) == 0
	_check("arranca con 1 reina, 3 obreras y 1 soldado (5 hormigas)", ok, "vivas=%d" % sim.ants.alive_count)
	_check("y con 1 larva", sim.brood.total_alive() == 1 and sim.brood.stage[0] == BroodSystem.Stage.LARVA)
	_check("la comida inicial es la configurada y el agua no cuenta", sim.colony.food == cfg.inc_start_food and sim.colony.water == 0.0)
	var plain := Simulation.new(cfg, 7)
	_check("sin spawn_incremental_start la simulación sigue en modo clásico", not plain.incremental and plain.ants.alive_count == cfg.initial_ants)


func _t_no_spider_no_eras() -> void:
	var cfg := _cfg()
	var sim := _inc(cfg)
	sim.cmd_add_ants(cfg.spider_first_population + cfg.era3_population)  # población de sobra para araña y eras
	sim.cmd_force_spider()
	_run(sim, 30.0)
	_check("nunca aparece la araña (ni forzándola)", not sim.spider.alive and sim.spiders_spawned == 0)
	_check("las eras no avanzan", sim.era == Simulation.Era.FOUNDATION)


func _t_day_night() -> void:
	var cfg := _cfg()
	var L := cfg.day_length_s
	var dusk := L * (1.0 - cfg.night_fraction)
	_check("el juego empieza en el Día 1, de día", DayNight.day_number(0.0, cfg) == 1 and not DayNight.is_night(0.0, cfg))
	_check("al atardecer empieza la noche, todavía Día 1", DayNight.is_night(dusk + 1.0, cfg) and DayNight.day_number(dusk + 1.0, cfg) == 1)
	_check("tras un día y una noche se cuenta el Día 2", DayNight.day_number(L + 1.0, cfg) == 2 and not DayNight.is_night(L + 1.0, cfg))
	_check("la luz es 1 a mediodía y 0 de noche", DayNight.light(dusk * 0.5, cfg) == 1.0 and DayNight.light(dusk + L * 0.1, cfg) == 0.0)
	var sim := _inc(cfg)
	_run(sim, L + 2.0)
	_check("la simulación cuenta los días", sim.day_number() == 2)


func _t_leaves_become_food() -> void:
	var cfg := _cfg()
	var sim := _inc(cfg)
	var before := sim.colony.food
	sim.leaves_stored = 5
	sim.tick()
	var gained := sim.colony.food - before
	_check("cada hoja que llega al nido se vuelve comida", sim.leaves_stored == 0 and absf(gained - 5.0 * cfg.inc_food_per_leaf) < 0.1, "ganó %.2f" % gained)


func _t_buy_costs_food_and_scales() -> void:
	var cfg := _cfg()
	var sim := _inc(cfg)
	sim.colony.food = 5.0
	_check("sin comida suficiente no se puede comprar", not sim.cmd_buy(CasteDefs.Caste.WORKER) and sim.brood.total_alive() == 1)
	sim.colony.food = 200.0
	var c1 := sim.econ.cost(CasteDefs.Caste.WORKER)
	var ok := sim.cmd_buy(CasteDefs.Caste.WORKER)
	_check("comprar una obrera cuesta su precio y pone un huevo", ok and sim.colony.food == 200.0 - c1 and sim.brood.total_alive() == 2, "precio %.0f" % c1)
	_check("la siguiente obrera sale más cara", sim.econ.cost(CasteDefs.Caste.WORKER) > c1, "%.0f -> %.0f" % [c1, sim.econ.cost(CasteDefs.Caste.WORKER)])
	var s1 := sim.econ.cost(CasteDefs.Caste.SOLDIER)
	_check("el soldado cuesta más que la obrera", s1 > c1 and sim.cmd_buy(CasteDefs.Caste.SOLDIER))
	_check("las nodrizas no se compran", not sim.cmd_buy(CasteDefs.Caste.NURSE))


func _t_bought_egg_hatches_as_that_caste() -> void:
	var cfg := _cfg()
	var sim := _inc(cfg)
	sim.colony.food = 200.0
	sim.cmd_buy(CasteDefs.Caste.SOLDIER)
	var soldiers := _count(sim, CasteDefs.Caste.SOLDIER)
	var total_s := (cfg.egg_time_s + cfg.larva_time_s + cfg.pupa_time_s) / cfg.inc_brood_speed / CasteDefs.DEV_SPEED_MULT[CasteDefs.Caste.SOLDIER]
	_run(sim, total_s + 5.0)
	_check("el huevo comprado nace como soldado (sin nodrizas, en %.0f s)" % total_s, _count(sim, CasteDefs.Caste.SOLDIER) == soldiers + 1, "soldados %d -> %d" % [soldiers, _count(sim, CasteDefs.Caste.SOLDIER)])


func _t_auto_buy_keeps_reserve() -> void:
	var cfg := _cfg()
	var sim := _inc(cfg)
	sim.cmd_cycle_auto_buy()
	_check("9 activa la auto-compra de obreras", sim.econ.auto_mode == IncrementalEconomy.Auto.WORKER)
	var cost := sim.econ.cost(CasteDefs.Caste.WORKER)
	sim.colony.food = cost + cfg.inc_auto_reserve - 1.0
	sim.tick()
	_check("no compra si se comería la reserva", sim.econ.bought[CasteDefs.Caste.WORKER] == 0)
	sim.colony.food = cost + cfg.inc_auto_reserve + 1.0
	sim.tick()
	_check("compra sola en cuanto alcanza", sim.econ.bought[CasteDefs.Caste.WORKER] == 1 and sim.colony.food >= cfg.inc_auto_reserve - 0.1)
	sim.cmd_cycle_auto_buy()
	sim.cmd_cycle_auto_buy()
	_check("9 recorre obreras -> soldados -> apagada", sim.econ.auto_mode == IncrementalEconomy.Auto.OFF)


func _t_plants_regrow_only_by_day() -> void:
	var cfg := _cfg()
	var sim := _inc(cfg)
	var p := sim.plants[0]
	p.leaves = 0
	sim.econ.regrow_plants(1.5 / cfg.inc_plant_regrow_per_s)  # 1.5 hojas acumuladas: rebrota 1
	var day_leaves := p.leaves
	_run(sim, cfg.day_length_s * (1.0 - cfg.night_fraction) + 2.0)  # ahora es de noche
	p.leaves = 0
	p.regrow_acc = 0.0
	sim.econ.regrow_plants(100.0)
	_check("las plantas rebrotan de día y no de noche", day_leaves >= 1 and p.leaves == 0, "de día %d, de noche %d" % [day_leaves, p.leaves])


func _t_colony_grows_on_its_own() -> void:
	# Con lluvia, como en el juego real: 6 minutos (2 días) con la auto-compra de obreras.
	var cfg := _cfg(true)
	var sim := _inc(cfg, 12345)
	sim.cmd_cycle_auto_buy()
	_run(sim, 360.0)
	_check("con auto-compra la colonia crece sola sin morir (6 min)", not sim.game_over and sim.ants.alive_count >= 10 and sim.econ.food_earned > 150.0,
		"hormigas %d, comida ganada %.0f" % [sim.ants.alive_count, sim.econ.food_earned])


func _t_save_load_keeps_incremental() -> void:
	var cfg := _cfg()
	var sim := _inc(cfg)
	sim.colony.food = 120.0
	sim.cmd_buy(CasteDefs.Caste.WORKER)
	sim.cmd_cycle_auto_buy()
	_run(sim, 40.0)
	var loaded := SaveSystem.from_dict(JSON.parse_string(JSON.stringify(SaveSystem.to_dict(sim))), cfg)
	_check("guardar y cargar conserva el modo incremental, compras y auto-compra",
		loaded.incremental and loaded.econ.bought[CasteDefs.Caste.WORKER] == sim.econ.bought[CasteDefs.Caste.WORKER]
		and loaded.econ.auto_mode == sim.econ.auto_mode and loaded.econ.known_plants == sim.econ.known_plants)
	_check("y la huella no cambia", loaded.checksum() == sim.checksum(), "%d / %d" % [sim.checksum(), loaded.checksum()])
	_run(sim, 30.0)
	_run(loaded, 30.0)
	_check("tras cargar la partida sigue igual", loaded.checksum() == sim.checksum())


func _t_deterministic() -> void:
	var cfg := _cfg(true)
	var a := _inc(cfg, 99)
	var b := _inc(cfg, 99)
	a.cmd_cycle_auto_buy()
	b.cmd_cycle_auto_buy()
	_run(a, 120.0)
	_run(b, 120.0)
	_check("misma semilla y mismas acciones dan el mismo resultado", a.checksum() == b.checksum())
