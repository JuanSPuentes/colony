class_name CentipedeView
extends Node2D
## Dibuja el ciempiés (Fase 5): cuerpo alargado y segmentado, para distinguirlo a simple vista de
## la araña (redonda) aunque los dos sean siluetas simples.

var sim: Simulation


func setup(s: Simulation) -> void:
	sim = s
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if sim == null or sim.centipede == null or not sim.centipede.alive:
		return
	var c := sim.centipede
	var body := Color("2a1a0f")
	var mark := Color("c0392b") if c.state == Centipede.State.ATTACK else Color("ff8030")
	var dir := Vector2.RIGHT
	if c.state == Centipede.State.CHASE or c.state == Centipede.State.RETREAT:
		dir = (c.pos - sim.ants.pos[c.target_ant]).normalized() if c.target_ant >= 0 and sim.ants.alive[c.target_ant] == 1 else dir
	var perp := Vector2(-dir.y, dir.x)
	const SEGMENTS := 6
	const SEG_LEN := 3.0
	for s in SEGMENTS:
		var seg_p := c.pos - dir * SEG_LEN * s
		draw_circle(seg_p, 2.2, body)
		# Patas cortas a los lados de cada segmento.
		draw_line(seg_p, seg_p + perp * 3.5, body, 1.0)
		draw_line(seg_p, seg_p - perp * 3.5, body, 1.0)
	draw_circle(c.pos, 2.6, mark)
	# Barra de vida, pequeña y por encima.
	var frac := clampf(c.hp / maxf(c.max_hp, 0.01), 0.0, 1.0)
	var bar_w := 14.0
	draw_rect(Rect2(c.pos.x - bar_w * 0.5, c.pos.y - 10.0, bar_w, 2.0), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(c.pos.x - bar_w * 0.5, c.pos.y - 10.0, bar_w * frac, 2.0), Color("ff4a4a"))
