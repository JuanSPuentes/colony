class_name OverlayView
extends Node2D
## Capas sobre el terreno. Cada una es una Image del tamaño de la cuadrícula que se copia a una
## ImageTexture unas 5 veces por segundo (no en cada frame) y se escala a 8x.
## Fase 1: se añadieron 3 feromonas más y una capa de castas.

## `PLAYER_PHEROS` se agrega al final a propósito (no entre NONE y FOOD): el resto del código
## (`tools/screenshot.gd -- capaN`, el orden de `PHERO_COLORS`) ya asume esos índices, y GDScript
## no deja fijar el valor de un solo campo de enum sin fijarlos todos.
enum Layer { NONE, FOOD, HOME, DANGER, ATTACK, EVACUATE, WATER, STATES, CASTES, PLAYER_PHEROS }

const LAYER_NAMES: Array[String] = ["ninguna", "feromona de comida", "feromona de hogar",
	"feromona de peligro", "feromona de ataque", "feromona de evacuar", "nivel de agua",
	"estado de las hormigas", "casta de las hormigas", "feromonas del jugador"]
## Color base de cada feromona pintable (orden: FOOD, HOME, DANGER, ATTACK, EVACUATE).
const PHERO_COLORS: Array[Color] = [
	Color(0.25, 1.0, 0.3), Color(0.35, 0.6, 1.0), Color(1.0, 0.25, 0.25),
	Color(1.0, 0.55, 0.1), Color(1.0, 1.0, 0.3),
]
## Qué feromonas se dibujan juntas en `Layer.PLAYER_PHEROS` (todas las que el jugador pinta a
## mano): Hogar queda afuera a propósito porque la depositan las hormigas solas al salir del nido,
## no el jugador, y mostrarla siempre ensuciaría la vista con el rastro de las 100+ hormigas.
const PLAYER_PHERO_LAYERS: Array[Layer] = [Layer.FOOD, Layer.DANGER, Layer.ATTACK, Layer.EVACUATE]
const WATER_COLOR := Color(0.2, 0.45, 0.95)

var sim: Simulation
## Por defecto se ven todas las feromonas que el jugador puede pintar (antes arrancaba mostrando
## solo Comida; había que usar Tab a mano para ver Peligro/Ataque/Evacuar mientras se pintan).
var layer := Layer.PLAYER_PHEROS
var _pher_img: Image
var _pher_tex: ImageTexture
var _pher_sprite: Sprite2D
var _water_img: Image
var _water_tex: ImageTexture
var _water_sprite: Sprite2D
var _room_img: Image
var _room_tex: ImageTexture
var _room_sprite: Sprite2D
## Las tres imágenes se arman como bytes RGBA8 de una vez (`Image.set_data`) en vez de 8.400
## `set_pixel` por capa: `refresh()` costaba ~7 ms y corre 5 veces por segundo (un tirón cada
## 200 ms). `_rgba8` reproduce exacto lo que hace `set_pixel` (trunca, no redondea), así que la
## imagen sale idéntica byte a byte. Cámaras y agua además se saltan si no cambió nada.
var _pher_bytes := PackedByteArray()
var _water_bytes := PackedByteArray()
var _room_bytes := PackedByteArray()
var _room_key := ""
var _water_blank := false
## Color de trabajo para pasar la opacidad por float32 (como la guarda `Color`) antes de truncarla.
var _tmp := Color()


func setup(s: Simulation) -> void:
	sim = s
	var w := sim.world.w
	var h := sim.world.h
	var scale_px := float(sim.cfg.cell_px)
	_pher_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	_water_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	_room_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	for b in [_pher_bytes, _water_bytes, _room_bytes]:
		b.resize(w * h * 4)
		b.fill(0)
	_room_key = ""
	_water_blank = false
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


## Lo mismo que `Image.set_pixel` guarda en un píxel RGBA8 para ese componente: trunca, no redondea.
static func _rgba8(f: float) -> int:
	return int(clampf(f * 255.0, 0.0, 255.0))


## Escribe un píxel en `bytes`: color fijo `c` con opacidad `a` (pasada por float32, como `Color`).
func _put(bytes: PackedByteArray, i: int, c: Color, a: float) -> void:
	_tmp.a = a
	var o := i * 4
	bytes[o] = _rgba8(c.r)
	bytes[o + 1] = _rgba8(c.g)
	bytes[o + 2] = _rgba8(c.b)
	bytes[o + 3] = _rgba8(_tmp.a)


func _clear_px(bytes: PackedByteArray, i: int) -> void:
	var o := i * 4
	bytes[o] = 0
	bytes[o + 1] = 0
	bytes[o + 2] = 0
	bytes[o + 3] = 0


func _upload(img: Image, tex: ImageTexture, bytes: PackedByteArray) -> void:
	img.set_data(sim.world.w, sim.world.h, false, Image.FORMAT_RGBA8, bytes)
	tex.update(img)


