class_name TerrainStyle
extends RefCounted
## Fase 20: cómo se ve el terreno, separado de cómo se arma la imagen (`TerrainView`). Solo paleta y
## texturas, sin estado de la partida.
##
## Idea (estilo Terraria): la tierra es una textura continua que no se corta en cada celda; detrás de
## lo excavado se ve una "pared de fondo" (la misma tierra, oscura y apagada); y donde la tierra toca
## un hueco hay un borde que la recorta. Para que sea rápido, cada material es una textura chica de
## `TILE` px que se repite sin costuras (`tile()`), y `TerrainView` copia de ella el trozo que le
## toca a cada celda con `Image.blit_rect` (nativo) en vez de pintar píxel por píxel.

const TILE := 32

enum Mat { DIRT_1, DIRT_2, DIRT_3, WALL_1, WALL_2, WALL_3, ROCK, ROOT, ROOT_WALL }

## Capas de tierra por profundidad (0 = superficie, 1 = fondo del mundo).
const LAYER_LIMITS: Array[float] = [0.3, 0.62]
const DIRT_BASE: Array[Color] = [Color("8a5a38"), Color("6b4429"), Color("4f3220")]
const ROCK_BASE := Color("74747e")
## Fase 29: raíces del árbol madre metidas en la tierra (madera con veta), y la pared de fondo de un
## túnel que pasa por una raíz.
const ROOT_BASE := Color("5b3a20")
## Pared de fondo: la tierra de esa capa, oscura y desaturada (se lee como "hueco").
const WALL_DARKEN := 0.55
const WALL_DESATURATE := 0.35
## Borde donde la tierra toca un hueco.
const EDGE_DARK := Color(0.16, 0.10, 0.06)
const EDGE_LIGHT_LIFT := 0.18
## Celda marcada para cavar (las grietas las agrega `DigEffectsView`).
const MARK_LINE := Color("ffd060")
const MARK_TINT := Color("f0b040")
const MARK_TINT_AMOUNT := 0.18

static var _tiles: Dictionary = {}


## Textura repetible de `TILE`x`TILE` para un material. Se genera la primera vez y se guarda.
static func tile(mat: int) -> Image:
	if not _tiles.has(mat):
		_tiles[mat] = _make_tile(mat)
	return _tiles[mat]


## Material de tierra de una celda. Cerca del límite entre capas se mezclan con ruido, para que el
## cambio de color no sea una línea recta.
static func dirt_mat(x: int, y: int, depth: float) -> int:
	var layer := _layer_of(depth + (float(noise(x, y, 7) & 0x3f) / 63.0 - 0.5) * 0.06)
	return Mat.DIRT_1 + layer


static func wall_mat(x: int, y: int, depth: float) -> int:
	return Mat.WALL_1 + _layer_of(depth + (float(noise(x, y, 7) & 0x3f) / 63.0 - 0.5) * 0.06)


static func _layer_of(depth: float) -> int:
	if depth < LAYER_LIMITS[0]:
		return 0
	if depth < LAYER_LIMITS[1]:
		return 1
	return 2


## Hash entero barato y determinista (mismo patrón en cada partida).
static func noise(x: int, y: int, k: int) -> int:
	var h := (x * 73856093) ^ (y * 19349663) ^ (k * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return (h ^ (h >> 16)) & 0xff


static func _make_tile(mat: int) -> Image:
	var base: Color
	var speck := 0.14
	var blotch := 0.07
	match mat:
		Mat.ROCK:
			base = ROCK_BASE
			speck = 0.2
			blotch = 0.05
		Mat.ROOT, Mat.ROOT_WALL:
			return _wood_tile(ROOT_BASE.darkened(WALL_DARKEN) if mat == Mat.ROOT_WALL else ROOT_BASE)
		Mat.WALL_1, Mat.WALL_2, Mat.WALL_3:
			var d: Color = DIRT_BASE[mat - Mat.WALL_1]
			base = d.darkened(WALL_DARKEN).lerp(Color(d.v, d.v, d.v).darkened(WALL_DARKEN), WALL_DESATURATE)
			speck = 0.1
			blotch = 0.05
		_:
			base = DIRT_BASE[mat - Mat.DIRT_1]
	var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	for y in TILE:
		for x in TILE:
			# Manchas suaves (ruido interpolado, sin escalones ni cuadrícula) y granitos sueltos de un
			# píxel, como la tierra de Terraria.
			var b := _smooth(x, y, mat + 100)
			var c := base.lightened(blotch * (b - 0.5) * 2.0) if b > 0.5 else base.darkened(blotch * (0.5 - b) * 2.0)
			var n := noise(x, y, mat + 200)
			if n < 22:
				c = c.darkened(speck)
			elif n > 238:
				c = c.lightened(speck * 0.8)
			img.set_pixel(x, y, c)
	return img


## Ruido suave 0..1 que se repite cada `TILE` px sin costura: valores al azar en una grilla de
## `CELL` px (que envuelve), interpolados con curva suave entre los 4 puntos vecinos.
const _SMOOTH_CELL := 8
static func _smooth(x: int, y: int, k: int) -> float:
	var n := TILE / _SMOOTH_CELL
	var gx := x / _SMOOTH_CELL
	var gy := y / _SMOOTH_CELL
	var fx := smoothstep(0.0, 1.0, float(x % _SMOOTH_CELL) / _SMOOTH_CELL)
	var fy := smoothstep(0.0, 1.0, float(y % _SMOOTH_CELL) / _SMOOTH_CELL)
	var a := float(noise(gx % n, gy % n, k)) / 255.0
	var b := float(noise((gx + 1) % n, gy % n, k)) / 255.0
	var c := float(noise(gx % n, (gy + 1) % n, k)) / 255.0
	var d := float(noise((gx + 1) % n, (gy + 1) % n, k)) / 255.0
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


## Color de cada tipo de cámara (antes en `OverlayView._room_color`, que las pintaba como bloques
## sólidos). Ahora `TerrainView` lo usa para un tinte suave y el contorno.
static func room_color(room_type: int) -> Color:
	match room_type:
		WorldGrid.Room.ROYAL:
			return Color(1.0, 0.85, 0.2)
		WorldGrid.Room.NURSERY:
			return Color(0.3, 0.85, 0.9)
		WorldGrid.Room.STORAGE:
			# Fase 17: naranja más marcado; el ocre de antes casi no se distinguía del amarillo de la Real.
			return Color(0.95, 0.45, 0.15)
	return Color(0, 0, 0, 0)


## Fase 29: madera de raíz — vetas horizontales onduladas (la raíz corre de lado bajo tierra) y algún
## nudo oscuro. Se repite sin costura como las demás.
static func _wood_tile(base: Color) -> Image:
	var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	for y in TILE:
		for x in TILE:
			var wave := sin((float(x) / TILE) * TAU * 2.0 + float(noise(0, y, 31) & 7) * 0.4) * 1.5
			var band := posmod(int(y + wave), 5)
			var c := base.darkened(0.35) if band == 0 else (base.lightened(0.22) if band == 2 else base)
			if noise(x, y, 33) < 6:
				c = c.darkened(0.35)
			img.set_pixel(x, y, c)
	return img
