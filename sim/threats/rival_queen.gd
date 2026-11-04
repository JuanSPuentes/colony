class_name RivalQueen
extends RefCounted
## Fase 9: objetivo de la batalla de fin de estación contra una colonia rival (ver
## `sim/colony/rival_colony.gd`, `sim/colony/season_system.gd`). Nunca se mueve ni pelea — es la
## reina del bando rival, el equivalente de la reina del jugador pero fuera de `AntSystem` (las
## hormigas rivales sí son entradas normales de `AntSystem`, bando 1; ella no necesita pathing ni
## estados, solo existir como el objetivo que hay que matar para ganar). Misma forma que
## `Spider`/`Centipede`/`Mantis` (`.pos`/`.hp`/`.max_hp`/`.alive`/`.take_damage()`) para que
## `AntSystem._nearest_threat()` la trate igual que cualquier otra amenaza — así toda la colonia
## del jugador la ataca en cuanto la tiene cerca, sin código nuevo de combate.

var sim: Simulation
var pos := Vector2.ZERO
var hp := 0.0
var max_hp := 0.0
var alive := false
## Fase 37: tick del último golpe; mientras sea reciente, sus hormigas acuden (`AntSystem._tick_rival`).
var last_hit_tick := -1


func _init(s: Simulation) -> void:
	sim = s


func spawn(at: Vector2, strength: float) -> void:
	pos = at
	max_hp = sim.cfg.rival_queen_hp_base * strength
	hp = max_hp
	alive = true


## Fase 37: ¿la atacaron hace poco (`cfg.rival_defend_s`)?
func under_attack() -> bool:
	return alive and last_hit_tick >= 0 and sim.tick_count - last_hit_tick <= int(sim.cfg.rival_defend_s * sim.cfg.tick_rate)


func take_damage(amount: float) -> void:
	if not alive:
		return
	hp -= amount
	last_hit_tick = sim.tick_count
	if hp <= 0.0:
		alive = false
		sim.spawn_corpse(pos, sim.cfg.corpse_food_value)
		sim.reward_kill(sim.cfg.kill_food_rival_queen)
