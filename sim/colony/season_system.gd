extends RefCounted
## Fase 9: estaciones del modo incremental. 4 estaciones fijas; al llegar al último día de cada
## una ataca la colonia rival correspondiente (`sim.rival_colony`) y la estación no avanza hasta
## que su reina muera. Derrotar a las 4 es la condición de victoria real de "Juego normal" —
## reemplaza la de la Fase 8 (sobrevivir tras la araña), retirada: ver README sección 15/16.
##
## `sim` no se tipa a propósito (mismo motivo que `era_system.gd`): este archivo lo carga
## `Simulation` con `preload`, tipar el parámetro crearía un ciclo de resolución.

const SEASON_COUNT := 4
const SEASON_NAMES: Array[String] = ["Primavera", "Verano", "Otoño", "Invierno"]


static func update(sim) -> void:
	if sim.game_over or not sim.incremental:
		return
	var rival = sim.rival_colony
	if rival.battle_active:
		rival.update()
		if rival.battle_won:
			_advance_season(sim)
		return
	if sim.season_index >= SEASON_COUNT:
		return  # ya se ganaron las 4 (no debería tickear más, game_over ya quedó en true)
	var cfg: SimConfig = sim.cfg
	if _day_in_season(sim) >= cfg.season_length_days - 1:
		var ant_count: int = cfg.rival_wave_base_ants + sim.season_index * cfg.rival_wave_ants_growth
		var strength: float = 1.0 + cfg.rival_queen_strength_growth * sim.season_index
		rival.start_battle(ant_count, strength)
		sim.notify("¡La colonia rival de %s ataca!" % SEASON_NAMES[sim.season_index])


## Día de simulación (1-based, `Simulation.day_number()`) dentro de la estación actual, 0-based.
static func _day_in_season(sim) -> int:
	var cfg: SimConfig = sim.cfg
	var day: int = sim.day_number()
	return (day - 1) % cfg.season_length_days


static func _advance_season(sim) -> void:
	sim.season_index += 1
	if sim.season_index >= SEASON_COUNT:
		sim.game_over = true
		sim.victory = true
		sim.game_over_reason = "Derrotaste a las 4 colonias rivales."
	else:
		sim.notify("Llegó %s." % SEASON_NAMES[sim.season_index])
