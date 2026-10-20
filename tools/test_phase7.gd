extends SceneTree
## Pruebas de la Fase 7: tercera amenaza, la mantis (README sección 14). A diferencia de la araña
## y el ciempiés, nunca se mueve: embosca quieta y pega mucho más fuerte.
## Uso: godot --headless --path . --script tools/test_phase7.gd      (código de salida 1 si algo falla)

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_t_no_mantis_before_threshold()
	_t_mantis_appears_at_threshold()
	_t_mantis_never_moves()
	_t_mantis_ignores_far_ant_but_strikes_close_one()
	_t_mantis_hits_harder_than_spider()
	_t_colony_wide_defense_against_mantis()
	_t_mantis_dies_and_leaves_corpse()
	_t_mantis_flees_at_low_hp()
	_t_incremental_mode_never_spawns_mantis()
	_t_save_load_keeps_mantis_state()
	print("RESULTADO: %d correctas, %d fallidas" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("[%s] %s %s" % ["OK " if ok else "FALLA", label, detail])


func _cfg(ants := 0) -> SimConfig:
	var c := SimConfig.new()
	c.initial_ants = ants
	c.rain_auto = false
	c.spider_first_population = 999999  # estas pruebas son solo de la mantis.
	c.centipede_first_population = 999999
	return c


func _colony(cfg: SimConfig, seed_value: int) -> Simulation:
	var sim := Simulation.new(cfg, seed_value)
	sim.spawn_colony_court()
	return sim


func _run(sim: Simulation, seconds: float) -> void:
	for i in int(seconds * sim.cfg.tick_rate):
		sim.tick()


## Umbrales de era bajados a propósito (mismo truco que test_phase1.gd._t_spider): con
## reina+nodrizas de `spawn_colony_court()` ya alcanza Colonia madura, que es cuando `tick()`
## empieza a llamar `_update_mantis()`.
func _mature_cfg(ants := 0) -> SimConfig:
	var c := _cfg(ants)
	c.era2_population = 1
	c.era3_population = 2
	return c


func _t_no_mantis_before_threshold() -> void:
	var cfg := _mature_cfg()
	cfg.mantis_first_population = 999999
	var sim := _colony(cfg, 1)
	_run(sim, 3.0)
	_check("sin alcanzar el umbral de población, la mantis nunca aparece",
		not sim.mantis.alive and sim.mantises_spawned == 0)


func _t_mantis_appears_at_threshold() -> void:
	var cfg := _mature_cfg()
	cfg.mantis_first_population = 1
	var sim := _colony(cfg, 2)
	_run(sim, 3.0)
	_check("al cruzar mantis_first_population en Colonia madura, aparece",
		sim.mantis.alive and sim.mantises_spawned == 1)


## El rasgo distintivo frente a la araña/ciempiés: nunca cambia de posición, ni buscando presa ni
## atacando a una que está lejos de su alcance. `mantis.step()` directo (no `_run()`): con un
## tick completo, hormigas sueltas cerca se defenderían solas (toda la colonia pelea ante una
## amenaza real, ver ant_system.gd._think) y podrían bajarle la vida hasta que huyera — eso
## probaría el estado RETREAT (que sí se mueve, ver `_t_mantis_flees_at_low_hp`), no esto.
func _t_mantis_never_moves() -> void:
	var cfg := _mature_cfg()
	var sim := _colony(cfg, 3)
	sim.cmd_force_mantis()
	var start_pos := sim.mantis.pos
	var close := sim.ants.add_ant_at(Vector2i(0, 0))
	sim.ants.pos[close] = sim.mantis.pos
	for k in 60:
		sim.mantis.step(sim.dt)
	_check("la mantis nunca cambia de posición mientras acecha o ataca", sim.mantis.pos == start_pos,
		"inicial=%s final=%s" % [start_pos, sim.mantis.pos])


## Llama `mantis.step()` directo en vez de `_run()` (tick completo): una obrera recién creada se
## pone a explorar sola y se alejaría de un radio de 7px en menos de un segundo, lo que haría la
## prueba frágil sin que tenga que ver con la mantis.
func _t_mantis_ignores_far_ant_but_strikes_close_one() -> void:
	var cfg := _mature_cfg()
	var sim := _colony(cfg, 4)
	sim.cmd_force_mantis()
	var far := sim.ants.add_ant_at(Vector2i(sim.cfg.nest_x + 60, sim.cfg.surface_y - 1))
	for k in 20:
		sim.mantis.step(sim.dt)
	_check("ignora una obrera fuera de mantis_strike_range_px", sim.ants.hp[far] == sim.cfg.ant_hp)

	var close := sim.ants.add_ant_at(Vector2i(0, 0))
	sim.ants.pos[close] = sim.mantis.pos
	for k in 20:
		sim.mantis.step(sim.dt)
	_check("ataca a una obrera que entra en mantis_strike_range_px",
		sim.ants.alive[close] == 0 or sim.ants.hp[close] < sim.cfg.ant_hp, "vida=%.1f" % sim.ants.hp[close])


## Daño comparado en el mismo tiempo de contacto: confirma que el número de `mantis_damage_per_s`
## es de verdad más alto que `spider_damage_per_s`, no solo que lo diga el comentario del config.
func _t_mantis_hits_harder_than_spider() -> void:
	_check("mantis_damage_per_s > spider_damage_per_s", SimConfig.new().mantis_damage_per_s > SimConfig.new().spider_damage_per_s)
	_check("mantis_damage_per_s > centipede_damage_per_s", SimConfig.new().mantis_damage_per_s > SimConfig.new().centipede_damage_per_s)


func _t_colony_wide_defense_against_mantis() -> void:
	var cfg := _mature_cfg()
	var sim := _colony(cfg, 5)
	sim.cmd_force_mantis()
	for k in 6:
		var s := sim.ants.add_ant_at(Vector2i(sim.cfg.nest_x, sim.cfg.surface_y - 1), CasteDefs.Caste.SOLDIER)
		sim.ants.pos[s] = sim.mantis.pos
	_run(sim, 10.0)
	_check("los soldados dañan a la mantis igual que a la araña y el ciempiés",
		not sim.mantis.alive or sim.mantis.hp < sim.mantis.max_hp,
		"vida=%.1f/%.1f" % [sim.mantis.hp, sim.mantis.max_hp])


func _t_mantis_dies_and_leaves_corpse() -> void:
	var cfg := _mature_cfg()
	var sim := _colony(cfg, 6)
	sim.cmd_force_mantis()
	sim.mantis.take_damage(sim.mantis.max_hp + 1.0)
	_check("muere al llegar a 0 de vida", not sim.mantis.alive)
	_check("deja un cadáver recolectable al morir", sim.corpses.size() == 1 and sim.corpses[0].food_value == sim.cfg.corpse_food_value_mantis)


func _t_mantis_flees_at_low_hp() -> void:
	var cfg := _mature_cfg()
	var sim := _colony(cfg, 7)
	sim.cmd_force_mantis()
	sim.mantis.hp = sim.mantis.max_hp * (sim.cfg.mantis_flee_hp_pct - 0.05)
	sim.mantis.step(sim.dt)
	_check("con poca vida pasa a huir", sim.mantis.state == Mantis.State.RETREAT)
	_run(sim, 30.0)
	_check("termina desapareciendo al llegar al borde del mapa", not sim.mantis.alive)


func _t_incremental_mode_never_spawns_mantis() -> void:
	var cfg := SimConfig.new()
	cfg.rain_auto = false
	cfg.mantis_first_population = 1
	var sim := Simulation.new(cfg, 8)
	sim.spawn_incremental_start()
	_run(sim, 3.0)
	_check("el modo incremental nunca dispara la mantis", not sim.mantis.alive and sim.mantises_spawned == 0)


func _t_save_load_keeps_mantis_state() -> void:
	var cfg := _mature_cfg()
	var sim := _colony(cfg, 9)
	sim.cmd_force_mantis()
	sim.mantis.hp = sim.mantis.max_hp * 0.5
	var d := SaveSystem.to_dict(sim)
	var loaded := SaveSystem.from_dict(d, sim.cfg)
	_check("cargar conserva si la mantis está viva", loaded.mantis.alive == sim.mantis.alive)
	_check("cargar conserva su vida", loaded.mantis.hp == sim.mantis.hp,
		"guardado=%.1f cargado=%.1f" % [sim.mantis.hp, loaded.mantis.hp])
	_check("cargar conserva cuántas han aparecido", loaded.mantises_spawned == sim.mantises_spawned)

	var old_d := SaveSystem.to_dict(sim)
	old_d.erase("mantis")
	old_d.erase("mantises_spawned")
	old_d.erase("mantis_next_s")
	var old_loaded := SaveSystem.from_dict(old_d, sim.cfg)
	_check("un guardado sin la llave de la mantis carga igual, sin mantis", not old_loaded.mantis.alive and old_loaded.mantises_spawned == 0)
