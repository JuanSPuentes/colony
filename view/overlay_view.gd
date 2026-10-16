class_name OverlayView
extends Node2D
## Capas sobre el terreno. Cada una es una Image del tamaño de la cuadrícula que se copia a una
## ImageTexture unas 5 veces por segundo (no en cada frame) y se escala a 8x.

enum Layer { NONE, FOOD, HOME, WATER, STATES }

const LAYER_NAMES: Array[String] = ["ninguna", "feromona de comida", "feromona de hogar", "nivel de agua", "estado de las hormigas"]

var sim: Simulation
var layer := Layer.FOOD
var _pher_img: Image
var _pher_tex: ImageTexture
var _pher_sprite: Sprite2D
var _water_img: Image
var _water_tex: ImageTexture
var _water_sprite: Sprite2D


func setup(s: Simulation) -> void:
	sim = s
	var w := sim.world.w
	var h := sim.world.h
	var scale_px := float(sim.cfg.cell_px)
	_pher_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	_water_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	_pher_tex = ImageTexture.create_from_image(_pher_img)
	_water_tex = ImageTexture.create_from_image(_water_img)
	if _pher_sprite == null:
		_pher_sprite = Sprite2D.new()
		_pher_sprite.centered = false
		add_child(_pher_sprite)
	if _water_sprite == null:
		_water_sprite = Sprite2D.new()
		_water_sprite.centered = false
		add_child(_water_sprite)
	_pher_sprite.texture = _pher_tex
	_water_sprite.texture = _water_tex
	_water_sprite.z_index = 1  # el agua se dibuja por encima de las hormigas
	_pher_sprite.scale = Vector2(scale_px, scale_px)
	_water_sprite.scale = Vector2(scale_px, scale_px)
	refresh()


func cycle_layer() -> void:
	layer = (layer + 1) % Layer.size() as Layer
	refresh()


func refresh() -> void:
	var w := sim.world.w
	var h := sim.world.h
	_pher_sprite.visible = layer == Layer.FOOD or layer == Layer.HOME
	if _pher_sprite.visible:
		var field := sim.food if layer == Layer.FOOD else sim.home
		var base := Color(0.25, 1.0, 0.3) if layer == Layer.FOOD else Color(0.35, 0.6, 1.0)
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
