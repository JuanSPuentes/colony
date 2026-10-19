extends SceneTree
## Pruebas de la Fase 4: condición de victoria de la colonia con reina (la que el plan original
## llamaba Fase 3 sección 4.1 y nunca se construyó porque esa fase terminó siendo el modo
## incremental). Sobrevivir `cfg.victory_survive_s` segundos en Colonia madura con la reina viva.
## Uso: godot --headless --path . --script tools/test_phase4.gd      (código de salida 1 si algo falla)

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_t_victory_after_surviving_mature()
	_t_no_victory_before_threshold()
	_t_queen_death_before_threshold_is_defeat_not_victory()
	_t_incremental_mode_never_wins()
	_t_save_load_keeps_victory_progress()
	print("RESULTADO: %d correctas, %d fallidas" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("[%s] %s %s" % ["OK " if ok else "FALLA", label, detail])


## Umbrales de era bajados a propósito (mismo truco que tools/test_phase1.gd._t_spider): con
## reina+nodrizas de `spawn_colony_court()` ya alcanza Colonia madura, y un `victory_survive_s`
## corto para que la prueba no tarde minutos reales de ticks.
func _cfg() -> SimConfig:
	var c := SimConfig.new()
	c.rain_auto = false
	c.era2_population = 1
	c.era3_population = 2
	c.spider_first_population = 999999  # sin araña de por medio: esta prueba es solo del timer.
	c.victory_survive_s = 5.0
	return c


func _colony(cfg: SimConfig, seed_value: int) -> Simulation:
	var sim := Simulation.new(cfg, seed_value)
	sim.spawn_colony_court()
	return sim


func _run(sim: Simulation, seconds: float) -> void:
	for i in int(seconds * sim.cfg.tick_rate):
		sim.tick()


func _t_victory_after_surviving_mature() -> void:
	var sim := _colony(_cfg(), 1)
	_run(sim, sim.cfg.victory_survive_s + 2.0)
	_check("gana tras sobrevivir victory_survive_s en Colonia madura con la reina viva",
		sim.game_over and sim.victory, "game_over=%s victory=%s era=%d" % [sim.game_over, sim.victory, sim.era])
	_check("game_over_reason queda con el texto de victoria, no el de derrota",
		sim.game_over_reason == "La colonia prosperó.", sim.game_over_reason)


func _t_no_victory_before_threshold() -> void:
	var sim := _colony(_cfg(), 2)
	_run(sim, sim.cfg.victory_survive_s * 0.5)
	_check("no gana antes de cumplir victory_survive_s", not sim.game_over and not sim.victory)


func _t_queen_death_before_threshold_is_defeat_not_victory() -> void:
	var sim := _colony(_cfg(), 3)
	_run(sim, 1.0)  # ya en Colonia madura (umbral bajado), pero lejos de victory_survive_s.
	sim.ants._kill(sim.queen_id, true)
	sim.tick()
	_check("la reina muerta antes de tiempo es derrota, no victoria",
		sim.game_over and not sim.victory and sim.game_over_reason == "La reina murió.")


## El modo incremental no pasa por `elif queen_id >= 0:` en `tick()` (nunca llama `spawn_colony_court`,
## así que `queen_id` queda en -1), que es la única rama que llama `_check_victory()`: confirma que
## la Fase 3 sigue exactamente igual que antes de esta fase, sin importar cuánto tiempo pase.
func _t_incremental_mode_never_wins() -> void:
	var cfg := SimConfig.new()
	cfg.rain_auto = false
	cfg.victory_survive_s = 0.01  # si se colara el chequeo, ganaría casi de inmediato.
	var sim := Simulation.new(cfg, 4)
	sim.spawn_incremental_start()
	_run(sim, 3.0)
	_check("el modo incremental nunca dispara victoria", not sim.victory, "victory=%s game_over=%s" % [sim.victory, sim.game_over])


func _t_save_load_keeps_victory_progress() -> void:
	var sim := _colony(_cfg(), 5)
	_run(sim, 1.0)  # ya en Colonia madura, con el cronómetro de victoria corriendo.
	var d := SaveSystem.to_dict(sim)
	var loaded := SaveSystem.from_dict(d, sim.cfg)
	_check("cargar conserva si ya está en Colonia madura (cronómetro de victoria)",
		loaded._mature_since_s == sim._mature_since_s, "guardado=%.2f cargado=%.2f" % [sim._mature_since_s, loaded._mature_since_s])
	_run(loaded, sim.cfg.victory_survive_s)
	_check("la partida cargada puede seguir hasta ganar", loaded.game_over and loaded.victory)
