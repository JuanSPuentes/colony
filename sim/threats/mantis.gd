class_name Mantis
extends RefCounted
## Fase 7: tercera amenaza. A diferencia de la araña (`Spider`, caza activa en superficie) y el
## ciempiés (`Centipede`, persigue por los túneles), la mantis se queda quieta y camuflada en un
## punto fijo de la superficie: nunca persigue, pero si una hormiga se acerca lo suficiente le pega
## mucho más fuerte que las otras dos. Sin pathing de ningún tipo (ni BFS ni caminar): toda su
## posición se decide una sola vez en `spawn()`.

enum State { HIDDEN, ATTACK, RETREAT, GONE }

var sim: Simulation
var pos := Vector2.ZERO
var state: int = State.GONE
var hp := 0.0
var max_hp := 0.0
var target_ant := -1
var alive := false


func _init(s: Simulation) -> void:
	sim = s


## Elige un punto de superficie fijo cerca del nido (mismo rango que usa `_place_plants` para las
## plantas) y se queda ahí para siempre mientras esté `HIDDEN`/`ATTACK`.
func spawn(strength: float) -> void:
	var cfg := sim.cfg
	max_hp = cfg.mantis_hp * strength
	hp = max_hp
	state = State.HIDDEN
	alive = true
	target_ant = -1
	var d := sim.rng.randf_range(cfg.plant_min_dist, cfg.plant_max_dist)
	var side := 1 if sim.rng.randf() < 0.5 else -1
	var x := clampi(cfg.nest_x + side * int(round(d)), 3, sim.world.w - 4)
	pos = Vector2((x + 0.5) * cfg.cell_px, (cfg.surface_y - 1 + 0.5) * cfg.cell_px)


func take_damage(amount: float) -> void:
	if not alive:
		return
	hp -= amount
	if hp <= 0.0:
		alive = false
		state = State.GONE
		sim.spawn_corpse(pos, sim.cfg.corpse_food_value_mantis)


func step(dt: float) -> void:
	if not alive:
		return
	var cfg := sim.cfg
	var ants := sim.ants
	match state:
		State.HIDDEN, State.ATTACK:
			if target_ant < 0 or ants.alive[target_ant] == 0:
				target_ant = _find_prey()
			if target_ant >= 0:
				state = State.ATTACK
				ants.hp[target_ant] -= cfg.mantis_damage_per_s * dt
				if ants.hp[target_ant] <= 0.0:
					ants._kill(target_ant, false)
					target_ant = -1
					state = State.HIDDEN
			else:
				state = State.HIDDEN
		State.RETREAT:
			# Misma huida simple que `Spider.State.RETREAT`: camina hacia el borde del mapa y
			# desaparece. La mantis no persigue nunca, pero sí puede huir si la hieren de cerca.
			var dir := 1.0 if pos.x > sim.world.w * cfg.cell_px * 0.5 else -1.0
			pos.x += dir * cfg.ant_speed * 1.4 * cfg.cell_px * dt
			if pos.x < 0.0 or pos.x > float(sim.world.w * cfg.cell_px):
				alive = false
				state = State.GONE
	if alive and state != State.RETREAT and hp < max_hp * cfg.mantis_flee_hp_pct:
		state = State.RETREAT
		sim.notify("La mantis huye.")


## Igual que `Spider._find_prey`: solo ve en superficie, solo obreras sueltas. A diferencia de la
## araña, el rango es `mantis_strike_range_px` (corto): no "ve" de lejos, solo reacciona a lo que
## ya está encima.
func _find_prey() -> int:
	var ants := sim.ants
	var cfg := sim.cfg
	var best := -1
	var best_d := cfg.mantis_strike_range_px
	for i in ants.count:
		if ants.alive[i] == 0 or ants.caste[i] != CasteDefs.Caste.WORKER:
			continue
		if ants.pos[i].y >= cfg.surface_y * cfg.cell_px:
			continue  # bajo tierra: a salvo de la mantis
		var d := pos.distance_to(ants.pos[i])
		if d < best_d:
			best_d = d
			best = i
	return best
