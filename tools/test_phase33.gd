extends SceneTree
## Pruebas de la Fase 33: árbol de mejoras del jugador (3 ramas de 4 mejoras, `sim/colony/upgrades.gd`).
## Uso: godot --headless --path . --script tools/test_phase33.gd      (código de salida 1 si algo falla)

const Id = Upgrades.Id

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_t_prerequisites_and_cost()
	_t_effects()
	_t_royal_assault()
	_t_healing()
	_t_big_load()
	_t_save_and_migration()
	_t_tree_window()
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
	sim.spawn_incremental_start()
	sim.colony.food = 1.0e6
	sim.colony.food_cap = 1.0e6
	return sim


func _t_prerequisites_and_cost() -> void:
	var sim := _fresh(1)
	var up := sim.upgrades
	_check("la segunda de una rama está bloqueada sin la primera",
		not up.can_buy(Id.MARCH) and not sim.cmd_buy_upgrade(Id.MARCH))
	var other := up.cost(Id.SHELL)
	_check("la primera de cada rama se puede comprar", sim.cmd_buy_upgrade(Id.MANDIBLES))
	_check("comprada, ya no se compra otra vez", not sim.cmd_buy_upgrade(Id.MANDIBLES))
	_check("y abre la siguiente de su rama", up.can_buy(Id.MARCH))
	_check("cada compra encarece las demás", up.cost(Id.SHELL) > other, "%.0f -> %.0f" % [other, up.cost(Id.SHELL)])
	sim.colony.food = 0.0
	_check("sin comida no se compra", not sim.cmd_buy_upgrade(Id.SHELL))


func _t_effects() -> void:
	var sim := _fresh(2)
	var ants := sim.ants
	var cell := Vector2i(sim.cfg.nest_x, sim.cfg.surface_y - 1)
	var w := ants.add_ant_at(cell, CasteDefs.Caste.WORKER)
	var s := ants.add_ant_at(cell, CasteDefs.Caste.SOLDIER)
	var q := sim.queen_id
	var hp_w := ants.hp[w]
	var hp_q := ants.hp[q]
	sim.cmd_buy_upgrade(Id.SHELL)
	sim.cmd_buy_upgrade(Id.TOUGH_QUEEN)
	_check("Reina robusta sube solo la vida de la reina",
		is_equal_approx(ants.hp[q], hp_q * 1.25 * 1.5) and is_equal_approx(ants.hp[w], hp_w * 1.25),
		"reina %.0f obrera %.1f" % [ants.hp[q], ants.hp[w]])
	sim.cmd_buy_upgrade(Id.MANDIBLES)
	sim.cmd_buy_upgrade(Id.MARCH)
	var up := sim.upgrades
	_check("Marcha acelera a los soldados y no a las obreras",
		up.speed_factor(ants.caste[s]) > 1.0 and is_equal_approx(up.speed_factor(ants.caste[w]), 1.0))
	sim.cmd_buy_upgrade(Id.DIGGERS)
	sim.cmd_buy_upgrade(Id.LIGHT_LEGS)
	sim.cmd_buy_upgrade(Id.KEEN_SCENT)
	_check("Patas ligeras acelera a las obreras", up.speed_factor(CasteDefs.Caste.WORKER) > 1.0)
	_check("Buen olfato: las obreras ven más lejos", up.sight_mult > 1.0)
	# Una semilla fuera de la vista normal pero dentro de la mejorada.
	var cfg := sim.cfg
	var d := cfg.sight_cells * cfg.cell_px * 1.2
	sim.corpses.clear()
	sim.corpses.append(Corpse.new(ants.pos[w] + Vector2(d, 0.0), cfg.drop_food_seed, Corpse.Kind.SEED))
	_check("y encuentran comida que antes no veían", ants._corpse_near(w) != null)


func _t_royal_assault() -> void:
	var sim := _fresh(3)
	var up := sim.upgrades
	var plain := up.damage(CasteDefs.Caste.SOLDIER, sim.rival_colony.queen)
	for id in [Id.MANDIBLES, Id.MARCH, Id.MANDIBLES_2, Id.ROYAL_ASSAULT]:
		sim.cmd_buy_upgrade(id)
	var vs_queen := up.damage(CasteDefs.Caste.SOLDIER, sim.rival_colony.queen)
	var vs_other := up.damage(CasteDefs.Caste.SOLDIER, null)
	_check("Asalto real: doble daño contra la reina rival",
		is_equal_approx(vs_queen, vs_other * 2.0) and vs_other > plain, "reina %.1f otros %.1f" % [vs_queen, vs_other])


