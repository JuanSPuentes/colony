class_name ProtoSurface
extends RefCounted
## PROTOTIPO (rama prototipo/exterior-cenital): el exterior visto desde arriba.
## Pregunta única que responde: ¿guiar hormigas con feromonas en un plano cenital se siente mejor
## que la superficie lateral actual? Es desechable: no lo usa nada del juego.
##
## Dos colonias (jugador a la izquierda, rival a la derecha) y un árbol en medio, en un mapa más
## grande que la pantalla (se recorre con la cámara). Las hormigas se mueven en continuo (posición +
## ángulo) y huelen la feromona con 3 sensores (izq/frente/der). Reutiliza PheromoneField del núcleo
## (sim/core) sin modificarlo.
##
## Niebla (solo para el jugador, como la del subsuelo de la Fase 24): el mapa empieza oculto salvo
## alrededor del nido; se descubre donde pasan tus hormigas y lo descubierto queda descubierto.
## Solo se puede pintar rastro sobre lo descubierto: hay que explorar antes de guiar.
##
## Paso A+B: tu colonia vive en un nido lateral (ProtoNest) que es el corte bajo la franja
## y = CUT_Y. Arranca SIN salida: hasta que un túnel llega arriba no hay orificio y nadie sale.
## Cada salida cavada aparece aquí como un orificio con montículo. Las hormigas cruzan de un mundo
## al otro por cualquier salida. (La rival sigue simplificada: un montículo fijo.)

const CELL := 4.0            # px por celda (feromona y niebla)
const MAP_W := 960.0
const MAP_H := 540.0
const W := 240               # MAP_W / CELL
const H := 135               # MAP_H / CELL
const SPEED := 24.0          # px/s
const SENSOR_DIST := 7.0
const SENSOR_ANGLE := 0.6
const TURN := 3.2            # rad/s máximo de giro hacia el olor
const JITTER := 1.4          # rad/s de giro al azar
const PICK_RADIUS := 5.0
const HOME_RADIUS := 6.0
const UNLOAD_S := 1.2        # tiempo "dentro del nido" antes de volver a salir
const LEAF_MAX := 6
const LEAF_REGROW_S := 8.0
const SIGHT := 14.0          # px que descubre cada hormiga del jugador a su alrededor
const NEST_SIGHT := 48.0     # px descubiertos al empezar alrededor del nido
const CANOPY := 70.0
const CUT_Y := 270.0         # franja del exterior bajo la que está el corte del nido
const DIG_S := 0.8           # segundos que tarda una hormiga en cavar una celda
const GIVE_UP_S := 30.0      # buscando sin éxito este tiempo, vuelve a casa con las manos vacías
const DIG_SHARE := 0.7       # con marcas pendientes, parte de las hormigas libres que va a cavar

enum { SEARCH, RETURN, INSIDE, N_IN, N_OUT, N_DIG, N_IDLE }

var rng := RandomNumberGenerator.new()
var trails: Array[PheromoneField] = []      # rastro de comida por equipo
var nests: Array[Vector2] = [Vector2(110, 270), Vector2(890, 270)]
var food: Array[int] = [0, 0]
var tree_center := Vector2(480, 270)
var trunk_radius := 14.0
## Fuentes de hojas: el anillo de la copa del árbol + arbustos sueltos para que explorar pague.
var leaves_pos := PackedVector2Array()
var leaves := PackedInt32Array()
var leaf_timer := PackedFloat32Array()
var bushes: Array[Vector3] = []             # x, y, radio (solo dibujo)
var rocks: Array[Vector3] = []              # x, y, radio
var revealed := PackedByteArray()           # niebla del jugador: 1 = descubierto
var fog_version := 0                        # sube al descubrir algo (para repintar)
var nest: ProtoNest
var entrances_px := PackedVector2Array()    # salidas de tu nido, en coordenadas del exterior
var entrance_use := PackedInt32Array()      # cuántas veces se usó cada una (tamaño del montículo)
var _nest_seen := -1

# Hormigas en arreglos planos (como AntSystem).
var pos := PackedVector2Array()
var ang := PackedFloat32Array()
var state := PackedInt32Array()
var team := PackedInt32Array()
var timer := PackedFloat32Array()
var carry_t := PackedFloat32Array()         # segundos desde que tomó la hoja (frescura del rastro)
var has_leaf := PackedByteArray()           # 1 = vuelve con hoja (0 = vuelve con las manos vacías)
var time := 0.0
var ticks := 0
var _decay_acc := 0.0
var _solid := PackedByteArray()             # celdas bloqueadas (tronco y piedras), precalculado


