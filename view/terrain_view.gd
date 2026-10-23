class_name TerrainView
extends Node2D
## Dibuja el cielo plano y el terreno. El terreno vive en una Image (8x8 px por celda) y solo se
## repintan las celdas que cambiaron.

const SKY := Color("6fb0e6")
const AIR_CLEAR := Color(0, 0, 0, 0)

var sim: Simulation
var _img: Image
var _tex: ImageTexture
var _sprite: Sprite2D


func setup(s: Simulation) -> void:
	sim = s
	var cpx := sim.cfg.cell_px
	_img = Image.create(sim.world.w * cpx, sim.world.h * cpx, false, Image.FORMAT_RGBA8)
	_img.fill(AIR_CLEAR)
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
	var ch := sim.world.take_changed()
	if ch.is_empty():
		return
	for i in ch:
		_paint(i % sim.world.w, i / sim.world.w)
		# Los vecinos pueden cambiar de borde.
	_tex.update(_img)


func _draw() -> void:
	if sim == null:
		return
	# Fase 16: el cielo lo dibuja `SkyView` (degradado, sol, nubes); este rectángulo plano solo queda
	# si no hay SkyView detrás (p.ej. una escena de prueba que arme las vistas a mano).
	if get_parent() != null and get_parent().get_child(0) is SkyView:
		return
	var cpx := sim.cfg.cell_px
	draw_rect(Rect2(0, 0, sim.world.w * cpx, sim.cfg.surface_y * cpx), SKY)


func _noise(x: int, y: int, k: int) -> int:
	var h := (x * 73856093) ^ (y * 19349663) ^ (k * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return (h ^ (h >> 16)) & 0xff


func _paint(x: int, y: int) -> void:
	var cpx := sim.cfg.cell_px
	var rect := Rect2i(x * cpx, y * cpx, cpx, cpx)
	var world := sim.world
	var depth := float(y - sim.cfg.surface_y) / float(world.h - sim.cfg.surface_y)
	var dirt: Color
	if depth < 0.3:
		dirt = Color("8a5a38")
	elif depth < 0.62:
		dirt = Color("6b4429")
	else:
		dirt = Color("4f3220")
	match world.type_at(x, y):
		WorldGrid.Cell.AIR:
			_img.fill_rect(rect, AIR_CLEAR)
		WorldGrid.Cell.DIRT, WorldGrid.Cell.MARKED:
			_img.fill_rect(rect, dirt)
			for k in 7:
				var n := _noise(x, y, k)
				var px := rect.position.x + (n & 7)
				var py := rect.position.y + ((n >> 3) & 7)
				_img.set_pixel(px, py, dirt.darkened(0.16) if (n & 0x80) == 0 else dirt.lightened(0.12))
			if y == sim.cfg.surface_y:
				_img.fill_rect(Rect2i(rect.position.x, rect.position.y, cpx, 2), Color("4c9a3a"))
			if world.type_at(x, y) == WorldGrid.Cell.MARKED:
				_img.fill_rect(rect, dirt.lerp(Color("f0b040"), 0.45))
				for e in cpx:
					_img.set_pixel(rect.position.x + e, rect.position.y, Color("ffd060"))
					_img.set_pixel(rect.position.x + e, rect.position.y + cpx - 1, Color("ffd060"))
					_img.set_pixel(rect.position.x, rect.position.y + e, Color("ffd060"))
					_img.set_pixel(rect.position.x + cpx - 1, rect.position.y + e, Color("ffd060"))
		WorldGrid.Cell.ROCK:
			var rc := Color("74747e")
			_img.fill_rect(rect, rc)
			for k in 8:
				var n2 := _noise(x, y, k + 20)
				_img.set_pixel(rect.position.x + (n2 & 7), rect.position.y + ((n2 >> 3) & 7), rc.darkened(0.22) if (n2 & 0x80) == 0 else rc.lightened(0.18))
		WorldGrid.Cell.TUNNEL:
			var tc := Color("5b4d44")
			_img.fill_rect(rect, tc)
			for k in 4:
				var n3 := _noise(x, y, k + 40)
				_img.set_pixel(rect.position.x + (n3 & 7), rect.position.y + ((n3 >> 3) & 7), tc.darkened(0.12))
