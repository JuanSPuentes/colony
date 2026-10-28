class_name UpgradeTreeView
extends Control
## Fase 34: ventana del árbol de mejoras (tecla U o el botón del panel). Hexágonos unidos por
## líneas: un hexágono central (la colonia) y una rama por color que sale en estrella, cada mejora
## más lejos que la anterior. Clic en un hexágono para comprarlo. A la derecha, el detalle de la
## mejora bajo el mouse y lo que ya suman las compradas (antes, "Estadísticas" del panel lateral).
## Mientras está abierta el juego queda en pausa (lo maneja `Hud.toggle_upgrade_tree`).

signal close_requested

## Color de cada rama, en el orden de `Upgrades.Branch`.
const BRANCH_COLORS: Array[Color] = [Color("c0503a"), Color("4a7fc0"), Color("5aa548")]
## Dirección de cada rama (grados): Ataque arriba, Defensa abajo a la izquierda, Recolección abajo
## a la derecha.
const BRANCH_ANGLES: Array[float] = [-90.0, 150.0, 30.0]
const HEX_R := 46.0
const STEP := 106.0
## Lugar que dejan libre arriba (la barra de datos) y abajo (las pistas).
const MARGIN_TOP := 70.0
const MARGIN_BOTTOM := 50.0
const INFO_W := 400.0
const LOCKED_FILL := Color("3a3129")
const LOCKED_EDGE := Color("6b5f52")

var sim: Simulation
var _hover := -2  # -2: nada; -1: el centro; 0..: `Upgrades.Id`
var _k := 1.0
var _center := Vector2.ZERO
var _close_rect := Rect2()


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


## Centro en pantalla de una mejora (o del hexágono central con -1).
func hex_pos(id: int) -> Vector2:
	if id < 0:
		return _center
	var node: Dictionary = Upgrades.NODES[id]
	var a := deg_to_rad(BRANCH_ANGLES[node.branch])
	return _center + Vector2(cos(a), sin(a)) * STEP * _k * (node.tier + 1)


func _layout() -> void:
	var tree_w := size.x - INFO_W
	var free_h := size.y - MARGIN_TOP - MARGIN_BOTTOM
	# Alto del árbol: 4 pasos hacia arriba + la mitad de eso hacia abajo, más los hexágonos.
	var up_h := Upgrades.TIERS * STEP + HEX_R
	var need_h := up_h + Upgrades.TIERS * STEP * 0.5 + HEX_R
	var need_w := Upgrades.TIERS * STEP * cos(deg_to_rad(30.0)) * 2.0 + HEX_R * 2.0
	_k = clampf(minf(tree_w / need_w, free_h / need_h), 0.4, 1.2)
	_center = Vector2(tree_w * 0.5, MARGIN_TOP + (free_h - need_h * _k) * 0.5 + up_h * _k)


func _hit(p: Vector2) -> int:
	for id in Upgrades.NODES.size():
		if p.distance_to(hex_pos(id)) <= HEX_R * _k * 0.9:
			return id
	if p.distance_to(_center) <= HEX_R * _k * 0.9:
		return -1
	return -2


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _hit(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _close_rect.has_point(event.position):
			close_requested.emit()
			return
		var id := _hit(event.position)
		if id >= 0 and sim != null:
			sim.cmd_buy_upgrade(id)
	accept_event()


func _draw() -> void:
	if sim == null:
		return
	_layout()
	var font := PixelUI.font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.03, 0.02, 0.94))
	var up := sim.upgrades
	# Líneas primero, para que queden debajo de los hexágonos.
	for id in Upgrades.NODES.size():
		var from := hex_pos(id - 1) if Upgrades.NODES[id].tier > 0 else _center
		var col: Color = BRANCH_COLORS[Upgrades.NODES[id].branch] if up.bought[id] else LOCKED_EDGE
		draw_line(from, hex_pos(id), col, 6.0 * _k)
	_draw_hex(_center, Color("6b4226"), PixelUI.GOLD, _hover == -1)
	_text_center(font, _center + Vector2(0, -8) * _k, tr("Colonia"), 18, PixelUI.TEXT)
	_text_center(font, _center + Vector2(0, 14) * _k, "%d / %d" % [up.bought_count, Upgrades.NODES.size()], 18, PixelUI.GOLD)
	for id in Upgrades.NODES.size():
		_draw_node(font, id)
	_draw_info(font)


