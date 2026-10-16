class_name DayNightView
extends CanvasModulate
## Oscurece el mundo de noche (Fase 3). Vive dentro del SubViewport del mundo, así que tiñe el
## terreno, las hormigas y las plantas, pero no el HUD. Fuera del modo incremental no tiñe nada.

const NIGHT := Color(0.34, 0.38, 0.6)

var sim: Simulation


func setup(s: Simulation) -> void:
	sim = s
	refresh()


func refresh() -> void:
	if sim == null or not sim.incremental:
		color = Color.WHITE
		return
	color = NIGHT.lerp(Color.WHITE, DayNight.light(sim.time_s(), sim.cfg))
