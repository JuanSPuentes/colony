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
##
## Paso C: los recursos son objetos sueltos que el árbol (y los arbustos) dejan caer con el tiempo,
## más insectos muertos que aparecen. Lo grande no se lleva entero: las hormigas se paran a cortarlo
## y cada una se lleva UN trozo en la boca. El objeto se achica hasta desaparecer.

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
const HOME_RADIUS := 6.0
const UNLOAD_S := 1.2        # tiempo "dentro del nido" antes de volver a salir
const SIGHT := 14.0          # px que descubre cada hormiga del jugador a su alrededor
const NEST_SIGHT := 48.0     # px descubiertos al empezar alrededor del nido
const CANOPY := 70.0
const CUT_Y := 270.0         # franja del exterior bajo la que está el corte del nido
const DIG_S := 0.8           # segundos que tarda una hormiga en cavar una celda
const GIVE_UP_S := 30.0      # buscando sin éxito este tiempo, vuelve a casa con las manos vacías
const DIG_SHARE := 0.7       # con marcas pendientes, parte de las hormigas libres que va a cavar

enum Kind { LEAF, SEED, FRUIT, BUG }
const KIND_PIECES := [3, 1, 8, 6]          # trozos que da cada objeto
const KIND_CUT_S := [1.0, 0.3, 1.5, 1.4]   # segundos para cortar un trozo
const KIND_FOOD := [1, 2, 1, 2]            # comida que vale cada trozo al llegar a la cámara
const KIND_SIZE := [3.5, 1.6, 5.0, 4.5]    # radio del objeto entero (px)
const DROP_S := 3.0          # el árbol suelta algo cada tanto
const BUSH_DROP_S := 9.0     # los arbustos sueltan hojas
const BUG_S := 22.0          # aparece un insecto muerto
const ITEMS_MAX := 40
const SEE_ITEM := 18.0       # a esta distancia una hormiga ve un objeto y va derecho a él

enum { SEARCH, RETURN, INSIDE, N_IN, N_OUT, N_DIG, N_IDLE, CUT }

var rng := RandomNumberGenerator.new()
var trails: Array[PheromoneField] = []      # rastro de comida por equipo
var nests: Array[Vector2] = [Vector2(110, 270), Vector2(890, 270)]
var food: Array[int] = [0, 0]
var tree_center := Vector2(480, 270)
var trunk_radius := 14.0
## Objetos sueltos en el suelo (recursos).
var item_pos := PackedVector2Array()
var item_kind := PackedInt32Array()
var item_left := PackedInt32Array()        # trozos que le quedan
var stock: Array[int] = [0, 0, 0, 0]       # trozos guardados en tu cámara, por tipo
var dropped := 0                           # veces que soltó algo el árbol (para pruebas)
var _drop_t := 0.0
var _bush_t := 0.0
var _bug_t := 0.0
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
var carry := PackedInt32Array()             # tipo del trozo que lleva en la boca, -1 = nada
var time := 0.0
var ticks := 0
var _decay_acc := 0.0
var _solid := PackedByteArray()             # celdas bloqueadas (tronco y piedras), precalculado


func _init(seed_v: int, ants_per_team := 10) -> void:
	rng.seed = seed_v
	for t in 2:
		trails.append(PheromoneField.new(W, H, 0.04))
	# Todo lo demás en espejo, para que la carrera sea pareja.
	for k in 3:
		var b := Vector3(rng.randf_range(150, 380), rng.randf_range(50, 490), rng.randf_range(10, 16))
		for side in 2:
			var bx := b.x if side == 0 else MAP_W - b.x
			bushes.append(Vector3(bx, b.y, b.z))
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
	# Lo que ya está en el suelo al empezar.
	for k in 6:
		_tree_drop()
	for k in bushes.size() / 2:
		_bush_drop(k)
	nest = ProtoNest.new(int(nests[0].x / CELL))
	_reveal(nests[0], NEST_SIGHT)
	for t in 2:
		for k in ants_per_team:
			_spawn(t)


func add_item(p: Vector2, kind: int) -> void:
	if item_pos.size() >= ITEMS_MAX or blocked(p):
		return
	item_pos.append(p)
	item_kind.append(kind)
	item_left.append(KIND_PIECES[kind])


func _remove_item(k: int) -> void:
	item_pos.remove_at(k)
	item_kind.remove_at(k)
	item_left.remove_at(k)


