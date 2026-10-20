extends SceneTree
## Pruebas de la Fase 6: el modo Test (sandbox, sin victoria ni derrota, panel de pruebas). Ver
## README sección 13.
## Uso: godot --headless --path . --script tools/test_phase6.gd      (código de salida 1 si algo falla)

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_t_fixed_composition()
	_t_starts_at_day()
	_t_queen_death_does_not_end_game()
	_t_rain_commands()
	_t_threat_commands()
	_t_add_caste_ants()
	_t_other_modes_unaffected()
	_t_save_load_keeps_test_mode()
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


func _test_sim(seed_value: int) -> Simulation:
	var sim := Simulation.new(_cfg(), seed_value)
	sim.spawn_test_start()
	return sim


func _run(sim: Simulation, seconds: float) -> void:
	for i in int(seconds * sim.cfg.tick_rate):
		sim.tick()


func _t_fixed_composition() -> void:
	var sim := _test_sim(1)
	var c := sim.ants.count_by_caste([CasteDefs.Caste.WORKER, CasteDefs.Caste.SOLDIER, CasteDefs.Caste.DRONE, CasteDefs.Caste.NURSE])
	_check("1 reina", sim.queen_id >= 0 and sim.ants.alive[sim.queen_id] == 1)
	_check("20 obreras", c[CasteDefs.Caste.WORKER] == sim.cfg.test_start_workers, "real=%d" % c[CasteDefs.Caste.WORKER])
	_check("20 guerreras (soldados)", c[CasteDefs.Caste.SOLDIER] == sim.cfg.test_start_soldiers, "real=%d" % c[CasteDefs.Caste.SOLDIER])
	_check("9 zánganos", c[CasteDefs.Caste.DRONE] == sim.cfg.test_start_drones, "real=%d" % c[CasteDefs.Caste.DRONE])
	_check("50 hormigas en total", sim.ants.alive_count == 50, "real=%d" % sim.ants.alive_count)


func _t_starts_at_day() -> void:
	var sim := _test_sim(2)
	_check("arranca de día", not sim.is_night())


func _t_queen_death_does_not_end_game() -> void:
	var sim := _test_sim(3)
	sim.ants._kill(sim.queen_id, true)
	_run(sim, 1.0)
	_check("la reina puede morir sin terminar la partida", not sim.game_over, "game_over=%s" % sim.game_over)
	_check("tampoco gana", not sim.victory)


func _t_rain_commands() -> void:
	var sim := _test_sim(4)
	sim.cmd_force_rain()
	_check("cmd_force_rain hace llover", sim.weather == Simulation.Weather.RAINING)
	sim.cmd_stop_rain()
	_check("cmd_stop_rain la detiene", sim.weather == Simulation.Weather.CLEAR and not sim.water.raining)


func _t_threat_commands() -> void:
	var sim := _test_sim(5)
	sim.cmd_force_spider()
	_check("cmd_force_spider la hace aparecer", sim.spider.alive)
	sim.cmd_remove_spider()
	_check("cmd_remove_spider la quita sin dejar cadáver", not sim.spider.alive and sim.corpses.is_empty())

	sim.cmd_force_centipede()
	_check("cmd_force_centipede lo hace aparecer", sim.centipede.alive)
	sim.cmd_remove_centipede()
	_check("cmd_remove_centipede lo quita sin dejar cadáver", not sim.centipede.alive and sim.corpses.is_empty())


func _t_add_caste_ants() -> void:
	var sim := _test_sim(6)
	var before := sim.ants.alive_count
	sim.cmd_add_caste_ants(CasteDefs.Caste.NURSE, 5)
	_check("cmd_add_caste_ants agrega la casta pedida",
		sim.ants.alive_count == before + 5 and sim.ants.count_by_caste([CasteDefs.Caste.NURSE])[CasteDefs.Caste.NURSE] == 5)


## El modo Test no debe cambiar nada del comportamiento de los otros dos modos (regresión rápida:
## la cobertura completa ya la dan test_phase0-5).
func _t_other_modes_unaffected() -> void:
	var cfg := _cfg()
	cfg.era2_population = 1
	cfg.era3_population = 2
	var sim := Simulation.new(cfg, 7)
	sim.spawn_colony_court()
	sim.ants._kill(sim.queen_id, true)
	sim.tick()
	_check("el modo Historia sigue terminando la partida al morir la reina", sim.game_over and sim.game_over_reason == "La reina murió.")

	var inc := Simulation.new(_cfg(), 8)
	inc.spawn_incremental_start()
	_check("el modo incremental sigue sin test_mode", not inc.test_mode)


func _t_save_load_keeps_test_mode() -> void:
	var sim := _test_sim(9)
	var d := SaveSystem.to_dict(sim)
	var loaded := SaveSystem.from_dict(d, sim.cfg)
	_check("cargar conserva test_mode", loaded.test_mode)

	var old_d := SaveSystem.to_dict(sim)
	old_d.erase("test_mode")
	var old_loaded := SaveSystem.from_dict(old_d, sim.cfg)
	_check("un guardado sin la llave carga con test_mode=false", not old_loaded.test_mode)
