class_name HudIcons
extends RefCounted
## Fase 28: íconos pixel del HUD (reemplazan a los emojis, que cada sistema dibuja distinto o ni
## dibuja). Cada ícono es un mapa de 12×12 caracteres: `.` es transparente y cada letra un color de
## `COLORS`. Se agrandan sin suavizado a la escala pedida y se guardan en caché. Para retocar uno,
## basta con editar su mapa.

const SIZE := 12

const COLORS := {
	"k": Color("1a0f08"),  # contorno
	"g": Color("3f7d2c"), "G": Color("78b84a"),  # hoja / brote
	"y": Color("e0a020"), "Y": Color("ffd43c"),  # oro / sol
	"o": Color("a8661c"),
	"w": Color("eef3f7"), "b": Color("8fb8e0"), "B": Color("4f86c6"),  # nieve / agua
	"r": Color("c0392b"), "S": Color("e6e8ec"),  # rojo / acero
	"n": Color("d9822b"), "N": Color("f0b040"),  # otoño
	"c": Color("cfd6df"), "m": Color("f2ecc4"),  # nube / luna
	"t": Color("8a5a33"),
}

const MAPS := {
	"tree": [  # Fase 34: botón del árbol de mejoras
		"....kkkk....",
		"..kkGGGGkk..",
		".kGGGgGGGGk.",
		"kGGgGGGGgGGk",
		"kGGGGGgGGGGk",
		".kGgGGGGGgk.",
		"..kkkttkkk..",
		".....tt.....",
		".....tt.....",
		"....tttt....",
		"...tt..tt...",
		"............"],
	"leaf": [
		"..........k.",
		"........kkGk",
		"......kGGGGk",
		"....kGGGgGk.",
		"...kGGGgGGk.",
		"..kGGGgGGk..",
		"..kGGgGGk...",
		"..kGgGGk....",
		"..kgkkk.....",
		".kk.........",
		"k...........",
		"............"],
	"crown": [
		"............",
		"............",
		".k...k...k..",
		".kYk.kYk.kYk",
		".kYYkYYYkYYk",
		".kYYYYYYYYYk",
		".kYrYYrYYrYk",
		".kYYYYYYYYYk",
		".kyyyyyyyyyk",
		".kkkkkkkkkkk",
		"............",
		"............"],
	"sun": [
		".....Y......",
		"..Y..Y..Y...",
		"...Y.Y.Y....",
		"....YYY.....",
		".YYYYYYYYY..",
		"....YYY.....",
		"...Y.Y.Y....",
		"..Y..Y..Y...",
		".....Y......",
		"............",
		"............",
		"............"],
	"moon": [
		"............",
		"....mmm.....",
		"...mm.......",
		"..mm........",
		"..mm........",
		"..mm........",
		"..mmm.......",
		"...mmmm.mm..",
		"....mmmmm...",
		"............",
		"............",
		"............"],
	"calendar": [
		"............",
		"..k.....k...",
		".krrrrrrrrk.",
		".krrrrrrrrk.",
		".kwwwwwwwwk.",
		".kwkwkwkwwk.",
		".kwwwwwwwwk.",
		".kwkwkwkwwk.",
		".kwwwwwwwwk.",
		".kkkkkkkkkk.",
		"............",
		"............"],
	"spring": [
		"............",
		"..GG....GG..",
		".GGGG..GGGG.",
		".GgGGkkGGgG.",
		"..GGgkkgGG..",
		".....kk.....",
		".....kk.....",
		".....kk.....",
		"...tttttt...",
		"..tttttttt..",
		"............",
		"............"],
	"autumn": [
		"..........k.",
		"........kkNk",
		"......kNNNNk",
		"....kNNNnNk.",
		"...kNNNnNNk.",
		"..kNNNnNNk..",
		"..kNNnNNk...",
		"..kNnNNk....",
		"..knkkk.....",
		".kk.........",
		"k...........",
		"............"],
	"winter": [
		".....w......",
		"...w.w.w....",
		"....www.....",
		".w..www..w..",
		"..wwwbwww...",
		"wwwwbBbwwww.",
		"..wwwbwww...",
		".w..www..w..",
		"....www.....",
		"...w.w.w....",
		".....w......",
		"............"],
	"swords": [
		"S.........S.",
		".S.......S..",
		"..S.....S...",
		"...S...S....",
		"....S.S.....",
		".....S......",
		"....S.S.....",
		"...t...t....",
		"..t.....t...",
		".t.......t..",
		"............",
		"............"],
	"rain": [
		"............",
		"....ccc.....",
		"..ccccccc...",
		".ccccccccc..",
		".ccccccccc..",
		"............",
		"..b..b..b...",
		".b..b..b....",
		"............",
		"..b..b..b...",
		".b..b..b....",
		"............"],
	"snow": [
		"............",
		"....ccc.....",
		"..ccccccc...",
		".ccccccccc..",
		".ccccccccc..",
		"............",
		"..w...w.....",
		".www.www....",
		"..w...w..w..",
		"........www.",
		".....w...w..",
		"....www....."],
	"pause": [
		"............",
		"............",
		"..kkk..kkk..",
		"..kSk..kSk..",
		"..kSk..kSk..",
		"..kSk..kSk..",
		"..kSk..kSk..",
		"..kSk..kSk..",
		"..kkk..kkk..",
		"............",
		"............",
		"............"],
	"fast": [
		"............",
		"............",
		".Y...Y......",
		".YY..YY.....",
		".YYY.YYY....",
		".YYYYYYYY...",
		".YYY.YYY....",
		".YY..YY.....",
		".Y...Y......",
		"............",
		"............",
		"............"],
	"water": [
		".....b......",
		"....bbb.....",
		"....bbb.....",
		"...bbbbb....",
		"..bbbbBbb...",
		"..bbbbbBb...",
		"..bbbbbBb...",
		"...bbbBb....",
		"....bbb.....",
		"............",
		"............",
		"............"],
	# Fase 28: íconos de las mejoras, basados en las referencias del jugador.
	"gear": [
		"............",
		".....kk.....",
		"..k.kSSk.k..",
		".kSkSSSSkSk.",
		"..kSSkkSSk..",
		".kSSk..kSSk.",
		".kSSk..kSSk.",
		"..kSSkkSSk..",
		".kSkSSSSkSk.",
		"..k.kSSk.k..",
		".....kk.....",
		"............"],
	"era": [
		"............",
		".....y......",
		"...yyyyy....",
		".yyyyyyyyy..",
		"..o.o.o.o...",
		"..o.o.o.o...",
		"..o.o.o.o...",
		"..o.o.o.o...",
		".yyyyyyyyy..",
		"............",
		"............",
		"............"],
}

static var _cache := {}


## Textura del ícono `name` agrandada `scale` veces. Un nombre desconocido da un ícono vacío.
static func get_icon(name: String, scale: int = 2) -> Texture2D:
	var key := "%s@%d" % [name, scale]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var rows: Array = MAPS.get(name, [])
	for y in rows.size():
		var row: String = rows[y]
		for x in mini(row.length(), SIZE):
			var ch := row[x]
			if COLORS.has(ch):
				img.set_pixel(x, y, COLORS[ch])
	img.resize(SIZE * scale, SIZE * scale, Image.INTERPOLATE_NEAREST)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex
