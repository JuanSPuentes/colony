class_name PixelUI
extends RefCounted
## Fase 28: estilo pixel art de la interfaz — "tierra y madera". Paleta, fuente pixel y los
## recuadros (marco de madera, tarjeta de tierra, botón de tabla) que usan el HUD y las pantallas.
## Las texturas se generan por código a partir de píxeles "de arte" y se agrandan `PX` veces sin
## suavizado, así los bordes quedan escalonados y nítidos a cualquier tamaño de recuadro (9-slice).
##
## Fuentes (licencia SIL OFL, libres para uso comercial; ver `view/ui/fonts/OFL*.txt`):
## - VT323 para el texto y los números: angosta y con dígitos claros, entra en el panel lateral.
## - Pixelify Sans solo para títulos de sección: más vistosa, pero sus dígitos se confunden (5/S).

## Cuántos píxeles de pantalla mide un píxel de arte de los recuadros.
const PX := 3

const WOOD_DARK := Color("2b1a0e")
const WOOD := Color("6b4226")
const WOOD_LIGHT := Color("94603a")
const WOOD_HI := Color("c08a52")
const SOIL := Color("1d140d")
const SOIL_CARD := Color("2a1d13")
const SOIL_SPECK := Color("35251a")
const TEXT := Color("f4ecd8")
const TEXT_DIM := Color("b9a98f")
## Encabezados de sección: verde hoja, para que no compitan con el dorado de los botones activos.
const HEADER := Color("a8d672")
const GOLD := Color("ffd43c")
const DISABLED := Color("3a3129")

const FONT_PATH := "res://view/ui/fonts/VT323.ttf"
const TITLE_FONT_PATH := "res://view/ui/fonts/PixelifySans.ttf"

static var _font: FontFile
static var _title_font: FontFile
static var _boxes := {}


## Fuente pixel. Con suavizado leve en gris: sin él, en tamaños que no son el de su grilla las letras
## salen con píxeles irregulares (un 5 parece una S); así se ven en bloque pero parejas.
static func font() -> FontFile:
	if _font == null:
		_font = _pixel(FONT_PATH)
	return _font


## Fuente de títulos (encabezados de sección, carteles).
static func title_font() -> FontFile:
	if _title_font == null:
		_title_font = _pixel(TITLE_FONT_PATH)
	return _title_font


static func _pixel(path: String) -> FontFile:
	var f := load(path) as FontFile
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return f


## Tema base con la fuente pixel y los colores de texto; las pantallas lo asignan a su raíz.
static func theme(font_size: int) -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = font_size
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	return t


## Marco grueso de madera con fondo de tierra: panel lateral, barra de arriba, pausa, fin de partida.
static func frame(pad := 6) -> StyleBoxTexture:
	return _box("frame", pad, func(img: Image, n: int) -> void:
		_fill_soil(img, n, SOIL)
		_ring(img, n, 0, WOOD_DARK)
		_ring(img, n, 1, WOOD)
		_ring(img, n, 2, WOOD_LIGHT)
		_ring(img, n, 3, WOOD_DARK)
		# Luz arriba a la izquierda sobre la madera.
		for k in range(2, n - 2):
			img.set_pixel(k, 1, WOOD_HI)
			img.set_pixel(1, k, WOOD_HI), 5)


## Tarjeta de sección: tierra un poco más clara, borde fino de madera oscura y luz arriba.
static func card(pad := 4) -> StyleBoxTexture:
	return _box("card", pad, func(img: Image, n: int) -> void:
		_fill_soil(img, n, SOIL_CARD)
		_ring(img, n, 0, WOOD_DARK)
		for k in range(1, n - 1):
			img.set_pixel(k, 1, SOIL_SPECK), 3)


## Botón como una tablita: madera con canto claro arriba y oscuro abajo (al apretarlo, al revés).
static func button(state: String) -> StyleBoxTexture:
	var face: Color = {"normal": WOOD, "hover": WOOD_LIGHT, "pressed": WOOD_DARK.lightened(0.1), "disabled": DISABLED}[state]
	var top: Color = WOOD_DARK if state == "pressed" else (face.lightened(0.25) if state != "disabled" else face)
	var bottom: Color = face.lightened(0.2) if state == "pressed" else WOOD_DARK
	var edge: Color = GOLD if state == "hover" else WOOD_DARK
	return _box("btn_" + state, 2, func(img: Image, n: int) -> void:
		img.fill(face)
		for k in n:
			img.set_pixel(k, 1, top)
			img.set_pixel(k, n - 2, bottom)
		_ring(img, n, 0, edge), 3)


## Aplica los cuatro estados de botón y los colores de texto a un botón.
static func style_button(b: Button) -> void:
	for s in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(s, button(s))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", TEXT_DIM)
	b.add_theme_color_override("font_disabled_color", Color("7d7064"))


## Arma (una vez) un recuadro 9-slice: `draw` pinta una imagen de `n`×`n` píxeles de arte, con
## `margin` píxeles de borde que no se estiran; el centro se repite (las motas de tierra no se
## deforman). `pad` es el margen interno del contenido, en píxeles de arte.
static func _box(key: String, pad: int, draw: Callable, margin: int) -> StyleBoxTexture:
	var cache_key := "%s_%d" % [key, pad]
	if _boxes.has(cache_key):
		return _boxes[cache_key]
	var n := margin * 2 + 6
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	draw.call(img, n)
	img.resize(n * PX, n * PX, Image.INTERPOLATE_NEAREST)
	var sb := StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(img)
	sb.texture_margin_left = margin * PX
	sb.texture_margin_right = margin * PX
	sb.texture_margin_top = margin * PX
	sb.texture_margin_bottom = margin * PX
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.content_margin_left = pad * PX
	sb.content_margin_right = pad * PX
	sb.content_margin_top = pad * PX
	sb.content_margin_bottom = pad * PX
	_boxes[cache_key] = sb
	return sb


static func _fill_soil(img: Image, n: int, base: Color) -> void:
	img.fill(base)
	# Motas fijas (no al azar): el mismo recuadro siempre se ve igual.
	for k in n * n / 9:
		var x := (k * 7 + 3) % n
		var y := (k * 5 + (k / n) * 3 + 1) % n
		img.set_pixel(x, y, SOIL_SPECK)


## Contorno de un píxel a `inset` del borde.
static func _ring(img: Image, n: int, inset: int, c: Color) -> void:
	for k in range(inset, n - inset):
		img.set_pixel(k, inset, c)
		img.set_pixel(k, n - 1 - inset, c)
		img.set_pixel(inset, k, c)
		img.set_pixel(n - 1 - inset, k, c)
