class_name Upgrades
extends RefCounted
## Fase 9: mejoras de la colonia del modo incremental, compradas con comida (mismo patrón de
## costo creciente que `IncrementalEconomy.buy_egg`). Cada nivel sube un multiplicador del bando
## del jugador (daño, vida, velocidad de movimiento, velocidad de trabajo al cavar) — progresivas
## de verdad: afectan a TODA la colonia, no solo a las hormigas que nazcan después de comprar.
## Daño/velocidad/trabajo ya eran así desde la Fase 9 sin querer: `AntSystem`/`AntCasteAI` leen
## `damage_mult`/`speed_mult`/`work_mult` en vivo cada vez que una hormiga ataca, camina o cava, no
## los fijan una sola vez al nacer. Vida era la única excepción (`hp[i] *= hp_mult` solo en
## `add_ant_at`, Fase 13: se corrigió con `AntSystem.apply_hp_upgrade()`, que escala la vida de
## toda hormiga viva del bando del jugador proporcional al cambio de multiplicador cuando se
## compra un nivel — una hormiga a la mitad de vida sigue a la mitad de vida en el nuevo máximo,
## no se cura de golpe).
##
## Población máxima quedó deliberadamente fuera de esta primera entrega: el modo incremental no
## tiene techo de población hoy, e inventar uno nuevo solo para "mejorarlo" después sería una
## restricción nueva no pedida, con riesgo real de cambiar el balance ya probado (ver
## `tools/test_phase3.gd`).

enum Stat { DAMAGE, HP, SPEED, WORK }
const STAT_NAMES: Array[String] = ["Daño", "Vida", "Velocidad", "Trabajo"]
const STAT_COUNT := 4

var sim: Simulation
var levels: Array[int] = [0, 0, 0, 0]
var damage_mult := 1.0
var hp_mult := 1.0
var speed_mult := 1.0
var work_mult := 1.0


func _init(s: Simulation) -> void:
	sim = s


func cost(stat: int) -> float:
	return roundf(sim.cfg.inc_upgrade_base_cost * pow(sim.cfg.inc_upgrade_cost_growth, levels[stat]))


func can_buy(stat: int) -> bool:
	return sim.incremental and sim.colony.food >= cost(stat)


## Devuelve si pudo comprar (sin comida suficiente, no hace nada).
func buy(stat: int) -> bool:
	if not can_buy(stat):
		return false
	sim.colony.food -= cost(stat)
	levels[stat] += 1
	var cfg := sim.cfg
	match stat:
		Stat.DAMAGE:
			damage_mult += cfg.inc_upgrade_damage_step
		Stat.HP:
			var old_mult := hp_mult
			hp_mult += cfg.inc_upgrade_hp_step
			sim.ants.apply_hp_upgrade(hp_mult / old_mult)
		Stat.SPEED:
			speed_mult += cfg.inc_upgrade_speed_step
		Stat.WORK:
			work_mult += cfg.inc_upgrade_work_step
	return true