func _draw_node(font: Font, id: int) -> void:
	var up := sim.upgrades
	var node: Dictionary = Upgrades.NODES[id]
	var base: Color = BRANCH_COLORS[node.branch]
	var p := hex_pos(id)
	var fill := LOCKED_FILL
	var edge := LOCKED_EDGE
	var text_col := PixelUI.TEXT_DIM
	var price := ""
	if up.bought[id]:
		fill = base
		edge = base.lightened(0.45)
		text_col = PixelUI.TEXT
	elif up.unlocked(id):
		fill = base.darkened(0.6)
		edge = PixelUI.GOLD if up.can_buy(id) else base
		text_col = PixelUI.TEXT
		price = "%.0f" % up.cost(id)
	_draw_hex(p, fill, edge, _hover == id)
	var words: PackedStringArray = tr(node.name).split(" ")
	var lines: Array[String] = [words[0]]
	if words.size() > 1:
		lines.append(" ".join(words.slice(1)))
	var y := -8.0 * (lines.size() - 1) - (8.0 if price != "" else 0.0)
	for line in lines:
		_text_center(font, p + Vector2(0, y) * _k, line, 17, text_col)
		y += 17.0
	if price != "":
		_text_center(font, p + Vector2(0, y + 2.0) * _k, price, 17, PixelUI.GOLD)


