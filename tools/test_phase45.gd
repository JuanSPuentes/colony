extends SceneTree
## Pruebas de la Fase 45 (sonido, temblor, «!» y destello) y de la Fase 44 (huida y alarma de las
## obreras). No escucha nada: comprueba que los sonidos se generan, que suenan cuando pasa lo que
## tiene que pasar y que la simulación sigue igual.
## Uso: godot --headless --path . --script tools/test_phase45.gd      (código de salida 1 si algo falla)

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


func _new_sim() -> Simulation:
	var cfg := SimConfig.new()
	cfg.rain_auto = false
	var sim := Simulation.new(cfg, 3)
	sim.spawn_incremental_start(true)
	return sim


func _run() -> void:
	# --- Sonidos generados ---
	var all_ok := true
	for key in Sfx.SOUNDS:
		var spec: Dictionary = Sfx.SOUNDS[key]
		var st := SoundSynth.make(spec)
		var n := int(float(spec.get("dur", 0.15)) * SoundSynth.RATE)
		var loud := 0
		for k in range(0, st.data.size(), 2):
			loud = maxi(loud, absi(st.data.decode_s16(k)))
		if st.data.size() != n * 2 or loud < 500:
			all_ok = false
			print("   sonido malo: ", key, " tamaño ", st.data.size(), " pico ", loud)
	_check("cada sonido se genera con su duración y se oye", all_ok)
	_check("el mismo sonido se genera siempre igual",
		SoundSynth.make(Sfx.SOUNDS["hit"]).data == SoundSynth.make(Sfx.SOUNDS["hit"]).data)

	var sfx := Sfx.new()
	root.add_child(sfx)
	await process_frame
	_check("el reproductor crea el bus de efectos", AudioServer.get_bus_index(Sfx.BUS) >= 0)
	_check("Sfx.find lo encuentra", Sfx.find(self) == sfx)
	sfx.play("dig")
	var after_first: int = sfx._next
	sfx.play("dig")
	_check("el mismo sonido no se repite antes de su espera (cavar)", sfx._next == after_first)
	sfx.play("egg")
	_check("otro sonido sí suena", sfx._next == (after_first + 1) % Sfx.VOICES)
	var b := Button.new()
	root.add_child(b)
	_check("los botones nuevos quedan con su clic", b.pressed.get_connections().size() > 0)
	b.queue_free()

	var settings := AppSettings.new()
	settings.sfx_volume = 0.0
	settings.apply_volume()
	_check("volumen de efectos en 0 silencia su bus", AudioServer.is_bus_mute(AudioServer.get_bus_index(Sfx.BUS)))
	settings.sfx_volume = 0.5
	settings.apply_volume()
	_check("volumen de efectos en 50% lo vuelve a prender",
		not AudioServer.is_bus_mute(AudioServer.get_bus_index(Sfx.BUS)) and absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(Sfx.BUS)) - linear_to_db(0.5)) < 0.01)

	# --- Director: qué suena y cuándo tiembla ---
	var sim := _new_sim()
	var director := SfxDirector.new()
	root.add_child(director)
	var shakes: Array[float] = []
	director.shake_requested.connect(func(s: float) -> void: shakes.append(s))
	director.setup(sim)
	sfx._last_played.clear()
	sim.dug += 1
	director._process(0.016)
	_check("cavar una celda suena", sfx._last_played.has("dig"))
	_check("lo que no pasó no suena", not sfx._last_played.has("deliver") and not sfx._last_played.has("death"))
	sim.rival_colony.queen.take_damage(sim.rival_colony.queen.hp + 1.0)
	director._process(0.016)
	_check("matar a la reina rival suena y hace temblar", sfx._last_played.has("queen_kill") and shakes.size() == 1)
	sim.game_over = true
	sim.victory = false
	director._process(0.016)
	_check("perder suena y tiembla", sfx._last_played.has("defeat") and shakes.size() == 2)
	var next_sim := _new_sim()
	next_sim.season_index = sim.season_index + 1
	director.setup(next_sim)
	_check("pasar de estación suena", sfx._last_played.has("season"))

	# --- Fase 44: huida y alarma ---
	sim = _new_sim()
	var cfg := sim.cfg
	var y := cfg.surface_y - 1
	var far_x := sim.world.w - 6
	var w := sim.ants.add_ant_at(Vector2i(far_x, y), CasteDefs.Caste.WORKER)
	var r := sim.ants.add_ant_at(Vector2i(far_x - 1, y), CasteDefs.Caste.SOLDIER, 1)
	sim.ants.next_think[w] = sim.tick_count
	sim.tick()
	_check("lejos del nido, la obrera atacada por una rival huye",
		sim.ants.state[w] == AntSystem.State.FLEE_ENEMY, AntSystem.STATE_NAMES[sim.ants.state[w]])
	_check("y da la alarma donde está la rival", sim.ants.alarm_active() and sim.ants.alarm_pos.distance_to(sim.ants.pos[r]) < cfg.cell_px * 2)
	for k in 20:  # 1 s: menos que la huida mínima
		sim.tick()
	_check("no vuelve a pelear antes de la huida mínima", sim.ants.alive[w] == 0 or sim.ants.state[w] == AntSystem.State.FLEE_ENEMY)
	_check("la alarma sigue activa un rato", sim.ants.alarm_active())
	for k in int((cfg.alarm_s + 1.0) * cfg.tick_rate):
		sim.tick()
	_check("la alarma se apaga sola", not sim.ants.alarm_active())

	sim = _new_sim()
	var nest_cell: int = sim.world.nest_cells[0]
	var nc := Vector2i(nest_cell % sim.world.w, nest_cell / sim.world.w)
	var w2 := sim.ants.add_ant_at(nc, CasteDefs.Caste.WORKER)
	sim.ants.add_ant_at(nc, CasteDefs.Caste.SOLDIER, 1)
	sim.ants.next_think[w2] = sim.tick_count
	sim.tick()
	_check("en el nido, la obrera no huye: defiende", sim.ants.state[w2] == AntSystem.State.ATTACK,
		AntSystem.STATE_NAMES[sim.ants.state[w2]])

	sim = _new_sim()
	var sold := sim.ants.add_ant_at(Vector2i(cfg.nest_x, y), CasteDefs.Caste.SOLDIER)
	sim.ants.raise_alarm(Vector2((cfg.nest_x + 30) * cfg.cell_px, (y + 0.5) * cfg.cell_px))
	sim.ants.next_think[sold] = sim.tick_count
	var d0: float = sim.ants.pos[sold].distance_to(sim.ants.alarm_pos)
	for k in 60:
		sim.tick()
	_check("un soldado sin pelea acude a la alarma", sim.ants.pos[sold].distance_to(sim.ants.alarm_pos) < d0 - cfg.cell_px * 3,
		"%.0f -> %.0f" % [d0, sim.ants.pos[sold].distance_to(sim.ants.alarm_pos)])

	var saved := SaveSystem.from_dict(SaveSystem.to_dict(sim), sim.cfg)
	_check("la alarma se guarda y se carga", saved.ants.alarm_tick == sim.ants.alarm_tick and saved.ants.alarm_pos == sim.ants.alarm_pos)

	# --- Fase 45: «!» y destello ---
	sim = _new_sim()
	var renderer := AntRenderer.new()
	root.add_child(renderer)
	renderer.setup(sim)
	var a := sim.ants.add_ant_at(Vector2i(far_x, y), CasteDefs.Caste.WORKER)
	renderer.update(1.0)
	_check("sin huir no hay «!»", renderer._alert_mm.visible_instance_count == 0)
	sim.ants.state[a] = AntSystem.State.FLEE_ENEMY
	sim.ants.hp[a] -= 1.0
	renderer.update(1.0)
	_check("la obrera que huye muestra «!» (palito y punto)", renderer._alert_mm.visible_instance_count == 2)
	_check("al recibir daño destella", renderer._flash[a] > 0)
	for k in AntRenderer.FLASH_FRAMES + 1:
		renderer.update(1.0)
	_check("el destello se apaga solo", renderer._flash[a] == 0)

	print("\n%d bien, %d fallas" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
