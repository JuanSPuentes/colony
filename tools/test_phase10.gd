extends SceneTree
## Pruebas de la Fase 10: tutorial guiado de "Juego normal" (modo incremental), que hasta ahora
## no tenía ninguna guía aunque es el modo que arranca primero en el menú desde la Fase 9.
## `TutorialView` ya existía para "Modo infinito" (colonia con reina); se agregó una segunda lista
## de pasos propia del modo incremental (cavar, comida, comprar huevo, comprar mejora), se
## excluyó el modo Test (tiene su propio panel, una burbuja de tutorial ahí solo estorbaría) y se
## arregló que el progreso no se reiniciaba al volver a arrancar partida (`main.gd::start()`).
## Uso: godot --headless --path . --script tools/test_phase10.gd      (código de salida 1 si algo falla)

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


func _cfg() -> SimConfig:
	var c := SimConfig.new()
	c.rain_auto = false
	return c


func _run() -> void:
	var tv := TutorialView.new()
	root.add_child(tv)
	await process_frame
	await process_frame

	# --- Modo incremental: pasos propios, en el orden cavar -> comida -> huevo -> mejora ---
	var sim := Simulation.new(_cfg(), 1)
	sim.spawn_incremental_start()
	tv.step = 0
	tv.update(sim)
	_check("arranca en el paso 0 (cavar)", tv.step == 0 and tv._label.text == TutorialView.STEPS_INCREMENTAL[0],
		"texto=%s" % tv._label.text)

	sim.dug = 1
	tv.update(sim)
	_check("cavar completa el paso 0 y pasa al 1 (comida)", tv.step == 1)

	sim.food_painted = true
	tv.update(sim)
	_check("pintar comida completa el paso 1 y pasa al 2 (comprar huevo)", tv.step == 2)

	sim.eggs_bought = 1
	tv.update(sim)
	_check("comprar un huevo completa el paso 2 y pasa al 3 (comprar mejora)", tv.step == 3)

	sim.upgrades_bought = 1
	tv.update(sim)
	_check("comprar una mejora completa el último paso y oculta la burbuja",
		tv.step >= TutorialView.STEPS_INCREMENTAL.size() and not tv._panel.visible)

	# --- cmd_buy_egg/cmd_buy_upgrade de verdad incrementan los contadores que lee el tutorial ---
	var sim2 := Simulation.new(_cfg(), 2)
	sim2.spawn_incremental_start()
	sim2.colony.food = 999999.0
	var eggs_before := sim2.eggs_bought
	sim2.cmd_buy_egg()
	_check("cmd_buy_egg incrementa sim.eggs_bought", sim2.eggs_bought == eggs_before + 1)
	var upgrades_before := sim2.upgrades_bought
	sim2.cmd_buy_upgrade(Upgrades.Stat.DAMAGE)
	_check("cmd_buy_upgrade incrementa sim.upgrades_bought", sim2.upgrades_bought == upgrades_before + 1)

	# --- "Modo infinito" (historia): sigue con sus 4 pasos de siempre, sin tocar ---
	var sim_h := Simulation.new(_cfg(), 3)
	sim_h.spawn_colony_court()
	tv.step = 0
	tv.update(sim_h)
	_check("modo historia arranca en su propio paso 0 (pintar comida)",
		tv.step == 0 and tv._label.text == TutorialView.STEPS[0])

	# --- Modo Test: nunca se muestra, sin importar el progreso que traiga ---
	var sim_t := Simulation.new(_cfg(), 4)
	sim_t.spawn_test_start()
	tv.step = 0
	tv.update(sim_t)
	_check("modo Test no muestra ninguna burbuja de tutorial", not tv._panel.visible)

	# --- Reinicio de partida: el progreso del tutorial no debe arrastrarse de una partida a otra ---
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.tutorial.step = 2
	main.start(main.seed_value)
	_check("main.start() reinicia el progreso del tutorial a 0", main.tutorial.step == 0)

	print("RESULTADO: %d correctas, %d fallidas" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
