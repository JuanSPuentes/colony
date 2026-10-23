extends RefCounted
## Traduce una celda del mundo (ya resuelta por `main.gd` a partir del mouse) a los `cmd_*` de
## `Simulation` según la herramienta activa (cavar/feromona/cámara/borrar/mover reina). Separado
## de `main.gd` para que ese archivo se quede con entrada+cámara, no con las reglas de qué hace
## cada herramienta (ARCHITECTURE.md sección 4: "main.gd solo arma piezas, lee entrada y avanza
## el reloj").
##
## `main` no se tipa (sería `Node2D` con un montón de campos propios de `main.gd`, no una clase
## con nombre global): recibe la instancia de `main.gd` y lee/escribe sus campos (`tool`,
## `_erasing`, `_stroke_n`, `_last_cell`, `room_index`, `phero_index`, `cfg`, `sim`) igual que
## hacían estas funciones cuando vivían ahí.


static func current_phero(main) -> PheromoneField:
	var sim: Simulation = main.sim
	match main.PHERO_FIELDS[main.phero_index]:
		"home":
			return sim.home
		"danger":
			return sim.danger
		"attack":
			return sim.attack
		"evacuate":
			return sim.evacuate
		_:
			return sim.food


static func apply_line(main, from: Vector2i, to: Vector2i) -> void:
	if from.x < 0:
		apply_at(main, to)
		return
	var steps := maxi(absi(to.x - from.x), absi(to.y - from.y))
	for i in range(1, steps + 1):
		var t := float(i) / steps
		apply_at(main, Vector2i(roundi(lerpf(from.x, to.x, t)), roundi(lerpf(from.y, to.y, t))))


static func apply_at(main, c: Vector2i) -> void:
	if c == main._last_cell:
		return
	main._last_cell = c
	var sim: Simulation = main.sim
	match main.tool:
		1:
			if main._erasing:
				sim.cmd_unmark(c.x, c.y)
			else:
				sim.cmd_mark(c.x, c.y)
		2:
			var field := current_phero(main)
			if main._erasing:
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var n := snap(main, Vector2i(c.x + dx, c.y + dy))
						if sim.world.in_bounds(n.x, n.y):
							sim.cmd_erase_phero(field, n.x, n.y)
			else:
				# La rampa crece a lo largo del trazo: arrastra desde el nido hacia el objetivo.
				var cfg: SimConfig = main.cfg
				var value := minf(1.0, cfg.paint_start + cfg.paint_ramp * main._stroke_n)
				var painted := false
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var n := snap(main, Vector2i(c.x + dx, c.y + dy))
						painted = sim.cmd_paint_phero(field, n.x, n.y, value) or painted
				if painted:
					main._stroke_n += 1
		3:
			if main._erasing:
				sim.cmd_clear_room(c.x, c.y)
			else:
				sim.cmd_assign_room(c.x, c.y, main.ROOM_TYPES[main.room_index])
		4:
			sim.cmd_unmark(c.x, c.y)
			sim.cmd_clear_room(c.x, c.y)
			for field_name in main.PHERO_FIELDS:
				var f: PheromoneField = sim.get(field_name)
				sim.cmd_erase_phero(f, c.x, c.y)
		5:
			# Clic derecho: ordena a la reina caminar hasta ahí. Shift + clic derecho: cancela la orden
			# en curso (se queda donde esté parada, no vuelve atrás).
			if main._erasing:
				sim.queen_goal_cell = -1
			else:
				sim.cmd_move_queen(c.x, c.y)


## Un clic en el cielo pinta sobre la fila del suelo.
static func snap(main, c: Vector2i) -> Vector2i:
	var cfg: SimConfig = main.cfg
	if c.y < cfg.surface_y - cfg.walk_band:
		return Vector2i(c.x, cfg.surface_y - 1)
	return c
