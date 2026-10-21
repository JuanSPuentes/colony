class_name CentipedeView
extends Node2D
## Dibuja el ciempiés con el sprite de `view/sprites/centipede/` (8 direcciones, pixel art en
## gris, 100x100, generado para este juego — mismo origen que `view/sprites/ant/` y
## `view/sprites/spider/`). Reemplaza el dibujo procedural de antes (segmentos + patas cortas a
## mano).
##
## Igual que `SpiderView`: una sola instancia a la vez (`Simulation.centipede`, singleton — ver
## README sección 12), así que alcanza con `draw_texture_rect` directo en `_draw()`, sin
## `MultiMesh`. La dirección se sigue por la posición del frame anterior (igual que `SpiderView`),
## no por el estado interno (`State.CHASE`/`RETREAT`): es más simple y da el mismo resultado,
## porque la posición ya se mueve hacia donde sea que el ciempiés esté yendo.

## 5 veces el tamaño de una hormiga obrera (`AntRenderer.BODY_SIZE`, escala 1.0 — a diferencia de
## la araña, acá el usuario pidió la referencia de la hormiga, no de la reina). Pedido explícito
## del usuario tras probar un tamaño fijo (11.5) y uno exagerado solo para el modo Test (20x la
## reina), que se descartó.
const SIZE_MULT := 5.0

## Mismo orden que `AntRenderer.DIR_TEXTURES`/`SpiderView.DIR_TEXTURES`.
const DIR_TEXTURES: Array[Texture2D] = [
	preload("res://view/sprites/centipede/east.png"),
	preload("res://view/sprites/centipede/south-east.png"),
	preload("res://view/sprites/centipede/south.png"),
	preload("res://view/sprites/centipede/south-west.png"),
	preload("res://view/sprites/centipede/west.png"),
	preload("res://view/sprites/centipede/north-west.png"),
	preload("res://view/sprites/centipede/north.png"),
	preload("res://view/sprites/centipede/north-east.png"),
]
const DIR_COUNT := 8
const TURN_EPS2 := 0.0004

## Mismo espíritu que `SpiderView.BOB_FRACTION`: un rebotecito proporcional al tamaño mientras se
## mueve de verdad, ya que el pack tampoco trae fotogramas de caminata para esta amenaza.
const BOB_FRACTION := 0.07
const BOB_FREQ := 0.9

var sim: Simulation
var _prev_pos := Vector2.ZERO
var _last_dir := 0


func setup(s: Simulation) -> void:
	sim = s
	if sim.centipede != null:
		_prev_pos = sim.centipede.pos
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


## Igual fórmula que `AntRenderer._dir_index`/`SpiderView._dir_index` (duplicada a propósito).
func _dir_index(angle: float) -> int:
	var a := fposmod(angle, TAU)
	return int(round(a / (PI / 4.0))) % DIR_COUNT


func _body_size() -> Vector2:
	return Vector2.ONE * AntRenderer.BODY_SIZE.x * SIZE_MULT


func _draw() -> void:
	if sim == null or sim.centipede == null or not sim.centipede.alive:
		return
	var c := sim.centipede
	var delta := c.pos - _prev_pos
	var moving := delta.length_squared() > TURN_EPS2
	if moving:
		_last_dir = _dir_index(delta.angle())
	_prev_pos = c.pos
	var tex := DIR_TEXTURES[_last_dir]
	var size := _body_size()
	var p := c.pos
	if moving:
		p.y -= absf(sin(float(sim.tick_count) * BOB_FREQ)) * size.y * BOB_FRACTION
	draw_texture_rect(tex, Rect2(p - size * 0.5, size), false)
	# Barra de vida, pequeña y por encima.
	var frac := clampf(c.hp / maxf(c.max_hp, 0.01), 0.0, 1.0)
	var bar_w := 14.0
	var bar_y := p.y - size.y * 0.5 - 4.0
	draw_rect(Rect2(p.x - bar_w * 0.5, bar_y, bar_w, 2.0), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(p.x - bar_w * 0.5, bar_y, bar_w * frac, 2.0), Color("ff4a4a"))
