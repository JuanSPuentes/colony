extends SceneTree
## Pruebas de la Fase 36 (playtest del 2026-11-04): las hormigas no depositan sobre los rastros que
## pinta el jugador, y la colonia se lleva su nido (túneles y cámaras) al mudarse de estación.
## Uso: godot --headless --path . --script tools/test_phase36.gd      (código de salida 1 si algo falla)

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_t_no_deposit_on_painted()
	_t_nest_survives_migration()
	print("RESULTADO: %d correctas, %d fallidas" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("[%s] %s %s" % ["OK " if ok else "FALLA", label, detail])


func _fresh(seed_value: int) -> Simulation:
	var cfg := SimConfig.new()
	cfg.rain_auto = false
	var sim := Simulation.new(cfg, seed_value)
	sim.spawn_incremental_start(true)
	return sim


func _t_no_deposit_on_painted() -> void:
	var sim := _fresh(1)
	var cfg := sim.cfg
	var y := cfg.surface_y - 1
	var painted := y * sim.world.w + cfg.nest_x + 3
	var plain := y * sim.world.w + cfg.nest_x + 6
	sim.cmd_paint_phero(sim.food, cfg.nest_x + 3, y, 0.4)
	var ant := -1
	for i in sim.ants.count:
		if sim.ants.alive[i] == 1 and sim.ants.faction[i] == 0 and i != sim.queen_id:
			ant = i
			break
	sim.ants.carry[ant] = 1
	sim.ants.trip_steps[ant] = 0
	sim.ants._on_enter(ant, painted)
	_check("una hormiga cargada no deposita Comida sobre lo pintado", is_equal_approx(sim.food.data[painted], 0.4), "%.3f" % sim.food.data[painted])
	sim.ants.trip_steps[ant] = 0
	sim.ants._on_enter(ant, plain)
	_check("fuera de lo pintado sigue dejando su rastro", sim.food.data[plain] > 0.0)
	var shaft := (cfg.surface_y + 1) * sim.world.w + cfg.nest_x
	sim.ants.trip_steps[ant] = 0
	sim.ants._on_enter(ant, shaft)
	_check("bajo tierra no deja Comida (nadie la sigue ahí y tapaba la salida)", sim.food.data[shaft] == 0.0)

	var home_c := (cfg.surface_y - 1) * sim.world.w + cfg.nest_x - 2
	sim.cmd_paint_phero(sim.home, cfg.nest_x - 2, cfg.surface_y - 1, 0.3)
	sim.ants.carry[ant] = 0
	sim.ants.state[ant] = AntSystem.State.EXPLORE
	sim.ants._on_enter(ant, home_c)
	_check("tampoco deposita Hogar sobre lo pintado", is_equal_approx(sim.home.data[home_c], 0.3), "%.3f" % sim.home.data[home_c])


func _t_nest_survives_migration() -> void:
	var old := _fresh(2)
	var cfg := old.cfg
	var w := old.world.w
	old._set_shaft(WorldGrid.Cell.TUNNEL)  # el jugador ya abrió el nido (el arranque lo trae cerrado)
	# Un pasillo nuevo bajo la Guardería, conectado al nido, etiquetado como Almacén.
	var y0 := cfg.surface_y + cfg.shaft_depth + cfg.chamber_h
	var dug: Array[int] = []
	for y in range(y0 - 1, y0 + 4):
		var i := y * w + cfg.nest_x
		old.world.cells[i] = WorldGrid.Cell.TUNNEL
		dug.append(i)
	old.world.room[dug[-1]] = WorldGrid.Room.STORAGE
	# Un hueco suelto, sin conexión al nido: no es parte del nido.
	var loose := (y0 + 10) * w + cfg.nest_x + 30
	old.world.cells[loose] = WorldGrid.Cell.TUNNEL
	old.world.passable_version += 1
	old.fields.recompute_terrain()
	var connected := true
	for i in dug:
		connected = connected and old.fields.nest_dist[i] < NestDistanceField.FAR
	_check("(preparación) el pasillo está unido al nido", connected)

	var sim := Migration.migrate(old, 99)
	var all_dug := true
	for i in dug:
		all_dug = all_dug and sim.world.cells[i] == WorldGrid.Cell.TUNNEL
	_check("el pasillo cavado viaja al mapa nuevo", all_dug)
	_check("con su etiqueta de cámara", sim.world.room[dug[-1]] == WorldGrid.Room.STORAGE)
	var same_rooms := true
	for i in range(cfg.surface_y * w, old.world.cells.size()):
		if old.world.room[i] != WorldGrid.Room.NONE and old.fields.nest_dist[i] < NestDistanceField.FAR:
			same_rooms = same_rooms and sim.world.room[i] == old.world.room[i]
	_check("todas las cámaras siguen donde estaban", same_rooms)
	var top := cfg.surface_y * w + cfg.nest_x
	_check("el nido abierto sigue abierto (el mapa nuevo lo traería cerrado)", sim.world.cells[top] == WorldGrid.Cell.TUNNEL and sim.fields.nest_dist[top - w] < NestDistanceField.FAR)
	_check("un hueco suelto (fuera del nido) no se suma al nido", old.fields.nest_dist[loose] >= NestDistanceField.FAR and sim.fields.nest_dist[loose] >= NestDistanceField.FAR)
	_check("el pasillo cuenta como nido en el mapa nuevo", sim.fields.nest_dist[dug[-1]] < NestDistanceField.FAR)
	var on_nest := true
	for i in sim.ants.count:
		if sim.ants.alive[i] == 1 and sim.ants.faction[i] == 0:
			var p := sim.ants.pos[i]
			var ci := int(p.y / cfg.cell_px) * w + int(p.x / cfg.cell_px)
			on_nest = on_nest and sim.fields.nest_dist[ci] < NestDistanceField.FAR
	_check("las hormigas llegan dentro del nido", on_nest)