func _draw_hex(p: Vector2, fill: Color, edge: Color, hover: bool) -> void:
	var r := HEX_R * _k * (1.06 if hover else 1.0)
	var pts := PackedVector2Array()
	for k in 6:
		var a := deg_to_rad(60.0 * k - 90.0)
		pts.append(p + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	draw_polyline(pts, edge, (4.0 if hover else 3.0) * _k)


func _text_center(font: Font, p: Vector2, text: String, font_size: int, col: Color) -> void:
	var fs := maxi(10, int(font_size * _k))
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, p + Vector2(-w * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Panel de la derecha: la mejora bajo el mouse y lo que suma la colonia.
func _draw_info(font: Font) -> void:
	var rect := Rect2(size.x - INFO_W, 0.0, INFO_W, size.y).grow(-12.0)
	PixelUI.frame().draw(get_canvas_item(), rect)
	_close_rect = Rect2(rect.end.x - 44.0, rect.position.y + 10.0, 32.0, 32.0)
	PixelUI.button("normal").draw(get_canvas_item(), _close_rect)
	draw_string(font, _close_rect.position + Vector2(10, 23), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, PixelUI.TEXT)
	var x := rect.position.x + 22.0
	var w := rect.size.x - 44.0
	var y := rect.position.y + 34.0
	draw_string(PixelUI.title_font(), Vector2(x, y), tr("Árbol de mejoras"), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, PixelUI.HEADER)
	y += 22.0
	draw_string(font, Vector2(x, y), tr("Comida: %.0f") % sim.colony.food, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, PixelUI.GOLD)
	y += 34.0
	var up := sim.upgrades
	if _hover >= 0:
		var node: Dictionary = Upgrades.NODES[_hover]
		draw_string(font, Vector2(x, y), tr(node.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, BRANCH_COLORS[node.branch].lightened(0.3))
		y += 22.0
		draw_string(font, Vector2(x, y), tr("Rama: %s") % tr(Upgrades.BRANCH_NAMES[node.branch]), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, PixelUI.TEXT_DIM)
		y += 24.0
		draw_multiline_string(font, Vector2(x, y), tr(node.desc), HORIZONTAL_ALIGNMENT_LEFT, w, 20, -1, PixelUI.TEXT)
		y += 46.0
		var state := ""
		if up.bought[_hover]:
			state = tr("Comprada")
		elif not up.unlocked(_hover):
			state = tr("Primero compra: %s") % tr(Upgrades.NODES[_hover - 1].name)
		elif up.can_buy(_hover):
			state = tr("Clic para comprar: %.0f de comida") % up.cost(_hover)
		else:
			state = tr("Te falta comida: %.0f") % up.cost(_hover)
		draw_multiline_string(font, Vector2(x, y), state, HORIZONTAL_ALIGNMENT_LEFT, w, 20, -1, PixelUI.GOLD)
	else:
		draw_multiline_string(font, Vector2(x, y), tr("Pasa el mouse por una mejora para verla; clic para comprarla. Cada compra encarece las demás."),
			HORIZONTAL_ALIGNMENT_LEFT, w, 20, -1, PixelUI.TEXT_DIM)
	y = rect.position.y + 250.0
	draw_string(font, Vector2(x, y), tr("TU COLONIA"), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, PixelUI.HEADER)
	y += 26.0
	for line in bonus_lines(up):
		draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, PixelUI.TEXT)
		y += 21.0
	y += 14.0
	_draw_stats(font, x, y)
	draw_string(font, Vector2(x, rect.end.y - 16.0), tr("[U] o [Esc] para cerrar · juego en pausa"), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, PixelUI.TEXT_DIM)


## Lo que suman las mejoras compradas, una línea por efecto ("Sin mejoras todavía" si no hay).
static func bonus_lines(up: Upgrades) -> Array[String]:
	var out: Array[String] = []
	var pct := func(label: String, m: float) -> void:
		if m > 1.0001:
			out.append(TranslationServer.translate(label) % roundi((m - 1.0) * 100.0))
	pct.call("Daño: +%d %%", up.damage_mult)
	pct.call("Vida: +%d %%", up.hp_mult)
	pct.call("Vida de la reina: +%d %%", up.queen_hp_mult)
	pct.call("Velocidad de soldados: +%d %%", up.soldier_speed_mult)
	pct.call("Velocidad de obreras: +%d %%", up.worker_speed_mult)
	pct.call("Velocidad al cavar: +%d %%", up.work_mult)
	pct.call("Vista de las obreras: +%d %%", up.sight_mult)
	pct.call("Comida por viaje: +%d %%", up.carry_mult)
	pct.call("Daño a la reina rival: +%d %%", up.queen_damage_mult)
	if up.nest_heal:
		out.append(TranslationServer.translate("Curación dentro del nido"))
	if out.is_empty():
		out.append(TranslationServer.translate("Sin mejoras todavía"))
	return out


## Tabla por casta con las mejoras ya aplicadas (mismo cálculo que `AntSystem`).
func _draw_stats(font: Font, x: float, y: float) -> void:
	var cfg := sim.cfg
	var up := sim.upgrades
	var cols: Array[float] = [x, x + 130.0, x + 200.0, x + 270.0]
	var heads: Array[String] = ["", tr("Vida"), tr("Vel."), tr("Daño/s")]
	for c in heads.size():
		draw_string(font, Vector2(cols[c], y), heads[c], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, PixelUI.TEXT_DIM)
	for caste in [CasteDefs.Caste.QUEEN, CasteDefs.Caste.WORKER, CasteDefs.Caste.SOLDIER, CasteDefs.Caste.DRONE]:
		y += 22.0
		var base_hp: float = cfg.queen_hp_base if caste == CasteDefs.Caste.QUEEN else cfg.ant_hp
		var vals: Array[String] = [
			tr(CasteDefs.NAMES[caste]),
			"%.0f" % (base_hp * CasteDefs.HP_MULT[caste] * up.hp_factor(caste)),
			"%.1f" % (cfg.ant_speed * CasteDefs.SPEED_MULT[caste] * up.speed_factor(caste)),
			"%.1f" % up.damage(caste, null)]
		for c in vals.size():
			draw_string(font, Vector2(cols[c], y), vals[c], HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
				CasteDefs.COLORS[caste] if c == 0 else PixelUI.TEXT)
	draw_string(font, Vector2(x, y + 26.0), tr("Cavar una celda: %.1f s") % (cfg.dig_seconds / up.work_mult),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, PixelUI.TEXT_DIM)
