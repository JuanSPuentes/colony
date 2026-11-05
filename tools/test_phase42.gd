extends SceneTree
## Pruebas de la Fase 42: registro del playtest (`PlaytestLog`). Sin pantalla el registro está
## apagado; acá se enciende a mano y se escribe a un archivo de prueba que se borra al final.
## Uso: godot --headless --path . --script tools/test_phase42.gd      (código de salida 1 si algo falla)

const TEST_PATH := "user://test_phase42_log.json"

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run()


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("[%s] %s %s" % ["OK " if ok else "FALLA", label, detail])


func _clean() -> void:
	for p in [TEST_PATH, TEST_PATH + SaveSystem.BACKUP_SUFFIX]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _run() -> void:
	_clean()
	_check("sin pantalla (pruebas) el registro no escribe nada", not PlaytestLog.new("incremental").enabled)

	var cfg := SimConfig.new()
	cfg.rain_auto = false
	var sim := Simulation.new(cfg, 1)
	sim.spawn_incremental_start(true)
	sim.cmd_add_caste_ants(CasteDefs.Caste.WORKER, 20)
	var log := PlaytestLog.new("incremental")
	log.enabled = true
	log.path = TEST_PATH
	log.sample(0.5, sim, 1, true, false)  # frame largo de carga (en pausa: no suma tiempo jugado)
	_check("los primeros segundos (la carga) no cuentan como trabón", log.data["hitches"] == 0)
	log._age = PlaytestLog.WARMUP_S
	log.sample(0.5, sim, 1, false, false)
	log.sample(0.25, sim, 4, false, true)
	log.sample(0.2, sim, 4, true, false)  # en pausa: no suma tiempo jugado
	var d := log.data
	_check("cuenta el tiempo jugado sin la pausa", is_equal_approx(d["played_s"], 0.75), str(d["played_s"]))
	_check("separa el tiempo por velocidad", is_equal_approx(d["speed_s"]["1"], 0.5) and is_equal_approx(d["speed_s"]["4"], 0.25), str(d["speed_s"]))
	var mine: int = sim.ants.count_by_caste([CasteDefs.Caste.WORKER, CasteDefs.Caste.SOLDIER, CasteDefs.Caste.DRONE]).values().reduce(func(a, b): return a + b, 0)
	_check("guarda la colonia más grande (sin contar a la reina ni a la rival)", d["max_ants"] == mine, "%d vs %d" % [d["max_ants"], mine])
	_check("anota cuándo no llegó a la velocidad pedida y con cuántas hormigas", is_equal_approx(d["behind_s"], 0.25) and d["behind_max_ants"] == mine)
	_check("cuenta los trabones (frames largos)", d["hitches"] == 3 and is_equal_approx(d["worst_frame_ms"], 500.0), "%d, %.0f ms" % [d["hitches"], d["worst_frame_ms"]])
	sim.game_over = true
	sim.victory = false
	log.sample(0.016, sim, 1, false, false)
	_check("anota cómo terminó", d["result"] == "derrota")
	log.save()
	var saved = JSON.parse_string(FileAccess.get_file_as_string(TEST_PATH))
	_check("se guarda como JSON legible", saved is Dictionary and saved["max_ants"] == mine and saved["mode"] == "incremental")
	_clean()

	var main: Node = load("res://main.tscn").instantiate()
	main.auto_start = false
	root.add_child(main)
	await process_frame
	main.start(main.cfg.world_seed, null, "tutorial")
	_check("el tutorial no se registra", main.playtest_log == null)
	main.queue_free()
	await process_frame
	main = load("res://main.tscn").instantiate()
	main.auto_start = false
	root.add_child(main)
	await process_frame
	main.start(7, null, "incremental")
	var first: PlaytestLog = main.playtest_log
	_check("Juego normal sí se registra", first != null)
	main.start(8, null, "incremental")
	_check("cargar o mudarse sigue en la misma sesión", main.playtest_log == first)
	main.queue_free()
	await process_frame
	print("RESULTADO: %d correctas, %d fallidas" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
