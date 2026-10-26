extends SceneTree
## Pruebas de la Fase 9: estaciones + colonia rival + mejoras (modo incremental). Reemplaza la
## Fase 8 (ver tools/test_phase4.gd, cambio intencional documentado) — derrotar a las 4 colonias
## rivales, una por estación, es la victoria real de "Juego normal".
## Uso: godot --headless --path . --script tools/test_phase9.gd      (código de salida 1 si algo falla)

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_t_rival_ants_dont_fight_each_other()
	_t_player_and_rival_damage_each_other()
	_t_wave_appears_on_last_day_not_before()
	_t_season_does_not_advance_while_battle_active()
	_t_battle_won_when_rival_queen_dies()
	_t_victory_after_four_seasons()
	_t_classic_mode_unaffected()
	_t_upgrades_are_colony_wide()
	_t_save_load_keeps_season_state()
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


func _inc(cfg: SimConfig, seed_value: int) -> Simulation:
	var sim := Simulation.new(cfg, seed_value)
	sim.spawn_incremental_start()
	return sim


func _run(sim: Simulation, seconds: float) -> void:
	for i in int(seconds * sim.cfg.tick_rate):
		sim.tick()


func _t_rival_ants_dont_fight_each_other() -> void:
	var sim := _inc(_cfg(), 1)
	var cell := Vector2i(10, sim.cfg.surface_y - 1)
	var idx_a := sim.ants.add_ant_at(cell, CasteDefs.Caste.SOLDIER, 1)
	var idx_b := sim.ants.add_ant_at(cell, CasteDefs.Caste.SOLDIER, 1)
	sim.ants.pos[idx_b] = sim.ants.pos[idx_a]  # pegadas, dentro de rango de melee si pelearan
	var hp_a := sim.ants.hp[idx_a]
	var hp_b := sim.ants.hp[idx_b]
	_run(sim, 5.0)
	_check("dos hormigas rivales una al lado de la otra no se lastiman entre sí",
		sim.ants.hp[idx_a] == hp_a and sim.ants.hp[idx_b] == hp_b,
		"hp_a %.1f->%.1f hp_b %.1f->%.1f" % [hp_a, sim.ants.hp[idx_a], hp_b, sim.ants.hp[idx_b]])


func _t_player_and_rival_damage_each_other() -> void:
	var sim := _inc(_cfg(), 2)
	var cell := Vector2i(10, sim.cfg.surface_y - 1)
	var player_idx := sim.ants.add_ant_at(cell, CasteDefs.Caste.SOLDIER, 0)
	var rival_idx := sim.ants.add_ant_at(cell, CasteDefs.Caste.SOLDIER, 1)
	sim.ants.pos[rival_idx] = sim.ants.pos[player_idx]
	var player_hp := sim.ants.hp[player_idx]
	var rival_hp := sim.ants.hp[rival_idx]
	_run(sim, 5.0)
	_check("una hormiga del jugador le pega a una rival cerca (vía _nearest_threat generalizado)",
		sim.ants.hp[rival_idx] < rival_hp, "rival hp %.1f -> %.1f" % [rival_hp, sim.ants.hp[rival_idx]])
	_check("la rival también le pega de vuelta (_tick_rival)",
		sim.ants.hp[player_idx] < player_hp, "jugador hp %.1f -> %.1f" % [player_hp, sim.ants.hp[player_idx]])


func _t_wave_appears_on_last_day_not_before() -> void:
	var cfg := _cfg()
	cfg.season_days = [2, 2, 2, 2]  # Fase 17: antes `season_length_days = 2` (un solo número)
	var sim := _inc(cfg, 3)
	_run(sim, cfg.day_length_s * 0.5)  # bien adentro del día 1, lejos del último día.
	_check("sin llegar al último día de la estación, la colonia rival no ataca",
		not sim.rival_colony.battle_active, "día=%d" % sim.day_number())
	_run(sim, cfg.day_length_s * 1.6)  # ya en el último día (estaciones de 2 días).
	_check("al llegar al último día de la estación, la colonia rival ataca",
		sim.rival_colony.battle_active, "día=%d" % sim.day_number())


func _t_season_does_not_advance_while_battle_active() -> void:
	var sim := _inc(_cfg(), 4)
	sim.rival_colony.start_battle(5, 1.0)
	sim.rival_colony.queen.hp = sim.rival_colony.queen.max_hp * 1000.0  # no la matan sin querer.
	var season_before := sim.season_index
	_run(sim, sim.cfg.day_length_s * (Simulation.SeasonSystem.season_length(sim) + 1))  # de sobra para "otro día".
	_check("la estación no avanza mientras la batalla sigue activa",
		sim.season_index == season_before and sim.rival_colony.battle_active)