func _t_healing() -> void:
	var sim := _fresh(4)
	var cfg := sim.cfg
	var ants := sim.ants
	var q := sim.queen_id
	ants.hp[q] = ants.max_hp(q) * 0.5
	for t in int(5.0 / sim.dt):
		sim.tick()
	_check("sin Curación la vida no sube sola", ants.hp[q] <= ants.max_hp(q) * 0.5 + 0.01)
	for id in [Id.SHELL, Id.TOUGH_QUEEN, Id.SHELL_2, Id.HEALING]:
		sim.cmd_buy_upgrade(id)
	var before := ants.hp[q]
	for t in int(5.0 / sim.dt):
		sim.tick()
	_check("con Curación se recupera dentro del nido", ants.hp[q] > before,
		"%.1f -> %.1f de %.1f" % [before, ants.hp[q], ants.max_hp(q)])
	var out := ants.add_ant_at(Vector2i(cfg.nest_x + 20, cfg.surface_y - 1), CasteDefs.Caste.SOLDIER)
	ants.hp[out] = ants.max_hp(out) * 0.5
	var out_before := ants.hp[out]
	sim.tick()
	_check("pero no en la superficie", ants.hp[out] <= out_before + 0.001)


func _t_big_load() -> void:
	var a := _fresh(5)
	var b := _fresh(5)
	for id in [Id.DIGGERS, Id.LIGHT_LEGS, Id.KEEN_SCENT, Id.BIG_LOAD]:
		b.cmd_buy_upgrade(id)
	a.colony.food = 100.0
	b.colony.food = 100.0
	a.drop_food_stored = 10.0
	b.drop_food_stored = 10.0
	a.econ.tick(0.0)
	b.econ.tick(0.0)
	_check("Carga grande: +50 % de comida por viaje", is_equal_approx(b.colony.food - 100.0, (a.colony.food - 100.0) * 1.5),
		"sin %.1f con %.1f" % [a.colony.food - 100.0, b.colony.food - 100.0])


func _t_save_and_migration() -> void:
	var cfg := SimConfig.new()
	cfg.rain_auto = false
	var sim := Simulation.new(cfg, 6)
	sim.spawn_incremental_start(true)
	sim.colony.food = 1.0e4
	sim.colony.food_cap = 1.0e4
	for id in [Id.SHELL, Id.TOUGH_QUEEN, Id.MANDIBLES]:
		sim.cmd_buy_upgrade(id)
	var loaded := SaveSystem.from_dict(SaveSystem.to_dict(sim), cfg)
	_check("guardar y cargar conserva el árbol", loaded.upgrades.bought == sim.upgrades.bought
		and is_equal_approx(loaded.upgrades.queen_hp_mult, sim.upgrades.queen_hp_mult)
		and is_equal_approx(loaded.upgrades.cost(Id.MARCH), sim.upgrades.cost(Id.MARCH)))
	_check("y la vida de la reina sigue sana (no se aplica dos veces)",
		is_equal_approx(loaded.ants.hp[loaded.queen_id], loaded.ants.max_hp(loaded.queen_id)))
	var moved := Migration.migrate(sim, 77)
	_check("la mudanza conserva el árbol", moved.upgrades.bought == sim.upgrades.bought)
	_check("y la reina llega con su vida mejorada",
		is_equal_approx(moved.ants.hp[moved.queen_id], moved.ants.max_hp(moved.queen_id)),
		"%.1f de %.1f" % [moved.ants.hp[moved.queen_id], moved.ants.max_hp(moved.queen_id)])


## Fase 34: la ventana del árbol (`UpgradeTreeView`): clic en un hexágono compra esa mejora.
func _t_tree_window() -> void:
	var sim := _fresh(7)
	var view := UpgradeTreeView.new()
	view.size = Vector2(1440, 810)
	view.sim = sim
	view._layout()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = view.hex_pos(Id.MARCH)
	view._gui_input(click)
	_check("clic en una mejora bloqueada no compra nada", not sim.upgrades.bought[Id.MARCH])
	click.position = view.hex_pos(Id.MANDIBLES)
	view._gui_input(click)
	_check("clic en una mejora disponible la compra", sim.upgrades.bought[Id.MANDIBLES])
	var lines := UpgradeTreeView.bonus_lines(sim.upgrades)
	_check("el resumen de la colonia muestra lo que suma", lines.size() == 1 and lines[0].contains("25"), str(lines))
	view.free()
