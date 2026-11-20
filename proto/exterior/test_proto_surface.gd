extends SceneTree
## PROTOTIPO: comprobaciones mínimas del exterior cenital + nido lateral (no es una suite de fase).
## Uso: godot --headless --path . --script proto/exterior/test_proto_surface.gd

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run()
	print("\n%d OK, %d FALLA" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("[%s] %s %s" % ["OK " if ok else "FALLA", label, detail])


func _run_for(s: ProtoSurface, seconds: float) -> void:
	for k in int(seconds * 60):
		s.step(1.0 / 60.0)


func _opened(seed_v: int) -> ProtoSurface:
	var s := ProtoSurface.new(seed_v)
	s.debug_open_entrance()
	return s


func _outside_count(s: ProtoSurface) -> int:
	var n := 0
	for i in s.count():
		if s.team[i] == 0 and s.outside(i):
			n += 1
	return n


func _run() -> void:
	# --- A: el nido arranca cerrado y la salida se cava ---
	var c := ProtoSurface.new(5)
	_run_for(c, 10)
	_check("Sin salida nadie de tu colonia sale", c.entrances_px.is_empty() and _outside_count(c) == 0)

	var cx := int(c.nests[0].x / ProtoSurface.CELL) + 6
	for y in 26:
		c.nest.set_mark(c.nest.idx(cx, y), true)
	for x in range(cx - 6, cx + 1):
		c.nest.set_mark(c.nest.idx(x, 25), true)
	_run_for(c, 90)
	_check("Las hormigas cavan lo marcado hasta la superficie", c.entrances_px.size() == 1,
		"(salidas: %d)" % c.entrances_px.size())
	_check("La salida aparece en el exterior en la misma x",
		c.entrances_px.size() == 1 and absf(c.entrances_px[0].x - (cx + 0.5) * ProtoSurface.CELL) < 1.0
		and c.entrances_px[0].y == ProtoSurface.CUT_Y)
	_check("Con salida, las hormigas salen", _outside_count(c) > 0, "(afuera: %d)" % _outside_count(c))

	# Una segunda salida = un segundo orificio.
	var two := _opened(6)
	var x2 := int(two.nests[0].x / ProtoSurface.CELL) - 4
	for y in 25:
		two.nest.set_mark(two.nest.idx(x2, y), true)
	for x in range(x2, x2 + 4):
		two.nest.set_mark(two.nest.idx(x, 24), true)
	_run_for(two, 90)
	_check("Cada salida nueva es otro orificio", two.entrances_px.size() == 2,
		"(salidas: %d)" % two.entrances_px.size())

	# --- B (simulación): cruzan en los dos sentidos y la hoja llega a la cámara ---
	var s := _opened(5)
	_run_for(s, 150)
	var used := 0
	for u in s.entrance_use:
		used += u
	_check("Las hormigas entran y salen por la salida", used > 10, "(cruces: %d)" % used)
	_check("Las hojas llegan a la cámara del nido", s.food[0] > 0 and s.food[1] > 0,
		"(jugador %d, rival %d)" % [s.food[0], s.food[1]])
	var lost := 0
	for i in s.count():
		if s.team[i] == 0 and not s.outside(i):
			if s.nest.open[s.nest.cell_at(s.pos[i])] == 0:
				lost += 1
		elif s.blocked(s.pos[i]):
			lost += 1
	_check("Nadie atraviesa tierra, piedras ni el tronco", lost == 0, "(%d)" % lost)

	var a := _opened(5)
	var b := _opened(5)
	_run_for(a, 30)
	_run_for(b, 30)
	_check("Determinista con la misma semilla", a.fingerprint() == b.fingerprint())

	# Pintar sigue importando.
	var plain := _opened(9)
	var painted := _opened(9)
	# Se pinta solo lo ya descubierto: esperar a que las exploradoras abran el camino.
	_run_for(plain, 60)
	_run_for(painted, 60)
	for k in 60:
		painted.paint(painted.nests[0].lerp(painted.tree_center + Vector2(-40, 0), k / 59.0))
	_run_for(plain, 120)
	_run_for(painted, 120)
	_check("Pintar un rastro al árbol trae más hojas", painted.food[0] > plain.food[0],
		"(sin rastro %d, con rastro %d)" % [plain.food[0], painted.food[0]])

	# --- Niebla ---
	var f := ProtoSurface.new(4)
	_check("Al empezar solo se ve el nido", f.is_revealed(f.nests[0]) and not f.is_revealed(f.nests[1])
		and not f.is_revealed(f.tree_center))
	f.paint(f.tree_center + Vector2(-40, 0))
	_check("No se puede pintar en la niebla",
		f.trails[0].data[f._cell(f.tree_center + Vector2(-40, 0))] == 0.0)

	var n := ProtoSurface.new(3)
	_check("Son 20 hormigas en total", n.count() == 20, "(%d)" % n.count())
