class_name TerrainView
extends Node2D
## Arma la imagen del terreno (8x8 px por celda) y solo repinta lo que cambió. Cómo se ve cada
## material lo decide `TerrainStyle`; acá solo se decide qué va en cada celda:
## - Tierra y roca: su textura continua, con un borde oscuro en los lados que dan a un hueco.
## - Túnel: la "pared de fondo" (tierra oscura). Si es parte de una cámara, un tinte suave del color
##   de la cámara y un contorno donde termina — antes eran bloques de color sólido (`OverlayView`).
## - Marcada para cavar: tierra con un contorno punteado; las grietas las dibuja `DigEffectsView`.
## Los bordes dependen de las vecinas, así que al cambiar una celda se repintan también las 4 de
## al lado.

const SKY := Color("6fb0e6")
const AIR_CLEAR := Color(0, 0, 0, 0)
const ROOM_TINT_VALID := 0.26
const ROOM_TINT_INVALID := 0.12
const ROOM_LINE_VALID := 0.85
const ROOM_LINE_INVALID := 0.45
const N4: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

var sim: Simulation
var _img: Image
var _tex: ImageTexture
var _sprite: Sprite2D
var _room_key := ""
## Cuadraditos de color semitransparente (uno por cámara y validez) para teñir con `blend_rect`.
var _tints: Dictionary = {}


func setup(s: Simulation) -> void:
	sim = s
	var cpx := sim.cfg.cell_px
	_img = Image.create(sim.world.w * cpx, sim.world.h * cpx, false, Image.FORMAT_RGBA8)
	_img.fill(AIR_CLEAR)
	_room_key = _rooms_key()
	for y in sim.world.h:
		for x in sim.world.w:
			_paint(x, y)
	_tex = ImageTexture.create_from_image(_img)
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.centered = false
		add_child(_sprite)
	_sprite.texture = _tex
	sim.world.take_changed()
	queue_redraw()


func refresh() -> void:
	var world := sim.world
	var dirty := {}
	for i in world.take_changed():
		var c := Vector2i(i % world.w, i / world.w)
		dirty[c] = true
		for d in N4:
			dirty[c + d] = true
	# Si cambian las cámaras (o cuáles son válidas) se repintan todos los túneles: pasa muy poco.
	var key := _rooms_key()
	if key != _room_key:
		_room_key = key
		for i in world.w * world.h:
			if world.cells[i] == WorldGrid.Cell.TUNNEL:
				dirty[Vector2i(i % world.w, i / world.w)] = true
	if dirty.is_empty():
		return
	for c in dirty:
		if world.in_bounds(c.x, c.y):
			_paint(c.x, c.y)
	_tex.update(_img)


func _rooms_key() -> String:
	return "%d|%s" % [sim.world.rooms_version, sim.rooms.valid]


func _draw() -> void:
	if sim == null:
		return
	# Fase 16: el cielo lo dibuja `SkyView` (degradado, sol, nubes); este rectángulo plano solo queda
	# si no hay SkyView detrás (p.ej. una escena de prueba que arme las vistas a mano).
	if get_parent() != null and get_parent().get_child(0) is SkyView:
		return
	var cpx := sim.cfg.cell_px
	draw_rect(Rect2(0, 0, sim.world.w * cpx, sim.cfg.surface_y * cpx), SKY)


# --- Una celda ------------------------------------------------------------------------------------

func _paint(x: int, y: int) -> void:
	var cpx := sim.cfg.cell_px
	var rect := Rect2i(x * cpx, y * cpx, cpx, cpx)
	var world := sim.world
	var depth := float(y - sim.cfg.surface_y) / float(world.h - sim.cfg.surface_y)
	match world.type_at(x, y):
		WorldGrid.Cell.AIR:
			_img.fill_rect(rect, AIR_CLEAR)
		WorldGrid.Cell.DIRT:
			_blit(TerrainStyle.dirt_mat(x, y, depth), rect)
			_edges(x, y, rect)
			if y == sim.cfg.surface_y:
				_grass(x, rect)
		WorldGrid.Cell.MARKED:
			_blit(TerrainStyle.dirt_mat(x, y, depth), rect)
			_img.blend_rect(_tint_img(TerrainStyle.MARK_TINT, TerrainStyle.MARK_TINT_AMOUNT), Rect2i(0, 0, cpx, cpx), rect.position)
			_edges(x, y, rect)
			if y == sim.cfg.surface_y:
				_grass(x, rect)
			_dashed_outline(rect, TerrainStyle.MARK_LINE)
		WorldGrid.Cell.ROCK:
			_blit(TerrainStyle.Mat.ROCK, rect)
			_edges(x, y, rect)
		WorldGrid.Cell.TUNNEL:
			_blit(TerrainStyle.wall_mat(x, y, depth), rect)
			_room(x, y, rect)


## Copia el trozo de la textura del material que cae en esta celda (por coordenadas de mundo, así
## la textura sigue de una celda a la otra sin cortes).
func _blit(mat: int, rect: Rect2i) -> void:
	var t := TerrainStyle.TILE
	var src := Rect2i(rect.position.x % t, rect.position.y % t, rect.size.x, rect.size.y)
	_img.blit_rect(TerrainStyle.tile(mat), src, rect.position)


