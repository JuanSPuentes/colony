extends RefCounted
## Reglas de población (cambio de era) y de victoria, separadas de `simulation.gd` para que
## `tick()` siga leyéndose como una lista de pasos, no como lógica de juego (ARCHITECTURE.md
## sección 1: "no le pongas reglas de juego aquí"). Vive en `colony/` porque son reglas de la
## colonia (población, cuánto dura viva), no del mundo físico.
##
## `sim` no se tipa como `Simulation` a propósito: este archivo lo carga `Simulation` con
## `preload`, y tipar el parámetro crearía un ciclo de resolución (igual que `ant_caste_ai.gd`
## con `AntSystem`). Referenciar `Simulation.Era` como tipo en el cuerpo de las funciones sí es
## seguro porque se resuelve en tiempo de ejecución, no al cargar.


static func update_era(sim) -> void:
	var cfg: SimConfig = sim.cfg
	var ants: AntSystem = sim.ants
	var pop: int = ants.alive_count
	var new_era: int = Simulation.Era.FOUNDATION
	if pop >= cfg.era3_population:
		new_era = Simulation.Era.MATURE
	elif pop >= cfg.era2_population:
		new_era = Simulation.Era.YOUNG
	if new_era != sim.era:
		sim.era = new_era
		match new_era:
			Simulation.Era.YOUNG:
				sim.notify("Nueva era: Colonia joven. Soldados disponibles.")
			Simulation.Era.MATURE:
				sim.notify("Nueva era: Colonia madura. Peligro, Ataque, Evacuar y la araña.")
				if sim._mature_since_s < 0.0:
					sim._mature_since_s = sim.time_s()


## Fase 4: condición de victoria (prompt_fase3_godot.md sección 4.1, adaptada sin día/noche):
## sobrevivir `cfg.victory_survive_s` segundos de simulación DESPUÉS de llegar a Colonia madura,
## con la reina viva. Solo aplica a la colonia con reina (`simulation.gd` no llama esto en el modo
## incremental).
static func check_victory(sim) -> void:
	var cfg: SimConfig = sim.cfg
	if sim.game_over or sim._mature_since_s < 0.0:
		return
	if sim.time_s() - sim._mature_since_s >= cfg.victory_survive_s:
		sim.game_over = true
		sim.victory = true
		sim.game_over_reason = "La colonia prosperó."
