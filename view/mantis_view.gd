class_name MantisView
extends Node2D
## Dibuja la mantis (Fase 7): cuerpo alargado con dos "brazos" en V al frente, para distinguirla
## de la araña (redonda) y el ciempiés (segmentado) aunque las tres sean siluetas simples.

var sim: Simulation


func setup(s: Simulation) -> void:
	sim = s
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if sim == null or sim.mantis == null or not sim.mantis.alive:
		return
	var m := sim.mantis
	var body := Color("2f4a1f")
	var mark := Color("c0392b") if m.state == Mantis.State.ATTACK else Color("8fce5f")
	var p := m.pos
	# Cuerpo: un óvalo alargado vertical (cabeza arriba).
	draw_line(p + Vector2(0, -7), p + Vector2(0, 6), body, 2.5)
	draw_circle(p + Vector2(0, -7), 2.0, body)  # cabeza
	# Brazos raptores en V, al frente de la cabeza.
	draw_line(p + Vector2(0, -5), p + Vector2(-5, -9), body, 1.5)
	draw_line(p + Vector2(0, -5), p + Vector2(5, -9), body, 1.5)
	draw_circle(p, 2.0, mark)
	# Barra de vida, pequeña y por encima.
	var frac := clampf(m.hp / maxf(m.max_hp, 0.01), 0.0, 1.0)
	var bar_w := 14.0
	draw_rect(Rect2(p.x - bar_w * 0.5, p.y - 14.0, bar_w, 2.0), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(p.x - bar_w * 0.5, p.y - 14.0, bar_w * frac, 2.0), Color("ff4a4a"))
