class_name ThreatSpriteView
extends Node2D
## Base común para las vistas de una amenaza de una sola instancia (araña/ciempiés/mantis, ver
## `Simulation.spider`/`centipede`/`mantis`, todas singleton): sigue la posición y dirección del
## objeto, dibuja el sprite de la dirección correspondiente con un rebotecito proporcional al
## tamaño mientras se mueve de verdad (el pack de arte solo trae la pose Idle, sin fotogramas de
## caminata) y una barra de vida arriba.
##
## Antes esto estaba triplicado casi línea por línea en `spider_view.gd`/`centipede_view.gd`/
## `mantis_view.gd` (mismo `_draw()`, mismo rebote, misma barra de vida, cada uno con su propia
## copia de `_dir_index`). Cada subclase ahora solo define sus texturas (`_dir_textures`), su
## tamaño (`_body_size`) y de dónde sale el objeto de la amenaza en el tick actual (`_get_threat`);
## el resto se escribe una sola vez acá.
##
## A diferencia de `AntRenderer` (que dibuja 500 hormigas con `MultiMeshInstance2D`), acá alcanza
## con `draw_texture_rect` directo en `_draw()`: una sola instancia no justifica montar un
## `MultiMesh`, y tampoco hace falta el flip vertical que sí necesitaba `AntRenderer` (ese era un
## efecto secundario de `QuadMesh`, una malla pensada para 3D; `draw_texture_rect` ya usa
## coordenadas de pantalla tal cual).

const TURN_EPS2 := 0.0004
const BOB_FRACTION := 0.07
const BOB_FREQ := 0.9

var sim: Simulation
var _prev_pos := Vector2.ZERO
var _last_dir := 0


func setup(s: Simulation) -> void:
	sim = s
	var t = _get_threat()
	if t != null:
		_prev_pos = t.pos
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


## A implementar por cada subclase: el objeto de `sim` con `.pos`/`.alive`/`.hp`/`.max_hp` de este
## tick, o `null` si `sim` todavía no está listo. Sin tipar a propósito — cada amenaza es una clase
## distinta sin clase base en `sim/threats/`, solo la misma forma (duck typing, mismo criterio que
## `AntSystem._nearest_threat`).
func _get_threat():
	return null


## Las 8 texturas de dirección, mismo orden que usa `SpriteDir` (ver `AntRenderer.DIR_TEXTURES`).
func _dir_textures() -> Array[Texture2D]:
	return []


## Tamaño en pantalla del sprite (pixeles de mundo, mismas unidades que `ants.pos`).
func _body_size() -> Vector2:
	return Vector2.ONE


func _draw() -> void:
	var t = _get_threat()
	if sim == null or t == null or not t.alive:
		return
	var tpos: Vector2 = t.pos
	var delta := tpos - _prev_pos
	var moving := delta.length_squared() > TURN_EPS2
	if moving:
		_last_dir = SpriteDir.index(delta.angle())
	_prev_pos = tpos
	var tex := _dir_textures()[_last_dir]
	var size := _body_size()
	var p := tpos
	if moving:
		p.y -= absf(sin(float(sim.tick_count) * BOB_FREQ)) * size.y * BOB_FRACTION
	draw_texture_rect(tex, Rect2(p - size * 0.5, size), false)
	# Barra de vida, pequeña y por encima.
	var hp: float = t.hp
	var max_hp: float = t.max_hp
	var frac := clampf(hp / maxf(max_hp, 0.01), 0.0, 1.0)
	var bar_w := 14.0
	var bar_y := p.y - size.y * 0.5 - 4.0
	draw_rect(Rect2(p.x - bar_w * 0.5, bar_y, bar_w, 2.0), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(p.x - bar_w * 0.5, bar_y, bar_w * frac, 2.0), Color("ff4a4a"))