func _t_battle_won_when_rival_queen_dies() -> void:
	var sim := _inc(_cfg(), 5)
	sim.rival_colony.start_battle(3, 1.0)
	var season_before := sim.season_index
	sim.rival_colony.queen.take_damage(sim.rival_colony.queen.max_hp + 1.0)
	sim.tick()
	_check("la batalla se gana al morir la reina rival",
		sim.rival_colony.battle_won and not sim.rival_colony.battle_active)
	_check("al ganar, la estación avanza", sim.season_index == season_before + 1,
		"antes=%d después=%d" % [season_before, sim.season_index])


func _t_victory_after_four_seasons() -> void:
	var sim := _inc(_cfg(), 6)
	for k in 4:
		sim.rival_colony.start_battle(3, 1.0)
		sim.rival_colony.queen.take_damage(sim.rival_colony.queen.max_hp + 1.0)
		sim.tick()
	_check("derrotar a las 4 colonias rivales gana el juego",
		sim.game_over and sim.victory, "season_index=%d game_over=%s victory=%s" % [sim.season_index, sim.game_over, sim.victory])
	_check("game_over_reason queda con el texto de victoria",
		sim.game_over_reason == "Derrotaste a las 4 colonias rivales.", sim.game_over_reason)


## El modo clásico (con reina, `spawn_colony_court`) no tiene estaciones ni colonia rival: ver
## también `tools/test_phase4.gd._t_classic_mode_unaffected_by_seasons`, mismo chequeo desde el
## otro lado (acá además confirma que `start_battle` nunca se llama sin `sim.incremental`).
func _t_classic_mode_unaffected() -> void:
	var cfg := _cfg()
	cfg.era2_population = 1
	cfg.era3_population = 2
	var sim := Simulation.new(cfg, 7)
	sim.spawn_colony_court()
	_run(sim, cfg.day_length_s * (cfg.season_days[0] + 2))
	_check("el modo clásico nunca arranca una batalla rival aunque pase de sobra el tiempo",
		not sim.rival_colony.battle_active and sim.season_index == 0)


## Fase 13: las mejoras son progresivas de verdad — afectan a toda la colonia, no solo a las
## hormigas que nazcan después de comprar (antes solo la vida tenía esa limitación por accidente;
## ver nota en upgrades.gd). Cambio intencional documentado: este test se llamaba
## "_t_upgrades_raise_new_ants_stats" y afirmaba justo lo contrario para la vida.
func _t_upgrades_are_colony_wide() -> void:
	var sim := _inc(_cfg(), 8)
	sim.colony.food = 999999.0
	var baseline := sim.ants.add_ant_at(Vector2i(10, sim.cfg.surface_y - 1), CasteDefs.Caste.WORKER, 0)
	var baseline_hp := sim.ants.hp[baseline]
	var rival := sim.ants.add_ant_at(Vector2i(10, sim.cfg.surface_y - 1), CasteDefs.Caste.WORKER, 1)
	var rival_hp := sim.ants.hp[rival]
	_check("comprar la mejora de vida cuesta comida y sube el nivel",
		sim.cmd_buy_upgrade(Upgrades.Stat.HP) and sim.upgrades.levels[Upgrades.Stat.HP] == 1)
	_check("una hormiga que YA vivía también sube de vida al comprar la mejora (progresiva)",
		sim.ants.hp[baseline] > baseline_hp, "antes=%.2f después=%.2f" % [baseline_hp, sim.ants.hp[baseline]])
	var upgraded := sim.ants.add_ant_at(Vector2i(10, sim.cfg.surface_y - 1), CasteDefs.Caste.WORKER, 0)
	_check("una hormiga nueva tras comprar la mejora de vida nace con más HP",
		sim.ants.hp[upgraded] > baseline_hp, "antes=%.2f después=%.2f" % [baseline_hp, sim.ants.hp[upgraded]])
	_check("una hormiga rival (ya viva o nueva) NO se beneficia de las mejoras del jugador",
		sim.ants.hp[rival] == rival_hp and sim.ants.hp[sim.ants.add_ant_at(Vector2i(10, sim.cfg.surface_y - 1), CasteDefs.Caste.WORKER, 1)] == rival_hp)


func _t_save_load_keeps_season_state() -> void:
	var sim := _inc(_cfg(), 9)
	sim.season_index = 2
	sim.rival_colony.start_battle(4, 1.5)
	sim.cmd_buy_upgrade(Upgrades.Stat.DAMAGE)
	var d := SaveSystem.to_dict(sim)
	var loaded := SaveSystem.from_dict(d, sim.cfg)
	_check("cargar conserva la estación actual", loaded.season_index == sim.season_index)
	_check("cargar conserva si la batalla sigue activa", loaded.rival_colony.battle_active == sim.rival_colony.battle_active)
	_check("cargar conserva la vida de la reina rival",
		loaded.rival_colony.queen.hp == sim.rival_colony.queen.hp,
		"guardado=%.1f cargado=%.1f" % [sim.rival_colony.queen.hp, loaded.rival_colony.queen.hp])
	var any_rival_faction := false
	for i in loaded.ants.count:
		if loaded.ants.faction[i] == 1:
			any_rival_faction = true
			break
	_check("cargar conserva el bando de las hormigas rivales", any_rival_faction)
