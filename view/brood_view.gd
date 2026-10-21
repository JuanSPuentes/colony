class_name BroodView
extends Node2D
## Dibuja la cría en etapa Huevo (`BroodSystem.Stage.EGG`) con el sprite de
## `view/sprites/egg/egg.png` (racimo de huevos, pixel art en gris, generado para este juego).
## Antes la cría no tenía ningún dibujo en el mundo (solo se contaba en el HUD); esto es una vista
## nueva, no un reemplazo.
##
## Solo Huevo tiene sprite por ahora — Larva y Pupa se quedan sin dibujo hasta que haya arte para
## esas etapas (decisión explícita: el pack que llegó es de huevos, no de larvas). Un solo sprite,
## sin direcciones: es un racimo simétrico que no gira ni "mira" a ningún lado, a diferencia de las
## hormigas o las amenazas. Quieto de verdad: `BroodSystem.pos[i]` no cambia salvo que un Zángano
## esté cargando ese huevo (`AntSystem._think_drone`, ya existente), así que acá no hace falta
## ninguna lógica de movimiento — el huevo sigue al zángano solo, dibujar su posición actual basta.

const EGG_TEXTURE := preload("res://view/sprites/egg/egg.png")
## Chico a propósito: más pequeño que una hormiga (`AntRenderer.BODY_SIZE` = 7.5), para que no
## compita visualmente con las castas adultas ("que se queden quietas sin molestar").
const EGG_SIZE := Vector2(4.0, 4.0)

var sim: Simulation


func setup(s: Simulation) -> void:
	sim = s
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if sim == null or sim.queen_id < 0:
		return
	var brood := sim.brood
	for i in brood.stage.size():
		if not brood.alive[i] or brood.stage[i] != BroodSystem.Stage.EGG:
			continue
		var p := brood.pos[i]
		draw_texture_rect(EGG_TEXTURE, Rect2(p - EGG_SIZE * 0.5, EGG_SIZE), false)
