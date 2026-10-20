extends SceneTree
## Pruebas de la Fase 5: segunda amenaza, el ciempiés (README sección 12). A diferencia de la
## araña, entra por los túneles y puede alcanzar hormigas bajo tierra.
## Uso: godot --headless --path . --script tools/test_phase5.gd      (código de salida 1 si algo falla)

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_t_no_centipede_before_threshold()
	_t_centipede_appears_at_threshold()
	_t_centipede_finds_prey_underground()
	_t_colony_wide_defense_against_centipede()
	_t_centipede_dies_and_leaves_corpse()
	_t_centipede_flees_at_low_hp()
	_t_incremental_mode_never_spawns_centipede()
	_t_save_load_keeps_centipede_state()
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
	c.spider_first_population = 999999  # estas pruebas son solo del ciempiés.
	return c


func _colony(cfg: SimConfig, seed_value: int) -> Simulation:
	var sim := Simulation.new(cfg, seed_value)
	sim.spawn_colony_court()
	return sim


func _run(sim: Simulation, seconds: float) -> void:
	for i in int(seconds * sim.cfg.tick_rate):
		sim.tick()


func _carve(sim: Simulation, x0: int, y0: int, x1: int, y1: int) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			sim.world.cells[y * sim.world.w + x] = WorldGrid.Cell.TUNNEL
	sim.world.passable_version += 1
	sim.fields.recompute_terrain()  # para que surface_dist/nest_dist vean el túnel nuevo de inmediato


## Umbrales de era bajados a propósito (mismo truco que test_phase1.gd._t_spider): con
## reina+nodrizas de `spawn_colony_court()` ya alcanza Colonia madura, que es cuando `tick()`
## empieza a llamar `_update_centipede()`.
func _mature_cfg(ants := 0) -> SimConfig:
	var c := _cfg(ants)
	c.era2_population = 1
	c.era3_population = 2
	return c


func _t_no_centipede_before_threshold() -> void:
	var cfg := _mature_cfg()
	cfg.centipede_first_population = 999999
	var sim := _colony(cfg, 1)
	_run(sim, 3.0)
	_check("sin alcanzar el umbral de población, el ciempiés nunca aparece",
		not sim.centipede.alive and sim.centipedes_spawned == 0)


func _t_centipede_appears_at_threshold() -> void:
	var cfg := _mature_cfg()
	cfg.centipede_first_population = 1
	var sim := _colony(cfg, 2)
	_run(sim, 3.0)
	_check("al cruzar centipede_first_population en Colonia madura, aparece",
		sim.centipede.alive and sim.centipedes_spawned == 1)


## El caso que de verdad prueba el rasgo distintivo frente a la araña: una hormiga lejos de la
## superficie, al fondo de un túnel recto, con el ciempiés puesto a cazar en la entrada. La araña
## (ver test_phase1.gd._t_spider) nunca encontraría esto; el ciempiés sí, porque sigue
## `NestDistanceField.bfs_from()` por el túnel real en vez de quedarse en la superficie.
func _t_centipede_finds_prey_underground() -> void:
	var cfg := _mature_cfg()
	cfg.centipede_retarget_ticks = 1  # recalcular siempre: esta prueba corre pocos segundos.
	var sim := _colony(cfg, 3)
	var sy := sim.cfg.surface_y + sim.cfg.shaft_depth
	var nx := sim.cfg.nest_x
	_carve(sim, nx + 3, sy, nx + 30, sy + 1)  # túnel recto, lejos bajo tierra
	var deep := sim.ants.add_ant_at(Vector2i(nx + 28, sy))
	sim.cmd_force_centipede()
	_run(sim, 20.0)
	_check("el ciempiés encuentra y daña a una hormiga bajo tierra, no solo en superficie",
		sim.ants.alive[deep] == 0 or sim.ants.hp[deep] < sim.cfg.ant_hp, "vida=%.1f" % sim.ants.hp[deep])


