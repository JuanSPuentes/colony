class_name OverlayView
extends Node2D
## Capas sobre el terreno. Cada una es una Image del tamaño de la cuadrícula que se copia a una
## ImageTexture unas 5 veces por segundo (no en cada frame) y se escala a 8x.
## Fase 1: se añadieron 3 feromonas más y una capa de castas.

enum Layer { NONE, FOOD, HOME, DANGER, ATTACK, EVACUATE, WATER, STATES, CASTES }

const LAYER_NAMES: Array[String] = ["ninguna", "feromona de comida", "feromona de hogar",
	"feromona de peligro", "feromona de ataque", "feromona de evacuar", "nivel de agua",
	"estado de las hormigas", "casta de las hormigas"]
## Color base de cada feromona pintable (orden: FOOD, HOME, DANGER, ATTACK, EVACUATE).
const PHERO_COLORS: Array[Color] = [
	Color(0.25, 1.0, 0.3), Color(0.35, 0.6, 1.0), Color(1.0, 0.25, 0.25),
	Color(1.0, 0.55, 0.1), Color(1.0, 1.0, 0.3),
]

var sim: Simulation
var layer := Layer.FOOD
var _pher_img: Image
var _pher_tex: ImageTexture
var _pher_sprite: Sprite2D
var _water_img: Image
var _water_tex: ImageTexture
var _water_sprite: Sprite2D
var _room_img: Image
var _room_tex: ImageTexture
var _room_sprite: Sprite2D


func setup(s: Simulation) -> void:
	sim = s
	var w := sim.world.w
	var h := sim.world.h
	var scale_px := float(sim.cfg.cell_px)
	_pher_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	_water_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	_room_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	_pher_tex = ImageTexture.create_from_image(_pher_img)
	_water_tex = ImageTexture.create_from_image(_water_img)
	_room_tex = ImageTexture.create_from_image(_room_img)
	if _pher_sprite == null:
		_pher_sprite = Sprite2D.new()
		_pher_sprite.centered = false
		add_child(_pher_sprite)
	if _water_sprite == null:
		_water_sprite = Sprite2D.new()
		_water_sprite.centered = false
		add_child(_water_sprite)
	if _room_sprite == null:
		_room_sprite = Sprite2D.new()
		_room_sprite.centered = false
		add_child(_room_sprite)
	_pher_sprite.texture = _pher_tex
	_water_sprite.texture = _water_tex
	_room_sprite.texture = _room_tex
	_water_sprite.z_index = 1  # el agua se dibuja por encima de las hormigas
	_pher_sprite.scale = Vector2(scale_px, scale_px)
	_water_sprite.scale = Vector2(scale_px, scale_px)
	_room_sprite.scale = Vector2(scale_px, scale_px)
	refresh()


func cycle_layer() -> void:
	layer = (layer + 1) % Layer.size() as Layer
	refresh()


func _phero_field(l: int) -> PheromoneField:
	match l:
		Layer.FOOD:
			return sim.food
		Layer.HOME:
			return sim.home
		Layer.DANGER:
			return sim.danger
		Layer.ATTACK:
			return sim.attack
		Layer.EVACUATE:
			return sim.evacuate
		_:
			return null


func _room_color(room_type: int, is_valid: bool) -> Color:
	var base: Color
	match room_type:
		WorldGrid.Room.ROYAL:
			base = Color(1.0, 0.85, 0.2)
		WorldGrid.Room.NURSERY:
			base = Color(0.3, 0.85, 0.9)
		WorldGrid.Room.STORAGE:
			base = Color(0.8, 0.6, 0.2)
		WorldGrid.Room.FUNGUS:
			base = Color(0.4, 0.9, 0.3)
		WorldGrid.Room.DRAIN:
			base = Color(0.3, 0.4, 1.0)
		_:
			return Color(0, 0, 0, 0)
	return Color(base.r, base.g, base.b, 0.55 if is_valid else 0.22)


func refresh() -> void:
	var w := sim.world.w
	var h := sim.world.h
	# Siempre se dibujan las cámaras designadas, sean o no la capa activa (ayuda a construir).
	sim.rooms.maybe_recompute()
	for y in h:
		for x in w:
			var i := y * w + x
			var r := sim.world.room[i]
			_room_img.set_pixel(x, y, _room_color(r, sim.rooms.valid[r]) if r != WorldGrid.Room.NONE else Color(0, 0, 0, 0))
	_room_tex.update(_room_img)
	var field := _phero_field(layer)
	_pher_sprite.visible = field != null
	if field != null:
		var base: Color = PHERO_COLORS[layer - 1]
		for y in h:
			for x in w:
				var v := field.data[y * w + x]
				_pher_img.set_pixel(x, y, Color(base.r, base.g, base.b, minf(v * 0.9, 0.9)) if v > 0.02 else Color(0, 0, 0, 0))
		_pher_tex.update(_pher_img)
	var strong := layer == Layer.WATER
	var deep := sim.cfg.deep_level
	for y in h:
		for x in w:
			var v2 := sim.water.level[y * w + x]
			if v2 > 0.01:
				var c := Color(0.2, 0.45, 0.95, minf(v2 * 0.7, 0.75))
				if strong:
					c = Color(0.1, 0.9, 0.9, 0.85) if v2 < sim.cfg.flee_level else (Color(1.0, 0.85, 0.2, 0.9) if v2 < deep else Color(1.0, 0.25, 0.25, 0.95))
				_water_img.set_pixel(x, y, c)
			else:
				_water_img.set_pixel(x, y, Color(0, 0, 0, 0))
	_water_tex.update(_water_img)
