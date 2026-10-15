class_name Spider
extends RefCounted
## The first enemy. Enters the surface, hunts exposed ants, lingers at the entrance and,
## if the entrance is undefended for too long, invades the tunnels towards the queen.
## It retreats when badly hurt and dies when its health runs out.

enum S { ENTER, HUNT, INVADE, RETREAT, DEAD }

var state := S.ENTER
var pos := Vector2.ZERO
var prev_pos := Vector2.ZERO
var cell := Vector2i.ZERO
var hp := 90.0
var max_hp := 90.0
var power := 1
var speed := 2.1
var facing := 1
var anim := 0.0
var moving := false
var atk_cd := 0.0
var dwell := 0.0
var kills := 0
var path: Array[Vector2i] = []
var path_i := 0
var goal_x := Cfg.ENTRANCE_X
var emit_cd := 0.0
var flash := 0.0
var retreated := false
var invading: bool:
	get:
		return state == S.INVADE or (state == S.RETREAT and cell.y >= Cfg.SURFACE)


func _init(side: int, hp_value: float, level: int) -> void:
	var start_x := -3 if side < 0 else Cfg.W + 2
	cell = Vector2i(clampi(start_x, 0, Cfg.W - 1), Cfg.SURFACE_ROW)
	pos = Vector2(start_x * Cfg.CELL, (Cfg.SURFACE_ROW + 0.5) * Cfg.CELL)
	prev_pos = pos
	hp = hp_value
	max_hp = hp_value
	power = level
	facing = -side
	goal_x = Cfg.ENTRANCE_X + (-3 if side < 0 else 3)


func damage_per_hit() -> float:
	return 7.0 + 2.5 * power


func take_damage(amount: float, sim) -> void:
	if state == S.DEAD:
		return
	hp -= amount
	flash = 0.15
	if hp <= 0.0:
		state = S.DEAD
		sim.notify("The spider was defeated!", "good")
		sim.on_spider_gone(true)
	elif hp < max_hp * 0.3 and state != S.RETREAT:
		state = S.RETREAT
		retreated = true
		sim.notify("The spider is hurt and retreating.", "good")


func step(sim, dt: float) -> void:
	if state == S.DEAD:
		return
	prev_pos = pos
	flash = maxf(0.0, flash - dt)
	atk_cd -= dt
	moving = false
	match state:
		S.ENTER, S.HUNT:
			_surface_logic(sim, dt)
		S.INVADE:
			_invade_logic(sim, dt)
		S.RETREAT:
			_retreat_logic(sim, dt)
	emit_cd -= dt
	if emit_cd <= 0.0 and state != S.DEAD:
		emit_cd = 0.25
		_emit_alarm(sim)


func _target_ant(sim, reach_cells: float) -> Ant:
	var best: Ant = null
	var best_d := reach_cells * Cfg.CELL
	for a: Ant in sim.ants:
		if a.state == Cfg.State.DEAD:
			continue
		var exposed: bool = a.cell.y == Cfg.SURFACE_ROW or (a.cell.y <= Cfg.SURFACE + 2 and absi(a.cell.x - cell.x) <= 3)
		if state == S.INVADE:
			exposed = true
		if not exposed:
			continue
		var d := a.pos.distance_to(pos)
		if d < best_d:
			best_d = d
			best = a
	return best


func _surface_logic(sim, dt: float) -> void:
	var target := _target_ant(sim, 12.0)
	var dest_x := float(goal_x) * Cfg.CELL + Cfg.CELL * 0.5
	if target != null:
		dest_x = target.pos.x
		if pos.distance_to(target.pos) <= Cfg.CELL * 1.9:
			_attack(sim, target)
			return
	var dx := dest_x - pos.x
	if absf(dx) > Cfg.CELL * 0.4:
		_walk_x(signf(dx), dt)
		state = S.HUNT
		if target == null:
			dwell = maxf(0.0, dwell - dt)
	else:
		dwell += dt
		# Undefended entrance for too long: go inside.
		if dwell > 22.0 and sim.soldiers_near_entrance(9) == 0:
			var q: Ant = sim.queen
			if q != null and q.state != Cfg.State.DEAD:
				var p: Array[Vector2i] = sim.terrain.find_path(Vector2i(Cfg.ENTRANCE_X, Cfg.SURFACE_ROW), q.cell)
				if not p.is_empty():
					path = p
					path_i = 0
					state = S.INVADE
					sim.notify("The spider is entering the nest!", "danger")