func _init(seed_v: int, ants_per_team := 10) -> void:
	rng.seed = seed_v
	for t in 2:
		trails.append(PheromoneField.new(W, H, 0.04))
	# Hojas en la copa: un anillo alrededor del tronco.
	for k in 12:
		var a := TAU * k / 12.0 + rng.randf_range(-0.2, 0.2)
		_add_leaf(tree_center + Vector2(cos(a), sin(a)) * rng.randf_range(30.0, 60.0))
	# Todo lo demás en espejo, para que la carrera sea pareja.
	for k in 3:
		var b := Vector3(rng.randf_range(150, 380), rng.randf_range(50, 490), rng.randf_range(10, 16))
		for side in 2:
			var bx := b.x if side == 0 else MAP_W - b.x
			bushes.append(Vector3(bx, b.y, b.z))
			for j in 3:
				_add_leaf(Vector2(bx, b.y) + Vector2.from_angle(TAU * j / 3.0) * b.z * 0.6)
	for k in 7:
		var p := Vector2(rng.randf_range(130, 400), rng.randf_range(30, 510))
		var r := rng.randf_range(10, 22)
		if p.distance_to(nests[0]) < 60 or absf(p.y - CUT_Y) < r + 10:
			continue
		rocks.append(Vector3(p.x, p.y, r))
		rocks.append(Vector3(MAP_W - p.x, p.y, r))
	_solid.resize(W * H)
	revealed.resize(W * H)
	for y in H:
		for x in W:
			_solid[y * W + x] = 1 if _blocked_slow(Vector2((x + 0.5) * CELL, (y + 0.5) * CELL)) else 0
	nest = ProtoNest.new(int(nests[0].x / CELL))
	_reveal(nests[0], NEST_SIGHT)
	for t in 2:
		for k in ants_per_team:
			_spawn(t)


func _add_leaf(p: Vector2) -> void:
	leaves_pos.append(p)
	leaves.append(LEAF_MAX)
	leaf_timer.append(0.0)


func _spawn(t: int) -> void:
	var c := nest.chamber
	pos.append(nests[t] if t == 1 else nest.cell_center(nest.idx(
		rng.randi_range(c.position.x, c.end.x - 1), rng.randi_range(c.position.y, c.end.y - 1))))
	ang.append(rng.randf() * TAU)
	state.append(INSIDE if t == 1 else N_IDLE)
	team.append(t)
	timer.append(rng.randf() * 6.0)  # salen escalonadas
	carry_t.append(0.0)
	has_leaf.append(0)


func count() -> int:
	return pos.size()


## ¿La hormiga está en el exterior (true) o dentro de tu nido (false)?
func outside(i: int) -> bool:
	return state[i] == SEARCH or state[i] == RETURN or state[i] == INSIDE


## Salida más cercana a `x` (índice en entrances_px), o -1 si no hay ninguna.
func nearest_entrance(x: float) -> int:
	var best := -1
	for k in entrances_px.size():
		if best < 0 or absf(entrances_px[k].x - x) < absf(entrances_px[best].x - x):
			best = k
	return best


## Atajo de prueba/captura: abre de golpe un pozo desde la superficie hasta el túnel inicial.
func debug_open_entrance() -> void:
	var cx := int(nests[0].x / CELL)
	for y in 14:
		nest.open[nest.idx(cx, y)] = 1
	nest.version += 1
	nest.recompute()
	_sync_entrances()


## Las salidas salen del nido (fila 0 abierta); acá solo se reflejan en el exterior.
func _sync_entrances() -> void:
	if nest.version == _nest_seen:
		return
	_nest_seen = nest.version
	var old := entrances_px
	var old_use := entrance_use
	entrances_px = PackedVector2Array()
	entrance_use = PackedInt32Array()
	for x in nest.entrances():
		var p := Vector2((x + 0.5) * CELL, CUT_Y)
		var use := 0
		for k in old.size():
			if absf(old[k].x - p.x) < 8.0:
				use = old_use[k]
		if use == 0 and not is_revealed(p):
			_reveal(p, NEST_SIGHT * 0.6)
		entrances_px.append(p)
		entrance_use.append(use)


func blocked(p: Vector2) -> bool:
	if p.x < 2 or p.y < 2 or p.x > MAP_W - 2 or p.y > MAP_H - 2:
		return true
	return _solid[int(p.y / CELL) * W + int(p.x / CELL)] == 1


func _blocked_slow(p: Vector2) -> bool:
	if p.distance_to(tree_center) < trunk_radius:
		return true
	for r in rocks:
		if p.distance_to(Vector2(r.x, r.y)) < r.z:
			return true
	return false