## Las 4 feromonas pintables a la vez: en cada celda gana la que tenga más valor ahí (en vez de
## mezclar colores, que quedaría turbio donde se pisan dos rastros), con su propio color.
func _draw_player_pheros(w: int, h: int) -> void:
	# Bucle caliente (8.400 celdas, 5 veces por segundo): todo en línea, sin llamadas por celda.
	var d0 := _phero_field(PLAYER_PHERO_LAYERS[0]).data
	var d1 := _phero_field(PLAYER_PHERO_LAYERS[1]).data
	var d2 := _phero_field(PLAYER_PHERO_LAYERS[2]).data
	var d3 := _phero_field(PLAYER_PHERO_LAYERS[3]).data
	var rgb := PackedByteArray()
	for l in PLAYER_PHERO_LAYERS:
		var c: Color = PHERO_COLORS[l - 1]
		rgb.append_array(PackedByteArray([_rgba8(c.r), _rgba8(c.g), _rgba8(c.b)]))
	var bytes := _pher_bytes
	for i in w * h:
		var best_v := 0.02
		var best_k := -1
		var v := d0[i]
		if v > best_v:
			best_v = v
			best_k = 0
		v = d1[i]
		if v > best_v:
			best_v = v
			best_k = 1
		v = d2[i]
		if v > best_v:
			best_v = v
			best_k = 2
		v = d3[i]
		if v > best_v:
			best_v = v
			best_k = 3
		var o := i * 4
		if best_k < 0:
			bytes[o] = 0
			bytes[o + 1] = 0
			bytes[o + 2] = 0
			bytes[o + 3] = 0
		else:
			_tmp.a = minf(best_v * 0.9, 0.9)
			bytes[o] = rgb[best_k * 3]
			bytes[o + 1] = rgb[best_k * 3 + 1]
			bytes[o + 2] = rgb[best_k * 3 + 2]
			bytes[o + 3] = int(_tmp.a * 255.0)
	_pher_bytes = bytes
	_upload(_pher_img, _pher_tex, _pher_bytes)


func _room_color(room_type: int, is_valid: bool) -> Color:
	var base: Color
	match room_type:
		WorldGrid.Room.ROYAL:
			base = Color(1.0, 0.85, 0.2)
		WorldGrid.Room.NURSERY:
			base = Color(0.3, 0.85, 0.9)
		WorldGrid.Room.STORAGE:
			# Fase 17: naranja más marcado; el ocre de antes casi no se distinguía del amarillo de la Real.
			base = Color(0.95, 0.45, 0.15)
		_:
			return Color(0, 0, 0, 0)
	return Color(base.r, base.g, base.b, 0.55 if is_valid else 0.22)


func refresh() -> void:
	var w := sim.world.w
	var h := sim.world.h
	# Siempre se dibujan las cámaras designadas, sean o no la capa activa (ayuda a construir).
	sim.rooms.maybe_recompute()
	# Las cámaras casi nunca cambian: solo se redibujan si cambió alguna o cuáles son válidas.
	var key := "%d|%s" % [sim.world.rooms_version, sim.rooms.valid]
	if key != _room_key:
		_room_key = key
		var room := sim.world.room
		for i in w * h:
			var r := room[i]
			if r == WorldGrid.Room.NONE:
				_clear_px(_room_bytes, i)
			else:
				var rc := _room_color(r, sim.rooms.valid[r])
				_put(_room_bytes, i, rc, rc.a)
		_upload(_room_img, _room_tex, _room_bytes)
	if layer == Layer.PLAYER_PHEROS:
		_pher_sprite.visible = true
		_draw_player_pheros(w, h)
	else:
		var field := _phero_field(layer)
		_pher_sprite.visible = field != null
		if field != null:
			var base: Color = PHERO_COLORS[layer - 1]
			var fd := field.data
			for i in w * h:
				var v := fd[i]
				if v > 0.02:
					_put(_pher_bytes, i, base, minf(v * 0.9, 0.9))
				else:
					_clear_px(_pher_bytes, i)
			_upload(_pher_img, _pher_tex, _pher_bytes)
	_refresh_water(w, h)


func _refresh_water(w: int, h: int) -> void:
	var level := sim.water.level
	var any := false
	for i in w * h:
		if level[i] > 0.01:
			any = true
			break
	# Sin agua en ningún lado y la imagen ya vacía: nada que redibujar (es lo normal fuera de la lluvia).
	if not any and _water_blank:
		return
	_water_blank = not any
	var strong := layer == Layer.WATER
	var deep := sim.cfg.deep_level
	var flee := sim.cfg.flee_level
	for i in w * h:
		var v2 := level[i]
		if v2 > 0.01:
			if strong:
				var c := Color(0.1, 0.9, 0.9, 0.85) if v2 < flee else (Color(1.0, 0.85, 0.2, 0.9) if v2 < deep else Color(1.0, 0.25, 0.25, 0.95))
				_put(_water_bytes, i, c, c.a)
			else:
				_put(_water_bytes, i, WATER_COLOR, minf(v2 * 0.7, 0.75))
		else:
			_clear_px(_water_bytes, i)
	_upload(_water_img, _water_tex, _water_bytes)
