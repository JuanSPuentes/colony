class_name PlantView
extends Node2D
## Plantas con hojas finitas: cuantas menos hojas quedan, más pequeña se dibuja la planta.

var sim: Simulation


func setup(s: Simulation) -> void:
	sim = s
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if sim == null:
		return
	var cpx := sim.cfg.cell_px
	for p in sim.plants:
		var frac := float(p.leaves) / float(p.max_leaves)
		var base := Vector2((p.cell.x + 0.5) * cpx, (p.cell.y + 1) * cpx)
		draw_rect(Rect2(base.x - 0.5, base.y - 7.0 * maxf(frac, 0.25), 1, 7.0 * maxf(frac, 0.25)), Color("2f6b2a"))
		if p.leaves > 0:
			var r := 2.0 + 4.0 * frac
			draw_rect(Rect2(base.x - r, base.y - 6.0 - r * 0.6, r * 2.0, r), Color("4fb040"))
			draw_rect(Rect2(base.x - r * 0.6, base.y - 6.0 - r * 1.3, r * 1.2, r * 0.8), Color("7fd460"))