## El árbol suelta algo bajo la copa (en espejo: lo mismo de cada lado, para que sea parejo).
func _tree_drop() -> void:
	var r := rng.randf()
	var kind := Kind.LEAF if r < 0.6 else (Kind.SEED if r < 0.85 else Kind.FRUIT)
	var a := rng.randf_range(-PI * 0.5, PI * 0.5)
	var off := Vector2.from_angle(a) * rng.randf_range(trunk_radius + 6.0, CANOPY - 4.0)
	dropped += 1
	add_item(tree_center - off, kind)
	add_item(tree_center + Vector2(off.x, -off.y), kind)


func _bush_drop(k: int) -> void:
	var off := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(4.0, 14.0)
	for side in 2:
		var b := bushes[k * 2 + side]
		var o := off if side == 0 else Vector2(-off.x, off.y)
		add_item(Vector2(b.x, b.y) + o, Kind.LEAF)


func _bug_drop() -> void:
	var p := Vector2(rng.randf_range(150, 400), rng.randf_range(30, 510))
	add_item(p, Kind.BUG)
	add_item(Vector2(MAP_W - p.x, p.y), Kind.BUG)


## Objeto más cercano a `p` dentro de `radius` (contando el tamaño del objeto), o -1.
func item_near(p: Vector2, radius: float) -> int:
	var best := -1
	var best_d := INF
	for k in item_pos.size():
		var d: float = p.distance_to(item_pos[k]) - KIND_SIZE[item_kind[k]]
		if d < radius and d < best_d:
			best = k
			best_d = d
	return best


func _spawn(t: int) -> void:
	var c := nest.chamber
	pos.append(nests[t] if t == 1 else nest.cell_center(nest.idx(
		rng.randi_range(c.position.x, c.end.x - 1), rng.randi_range(c.position.y, c.end.y - 1))))
	ang.append(rng.randf() * TAU)
	state.append(INSIDE if t == 1 else N_IDLE)
	team.append(t)
	timer.append(rng.randf() * 6.0)  # salen escalonadas
	carry_t.append(0.0)
	carry.append(-1)


func count() -> int:
	return pos.size()


## ¿La hormiga está en el exterior (true) o dentro de tu nido (false)?
func outside(i: int) -> bool:
	return state[i] == SEARCH or state[i] == RETURN or state[i] == INSIDE or state[i] == CUT


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
	_drop_t += dt
	if _drop_t >= DROP_S:
		_drop_t = 0.0
		_tree_drop()
	_bush_t += dt
	if _bush_t >= BUSH_DROP_S:
		_bush_t = 0.0
		_bush_drop(rng.randi() % (bushes.size() / 2))
	_bug_t += dt
	if _bug_t >= BUG_S:
		_bug_t = 0.0
		_bug_drop()
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
			CUT:
				_cut(i, dt)
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
	# Ver un objeto cerca le gana al olfato: va derecho a él.
	var seen := item_near(p, SEE_ITEM)
	if seen >= 0:
		a = rotate_toward(a, (item_pos[seen] - p).angle(), TURN * 2.0 * dt)
	ang[i] = a
	_move(i, dt)
	timer[i] += dt
	if t == 0 and timer[i] > GIVE_UP_S:
		state[i] = RETURN
		carry[i] = -1
		return
	if item_near(pos[i], 2.0) >= 0:
		state[i] = CUT
		timer[i] = 0.0


## Parada junto a un objeto, cortando un trozo. Si otras se lo terminan antes, sigue buscando.
func _cut(i: int, dt: float) -> void:
	var k := item_near(pos[i], 3.0)
	if k < 0:
		state[i] = SEARCH
		timer[i] = 0.0
		return
	ang[i] = rotate_toward(ang[i], (item_pos[k] - pos[i]).angle(), TURN * dt)
	timer[i] += dt
	if timer[i] < KIND_CUT_S[item_kind[k]]:
		return
	carry[i] = item_kind[k]
	item_left[k] -= 1
	if item_left[k] <= 0:
		_remove_item(k)
	state[i] = RETURN
	carry_t[i] = 0.0
	ang[i] += PI


func _return(i: int, dt: float) -> void:
	var t := team[i]
	carry_t[i] += dt
	# Rastro de comida: más fuerte cerca de la hoja, así la pendiente apunta a la comida.
	if carry[i] >= 0:
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
			if carry[i] >= 0:
				food[t] += KIND_FOOD[carry[i]]
			carry[i] = -1
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
				if carry[i] >= 0:
					food[0] += KIND_FOOD[carry[i]]
					stock[carry[i]] += 1
				carry[i] = -1
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
