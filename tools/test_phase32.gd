extends SceneTree
## Pruebas de la Fase 32 (etapa B del núcleo, NUCLEO.md): el árbol en disputa. Lo valioso cae en el
## medio, lejos de los dos nidos, y la rival también recoge lo que cae en su mitad del mapa.
## Uso: godot --headless --path . --script tools/test_phase32.gd      (código de salida 1 si algo falla)

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_t_rich_drops_in_the_middle()
	_t_rival_collects()
	_t_rival_only_its_half()
	_t_save_keeps_rival_food()
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
	sim.corpses.clear()  # sin la comida inicial junto a los nidos: se prueba solo lo del árbol
	return sim


func _drop_at(sim: Simulation, x: int, kind: Corpse.Kind, value: float) -> Corpse:
	var cfg := sim.cfg
	var c := Corpse.new(Vector2((x + 0.5) * cfg.cell_px, cfg.surface_y * cfg.cell_px - 1.0), value, kind)
	sim.corpses.append(c)
	return c


func _t_rich_drops_in_the_middle() -> void:
	var sim := _fresh(1)
	var cfg := sim.cfg
	var tree := sim.home_tree
	var rich_far := 0
	var leaf_far := 0
	var rich := 0
	for k in 400:
		tree.drop(sim)
	var rich_r := int(round(cfg.home_tree_drop_radius * cfg.home_tree_rich_spread))
	for c in sim.corpses:
		var dx := absf(c.pos.x / cfg.cell_px - (tree.x + 0.5))
		if c.kind == Corpse.Kind.LEAF:
			if dx > rich_r + 1:
				leaf_far += 1
		else:
			rich += 1
			if dx > rich_r + 1:
				rich_far += 1
	_check("semillas y frutas caen solo cerca del tronco", rich > 0 and rich_far == 0, "lejos=%d de %d" % [rich_far, rich])
	_check("las hojas siguen cayendo por toda la copa", leaf_far > 0)


func _t_rival_collects() -> void:
	var sim := _fresh(2)
	var cfg := sim.cfg
	var rival := sim.rival_colony
	var span := rival.rival_range()
	var x := clampi(rival.home_x + signi(rival.midpoint_x() - rival.home_x) * 8, span.x, span.y)
	var seed := _drop_at(sim, x, Corpse.Kind.SEED, cfg.drop_food_seed)
	var always_guard := true
	for t in int(90.0 / sim.dt):
		sim.tick()
		if rival.forager_count() > rival.forager_limit() or rival.forager_count() >= rival.alive_count():
			always_guard = false
		if rival.food_stored > 0.0:
			break
	_check("pocas recolectoras y siempre queda una guardia", always_guard)
	_check("una guardia rival recoge lo que cae en su mitad", seed.food_value == 0.0)
	_check("y lo lleva al montículo", is_equal_approx(rival.food_stored, cfg.drop_food_seed), "guardado=%.1f" % rival.food_stored)
	_check("pero no la hace crecer", rival.alive_count() == cfg.rival_start_ants)


func _t_rival_only_its_half() -> void:
	var sim := _fresh(3)
	var cfg := sim.cfg
	var rival := sim.rival_colony
	sim.home_tree = null  # que el árbol no suelte nada en su mitad: solo cuenta si cruza
	var mine := _drop_at(sim, cfg.nest_x, Corpse.Kind.FRUIT, cfg.drop_food_fruit)
	# Que nadie del jugador lo recoja: solo importa si la rival cruza a buscarlo.
	for i in sim.ants.count:
		if sim.ants.faction[i] == 0 and i != sim.queen_id:
			sim.ants.alive[i] = 0
	sim.ants._members_dirty = true
	for t in int(40.0 / sim.dt):
		sim.tick()
	_check("la rival no cruza a buscar comida a tu mitad", mine.food_value > 0.0 and rival.food_stored == 0.0,
		"fruta=%.0f guardado=%.0f" % [mine.food_value, rival.food_stored])


func _t_save_keeps_rival_food() -> void:
	var sim := _fresh(4)
	sim.rival_colony.store_food(12.0)
	var loaded := SaveSystem.from_dict(SaveSystem.to_dict(sim), sim.cfg)
	_check("guardar y cargar conserva lo que juntó la rival", is_equal_approx(loaded.rival_colony.food_stored, 12.0)
		and is_equal_approx(loaded.rival_colony.grow_acc, sim.rival_colony.grow_acc))