func is_revealed(p: Vector2) -> bool:
	if p.x < 0 or p.y < 0 or p.x >= MAP_W or p.y >= MAP_H:
		return false
	return revealed[int(p.y / CELL) * W + int(p.x / CELL)] == 1


func revealed_ratio() -> float:
	return float(revealed.count(1)) / revealed.size()


func _cell(p: Vector2) -> int:
	var x := clampi(int(p.x / CELL), 0, W - 1)
	var y := clampi(int(p.y / CELL), 0, H - 1)
	return y * W + x


func _smell(t: int, p: Vector2) -> float:
	return trails[t].get_v(int(p.x / CELL), int(p.y / CELL))


func _reveal(p: Vector2, radius: float) -> void:
	_brush(p, radius, func(i: int) -> void:
		if revealed[i] == 0:
			revealed[i] = 1
			fog_version += 1)


## Pincel del jugador: rastro fijo (piso que no decae) en el campo del equipo 0. Solo sobre lo
## descubierto: no se puede guiar hacia lo que la colonia todavía no conoce.
func paint(p: Vector2, radius := 6.0, value := 0.7) -> void:
	_brush(p, radius, func(i: int) -> void:
		if revealed[i] == 1:
			trails[0].paint(i, value))


func erase(p: Vector2, radius := 8.0) -> void:
	_brush(p, radius, func(i: int) -> void: trails[0].clear_cell(i))


func _brush(p: Vector2, radius: float, f: Callable) -> void:
	var r := int(ceil(radius / CELL))
	var c := Vector2i(int(p.x / CELL), int(p.y / CELL))
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			if x < 0 or y < 0 or x >= W or y >= H:
				continue
			if Vector2((x + 0.5) * CELL, (y + 0.5) * CELL).distance_to(p) <= radius:
				f.call(y * W + x)


func step(dt: float) -> void:
	time += dt
	ticks += 1
	_sync_entrances()
	_decay_acc += dt
	if _decay_acc >= 0.1:  # el desgaste es lento: no hace falta cada tick
		for t in 2:
			trails[t].decay(_decay_acc, 1.0)
		_decay_acc = 0.0
	for k in leaves.size():
		if leaves[k] < LEAF_MAX:
			leaf_timer[k] += dt
			if leaf_timer[k] >= LEAF_REGROW_S:
				leaf_timer[k] = 0.0
				leaves[k] += 1
	for i in pos.size():
		match state[i]:
			INSIDE:
				timer[i] -= dt
				if timer[i] <= 0.0:
					state[i] = SEARCH
					pos[i] = nests[team[i]]
					ang[i] = (tree_center - nests[team[i]]).angle() + rng.randf_range(-1.4, 1.4)
			SEARCH:
				_search(i, dt)
			RETURN:
				_return(i, dt)
			_:
				_nest_step(i, dt)
		# Descubrir cada pocos ticks (no hace falta cada uno, y así cuesta menos).
		if team[i] == 0 and outside(i) and (ticks + i) % 4 == 0:
			_reveal(pos[i], SIGHT)


func _search(i: int, dt: float) -> void:
	var t := team[i]
	var p := pos[i]
	var a := ang[i]
	# Tres sensores; un leve sesgo "hacia afuera del nido" para que un rastro sin pendiente
	# (el pincel del jugador) se recorra alejándose de casa.
	var out := (p - nests[t]).normalized()
	var best := -1.0
	var best_da := 0.0
	for da in [-SENSOR_ANGLE, 0.0, SENSOR_ANGLE]:
		var dir := Vector2.from_angle(a + da)
		var v := _smell(t, p + dir * SENSOR_DIST)
		if v > 0.0:
			v += 0.05 * dir.dot(out)
		if v > best:
			best = v
			best_da = da
	if best > 0.02:
		a += clampf(best_da, -TURN * dt, TURN * dt)
	a += rng.randf_range(-JITTER, JITTER) * dt
	ang[i] = a
	_move(i, dt)
	timer[i] += dt
	if t == 0 and timer[i] > GIVE_UP_S:
		state[i] = RETURN
		has_leaf[i] = 0
		return
	for k in leaves_pos.size():
		if leaves[k] > 0 and pos[i].distance_squared_to(leaves_pos[k]) < PICK_RADIUS * PICK_RADIUS:
			leaves[k] -= 1
			state[i] = RETURN
			has_leaf[i] = 1
			carry_t[i] = 0.0
			ang[i] += PI
			return


