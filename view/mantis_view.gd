class_name MantisView
extends Node2D
## Dibuja la mantis con el sprite de `view/sprites/mantis/` (8 direcciones, pixel art en gris,
## generado para este juego — mismo origen que `view/sprites/ant/`, `spider/` y `centipede/`).
## Reemplaza el dibujo procedural de antes (óvalo + "brazos" en V a mano).
##
## Igual que `SpiderView`/`CentipedeView`: una sola instancia a la vez (`Simulation.mantis`,
## singleton), así que alcanza con `draw_texture_rect` directo en `_draw()`, sin `MultiMesh`. La
## mantis casi nunca cambia de dirección (`Mantis.State.HIDDEN`/`ATTACK` no mueven su posición a
## propósito, ver `sim/threats/mantis.gd`): la dirección solo cambia de verdad cuando huye
## (`State.RETREAT`), y el seguimiento por posición del frame anterior (igual que las otras dos
## vistas) ya lo resuelve solo, sin casos especiales.

## 2 veces el tamaño de la reina (misma referencia en vivo que `SpiderView.SIZE_MULT`, ver ahí).
const SIZE_MULT := 2.0

## Mismo orden que `AntRenderer.DIR_TEXTURES`/`SpiderView.DIR_TEXTURES`/`CentipedeView.DIR_TEXTURES`.
const DIR_TEXTURES: Array[Texture2D] = [
	preload("res://view/sprites/mantis/east.png"),
	preload("res://view/sprites/mantis/south-east.png"),
	preload("res://view/sprites/mantis/south.png"),
	preload("res://view/sprites/mantis/south-west.png"),
	preload("res://view/sprites/mantis/west.png"),
	preload("res://view/sprites/mantis/north-west.png"),
	preload("res://view/sprites/mantis/north.png"),
	preload("res://view/sprites/mantis/north-east.png"),
]
const DIR_COUNT := 8
const TURN_EPS2 := 0.0004

## Mismo espíritu que `SpiderView.BOB_FRACTION`: rebotecito proporcional al tamaño mientras se
## mueve de verdad. En la práctica casi nunca se ve (la mantis no persigue, solo huye si la
## hieren), pero mantiene el mismo lenguaje visual que las otras dos amenazas.
const BOB_FRACTION := 0.07
const BOB_FREQ := 0.9

var sim: Simulation
var _prev_pos := Vector2.ZERO
var _last_dir := 0


func setup(s: Simulation) -> void:
	sim = s
	if sim.mantis != null:
		_prev_pos = sim.mantis.pos
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


## Igual fórmula que `AntRenderer._dir_index`/`SpiderView._dir_index`/`CentipedeView._dir_index`
## (duplicada a propósito).
func _dir_index(angle: float) -> int:
	var a := fposmod(angle, TAU)
	return int(round(a / (PI / 4.0))) % DIR_COUNT


func _body_size() -> Vector2:
	var queen_size := AntRenderer.BODY_SIZE.x * CasteDefs.VISUAL_SCALE[CasteDefs.Caste.QUEEN]
	return Vector2.ONE * queen_size * SIZE_MULT


func _draw() -> void:
	if sim == null or sim.mantis == null or not sim.mantis.alive:
		return
	var m := sim.mantis
	var delta := m.pos - _prev_pos
	var moving := delta.length_squared() > TURN_EPS2
	if moving:
		_last_dir = _dir_index(delta.angle())
	_prev_pos = m.pos
	var tex := DIR_TEXTURES[_last_dir]
	var size := _body_size()
	var p := m.pos
	if moving:
		p.y -= absf(sin(float(sim.tick_count) * BOB_FREQ)) * size.y * BOB_FRACTION
	draw_texture_rect(tex, Rect2(p - size * 0.5, size), false)
	# Barra de vida, pequeña y por encima.
	var frac := clampf(m.hp / maxf(m.max_hp, 0.01), 0.0, 1.0)
	var bar_w := 14.0
	var bar_y := p.y - size.y * 0.5 - 4.0
	draw_rect(Rect2(p.x - bar_w * 0.5, bar_y, bar_w, 2.0), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(p.x - bar_w * 0.5, bar_y, bar_w * frac, 2.0), Color("ff4a4a"))
