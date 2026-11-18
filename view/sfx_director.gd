class_name SfxDirector
extends Node
## Fase 45: decide qué suena y cuándo tiembla la pantalla mirando la simulación. Solo lee
## contadores que la simulación ya lleva (celdas cavadas, entregas, huevos, muertes, amenazas…) y
## compara con lo que vio en el cuadro anterior: la simulación no sabe nada de sonido y sigue
## siendo determinística. Sin `Sfx` en el árbol (pruebas) no suena nada, pero el temblor igual se
## pide (lo aplica `main.gd` si está activado en Opciones).

signal shake_requested(strength: float)

const SHAKE_QUEEN_KILL := 6.0
const SHAKE_DEFEAT := 4.0

var sim: Simulation
var _sfx: Sfx
var _seen := {}
var _threat_hp := 0.0
var _rival_queen_alive := false
var _game_over := false


## Con cada simulación nueva (partida nueva, carga, mudanza). Si la estación avanzó, suena la
## victoria de estación.
func setup(s: Simulation) -> void:
	var won_season := sim != null and s.season_index > sim.season_index
	sim = s
	_sfx = Sfx.find(get_tree())
	_seen = _counters()
	_threat_hp = _total_threat_hp()
	_rival_queen_alive = _rival_queen_is_alive()
	_game_over = sim.game_over
	if won_season:
		# La reina rival murió y la mudanza ocurrió en el mismo cuadro: `_process` no llegó a verla.
		_play("season")
		shake_requested.emit(SHAKE_QUEEN_KILL)


func _process(_delta: float) -> void:
	if sim == null:
		return
	var now := _counters()
	for key in now:
		if now[key] > _seen[key]:
			_play(key)
	_seen = now
	var hp := _total_threat_hp()
	if hp < _threat_hp - 0.01:
		_play("hit")
	_threat_hp = hp
	var rq := _rival_queen_is_alive()
	if _rival_queen_alive and not rq:
		_play("queen_kill")
		shake_requested.emit(SHAKE_QUEEN_KILL)
	_rival_queen_alive = rq
	if sim.game_over and not _game_over:
		_play("victory" if sim.victory else "defeat")
		if not sim.victory:
			shake_requested.emit(SHAKE_DEFEAT)
	_game_over = sim.game_over


## Cada contador lleva el nombre del sonido que toca cuando sube.
func _counters() -> Dictionary:
	var rival := sim.rival_colony
	return {
		"dig": sim.dug,
		"deliver": sim.delivered,
		"egg": sim.eggs_bought,
		"hatch": sim.brood.hatched,
		"death": sim.ants.killed[0],
		"enemy_death": sim.ants.killed[1],
		"alarm": sim.ants.alarm_tick,
		"raid": rival.raids_sent if rival != null else 0,
		"threat": sim.spiders_spawned + sim.centipedes_spawned + sim.mantises_spawned,
	}


## Vida sumada de las amenazas grandes vivas: si baja, alguien les pegó.
func _total_threat_hp() -> float:
	var total := 0.0
	for t in [sim.spider, sim.centipede, sim.mantis]:
		if t != null and t.alive:
			total += t.hp
	if _rival_queen_is_alive():
		total += sim.rival_colony.queen.hp
	return total


func _rival_queen_is_alive() -> bool:
	return sim.rival_colony != null and sim.rival_colony.queen.alive


func _play(key: String) -> void:
	if _sfx != null:
		_sfx.play(key)
