extends SceneTree
## Pruebas de la Fase 31 (etapa A del núcleo, NUCLEO.md): la colonia rival vive en el mapa desde el
## principio, crece, manda incursiones y se gana la estación matando a su reina.
## Uso: godot --headless --path . --script tools/test_phase31.gd      (código de salida 1 si algo falla)

const SeasonSystem := preload("res://sim/colony/season_system.gd")

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_t_layout()
	_t_growth_and_raids()
	_t_guards_and_raiders()
	_t_patrols_stay_home()
	_t_attack_and_win()
	_t_win_without_attack()
	_t_last_day_fallback()
	_t_save_and_migrate()
	_t_classic_unchanged()
	print("RESULTADO: %d correctas, %d fallidas" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


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


func _fresh(seed_value: int) -> Simulation:
	var sim := Simulation.new(_cfg(), seed_value)
	sim.spawn_incremental_start(true)
	return sim


func _rivals(sim: Simulation, raiding := -1) -> Array[int]:
	var out: Array[int] = []
	for i in sim.ants.count:
		if sim.ants.alive[i] == 1 and sim.ants.faction[i] == 1 and (raiding < 0 or sim.ants.raiding[i] == raiding):
			out.append(i)
	return out


## Abre el pozo del nido del jugador (como si lo hubiera cavado).
func _open_nest(sim: Simulation) -> void:
	var w := sim.world.w
	for y in range(sim.cfg.surface_y, sim.cfg.surface_y + sim.cfg.shaft_depth):
		sim.world.cells[y * w + sim.cfg.nest_x] = WorldGrid.Cell.TUNNEL
		sim.world.changed.append(y * w + sim.cfg.nest_x)
	sim.world.passable_version += 1
	sim.fields.recompute_terrain()


func _t_layout() -> void:
	for s in [1, 2, 3, 4]:
		var sim := _fresh(s)
		var cfg := sim.cfg
		var rival := sim.rival_colony
		_check("semilla %d: la rival vive en el mapa, del otro lado" % s, rival.home and rival.queen.alive
			and absi(rival.home_x - cfg.nest_x) == cfg.rival_spawn_dist)
		_check("semilla %d: el árbol madre queda en el medio de los dos nidos" % s,
			sim.home_tree.x == (cfg.nest_x + rival.home_x) / 2, "árbol=%d nido=%d rival=%d" % [sim.home_tree.x, cfg.nest_x, rival.home_x])
		_check("semilla %d: arranca con %d guardias" % [s, cfg.rival_start_ants],
			_rivals(sim).size() == cfg.rival_start_ants and _rivals(sim, 1).is_empty())


func _t_growth_and_raids() -> void:
	var sim := _fresh(5)
	var cfg := sim.cfg
	var rival := sim.rival_colony
	rival.update_home(cfg.rival_grow_s[0] * 3.0 + 0.01)
	_check("crece una hormiga por intervalo", _rivals(sim).size() == cfg.rival_start_ants + 3, "%d" % _rivals(sim).size())
	_check("la próxima incursión se cuenta hacia atrás", rival.raid_eta_s() < cfg.rival_raid_s)
	rival.update_home(cfg.rival_raid_s)  # en esos segundos también crece: la mitad se cuenta al salir
	var raiders := _rivals(sim, 1).size()
	_check("cada incursión manda a la mitad", raiders == maxi(1, int(round(_rivals(sim).size() * cfg.rival_raid_fraction))),
		"incursión=%d de %d" % [raiders, _rivals(sim).size()])
	var noted := false
	for n in sim.notifications:
		noted = noted or n.begins_with("¡Incursión rival")
	_check("la incursión avisa", noted)
	var capped := _fresh(5)
	capped.rival_colony.update_home(cfg.rival_grow_s[0] * (cfg.rival_max_ants + 20))
	_check("no pasa del máximo de hormigas", _rivals(capped).size() <= cfg.rival_max_ants, "%d" % _rivals(capped).size())
	var later := _fresh(5)
	later.season_index = 3
	later.rival_colony.update_home(cfg.rival_grow_s[3] * 2.0 + 0.01)
	_check("en invierno crece más rápido", _rivals(later).size() == cfg.rival_start_ants + 2)


func _t_guards_and_raiders() -> void:
	var sim := _fresh(6)
	var cfg := sim.cfg
	var rival := sim.rival_colony
	for t in int(20.0 / sim.dt):
		sim.tick()
	var far := 0
	for i in _rivals(sim, 0):
		if absf(sim.ants.pos[i].x / cfg.cell_px - rival.home_x) > cfg.rival_guard_radius + 3:
			far += 1
	_check("las guardias se quedan cerca de su montículo", far == 0, "lejos=%d" % far)
	rival.update_home(cfg.rival_raid_s)
	var raiders := _rivals(sim, 1)
	var d0 := 0.0
	for i in raiders:
		d0 += absf(sim.ants.pos[i].x / cfg.cell_px - cfg.nest_x)
	for t in int(15.0 / sim.dt):
		sim.tick()
	var d1 := 0.0
	for i in raiders:
		d1 += absf(sim.ants.pos[i].x / cfg.cell_px - cfg.nest_x)
	_check("las de la incursión avanzan hacia el nido del jugador", d1 < d0, "distancia %.0f -> %.0f" % [d0, d1])


func _t_attack_and_win() -> void:
	var sim := _fresh(7)
	var rival := sim.rival_colony
	_open_nest(sim)
	_check("¡Atacar! pone a los soldados en modo batalla", sim.cmd_attack_rival() and rival.fighting() and not rival.battle_active)
	_check("no se puede pedir dos veces", not sim.cmd_attack_rival())
	var season0 := sim.season_index
	rival.queen.take_damage(99999.0)
	sim.tick()
	_check("matar a su reina gana la estación", sim.season_index == season0 + 1 and rival.battle_won and not rival.fighting())
	_check("y la colonia se muda a un mapa nuevo", sim.migration_pending)


func _t_win_without_attack() -> void:
	var sim := _fresh(8)
	sim.rival_colony.queen.take_damage(99999.0)
	sim.tick()
	_check("si su reina muere sin pedir ataque, igual se gana", sim.season_index == 1 and sim.migration_pending)
	var alive := _fresh(8)
	_check("la reina rival viva cuenta como amenaza fuera de una batalla",
		alive.ants._nearest_threat(alive.rival_colony.queen.pos, 4.0) == alive.rival_colony.queen)


func _t_last_day_fallback() -> void:
	var sim := _fresh(9)
	var rival := sim.rival_colony
	var qpos := rival.queen.pos
	var before := _rivals(sim).size()
	sim.tick_count = int((SeasonSystem.season_length(sim) - 1) * sim.cfg.day_length_s / sim.dt) + 10
	SeasonSystem.update(sim)
	_check("el último día igual llega la oleada final", rival.battle_active and _rivals(sim).size() > before)
	_check("en la oleada final todas van contra el nido y la reina no se mueve",
		_rivals(sim, 0).is_empty() and rival.queen.pos == qpos)


func _t_save_and_migrate() -> void:
	var sim := _fresh(10)
	var rival := sim.rival_colony
	rival.update_home(sim.cfg.rival_raid_s * 0.5)
	rival.update_home(sim.cfg.rival_raid_s * 0.6)
	var loaded := SaveSystem.from_dict(SaveSystem.to_dict(sim), sim.cfg)
	var lr := loaded.rival_colony
	_check("guardar y cargar conserva el montículo y sus relojes", lr.home and lr.home_x == rival.home_x
		and is_equal_approx(lr.raid_acc, rival.raid_acc) and is_equal_approx(lr.grow_acc, rival.grow_acc))
	_check("y quién está de incursión", _rivals(loaded, 1).size() == _rivals(sim, 1).size() and _rivals(loaded, 1).size() > 0)
	var hp0 := rival.queen.max_hp
	SeasonSystem._advance_season(sim)
	var moved := Migration.migrate(sim, 77)
	_check("al mudarse hay una rival nueva, más fuerte", moved.rival_colony.home and moved.rival_colony.queen.alive
		and moved.rival_colony.queen.max_hp > hp0 and _rivals(moved).size() == moved.cfg.rival_start_ants)
	_check("y el árbol sigue en el medio", moved.home_tree.x == (moved.cfg.nest_x + moved.rival_colony.home_x) / 2)


func _t_classic_unchanged() -> void:
	var sim := Simulation.new(_cfg(), 1)
	sim.spawn_incremental_start()
	_check("el mapa fijo (pruebas, Nivel 0) no tiene rival en el mapa", not sim.rival_colony.home and not sim.rival_colony.queen.alive)
	sim.rival_colony.start_battle(4, 1.0)
	_check("ahí la oleada final sigue igual: reina y rivales que atacan", sim.rival_colony.queen.alive and _rivals(sim, 1).size() == 4)


## Sin la orden de atacar, los soldados patrullan solo su mitad (hasta el árbol): no llegan solos al
## montículo ni matan a la reina rival por su cuenta (sí pueden perseguir una incursión un poco más allá). Con la orden, sí van.
func _t_patrols_stay_home() -> void:
	var sim := _fresh(11)
	var cfg := sim.cfg
	var rival := sim.rival_colony
	_open_nest(sim)
	sim.cmd_add_caste_ants(CasteDefs.Caste.SOLDIER, 9)
	var near_mound := 0
	for t in int(120.0 / sim.dt):
		sim.tick()
		if t % 20 == 0:
			for i in sim.ants.count:
				if sim.ants.alive[i] == 1 and sim.ants.faction[i] == 0 and sim.ants.caste[i] == CasteDefs.Caste.SOLDIER:
					# Perseguir a una incursión un poco más allá del árbol está bien (es defender);
					# llegar al montículo por su cuenta, no.
					if absf(sim.ants.pos[i].x / cfg.cell_px - rival.home_x) < 8.0:
						near_mound += 1
	_check("sin orden de ataque, los soldados no llegan al montículo rival", near_mound == 0, "veces cerca=%d" % near_mound)
	_check("y la reina rival sigue viva", rival.queen.alive and sim.season_index == 0)
	sim.cmd_attack_rival()
	for t in int(90.0 / sim.dt):
		sim.tick()
		if sim.season_index > 0:
			break
	_check("con la orden, marchan y la matan", sim.season_index == 1, "vida reina %.0f/%.0f" % [rival.queen.hp, rival.queen.max_hp])
