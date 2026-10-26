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
## Más chico que una hormiga (`AntRenderer.BODY_SIZE` = 7.5), para que no compita con las castas
## adultas. Fase 14: de 4 a 5 px, y la cría se dibuja por encima de la capa de feromonas/cámaras
## (ver el orden en `main.gd`): con un tinte de cámara y un rastro de hogar encima, 4 px no se veían.
const EGG_SIZE := Vector2(5.0, 5.0)
## Fase 14: larva y pupa sin sprite propio, con formas simples: así la cría no "desaparece" en
## cuanto el huevo pasa de etapa (en Juego normal eso pasa en pocos segundos).
const LARVA_COLOR := Color("f2ead2")
const PUPA_COLOR := Color("c9a46a")
const OUTLINE := Color(0.1, 0.07, 0.05, 0.9)

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
		if not brood.alive[i]:
			continue
		var p := brood.pos[i]
		match brood.stage[i]:
			BroodSystem.Stage.EGG:
				draw_texture_rect(EGG_TEXTURE, Rect2(p - EGG_SIZE * 0.5, EGG_SIZE), false)
			BroodSystem.Stage.LARVA:
				# Gusanito curvo: tres círculos que se achican.
				for k in 3:
					var c := p + Vector2(-1.4 + 1.4 * k, 0.5 - absf(k - 1) * 0.6)
					draw_circle(c, 1.35 - 0.25 * k, OUTLINE)
					draw_circle(c, 1.0 - 0.25 * k, LARVA_COLOR)
			BroodSystem.Stage.PUPA:
				draw_set_transform(p, 0.0, Vector2(1.0, 1.6))
				draw_circle(Vector2.ZERO, 1.7, OUTLINE)
				draw_circle(Vector2.ZERO, 1.3, PUPA_COLOR)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
