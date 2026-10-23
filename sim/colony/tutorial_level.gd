extends RefCounted
## Fase 14: el "Nivel 0" (tutorial jugable). Es el modo incremental de siempre (`sim.incremental`)
## con tres diferencias, todas activadas solo por `sim.tutorial_level`:
## - No hay estaciones automáticas (`SeasonSystem.update` no corre): la única batalla la pide la
##   guía (`view/coach_view.gd`) llamando a `cmd_start_tutorial_battle()` cuando el jugador ya vio
##   lo básico, no un reloj que lo sorprenda a mitad de una explicación.
## - Esa batalla es un ejército chico (`cfg.tut_rival_ants`, reina rival con `cfg.tut_rival_strength`)
##   y ganarla termina el nivel con victoria: es la versión en miniatura del final de estación.
## - Sin araña ni lluvia automática (ver `Simulation.spawn_tutorial_start`): se explican con texto,
##   pero no interrumpen el aprendizaje.
##
## `sim` sin tipar por el mismo motivo que `season_system.gd` (ciclo de resolución con `preload`).


static func update(sim) -> void:
	if sim.game_over or not sim.tutorial_level:
		return
	var rival = sim.rival_colony
	if not rival.battle_active:
		return
	rival.update()
	if rival.battle_won:
		sim.game_over = true
		sim.victory = true
		sim.game_over_reason = "Derrotaste a la reina rival y superaste el Nivel 0.\nEn Juego normal, así termina cada estación."


static func start_battle(sim) -> bool:
	if not sim.tutorial_level or sim.tutorial_battle_started:
		return false
	var cfg: SimConfig = sim.cfg
	sim.tutorial_battle_started = true
	# Refuerzos del tutorial: la batalla debe poder ganarse aunque el azar de los huevos comprados
	# haya dado solo obreras. Nacen en el nido, igual que cualquier adulta.
	for k in cfg.tut_bonus_soldiers:
		sim.ants.add_ant_at(sim._random_nest_cell(), CasteDefs.Caste.SOLDIER)
	sim.rival_colony.start_battle(cfg.tut_rival_ants, cfg.tut_rival_strength)
	sim.notify("¡Un pequeño ejército rival ataca! Derrota a su reina.")
	return true
