class_name DayNight
extends RefCounted
## Ciclo de día y noche (Fase 3). No guarda estado: todo se deduce del tiempo de simulación, así
## que no hay nada que guardar/cargar y no puede desincronizarse. El ciclo arranca al amanecer;
## un día de luz seguido de una noche cuenta como 1 día (Día 1, Día 2, ...).

## Fracción del ciclo que dura la transición de oscuridad a luz plena en `light()` (también se usa
## al atardecer). `Simulation.spawn_incremental_start()` adelanta el reloj este mismo tramo para
## que la partida arranque ya a pleno día en vez de a mitad de un amanecer que empieza casi negro.
const FADE := 0.06


## Posición dentro del ciclo actual, de 0 (amanecer) a 1 (fin de la noche).
static func phase(time_s: float, cfg: SimConfig) -> float:
	return fposmod(time_s, cfg.day_length_s) / cfg.day_length_s


static func day_number(time_s: float, cfg: SimConfig) -> int:
	return int(time_s / cfg.day_length_s) + 1


static func is_night(time_s: float, cfg: SimConfig) -> bool:
	return phase(time_s, cfg) >= 1.0 - cfg.night_fraction


## Segundos hasta el próximo cambio (anochecer si es de día, amanecer si es de noche).
static func seconds_to_change(time_s: float, cfg: SimConfig) -> float:
	var p := phase(time_s, cfg)
	var dusk := 1.0 - cfg.night_fraction
	var to := dusk - p if p < dusk else 1.0 - p
	return to * cfg.day_length_s


## Luz de 0 (noche cerrada) a 1 (pleno día), con transiciones suaves en el amanecer y el atardecer.
## Solo la usa la vista; la simulación se guía por `is_night`.
static func light(time_s: float, cfg: SimConfig) -> float:
	var p := phase(time_s, cfg)
	var dusk := 1.0 - cfg.night_fraction
	if p < FADE:
		return smoothstep(0.0, FADE, p)
	if p < dusk - FADE:
		return 1.0
	if p < dusk:
		return 1.0 - smoothstep(dusk - FADE, dusk, p)
	return 0.0
