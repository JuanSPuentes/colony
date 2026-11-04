extends SceneTree
## Pruebas de la Fase 37 (balance tras el primer playtest): la reina rival aguanta más y sus hormigas
## la defienden, matar rivales da comida al instante y el huevo encarece más despacio.
## Uso: godot --headless --path . --script tools/test_phase37.gd      (código de salida 1 si algo falla)

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_t_queen_hp()
	_t_kill_rewards()
	_t_guards_defend_queen()
	_t_egg_cost()
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


func _rival_ant(sim: Simulation) -> int:
	for i in sim.ants.count:
		if sim.ants.alive[i] == 1 and sim.ants.faction[i] == 1:
			return i
	return -1


func _t_queen_hp() -> void:
	var sim := _fresh(1)
	_check("la reina rival de la primera estación tiene 200 de vida", is_equal_approx(sim.rival_colony.queen.max_hp, 200.0), "%.0f" % sim.rival_colony.queen.max_hp)


func _t_kill_rewards() -> void:
	var sim := _fresh(2)
	sim.colony.food = 0.0
	sim.colony.food_cap = 1000.0
	var r := _rival_ant(sim)
	sim.ants._kill(r, false)
	_check("matar una hormiga rival da comida al instante", is_equal_approx(sim.colony.food, sim.cfg.kill_food_rival_ant), "%.1f" % sim.colony.food)
	var mine := -1
	for i in sim.ants.count:
		if sim.ants.alive[i] == 1 and sim.ants.faction[i] == 0 and i != sim.queen_id:
			mine = i
			break
	var before := sim.colony.food
	sim.ants._kill(mine, false)
	_check("perder una propia no da nada", is_equal_approx(sim.colony.food, before))
	var q := sim.rival_colony.queen
	q.take_damage(q.hp + 1.0)
	_check("matar a la reina rival da su recompensa", is_equal_approx(sim.colony.food, before + sim.cfg.kill_food_rival_queen), "%.1f" % sim.colony.food)
	sim.colony.food_cap = sim.colony.food + 1.0
	var r2 := _rival_ant(sim)
	sim.ants._kill(r2, false)
	_check("la recompensa respeta el tope del Almacén", sim.colony.food <= sim.colony.food_cap + 0.001)


func _t_guards_defend_queen() -> void:
	var sim := _fresh(3)
	var q := sim.rival_colony.queen
	_check("sin golpes, la reina no está bajo ataque", not q.under_attack())
	# Una guardia rival lejos de su reina, y la reina recibe un golpe.
	var r := _rival_ant(sim)
	sim.ants.pos[r] = q.pos + Vector2(sim.cfg.cell_px * 12, 0.0)
	var d0 := sim.ants.pos[r].distance_to(q.pos)
	q.take_damage(1.0)
	_check("tras un golpe, está bajo ataque", q.under_attack())
	for t in 3 * sim.cfg.tick_rate:
		q.last_hit_tick = sim.tick_count  # la siguen golpeando
		sim.tick()
	_check("las guardias acuden a defenderla", sim.ants.pos[r].distance_to(q.pos) < d0 * 0.6, "%.0f -> %.0f px" % [d0, sim.ants.pos[r].distance_to(q.pos)])
	sim.tick_count += int((sim.cfg.rival_defend_s + 1.0) * sim.cfg.tick_rate)
	_check("sin golpes por un rato, deja de estar bajo ataque", not q.under_attack())


func _t_egg_cost() -> void:
	var sim := _fresh(4)
	var c0 := sim.econ.egg_cost()
	sim.econ.bought_eggs = 10
	var ratio := sim.econ.egg_cost() / c0
	_check("10 huevos después el precio sube como mucho un 50% (antes casi se duplicaba)", ratio <= 1.5, "x%.2f" % ratio)
