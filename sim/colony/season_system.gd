extends RefCounted
## Fase 9: estaciones del modo incremental. 4 estaciones fijas; al llegar al último día de cada
## una ataca la colonia rival correspondiente (`sim.rival_colony`) y la estación no avanza hasta
## que su reina muera. Fase 31: en "Juego normal" la rival vive en el mapa desde el principio y la
## estación se gana en cuanto muere su reina (el jugador decide cuándo atacar); el último día queda
## como red de seguridad. Derrotar a las 4 es la condición de victoria real de "Juego normal" —
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
	# Fase 31: con la rival en el mapa, crece y manda incursiones todo el tiempo.
	rival.update_home(sim.dt)
	if rival.fighting():
		rival.update()
		if rival.battle_won:
			_advance_season(sim)
			return
		if rival.battle_active:
			return
	elif rival.home and not rival.queen.alive and not rival.battle_won:
		# Su reina murió sin que el jugador pidiera atacar (una patrulla, una incursión rechazada
		# que llegó hasta ella...): igual gana la estación.
		rival.battle_won = true
		_advance_season(sim)
		return
	if sim.season_index >= SEASON_COUNT:
		return  # ya se ganaron las 4 (no debería tickear más, game_over ya quedó en true)
	var cfg: SimConfig = sim.cfg
	if day_in_season(sim) >= season_length(sim) - 1:
		var ant_count: int = cfg.rival_wave_base_ants + sim.season_index * cfg.rival_wave_ants_growth
		var strength: float = 1.0 + cfg.rival_queen_strength_growth * sim.season_index
		rival.start_battle(ant_count, strength)
		sim.notify("¡La colonia rival de %s ataca!", [SEASON_NAMES[sim.season_index]])


## Día dentro de la estación actual, 0-based (negativo: la estación todavía no empezó, ver
## `_advance_season`). Fase 17: se cuenta desde `sim.season_start_day`, no con `(día - 1) % largo`:
## así, ganar la batalla el último día hacía que la estación siguiente arrancara YA en su último día
## (otra oleada y otra reina al instante, "la reina revive"), y una batalla larga le comía días a la
## siguiente (podía durar 3 días en vez de 5).
## Días que dura la estación actual (`cfg.season_days`).
static func season_length(sim) -> int:
	var days: Array[int] = sim.cfg.season_days
	return days[clampi(sim.season_index, 0, days.size() - 1)]


static func day_in_season(sim) -> int:
	return sim.day_number() - sim.season_start_day


static func _advance_season(sim) -> void:
	sim.season_index += 1
	# La estación siguiente empieza mañana y dura sus `season_length(sim)` días completos.
	sim.season_start_day = sim.day_number() + 1
	if sim.season_index >= SEASON_COUNT:
		sim.game_over = true
		sim.victory = true
		sim.game_over_reason = "Derrotaste a las 4 colonias rivales."
	else:
		sim.notify("¡Batalla ganada! %s empieza mañana.", [SEASON_NAMES[sim.season_index]])
		# Fase 25: con el mapa al azar (el que tiene niebla) la colonia se muda a un territorio
		# nuevo; lo hace `main.gd` con `Migration.migrate`. El mapa fijo de las pruebas no se muda.
		if sim.fog != null:
			sim.migration_pending = true
