class_name SpiderView
extends Node2D
## Dibuja la araña con el sprite de `view/sprites/spider/` (8 direcciones, pixel art en gris,
## 64x64, generado para este juego — mismo origen que `view/sprites/ant/`, ver
## `A_high-quality_2D_pixel_art_spider_enemy_for_a_dar.zip`). Reemplaza la silueta procedural de
## antes (8 patas dibujadas a mano).
##
## A diferencia de `AntRenderer` (que dibuja 500 hormigas con `MultiMeshInstance2D`), acá solo hay
## una araña a la vez (ver `Simulation.spider`, singleton — una decisión ya tomada: no vale la
## pena el costo de convertirla a lista por esto), así que alcanza con `draw_texture_rect` directo
## en `_draw()`: más simple, sin necesidad de montar un `MultiMesh` para una sola instancia. Por la
## misma razón no hace falta el flip vertical que sí necesitaba `AntRenderer` (ese era un efecto
## secundario de usar `QuadMesh`, una malla pensada para 3D, dentro de un `MultiMesh`;
## `draw_texture_rect` ya usa las coordenadas de pantalla tal cual).

## 4 veces el tamaño de la reina (`AntRenderer.BODY_SIZE` × `CasteDefs.VISUAL_SCALE[QUEEN]`, la
## misma cuenta que usa `AntRenderer` para dibujarla — no un número aparte que se podría
## desincronizar si alguno de los dos cambia), siempre, no solo en el modo Test. Pedido explícito
## del usuario tras probar un primer tamaño fijo (11.5) y uno exagerado solo para el modo Test
## (10x), que se descartó.
const SIZE_MULT := 4.0

## Mismo orden que `AntRenderer.DIR_TEXTURES`: crece con `Vector2.angle()` (0 = este, Y+ = hacia
## abajo/"sur").
const DIR_TEXTURES: Array[Texture2D] = [
	preload("res://view/sprites/spider/east.png"),
	preload("res://view/sprites/spider/south-east.png"),
	preload("res://view/sprites/spider/south.png"),
	preload("res://view/sprites/spider/south-west.png"),
	preload("res://view/sprites/spider/west.png"),
	preload("res://view/sprites/spider/north-west.png"),
	preload("res://view/sprites/spider/north.png"),
	preload("res://view/sprites/spider/north-east.png"),
]
const DIR_COUNT := 8
const TURN_EPS2 := 0.0004

## Mismo espíritu que el rebote de `AntRenderer` (sin fotogramas de caminata en el pack, un
## rebotecito mientras se mueve de verdad en vez de deslizarse quieta): acá como fracción del
## tamaño del cuerpo (`BOB_FRACTION`) en vez de un número fijo, para que se vea proporcional al
## tamaño mucho más grande de la araña.
const BOB_FRACTION := 0.07
const BOB_FREQ := 0.9

var sim: Simulation
var _prev_pos := Vector2.ZERO
var _last_dir := 0


func setup(s: Simulation) -> void:
	sim = s
	if sim.spider != null:
		_prev_pos = sim.spider.pos
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


## Igual fórmula que `AntRenderer._dir_index` (duplicada a propósito: tres líneas puras, no vale
## la pena una dependencia compartida por esto todavía).
func _dir_index(angle: float) -> int:
	var a := fposmod(angle, TAU)
	return int(round(a / (PI / 4.0))) % DIR_COUNT


func _body_size() -> Vector2:
	var queen_size := AntRenderer.BODY_SIZE.x * CasteDefs.VISUAL_SCALE[CasteDefs.Caste.QUEEN]
	return Vector2.ONE * queen_size * SIZE_MULT


func _draw() -> void:
	if sim == null or sim.spider == null or not sim.spider.alive:
		return
	var p := sim.spider.pos
	var delta := p - _prev_pos
	var moving := delta.length_squared() > TURN_EPS2
	if moving:
		_last_dir = _dir_index(delta.angle())
	_prev_pos = p
	var tex := DIR_TEXTURES[_last_dir]
	var size := _body_size()
	if moving:
		p.y -= absf(sin(float(sim.tick_count) * BOB_FREQ)) * size.y * BOB_FRACTION
	draw_texture_rect(tex, Rect2(p - size * 0.5, size), false)
	# Barra de vida, pequeña y por encima.
	var frac := clampf(sim.spider.hp / maxf(sim.spider.max_hp, 0.01), 0.0, 1.0)
	var bar_w := 14.0
	var bar_y := p.y - size.y * 0.5 - 4.0
	draw_rect(Rect2(p.x - bar_w * 0.5, bar_y, bar_w, 2.0), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(p.x - bar_w * 0.5, bar_y, bar_w * frac, 2.0), Color("ff4a4a"))
