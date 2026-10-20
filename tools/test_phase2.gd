extends SceneTree
## Pruebas de la Fase 2: guardado y carga de partida (ver sim/save_system.gd).
## Uso: godot --headless --path . --script tools/test_phase2.gd      (código de salida 1 si algo falla)

var _pass := 0
var _fail := 0
const SAVE_PATH := "user://test_phase2_save.json"


func _initialize() -> void:
	_t_roundtrip_in_memory()
	_t_file_roundtrip()
	_t_continues_deterministically_after_load()
	_t_missing_file_returns_null()
	_t_works_without_colony()
	_t_rooms_and_rain_survive()
	print("RESULTADO: %d correctas, %d fallidas" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("[%s] %s %s" % ["OK " if ok else "FALLA", label, detail])


func _cfg(ants := 30) -> SimConfig:
	var c := SimConfig.new()
	c.initial_ants = ants
	c.rain_auto = false
	return c


func _colony(cfg: SimConfig, seed_value: int) -> Simulation:
	var sim := Simulation.new(cfg, seed_value)
	sim.spawn_colony_court()
	return sim


func _run(sim: Simulation, seconds: float) -> void:
	for i in int(seconds * sim.cfg.tick_rate):
		sim.tick()


# --- Pruebas ----------------------------------------------------------------------------------

func _t_roundtrip_in_memory() -> void:
	var sim := _colony(_cfg(40), 1)
	sim.colony.food = 250.0
	sim.cmd_mark(sim.cfg.nest_x + 3, sim.cfg.surface_y + 2)
	_run(sim, 20.0)
	var before := sim.checksum()
	var loaded := SaveSystem.from_dict(SaveSystem.to_dict(sim), sim.cfg)
	_check("guardar y cargar en memoria da la misma huella", loaded.checksum() == before, "%d / %d" % [before, loaded.checksum()])
	_check("la población coincide", loaded.ants.alive_count == sim.ants.alive_count, "%d / %d" % [sim.ants.alive_count, loaded.ants.alive_count])
	_check("la reina sigue siendo la reina", loaded.queen_id == sim.queen_id and loaded.ants.caste[loaded.queen_id] == CasteDefs.Caste.QUEEN)


func _t_file_roundtrip() -> void:
	var sim := _colony(_cfg(25), 2)
	sim.colony.food = 180.0
	_run(sim, 15.0)
	var before := sim.checksum()
	var err := SaveSystem.save_file(sim, SAVE_PATH)
	_check("guardar a un archivo real no da error", err == OK, "error=%d" % err)
	var loaded := SaveSystem.load_file(SAVE_PATH, sim.cfg)
	_check("cargar desde ese archivo da la misma huella", loaded != null and loaded.checksum() == before)


func _t_continues_deterministically_after_load() -> void:
	var a := _colony(_cfg(35), 3)
	a.colony.food = 300.0
	_run(a, 25.0)
	var loaded := SaveSystem.from_dict(SaveSystem.to_dict(a), a.cfg)
	_run(a, 30.0)
	_run(loaded, 30.0)
	_check("tras cargar, la partida sigue exactamente igual que si nunca se hubiera guardado", a.checksum() == loaded.checksum(), "%d / %d" % [a.checksum(), loaded.checksum()])


func _t_missing_file_returns_null() -> void:
	var loaded := SaveSystem.load_file("user://esto_no_existe_%d.json" % Time.get_ticks_usec(), SimConfig.new())
	_check("cargar un archivo que no existe da null, no revienta", loaded == null)


func _t_works_without_colony() -> void:
	# Fase 0: una Simulation sin spawn_colony_court() (sin reina) también se guarda y se carga.
	var sim := Simulation.new(_cfg(50), 4)
	_run(sim, 15.0)
	var before := sim.checksum()
	var loaded := SaveSystem.from_dict(SaveSystem.to_dict(sim), sim.cfg)
	_check("una colonia sin reina (Fase 0) también se guarda y se carga", loaded.queen_id == -1 and loaded.checksum() == before)


func _t_rooms_and_rain_survive() -> void:
	var sim := _colony(_cfg(0), 5)
	var sy := sim.cfg.surface_y
	var nx := sim.cfg.nest_x
	var y0 := sy + sim.cfg.shaft_depth + sim.cfg.chamber_h
	for y in range(y0, y0 + 2):
		for x in range(nx - 3, nx + 3):
			sim.world.cells[y * sim.world.w + x] = WorldGrid.Cell.TUNNEL
	sim.fields.recompute_terrain()
	for y in range(y0, y0 + 2):
		for x in range(nx - 3, nx + 3):
			sim.cmd_assign_room(x, y, WorldGrid.Room.STORAGE)
	sim.cmd_force_rain()
	_run(sim, 5.0)
	var loaded := SaveSystem.from_dict(SaveSystem.to_dict(sim), sim.cfg)
	_check("las cámaras designadas sobreviven al guardado", loaded.rooms.counts[WorldGrid.Room.STORAGE] == sim.rooms.counts[WorldGrid.Room.STORAGE], "%d / %d" % [sim.rooms.counts[WorldGrid.Room.STORAGE], loaded.rooms.counts[WorldGrid.Room.STORAGE]])
	_check("la lluvia en curso sobrevive al guardado", loaded.weather == sim.weather and absf(loaded.water.volume - sim.water.volume) < 0.01)
