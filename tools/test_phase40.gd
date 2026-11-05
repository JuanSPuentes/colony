extends SceneTree
## Pruebas de la Fase 40: guardado seguro. Escritura a prueba de cortes (temporal + copia `.bak`),
## carga que cae a la copia si el archivo está dañado, partidas de versiones más nuevas rechazadas,
## y guardado automático en su propio archivo.
## Uso: godot --headless --path . --script tools/test_phase40.gd      (código de salida 1 si algo falla)

const PATH := "user://test_phase40_save.json"
const BAK := PATH + SaveSystem.BACKUP_SUFFIX
const TMP := PATH + SaveSystem.TEMP_SUFFIX

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	_clean()
	_t_atomic_write()
	_t_falls_back_to_backup()
	_t_rejects_bad_saves()
	_t_migrate_version()
	await _t_autosave_rules()
	_clean()
	print("RESULTADO: %d correctas, %d fallidas" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("[%s] %s %s" % ["OK " if ok else "FALLA", label, detail])


func _clean() -> void:
	for p in [PATH, BAK, TMP]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _sim(seed_value: int) -> Simulation:
	var cfg := SimConfig.new()
	cfg.rain_auto = false
	var sim := Simulation.new(cfg, seed_value)
	sim.spawn_incremental_start(true)
	return sim


func _write_raw(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _t_atomic_write() -> void:
	var a := _sim(1)
	_check("guardar devuelve OK", SaveSystem.save_file(a, PATH) == OK)
	_check("la primera vez no hay copia ni temporal", FileAccess.file_exists(PATH) and not FileAccess.file_exists(BAK) and not FileAccess.file_exists(TMP))
	var b := _sim(2)
	b.tick_count = 12345
	SaveSystem.save_file(b, PATH)
	_check("al volver a guardar, el anterior pasa a ser la copia .bak", FileAccess.file_exists(BAK) and not FileAccess.file_exists(TMP))
	var loaded := SaveSystem.load_file(PATH, b.cfg)
	_check("se carga el guardado más nuevo", loaded != null and loaded.tick_count == 12345)


func _t_falls_back_to_backup() -> void:
	_clean()
	var a := _sim(3)
	a.tick_count = 111
	SaveSystem.save_file(a, PATH)
	var b := _sim(3)
	b.tick_count = 222
	SaveSystem.save_file(b, PATH)
	_write_raw(PATH, '{"version": 1, "seed": 3, "tick_co')  # cortado a la mitad
	var loaded := SaveSystem.load_file(PATH, a.cfg)
	_check("si el guardado está cortado, se carga la copia anterior", loaded != null and loaded.tick_count == 111)
	_write_raw(PATH, '{"version": 1, "seed": 3}')  # JSON válido pero incompleto
	loaded = SaveSystem.load_file(PATH, a.cfg)
	_check("si le faltan datos, también se carga la copia", loaded != null and loaded.tick_count == 111)
	DirAccess.remove_absolute(PATH)
	_check("sin el archivo principal, la copia sola alcanza", SaveSystem.load_file(PATH, a.cfg) != null)


func _t_rejects_bad_saves() -> void:
	_clean()
	_write_raw(PATH, "esto no es JSON")
	_check("un archivo ilegible sin copia no carga nada (no se rompe)", SaveSystem.load_file(PATH, SimConfig.new()) == null)
	var d := SaveSystem.to_dict(_sim(4))
	d["version"] = SaveSystem.SAVE_VERSION + 1
	_check("una partida de una versión más nueva no se carga", not SaveSystem.is_loadable(d))
	d["version"] = SaveSystem.SAVE_VERSION
	_check("la de la versión actual sí", SaveSystem.is_loadable(d))
	_clean()
	_check("sin archivos, no hay partida", SaveSystem.load_file(PATH, SimConfig.new()) == null)


func _t_migrate_version() -> void:
	var d := SaveSystem.to_dict(_sim(5))
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(d))
	_check("(preparación) el JSON devuelve la versión como número decimal", typeof(parsed["version"]) == TYPE_FLOAT)
	var m := SaveSystem.migrate(parsed)
	_check("al migrar, la versión queda como entero", typeof(m["version"]) == TYPE_INT and m["version"] == SaveSystem.SAVE_VERSION)
	parsed.erase("version")
	_check("un guardado sin versión cuenta como la 1", SaveSystem.migrate(parsed)["version"] == 1)


func _t_autosave_rules() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	main.auto_start = false
	root.add_child(main)
	await process_frame
	var had := FileAccess.file_exists(main.AUTOSAVE_PATH)
	var backup := FileAccess.get_file_as_string(main.AUTOSAVE_PATH) if had else ""
	if had:
		DirAccess.remove_absolute(main.AUTOSAVE_PATH)
	main.start(main.cfg.world_seed, null, "tutorial")
	main.autosave()
	_check("el tutorial no se guarda solo", not FileAccess.file_exists(main.AUTOSAVE_PATH))
	main.start(7, null, "incremental")
	main.sim.rival_colony.battle_active = true
	main._autosave_tick(main.AUTOSAVE_EVERY_S + 1.0)
	_check("durante una batalla no se guarda solo", not FileAccess.file_exists(main.AUTOSAVE_PATH))
	main.sim.rival_colony.battle_active = false
	main._autosave_tick(main.AUTOSAVE_EVERY_S + 1.0)
	_check("en Juego normal se guarda solo, en su propio archivo", FileAccess.file_exists(main.AUTOSAVE_PATH))
	_check("«Continuar» encuentra el guardado automático", main.newest_save_path() != "")
	DirAccess.remove_absolute(main.AUTOSAVE_PATH)
	if had:
		_write_raw(main.AUTOSAVE_PATH, backup)
	main.queue_free()
