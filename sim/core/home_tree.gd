class_name HomeTree
extends RefCounted
## Fase 29: el árbol madre, un árbol gigante plantado encima del nido en "Juego normal". No se
## cosecha directo (para eso están los demás árboles y, más adelante, escalarlo): suelta hojas,
## semillas y frutas alrededor del tronco a un ritmo fijo. Lo que cae es comida en el suelo
## (`Corpse` con su tipo), que las obreras recogen como los restos de un bicho. Comida segura pero
## limitada por el ritmo: la colonia no se muere de hambre, pero con esto solo no crece rápido.

## Cuántas raíces salen del tronco bajo tierra (ver `root_mask`).
const ROOTS := 8

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


## Fase 29: celdas de tierra por donde pasan las raíces (1 = raíz). Solo para el dibujo: la tierra
## se ve como madera ahí (y un túnel que la cruza, con pared de madera), pero se cava igual. Salen
## del tronco hacia los costados y hacia abajo, cada vez más finas; con la misma semilla, iguales.
func root_mask(w: int, h: int, surface_y: int) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(w * h)
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, "roots"])
	for k in ROOTS:
		var side := -1.0 if k % 2 == 0 else 1.0
		# Ángulo desde la horizontal hacia abajo: las de afuera, casi de lado; las del medio, más hondas.
		var angle := deg_to_rad(lerpf(12.0, 55.0, float(k / 2) / float(ROOTS / 2)) + r.randf_range(-6.0, 6.0))
		var dir := Vector2(cos(angle) * side, sin(angle))
		var p := Vector2(x + 0.5 + side * r.randf_range(1.0, 4.0), surface_y)
		var length := r.randf_range(18.0, 34.0)
		var radius := r.randf_range(1.6, 2.4)
		var step := 0.0
		while step < length:
			_stamp(mask, w, h, surface_y, p, radius * (1.0 - step / length * 0.7))
			dir = dir.rotated(r.randf_range(-0.12, 0.12))
			dir.y = maxf(dir.y, 0.05)  # nunca suben a la superficie
			p += dir.normalized() * 0.7
			step += 0.7
	return mask


static func _stamp(mask: PackedByteArray, w: int, h: int, surface_y: int, p: Vector2, radius: float) -> void:
	var rr := int(ceil(radius))
	for dy in range(-rr, rr + 1):
		for dx in range(-rr, rr + 1):
			var cx := int(p.x) + dx
			var cy := int(p.y) + dy
			if cx >= 0 and cx < w and cy > surface_y and cy < h and Vector2(dx, dy).length() <= radius:
				mask[cy * w + cx] = 1