func _return(i: int, dt: float) -> void:
	var t := team[i]
	carry_t[i] += dt
	# Rastro de comida: más fuerte cerca de la hoja, así la pendiente apunta a la comida.
	if has_leaf[i] == 1:
		trails[t].set_max(_cell(pos[i]), maxf(0.15, 1.0 - carry_t[i] * 0.04))
	var home := nests[t]
	var k := -1
	if t == 0:
		k = nearest_entrance(pos[i].x)
		if k >= 0:
			home = entrances_px[k]
	var want := (home - pos[i]).angle()
	ang[i] = rotate_toward(ang[i], want, TURN * dt) + rng.randf_range(-0.3, 0.3) * dt
	_move(i, dt)
	if pos[i].distance_to(home) < HOME_RADIUS:
		if t == 1:
			food[t] += has_leaf[i]
			has_leaf[i] = 0
			state[i] = INSIDE
			timer[i] = UNLOAD_S
		elif k >= 0:
			# Entra por el orificio: aparece arriba del túnel, en el nido, y baja a la cámara.
			entrance_use[k] += 1
			pos[i] = nest.cell_center(nest.idx(int(home.x / CELL), 0))
			state[i] = N_IN


# --- Dentro del nido ----------------------------------------------------------------------

func _nest_step(i: int, dt: float) -> void:
	var c := nest.cell_at(pos[i])
	match state[i]:
		N_IN:
			if _walk(i, nest.to_chamber, dt):
				food[0] += has_leaf[i]
				has_leaf[i] = 0
				_choose_task(i)
		N_OUT:
			if nest.to_exit[c] < 0:
				_choose_task(i)
			elif _walk(i, nest.to_exit, dt):
				# Sale por el orificio al exterior, en la misma x.
				var k := nearest_entrance(pos[i].x)
				if k < 0:
					_choose_task(i)
					return
				entrance_use[k] += 1
				pos[i] = entrances_px[k]
				ang[i] = (tree_center - entrances_px[k]).angle() + rng.randf_range(-1.6, 1.6)
				state[i] = SEARCH
				timer[i] = 0.0
		N_DIG:
			if nest.to_dig[c] < 0:
				_choose_task(i)
			elif _walk(i, nest.to_dig, dt):
				timer[i] += dt
				if timer[i] >= DIG_S:
					var target := nest.dig_target_near(c)
					if target >= 0:
						nest.dig(target)
					_choose_task(i)
		N_IDLE:
			timer[i] -= dt
			if timer[i] <= 0.0:
				_choose_task(i)


## Camina por los túneles bajando por `field`; true al llegar (distancia 0).
func _walk(i: int, field: PackedInt32Array, dt: float) -> bool:
	var c := nest.cell_at(pos[i])
	if field[c] == 0 and pos[i].distance_to(nest.cell_center(c)) < 1.0:
		return true
	var target := nest.cell_center(nest.step_down(field, c))
	var d := target - pos[i]
	var stepl := SPEED * dt
	if d.length() <= stepl:
		pos[i] = target
	else:
		ang[i] = d.angle()
		pos[i] += d.normalized() * stepl
	return false


## Qué hace una hormiga que está libre dentro del nido: cavar si hay marcas a su alcance (siempre,
## si todavía no hay salida), salir si hay salida, o esperar un momento en la cámara.
func _choose_task(i: int) -> void:
	var c := nest.cell_at(pos[i])
	timer[i] = 0.0
	var can_dig := nest.to_dig[c] >= 0
	var can_exit := nest.to_exit[c] >= 0
	if can_dig and (not can_exit or rng.randf() < DIG_SHARE):
		state[i] = N_DIG
	elif can_exit:
		state[i] = N_OUT
	else:
		state[i] = N_IDLE
		timer[i] = rng.randf_range(0.6, 1.4)


func _move(i: int, dt: float) -> void:
	var nxt := pos[i] + Vector2.from_angle(ang[i]) * SPEED * dt
	if blocked(nxt):
		# Rodear el obstáculo: probar girando a un lado y al otro.
		for da in [0.5, -0.5, 1.0, -1.0, 1.6, -1.6, PI]:
			var a: float = ang[i] + da
			var alt := pos[i] + Vector2.from_angle(a) * SPEED * dt
			if not blocked(alt):
				ang[i] = a
				pos[i] = alt
				return
		return
	pos[i] = nxt


## Huella para comprobar determinismo.
func fingerprint() -> int:
	var h := hash(food)
	for i in pos.size():
		h = hash([h, int(pos[i].x * 100), int(pos[i].y * 100), state[i]])
	return h
