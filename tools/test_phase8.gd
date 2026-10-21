extends SceneTree
## Pruebas de la Fase 8: condición de victoria del modo incremental ("Juego normal"). Mismo
## espíritu que la Fase 4 (sobrevivir un tiempo con la reina viva), pero sin eras: el disparador es
## que aparezca la primera araña, no llegar a Colonia madura (ver README sección 15).
## Uso: godot --headless --path . --script tools/test_phase8.gd      (código de salida 1 si algo falla)

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_t_victory_after_surviving_since_spider()
	_t_no_victory_before_threshold()
	_t_no_victory_before_spider_appears()
	_t_queen_death_before_threshold_is_defeat_not_victory()
	_t_classic_mode_unaffected()
	_t_save_load_keeps_victory_progress()
	print("RESULTADO: %d correctas, %d fallidas" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("[%s] %s %s" % ["OK " if ok else "FALLA", label, detail])


## `inc_spider_first_population` bajado a propósito: con la colonia inicial de
## `spawn_incremental_start()` ya alcanza, para que la araña aparezca de entrada y la prueba no
## dependa de esperar a que la población crezca sola. `inc_victory_survive_s` corto para que la
## prueba no tarde minutos reales de ticks (mismo truco que `tools/test_phase4.gd`).
func _cfg() -> SimConfig:
	var c := SimConfig.new()
	c.rain_auto = false
	c.inc_spider_first_population = 1
	c.inc_victory_survive_s = 5.0
	return c


func _inc(cfg: SimConfig, seed_value: int) -> Simulation:
	var sim := Simulation.new(cfg, seed_value)
	sim.spawn_incremental_start()
	return sim


func _run(sim: Simulation, seconds: float) -> void:
	for i in int(seconds * sim.cfg.tick_rate):
		sim.tick()


func _t_victory_after_surviving_since_spider() -> void:
	var sim := _inc(_cfg(), 1)
	_run(sim, sim.cfg.inc_victory_survive_s + 2.0)
	_check("gana tras sobrevivir inc_victory_survive_s desde que aparece la araña",
		sim.game_over and sim.victory, "game_over=%s victory=%s spider_alive=%s" % [sim.game_over, sim.victory, sim.spider.alive])
	_check("game_over_reason queda con el texto de victoria, no el de derrota",
		sim.game_over_reason == "La colonia prosperó.", sim.game_over_reason)


func _t_no_victory_before_threshold() -> void:
	var sim := _inc(_cfg(), 2)
	_run(sim, sim.cfg.inc_victory_survive_s * 0.5)
	_check("no gana antes de cumplir inc_victory_survive_s", not sim.game_over and not sim.victory)


## Sin araña, el cronómetro de victoria ni arranca (a diferencia de la Fase 4, acá no hay eras que
## avancen solas: si nadie sube el umbral de población, la araña nunca aparece).
func _t_no_victory_before_spider_appears() -> void:
	var cfg := _cfg()
	cfg.inc_spider_first_population = 999999
	var sim := _inc(cfg, 3)
	_run(sim, sim.cfg.inc_victory_survive_s + 2.0)
	_check("sin araña, nunca gana aunque pase de sobra el tiempo", not sim.game_over and not sim.victory,
		"spider_alive=%s spawned=%d" % [sim.spider.alive, sim.spiders_spawned])


func _t_queen_death_before_threshold_is_defeat_not_victory() -> void:
	var sim := _inc(_cfg(), 4)
	_run(sim, 1.0)  # la araña ya apareció (umbral bajado), pero lejos de inc_victory_survive_s.
	sim.ants._kill(sim.queen_id, true)
	sim.tick()
	_check("la reina muerta antes de tiempo es derrota, no victoria",
		sim.game_over and not sim.victory and sim.game_over_reason == "La reina murió.")


## El modo clásico (con reina, `spawn_colony_court`) sigue su propia condición de victoria
## (`EraSystem.check_victory`, Fase 4) sin que `inc_victory_survive_s`/`_inc_threat_since_s` lo
## afecten: son campos separados a propósito (ver sección 9c/15 del README).
func _t_classic_mode_unaffected() -> void:
	var cfg := _cfg()
	cfg.inc_victory_survive_s = 0.01  # si se colara en el modo clásico, ganaría casi de inmediato.
	cfg.era2_population = 1
	cfg.era3_population = 2
	cfg.spider_first_population = 999999  # esta prueba no es sobre la araña del modo clásico.
	cfg.victory_survive_s = 999999.0
	var sim := Simulation.new(cfg, 5)
	sim.spawn_colony_court()
	_run(sim, 3.0)
	_check("el modo clásico no usa inc_victory_survive_s (el campo es del incremental)", not sim.victory)


func _t_save_load_keeps_victory_progress() -> void:
	var sim := _inc(_cfg(), 6)
	_run(sim, 1.0)  # la araña ya apareció, con el cronómetro de victoria corriendo.
	var d := SaveSystem.to_dict(sim)
	var loaded := SaveSystem.from_dict(d, sim.cfg)
	_check("cargar conserva desde cuándo está la araña (cronómetro de victoria)",
		loaded._inc_threat_since_s == sim._inc_threat_since_s,
		"guardado=%.2f cargado=%.2f" % [sim._inc_threat_since_s, loaded._inc_threat_since_s])
	_run(loaded, sim.cfg.inc_victory_survive_s)
	_check("la partida cargada puede seguir hasta ganar", loaded.game_over and loaded.victory)
