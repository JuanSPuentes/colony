extends SceneTree
## Pruebas de la Fase 29: árbol madre encima del nido y lo que cae de él ("Juego normal").
## Uso: godot --headless --path . --script tools/test_phase29.gd      (código de salida 1 si algo falla)

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_t_layout()
	_t_drops()
	_t_pickup_and_food()
	_t_rot()
	_t_save_and_migrate()
	_t_roots()
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


func _drops(sim: Simulation) -> Array[Corpse]:
	var out: Array[Corpse] = []
	for c in sim.corpses:
		if c.is_tree_drop() and c.food_value > 0.0:
			out.append(c)
	return out


func _t_layout() -> void:
	for s in [1, 2, 3]:
		var sim := _fresh(s)
		var giants := 0
		var too_close := 0
		var trees := 0
		var mushrooms := 0
		for p in sim.plants:
			match p.kind:
				Plant.Kind.GIANT:
					giants += 1
				Plant.Kind.MUSHROOM:
					mushrooms += 1
				_:
					trees += 1
					if absi(p.cell.x - sim.cfg.nest_x) < sim.cfg.home_tree_clear_cells:
						too_close += 1
		_check("semilla %d: árbol madre sobre el nido" % s, sim.home_tree != null and sim.home_tree.x == sim.cfg.nest_x)
		_check("semilla %d: el árbol madre es el único gigante (y no hay otros árboles si así está configurado)" % s,
			giants == 0 and too_close == 0 and (trees == 0 if sim.cfg.home_tree_other_trees == 0 else trees <= sim.cfg.home_tree_other_trees + 1),
			"gigantes=%d cerca=%d árboles=%d" % [giants, too_close, trees])
		_check("semilla %d: siguen las cuevas de hongos" % s, mushrooms > 0)
	var classic := Simulation.new(_cfg(), 1)
	classic.spawn_incremental_start()
	_check("el mapa fijo (pruebas, Nivel 0) no tiene árbol madre", classic.home_tree == null)


func _t_drops() -> void:
	var sim := _fresh(4)
	var cfg := sim.cfg
	sim.home_tree.update(sim, cfg.home_tree_drop_interval_s * 3.0 + 0.01)
	_check("suelta a su ritmo (3 intervalos de día = 3 cosas)", _drops(sim).size() == 3, "%d" % _drops(sim).size())
	for k in 400:
		sim.home_tree.update(sim, cfg.home_tree_drop_interval_s)
	var drops := _drops(sim)
	_check("no pasa del máximo en el suelo", drops.size() == cfg.home_tree_max_drops, "%d" % drops.size())
	var near := true
	var on_grass := true
	var kinds := {}
	for c in drops:
		near = near and absf(c.pos.x / cfg.cell_px - (sim.home_tree.x + 0.5)) <= cfg.home_tree_drop_radius + 1
		on_grass = on_grass and floori(c.pos.y / cfg.cell_px) == cfg.surface_y - 1
		kinds[c.kind] = true
	_check("todo cae bajo la copa y sobre el pasto", near and on_grass)
	_check("caen hojas y semillas", kinds.has(Corpse.Kind.LEAF) and kinds.has(Corpse.Kind.SEED), str(kinds.keys()))
	# De noche cae la mitad.
	var night := _fresh(4)
	night.tick_count = int(cfg.day_length_s * (1.0 - cfg.night_fraction * 0.5) / night.dt)
	night.home_tree.update(night, cfg.home_tree_drop_interval_s * 4.0 + 0.01)
	_check("de noche cae la mitad", night.is_night() and _drops(night).size() == 2, "%d" % _drops(night).size())


func _t_pickup_and_food() -> void:
	var sim := _fresh(5)
	var cfg := sim.cfg
	var fruit := Corpse.new(Vector2((cfg.nest_x + 3.5) * cfg.cell_px, cfg.surface_y * cfg.cell_px - 1.0), cfg.drop_food_fruit, Corpse.Kind.FRUIT)
	sim.corpses.append(fruit)
	var ants := sim.ants
	var i := -1
	for k in ants.count:
		if ants.alive[k] == 1 and ants.caste[k] == CasteDefs.Caste.WORKER:
			i = k
			break
	ants.pos[i] = fruit.pos
	var ci := ants._cell_index(ants.pos[i])
	ants._corpse_logic(i, ci % sim.world.w, ci / sim.world.w, ci)
	_check("una obrera levanta la fruta con su valor", ants.carry[i] == 1 and ants.carry_kind[i] == AntSystem.CARRY_DROP + Corpse.Kind.FRUIT - 1
		and is_equal_approx(ants.carry_value[i], cfg.drop_food_fruit) and fruit.food_value == 0.0)
	ants._deliver(i)
	_check("al entregarla queda su comida en el nido", is_equal_approx(sim.drop_food_stored, cfg.drop_food_fruit))
	sim.colony.food = 10.0
	sim.econ.tick(0.0)
	_check("la economía la suma a la comida", is_equal_approx(sim.colony.food, 10.0 + cfg.drop_food_fruit) and sim.drop_food_stored == 0.0,
		"comida=%.1f" % sim.colony.food)


func _t_rot() -> void:
	var sim := _fresh(6)
	sim.home_tree.drop(sim)
	var c := _drops(sim)[0]
	c.age = sim.cfg.drop_decay_s + 1.0
	sim._update_corpses(0.0)
	_check("lo que nadie recoge se pudre", not sim.corpses.has(c))


func _t_save_and_migrate() -> void:
	var sim := _fresh(7)
	for k in 5:
		sim.home_tree.drop(sim)
	sim.home_tree.drop_acc = 2.5
	var loaded := SaveSystem.from_dict(SaveSystem.to_dict(sim), sim.cfg)
	var same := _drops(loaded).size() == 5
	for k in 5:
		same = same and _drops(loaded)[k].kind == _drops(sim)[k].kind
	_check("guardar y cargar conserva el árbol y lo caído", loaded.home_tree != null and loaded.home_tree.x == sim.home_tree.x
		and is_equal_approx(loaded.home_tree.drop_acc, 2.5) and same)
	var moved := Migration.migrate(sim, 99)
	_check("al mudarse, el mapa nuevo también tiene árbol madre", moved.home_tree != null)


## Las raíces son parte del dibujo de la tierra: salen del tronco, nunca sobre el pasto, y con la
## misma semilla (también tras guardar y cargar) son las mismas.
func _t_roots() -> void:
	var sim := _fresh(8)
	var w := sim.world.w
	var mask := sim.home_tree.root_mask(w, sim.world.h, sim.cfg.surface_y)
	var cells := 0
	var above := 0
	var near_trunk := false
	for i in mask.size():
		if mask[i] == 1:
			cells += 1
			if i / w <= sim.cfg.surface_y:
				above += 1
			if i / w == sim.cfg.surface_y + 1 and absi(i % w - sim.home_tree.x) <= 6:
				near_trunk = true
	_check("hay raíces bajo tierra, que salen del tronco", cells > 100 and near_trunk, "celdas=%d" % cells)
	_check("ninguna raíz queda sobre el pasto", above == 0)
	var loaded := SaveSystem.from_dict(SaveSystem.to_dict(sim), sim.cfg)
	_check("tras guardar y cargar, las mismas raíces", loaded.home_tree.root_mask(w, sim.world.h, sim.cfg.surface_y) == mask)
