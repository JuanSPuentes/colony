class_name DayNightView
extends CanvasModulate
## Oscurece el mundo de noche (Fase 3). Vive dentro del SubViewport del mundo, así que tiñe el
## terreno, las hormigas y las plantas, pero no el HUD. Fuera del modo incremental no tiñe nada.
## Godot solo deja un CanvasModulate activo por canvas, así que el brillo del menú de Opciones
## (Fase 3) se aplica aquí mismo como multiplicador en vez de con un segundo CanvasModulate aparte
## (ese segundo nodo simplemente se ignoraba y el brillo no tenía ningún efecto visible).

const NIGHT := Color(0.34, 0.38, 0.6)

var sim: Simulation
var brightness := 1.0


func setup(s: Simulation) -> void:
	sim = s
	refresh()


func set_brightness(b: float) -> void:
	brightness = b
	refresh()


func refresh() -> void:
	var base := Color.WHITE
	if sim != null and sim.incremental:
		base = NIGHT.lerp(Color.WHITE, DayNight.light(sim.time_s(), sim.cfg))
	color = base * Color(brightness, brightness, brightness)
