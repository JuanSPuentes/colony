class_name SpiderView
extends Node2D
## Dibuja la araña (Fase 1): una silueta sencilla de 8 patas que contraste con el fondo.

var sim: Simulation


func setup(s: Simulation) -> void:
	sim = s
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if sim == null or sim.spider == null or not sim.spider.alive:
		return
	var p := sim.spider.pos
	var r := 5.0
	var body := Color("1a1a1a")
	var mark := Color("c0392b") if sim.spider.state == Spider.State.ATTACK else Color("ff8030")
	for k in 8:
		var a := k * TAU / 8.0
		var leg := p + Vector2(cos(a), sin(a)) * (r + 3.0)
		draw_line(p, leg, body, 1.0)
	draw_circle(p, r, body)
	draw_circle(p, r * 0.45, mark)
	# Barra de vida, pequeña y por encima.
	var frac := clampf(sim.spider.hp / maxf(sim.spider.max_hp, 0.01), 0.0, 1.0)
	var bar_w := 14.0
	draw_rect(Rect2(p.x - bar_w * 0.5, p.y - r - 6.0, bar_w, 2.0), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(p.x - bar_w * 0.5, p.y - r - 6.0, bar_w * frac, 2.0), Color("ff4a4a"))
