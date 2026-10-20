class_name Centipede
extends RefCounted
## Fase 5: segunda amenaza. A diferencia de la araña (`Spider`, que solo caza en la superficie y
## asedia la entrada desde afuera), el ciempiés entra por los túneles ya cavados y puede alcanzar
## hormigas bajo tierra. Reusa el mismo mecanismo de BFS que `cmd_move_queen`/`AntCasteAI.think_queen`
## (`NestDistanceField.bfs_from`) para perseguir, recalculado cada `cfg.centipede_retarget_ticks`
## ticks (no cada tick: es un BFS de grilla completa) en vez de una vez como la orden de la reina.
## Para huir reusa `sim.fields.surface_dist`, que ya se mantiene solo sin que esto le agregue nada.

enum State { SEARCH, CHASE, ATTACK, RETREAT, GONE }

var sim: Simulation
var pos := Vector2.ZERO
var state: int = State.GONE
var hp := 0.0
var max_hp := 0.0
var target_ant := -1
var alive := false
## Campo de distancias hacia la celda del objetivo actual, recalculado cada `centipede_retarget_ticks`.
var _path_dist := PackedInt32Array()
var _path_target_cell := -1
var _retarget_at := 0


func _init(s: Simulation) -> void:
	sim = s


func spawn(strength: float) -> void:
	var cfg := sim.cfg
	max_hp = cfg.centipede_hp * strength
	hp = max_hp
	state = State.SEARCH
	alive = true
	target_ant = -1
	_path_target_cell = -1
	_retarget_at = 0
	# Entra por la misma boca del nido que cava el jugador, como una amenaza que se metió por el
	# túnel de siempre, no que aparece de la nada bajo tierra.
	pos = Vector2((cfg.nest_x + 0.5) * cfg.cell_px, (cfg.surface_y - 1 + 0.5) * cfg.cell_px)


func take_damage(amount: float) -> void:
	if not alive:
		return
	hp -= amount
	if hp <= 0.0:
		alive = false
		state = State.GONE
		sim.spawn_corpse(pos, sim.cfg.corpse_food_value_centipede)


func step(dt: float) -> void:
	if not alive:
		return
	var cfg := sim.cfg
	var ants := sim.ants
	match state:
		State.SEARCH, State.CHASE, State.ATTACK:
			if target_ant < 0 or ants.alive[target_ant] == 0:
				target_ant = _find_prey()
			if target_ant >= 0:
				var to: Vector2 = ants.pos[target_ant] - pos
				if to.length() <= cfg.centipede_bite_range:
					state = State.ATTACK
					ants.hp[target_ant] -= cfg.centipede_damage_per_s * dt
					if ants.hp[target_ant] <= 0.0:
						ants._kill(target_ant, false)
						target_ant = -1
						state = State.SEARCH
				else:
					state = State.CHASE
					_follow_path(_cell_index(ants.pos[target_ant]), cfg.centipede_speed, dt)
			# Sin presa: se queda cerca de la entrada (igual de simple que la araña en SIEGE),
			# esperando a que `_find_prey` encuentre algo alcanzable.
		State.RETREAT:
			_flee_to_surface(cfg.centipede_speed * 1.3, dt)
	if alive and state != State.RETREAT and hp < max_hp * cfg.centipede_flee_hp_pct:
		state = State.RETREAT
		sim.notify("El ciempiés huye.")


## A diferencia de `Spider._find_prey` (línea ~109 de spider.gd), no filtra por estar en
## superficie: esta es justo la diferencia de diseño con la araña, puede ver hormigas bajo tierra.
func _find_prey() -> int:
	var ants := sim.ants
	var cfg := sim.cfg
	var best := -1
	var best_d := cfg.centipede_sight_px
	for i in ants.count:
		if ants.alive[i] == 0 or ants.caste[i] == CasteDefs.Caste.QUEEN:
			continue
		var d := pos.distance_to(ants.pos[i])
		if d < best_d:
			best_d = d
			best = i
	return best


func _cell_index(p: Vector2) -> int:
	var cpx := float(sim.cfg.cell_px)
	var x := clampi(floori(p.x / cpx), 0, sim.world.w - 1)
	var y := clampi(floori(p.y / cpx), 0, sim.world.h - 1)
	return y * sim.world.w + x


## Sigue `_path_dist` greedy, célula a célula (mismo patrón que `AntCasteAI.think_queen` con
## `sim.queen_goal_dist`), recalculándolo solo cada `centipede_retarget_ticks` ticks o si cambió el
## objetivo.
func _follow_path(target_cell: int, speed: float, dt: float) -> void:
	var world := sim.world
	var w := world.w
	if target_cell != _path_target_cell or sim.tick_count >= _retarget_at:
		_path_target_cell = target_cell
		_path_dist = sim.fields.bfs_from([target_cell])
		_retarget_at = sim.tick_count + sim.cfg.centipede_retarget_ticks
	var ci := _cell_index(pos)
	if _path_dist.is_empty() or _path_dist[ci] >= NestDistanceField.FAR:
		return  # sin camino hoy (p.ej. tapiaron el túnel): espera al próximo recálculo
	var cx := ci % w
	var cy := ci / w
	var best_k := -1
	var best_d: int = NestDistanceField.FAR
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx := cx + dx
			var ny := cy + dy
			if not world.is_passable(nx, ny):
				continue
			if dx != 0 and dy != 0 and (not world.is_passable(cx + dx, cy) or not world.is_passable(cx, cy + dy)):
				continue  # nada de cortar esquinas de tierra, igual que `AntSystem._step`
			var nd: int = _path_dist[ny * w + nx]
			if nd < best_d:
				best_d = nd
				best_k = ny * w + nx
	if best_k < 0:
		return
	var dest := Vector2((best_k % w + 0.5) * sim.cfg.cell_px, (best_k / w + 0.5) * sim.cfg.cell_px)
	var to := dest - pos
	var d := to.length()
	var step := speed * sim.cfg.cell_px * dt
	pos += to.normalized() * minf(step, d) if d > 0.01 else Vector2.ZERO


## Huir reusa `sim.fields.surface_dist` (siempre al día, no hace falta BFS propio): bajar ese
## campo lleva derecho a la celda de superficie más cercana por un camino real.
func _flee_to_surface(speed: float, dt: float) -> void:
	var world := sim.world
	var fields := sim.fields
	var ci := _cell_index(pos)
	if fields.surface_dist[ci] == 0:
		alive = false
		state = State.GONE
		return
	var w := world.w
	var cx := ci % w
	var cy := ci / w
	var best_k := -1
	var best_d: int = fields.surface_dist[ci]
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx := cx + dx
			var ny := cy + dy
			if not world.is_passable(nx, ny):
				continue
			if dx != 0 and dy != 0 and (not world.is_passable(cx + dx, cy) or not world.is_passable(cx, cy + dy)):
				continue
			var nd: int = fields.surface_dist[ny * w + nx]
			if nd < best_d:
				best_d = nd
				best_k = ny * w + nx
	if best_k < 0:
		return
	var dest := Vector2((best_k % w + 0.5) * sim.cfg.cell_px, (best_k / w + 0.5) * sim.cfg.cell_px)
	var to := dest - pos
	var d := to.length()
	var step := speed * sim.cfg.cell_px * dt
	pos += to.normalized() * minf(step, d) if d > 0.01 else Vector2.ZERO