func _walk_x(dir: float, dt: float) -> void:
	pos.x += dir * speed * Cfg.CELL * dt
	pos.y = (Cfg.SURFACE_ROW + 0.5) * Cfg.CELL
	facing = 1 if dir > 0 else -1
	moving = true
	anim += dt * 6.0
	cell = Cfg.world_to_cell(pos)


func _attack(sim, target: Ant) -> void:
	facing = 1 if target.pos.x >= pos.x else -1
	if atk_cd > 0.0:
		return
	atk_cd = 0.9
	sim.damage_ant(target, damage_per_hit(), "spider")
	sim.fx("bite", target.pos)
	if target.state == Cfg.State.DEAD:
		kills += 1
		for dx in range(-6, 7):
			sim.pher.set_max(Cfg.Phero.DANGER, Vector2i(target.cell.x + dx, target.cell.y), 1.0)
		if kills >= 7 and hp < max_hp * 0.6:
			state = S.RETREAT


func _invade_logic(sim, dt: float) -> void:
	var target := _target_ant(sim, 2.0)
	if target != null:
		_attack(sim, target)
		return
	if path_i >= path.size():
		var q: Ant = sim.queen
		if q != null and q.state != Cfg.State.DEAD and q.pos.distance_to(pos) > Cfg.CELL * 1.5:
			path = sim.terrain.find_path(cell, q.cell)
			path_i = 0
			if path.is_empty():
				state = S.RETREAT
		return
	var wp := Cfg.cell_center(path[path_i])
	var to := wp - pos
	var step_len := speed * 0.75 * Cfg.CELL * dt
	if to.length() <= step_len:
		pos = wp
		cell = path[path_i]
		path_i += 1
	else:
		pos += to.normalized() * step_len
	if absf(to.x) > 1.0:
		facing = 1 if to.x > 0 else -1
	moving = true
	anim += dt * 5.0
	cell = Cfg.world_to_cell(pos)


func _retreat_logic(sim, dt: float) -> void:
	if cell.y >= Cfg.SURFACE:
		if path_i >= path.size() or path.is_empty() or path[path.size() - 1] != Vector2i(Cfg.ENTRANCE_X, Cfg.SURFACE_ROW):
			path = sim.terrain.find_path(cell, Vector2i(Cfg.ENTRANCE_X, Cfg.SURFACE_ROW))
			path_i = 0
			if path.is_empty():
				hp = 0.0
				state = S.DEAD
				sim.on_spider_gone(false)
				return
		var wp := Cfg.cell_center(path[path_i])
		var to := wp - pos
		var step_len := speed * Cfg.CELL * dt
		if to.length() <= step_len:
			pos = wp
			cell = path[path_i]
			path_i = mini(path_i + 1, path.size())
		else:
			pos += to.normalized() * step_len
		moving = true
		anim += dt * 5.0
		cell = Cfg.world_to_cell(pos)
		return
	var dir := 1.0 if pos.x >= Cfg.ENTRANCE_X * Cfg.CELL else -1.0
	_walk_x(dir, dt)
	pos.x += dir * speed * 0.3 * Cfg.CELL * dt
	if pos.x < -4 * Cfg.CELL or pos.x > (Cfg.W + 3) * Cfg.CELL:
		state = S.DEAD
		sim.notify("The spider left.", "info")
		sim.on_spider_gone(false)


func _emit_alarm(sim) -> void:
	if cell.y == Cfg.SURFACE_ROW:
		for dx in range(-5, 6):
			sim.pher.set_max(Cfg.Phero.DANGER, Vector2i(cell.x + dx, Cfg.SURFACE_ROW), 0.95 - absf(dx) * 0.1)
	else:
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var c := Vector2i(cell.x + dx, cell.y + dy)
				if sim.terrain.is_walkable(c):
					sim.pher.set_max(Cfg.Phero.DANGER, c, 0.9 - 0.15 * maxi(absi(dx), absi(dy)))
