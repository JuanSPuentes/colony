class_name Spider
extends RefCounted
## Intruso simple de la Fase 1: caza obreras sueltas en la superficie y, si nadie la detiene en
## la entrada, amenaza a la reina. Simplificación deliberada: no encuentra camino real por los
## túneles; el riesgo de "invasión" se modela como un temporizador de asedio en la entrada
## (SIEGE) que solo se detiene si hay soldados cerca.

enum State { SEARCH, ATTACK, SIEGE, RETREAT, GONE }

var sim: Simulation
var pos := Vector2.ZERO
var state: int = State.GONE
var hp := 0.0
var max_hp := 0.0
var target_ant := -1
var siege_t := 0.0
var alive := false


func _init(s: Simulation) -> void:
	sim = s


func spawn(strength: float) -> void:
	var cfg := sim.cfg
	max_hp = cfg.spider_hp * strength
	hp = max_hp
	state = State.SEARCH
	siege_t = 0.0
	alive = true
	target_ant = -1
	var from_left := sim.rng.randf() < 0.5
	var x := 1 if from_left else sim.world.w - 2
	pos = Vector2((x + 0.5) * cfg.cell_px, (cfg.surface_y - 1 + 0.5) * cfg.cell_px)


func take_damage(amount: float) -> void:
	if not alive:
		return
	hp -= amount
	if hp <= 0.0:
		alive = false
		state = State.GONE


func step(dt: float) -> void:
	if not alive:
		return
	var cfg := sim.cfg
	var ants := sim.ants
	match state:
		State.SEARCH, State.ATTACK:
			if target_ant < 0 or ants.alive[target_ant] == 0:
				target_ant = _find_prey()
			if target_ant >= 0:
				var to: Vector2 = ants.pos[target_ant] - pos
				if to.length() <= cfg.spider_bite_range:
					state = State.ATTACK
					ants.hp[target_ant] -= cfg.spider_damage_per_s * dt
					if ants.hp[target_ant] <= 0.0:
						ants._kill(target_ant, false)
						target_ant = -1
						state = State.SEARCH
				else:
					state = State.SEARCH
					pos += to.normalized() * cfg.spider_speed * cfg.cell_px * dt
			else:
				var to_nest := float(cfg.nest_x * cfg.cell_px) - pos.x
				if absf(to_nest) > float(cfg.cell_px):
					pos.x += signf(to_nest) * cfg.spider_speed * cfg.cell_px * dt
				else:
					state = State.SIEGE
		State.SIEGE:
			target_ant = _find_prey()
			if target_ant >= 0:
				state = State.SEARCH
			elif _soldiers_near(pos, cfg.spider_siege_guard_range) > 0:
				siege_t = 0.0
			else:
				siege_t += dt
				if siege_t >= cfg.spider_siege_time_s and sim.queen_id >= 0 and ants.alive[sim.queen_id] == 1:
					sim.notify("¡La araña entró al nido! La reina está en peligro.")
					ants.hp[sim.queen_id] -= cfg.spider_invasion_damage
					if ants.hp[sim.queen_id] <= 0.0:
						ants._kill(sim.queen_id, false)
					siege_t = 0.0
		State.RETREAT:
			var dir := 1.0 if pos.x > sim.world.w * cfg.cell_px * 0.5 else -1.0
			pos.x += dir * cfg.spider_speed * 1.4 * cfg.cell_px * dt
			if pos.x < 0.0 or pos.x > float(sim.world.w * cfg.cell_px):
				alive = false
				state = State.GONE
	if alive and state != State.RETREAT:
		var near_soldiers := _soldiers_near(pos, cfg.spider_bite_range * 1.5)
		if hp < max_hp * cfg.spider_flee_hp_pct or near_soldiers >= cfg.spider_flee_soldiers:
			state = State.RETREAT
			sim.notify("La araña huye.")


func _find_prey() -> int:
	var ants := sim.ants
	var cfg := sim.cfg
	var best := -1
	var best_d := cfg.spider_sight_px
	for i in ants.count:
		if ants.alive[i] == 0 or ants.caste[i] != CasteDefs.Caste.WORKER:
			continue
		if ants.pos[i].y >= cfg.surface_y * cfg.cell_px:
			continue  # bajo tierra: a salvo de la araña
		var d := pos.distance_to(ants.pos[i])
		if d < best_d:
			best_d = d
			best = i
	return best


func _soldiers_near(p: Vector2, range_px: float) -> int:
	var ants := sim.ants
	var n := 0
	for i in ants.count:
		if ants.alive[i] == 1 and ants.caste[i] == CasteDefs.Caste.SOLDIER and ants.pos[i].distance_to(p) <= range_px:
			n += 1
	return n