## Borde oscuro e irregular en los lados que dan a un hueco (túnel, o aire bajo la superficie), y
## las esquinas exteriores redondeadas, como en Terraria.
func _edges(x: int, y: int, rect: Rect2i) -> void:
	var open: Array[bool] = []
	for d in N4:
		open.append(_is_hollow(x + d.x, y + d.y))
	var cpx := rect.size.x
	var p := rect.position
	for k in cpx:
		var rough := TerrainStyle.noise(x * 8 + k, y, 31) < 70  # algunos píxeles un poco más adentro
		if open[0]:
			_img.set_pixel(p.x + k, p.y, TerrainStyle.EDGE_DARK)
			if rough:
				_img.set_pixel(p.x + k, p.y + 1, TerrainStyle.EDGE_DARK)
		if open[2]:
			_img.set_pixel(p.x + k, p.y + cpx - 1, TerrainStyle.EDGE_DARK)
		if open[1]:
			_img.set_pixel(p.x + cpx - 1, p.y + k, TerrainStyle.EDGE_DARK)
		if open[3]:
			_img.set_pixel(p.x, p.y + k, TerrainStyle.EDGE_DARK)
	# Luz de borde: una línea más clara justo adentro del borde de arriba (el hueco "ilumina").
	if open[0]:
		for k in range(1, cpx - 1):
			var c := _img.get_pixel(p.x + k, p.y + 2)
			_img.set_pixel(p.x + k, p.y + 2, c.lightened(TerrainStyle.EDGE_LIGHT_LIFT))
	# Esquinas redondeadas: donde se juntan dos lados abiertos, el píxel de la esquina es hueco.
	var corners := [[0, 3, Vector2i(0, 0)], [0, 1, Vector2i(cpx - 1, 0)], [2, 1, Vector2i(cpx - 1, cpx - 1)], [2, 3, Vector2i(0, cpx - 1)]]
	for cr in corners:
		if open[cr[0]] and open[cr[1]]:
			var cp: Vector2i = p + cr[2]
			_img.set_pixel(cp.x, cp.y, _hollow_color(x, y))


## Un hueco "de verdad" para el borde: túnel, o aire bajo la línea del suelo. El cielo no cuenta
## (el borde de arriba de la superficie es el pasto).
func _is_hollow(x: int, y: int) -> bool:
	var world := sim.world
	if not world.in_bounds(x, y):
		return false
	var t := world.type_at(x, y)
	return t == WorldGrid.Cell.TUNNEL or (t == WorldGrid.Cell.AIR and y >= sim.cfg.surface_y)


func _hollow_color(x: int, y: int) -> Color:
	var depth := float(y - sim.cfg.surface_y) / float(sim.world.h - sim.cfg.surface_y)
	return TerrainStyle.tile(TerrainStyle.wall_mat(x, y, depth)).get_pixel(0, 0)


func _grass(x: int, rect: Rect2i) -> void:
	var p := rect.position
	var season := SeasonStyle.of(sim)  # Fase 26: pasto (o nieve) del color de la estación
	var light: Color = SeasonStyle.GRASS[season]
	var dark: Color = SeasonStyle.GRASS_DARK[season]
	for k in rect.size.x:
		var h := 2 + int(TerrainStyle.noise(x * 8 + k, 0, 51) < 60)
		for j in h:
			_img.set_pixel(p.x + k, p.y + j, light if j < 2 else dark)


## Cámaras: tinte suave sobre la pared de fondo y un contorno donde la cámara termina (más tenue
## si la cámara todavía no es válida).
func _room(x: int, y: int, rect: Rect2i) -> void:
	var world := sim.world
	var r := world.room[y * world.w + x]
	if r == WorldGrid.Room.NONE:
		return
	var valid: bool = sim.rooms.valid[r]
	var base := TerrainStyle.room_color(r)
	_img.blend_rect(_tint_img(base, ROOM_TINT_VALID if valid else ROOM_TINT_INVALID), Rect2i(0, 0, rect.size.x, rect.size.y), rect.position)
	var line := Color(base, ROOM_LINE_VALID if valid else ROOM_LINE_INVALID)
	var p := rect.position
	var cpx := rect.size.x
	for di in N4.size():
		var d := N4[di]
		var nx := x + d.x
		var ny := y + d.y
		if world.in_bounds(nx, ny) and world.cells[ny * world.w + nx] == WorldGrid.Cell.TUNNEL and world.room[ny * world.w + nx] == r:
			continue
		for k in cpx:
			if not valid and k % 2 == 1:
				continue  # punteado si todavía no es válida
			var px := p.x + (k if d.y != 0 else (cpx - 1 if d.x > 0 else 0))
			var py := p.y + (k if d.x != 0 else (cpx - 1 if d.y > 0 else 0))
			_img.set_pixel(px, py, _img.get_pixel(px, py).lerp(line, line.a))


func _dashed_outline(rect: Rect2i, c: Color) -> void:
	var p := rect.position
	var n := rect.size.x
	for k in n:
		if k % 3 == 2:
			continue
		_img.set_pixel(p.x + k, p.y, c)
		_img.set_pixel(p.x + k, p.y + n - 1, c)
		_img.set_pixel(p.x, p.y + k, c)
		_img.set_pixel(p.x + n - 1, p.y + k, c)


func _tint_img(c: Color, alpha: float) -> Image:
	var key := "%s|%.2f" % [c.to_html(), alpha]
	if not _tints.has(key):
		var img := Image.create(sim.cfg.cell_px, sim.cfg.cell_px, false, Image.FORMAT_RGBA8)
		img.fill(Color(c, alpha))
		_tints[key] = img
	return _tints[key]