## Mismo criterio que test_phase1.gd._t_colony_wide_defense_by_caste, pero contra el ciempiés: la
## generalización de `AntSystem._nearest_threat()` es justo lo que hace que esto funcione sin
## tocar `_think_defend`/`_think_soldier`.
func _t_colony_wide_defense_against_centipede() -> void:
	var cfg := _mature_cfg()
	var sim := _colony(cfg, 4)
	sim.cmd_force_centipede()
	for k in 6:
		var s := sim.ants.add_ant_at(Vector2i(sim.cfg.nest_x, sim.cfg.surface_y - 1), CasteDefs.Caste.SOLDIER)
		sim.ants.pos[s] = sim.centipede.pos
	_run(sim, 10.0)
	_check("los soldados dañan al ciempiés igual que a la araña",
		not sim.centipede.alive or sim.centipede.hp < sim.centipede.max_hp,
		"vida=%.1f/%.1f" % [sim.centipede.hp, sim.centipede.max_hp])


func _t_centipede_dies_and_leaves_corpse() -> void:
	var cfg := _mature_cfg()
	var sim := _colony(cfg, 5)
	sim.cmd_force_centipede()
	sim.centipede.take_damage(sim.centipede.max_hp + 1.0)
	_check("muere al llegar a 0 de vida", not sim.centipede.alive)
	_check("deja un cadáver recolectable al morir", sim.corpses.size() == 1 and sim.corpses[0].food_value == sim.cfg.corpse_food_value_centipede)


func _t_centipede_flees_at_low_hp() -> void:
	var cfg := _mature_cfg()
	var sim := _colony(cfg, 6)
	sim.cmd_force_centipede()
	sim.centipede.hp = sim.centipede.max_hp * (sim.cfg.centipede_flee_hp_pct - 0.05)
	sim.centipede.step(sim.dt)
	_check("con poca vida pasa a huir", sim.centipede.state == Centipede.State.RETREAT)
	_run(sim, 30.0)
	_check("termina desapareciendo al llegar a la superficie", not sim.centipede.alive)


## El modo incremental no pasa por `elif queen_id >= 0:` en `tick()` (igual que la araña y la
## condición de victoria de la Fase 4): confirma que ese modo sigue exactamente igual que antes.
func _t_incremental_mode_never_spawns_centipede() -> void:
	var cfg := SimConfig.new()
	cfg.rain_auto = false
	cfg.centipede_first_population = 1
	var sim := Simulation.new(cfg, 7)
	sim.spawn_incremental_start()
	_run(sim, 3.0)
	_check("el modo incremental nunca dispara el ciempiés", not sim.centipede.alive and sim.centipedes_spawned == 0)


func _t_save_load_keeps_centipede_state() -> void:
	var cfg := _mature_cfg()
	var sim := _colony(cfg, 8)
	sim.cmd_force_centipede()
	sim.centipede.hp = sim.centipede.max_hp * 0.5
	var d := SaveSystem.to_dict(sim)
	var loaded := SaveSystem.from_dict(d, sim.cfg)
	_check("cargar conserva si el ciempiés está vivo", loaded.centipede.alive == sim.centipede.alive)
	_check("cargar conserva su vida", loaded.centipede.hp == sim.centipede.hp,
		"guardado=%.1f cargado=%.1f" % [sim.centipede.hp, loaded.centipede.hp])
	_check("cargar conserva cuántos han aparecido", loaded.centipedes_spawned == sim.centipedes_spawned)

	# Un guardado de ANTES de esta fase (sin la llave "centipede") debe cargar igual, sin reventar.
	var old_d := SaveSystem.to_dict(sim)
	old_d.erase("centipede")
	old_d.erase("centipedes_spawned")
	old_d.erase("centipede_next_s")
	var old_loaded := SaveSystem.from_dict(old_d, sim.cfg)
	_check("un guardado sin la llave del ciempiés carga igual, sin ciempiés", not old_loaded.centipede.alive and old_loaded.centipedes_spawned == 0)
