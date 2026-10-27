class_name HomeTree
extends RefCounted
## Fase 29: el árbol madre, un árbol gigante plantado encima del nido en "Juego normal". No se
## cosecha directo (para eso están los demás árboles y, más adelante, escalarlo): suelta hojas,
## semillas y frutas alrededor del tronco a un ritmo fijo. Lo que cae es comida en el suelo
## (`Corpse` con su tipo), que las obreras recogen como los restos de un bicho. Comida segura pero
## limitada por el ritmo: la colonia no se muere de hambre, pero con esto solo no crece rápido.

var x := 0  # columna del tronco
var drop_acc := 0.0
## Azar propio (derivado de la semilla de la partida): lo que cae no corre la secuencia del azar del
## resto de la simulación, así que agregar el árbol no cambia cómo se comporta lo demás.
var rng := RandomNumberGenerator.new()


func _init(trunk_x: int, seed_value: int = 0) -> void:
	x = trunk_x
	rng.seed = hash([seed_value, "home_tree"])


## Avanza el reloj de caída y suelta lo que toque. De noche cae la mitad.
func update(sim: Simulation, dt: float) -> void:
	var cfg := sim.cfg
	drop_acc += dt * (0.5 if sim.is_night() else 1.0)
	while drop_acc >= cfg.home_tree_drop_interval_s:
		drop_acc -= cfg.home_tree_drop_interval_s
		if drops_on_ground(sim) < cfg.home_tree_max_drops:
			drop(sim)


func drops_on_ground(sim: Simulation) -> int:
	var n := 0
	for c in sim.corpses:
		if c.is_tree_drop() and c.food_value > 0.0:
			n += 1
	return n


## Suelta una cosa al azar bajo la copa, apoyada sobre el pasto.
func drop(sim: Simulation) -> void:
	var cfg := sim.cfg
	var r := rng.randf()
	var kind := Corpse.Kind.LEAF
	var value := cfg.drop_food_leaf
	if r < cfg.home_tree_fruit_chance:
		kind = Corpse.Kind.FRUIT
		value = cfg.drop_food_fruit
	elif r < cfg.home_tree_fruit_chance + cfg.home_tree_seed_chance:
		kind = Corpse.Kind.SEED
		value = cfg.drop_food_seed
	var cx := clampi(x + rng.randi_range(-cfg.home_tree_drop_radius, cfg.home_tree_drop_radius), 1, sim.world.w - 2)
	var p := Vector2((cx + rng.randf_range(0.2, 0.8)) * cfg.cell_px, cfg.surface_y * cfg.cell_px - 1.0)
	sim.corpses.append(Corpse.new(p, value, kind))
