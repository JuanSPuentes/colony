class_name Upgrades
extends RefCounted
## Fase 33: árbol de mejoras del jugador (antes, Fase 9-13: cuatro stats con niveles sin tope).
## Tres ramas (Ataque, Defensa, Recolección) de cuatro mejoras; dentro de una rama cada una pide la
## anterior. Se compran con comida y cada compra encarece TODAS las demás
## (`inc_upgrade_cost_growth`), así que especializarse en una rama rinde más que repartir.
##
## Las mejoras son datos (`NODES`): sumar una es agregar una fila y, si su efecto es nuevo, un caso
## en `_apply`. Los efectos son multiplicadores que `AntSystem`/`AntCasteAI`/`IncrementalEconomy`
## leen en vivo, así que afectan a TODA la colonia, no solo a las hormigas que nazcan después
## (la vida se reescala a las vivas con `AntSystem.apply_hp_upgrade`). Solo bando del jugador.

enum Branch { ATTACK, DEFENSE, GATHER }
const BRANCH_NAMES: Array[String] = ["Ataque", "Defensa", "Recolección"]
const TIERS := 4

enum Id {
	MANDIBLES, MARCH, MANDIBLES_2, ROYAL_ASSAULT,
	SHELL, TOUGH_QUEEN, SHELL_2, HEALING,
	DIGGERS, LIGHT_LEGS, KEEN_SCENT, BIG_LOAD,
}
## En el orden de `Id`: rama, nivel (0-3, pide el anterior de la misma rama), nombre, descripción,
## efecto (`_apply`) y cuánto suma.
const NODES: Array[Dictionary] = [
	{"branch": Branch.ATTACK, "tier": 0, "name": "Mandíbulas", "desc": "+25 % de daño.", "effect": "damage", "amount": 0.25},
	{"branch": Branch.ATTACK, "tier": 1, "name": "Marcha", "desc": "+15 % de velocidad de los soldados.", "effect": "soldier_speed", "amount": 0.15},
	{"branch": Branch.ATTACK, "tier": 2, "name": "Mandíbulas II", "desc": "+25 % de daño.", "effect": "damage", "amount": 0.25},
	{"branch": Branch.ATTACK, "tier": 3, "name": "Asalto real", "desc": "Doble daño contra la reina rival.", "effect": "queen_damage", "amount": 1.0},
	{"branch": Branch.DEFENSE, "tier": 0, "name": "Caparazón", "desc": "+25 % de vida.", "effect": "hp", "amount": 0.25},
	{"branch": Branch.DEFENSE, "tier": 1, "name": "Reina robusta", "desc": "+50 % de vida de la reina.", "effect": "queen_hp", "amount": 0.5},
	{"branch": Branch.DEFENSE, "tier": 2, "name": "Caparazón II", "desc": "+25 % de vida.", "effect": "hp", "amount": 0.25},
	{"branch": Branch.DEFENSE, "tier": 3, "name": "Curación", "desc": "Las hormigas dentro del nido recuperan vida.", "effect": "heal", "amount": 1.0},
	{"branch": Branch.GATHER, "tier": 0, "name": "Excavadoras", "desc": "+25 % de velocidad al cavar.", "effect": "work", "amount": 0.25},
	{"branch": Branch.GATHER, "tier": 1, "name": "Patas ligeras", "desc": "+15 % de velocidad de las obreras.", "effect": "worker_speed", "amount": 0.15},
	{"branch": Branch.GATHER, "tier": 2, "name": "Buen olfato", "desc": "Las obreras ven la comida más lejos.", "effect": "sight", "amount": 0.5},
	{"branch": Branch.GATHER, "tier": 3, "name": "Carga grande", "desc": "+50 % de comida por cada viaje.", "effect": "carry", "amount": 0.5},
]

var sim: Simulation
var bought: Array[bool] = []
var bought_count := 0
var damage_mult := 1.0
var hp_mult := 1.0
var work_mult := 1.0
var soldier_speed_mult := 1.0
var worker_speed_mult := 1.0
var queen_hp_mult := 1.0
var queen_damage_mult := 1.0
var sight_mult := 1.0
var carry_mult := 1.0
var nest_heal := false


func _init(s: Simulation) -> void:
	sim = s
	bought.resize(NODES.size())
	bought.fill(false)


func cost(id: int) -> float:
	var cfg := sim.cfg
	return roundf(cfg.inc_upgrade_tier_cost[NODES[id].tier] * pow(cfg.inc_upgrade_cost_growth, bought_count))


## ¿Ya se compró la anterior de su rama? (la primera de cada rama siempre está abierta)
func unlocked(id: int) -> bool:
	return NODES[id].tier == 0 or bought[id - 1]


func can_buy(id: int) -> bool:
	return sim.incremental and not bought[id] and unlocked(id) and sim.colony.food >= cost(id)


## Cuántas se pueden comprar ahora (el botón del HUD y la guía lo avisan).
func available_count() -> int:
	var n := 0
	for id in NODES.size():
		if can_buy(id):
			n += 1
	return n


## Devuelve si pudo comprar (sin comida suficiente o bloqueada, no hace nada).
func buy(id: int) -> bool:
	if not can_buy(id):
		return false
	sim.colony.food -= cost(id)
	var old_hp := hp_mult
	var old_queen_hp := queen_hp_mult
	_apply(id)
	sim.ants.apply_hp_upgrade(hp_mult / old_hp, queen_hp_mult / old_queen_hp)
	return true


## Marca como compradas las mejoras de `list` (cargar partida, mudanza) recalculando los efectos.
## No toca la vida de las hormigas.
func set_bought(list: Array) -> void:
	var fresh := Upgrades.new(sim)
	for id in mini(list.size(), NODES.size()):
		if list[id]:
			fresh._apply(id)
	bought = fresh.bought
	bought_count = fresh.bought_count
	damage_mult = fresh.damage_mult
	hp_mult = fresh.hp_mult
	work_mult = fresh.work_mult
	soldier_speed_mult = fresh.soldier_speed_mult
	worker_speed_mult = fresh.worker_speed_mult
	queen_hp_mult = fresh.queen_hp_mult
	queen_damage_mult = fresh.queen_damage_mult
	sight_mult = fresh.sight_mult
	carry_mult = fresh.carry_mult
	nest_heal = fresh.nest_heal


func _apply(id: int) -> void:
	bought[id] = true
	bought_count += 1
	var a: float = NODES[id].amount
	match NODES[id].effect:
		"damage": damage_mult += a
		"hp": hp_mult += a
		"work": work_mult += a
		"soldier_speed": soldier_speed_mult += a
		"worker_speed": worker_speed_mult += a
		"queen_hp": queen_hp_mult += a
		"queen_damage": queen_damage_mult += a
		"sight": sight_mult += a
		"carry": carry_mult += a
		"heal": nest_heal = true


## Multiplicador de vida de una casta (la reina suma el suyo).
func hp_factor(caste: int) -> float:
	return hp_mult * (queen_hp_mult if caste == CasteDefs.Caste.QUEEN else 1.0)


## Multiplicador de velocidad de una casta.
func speed_factor(caste: int) -> float:
	match caste:
		CasteDefs.Caste.SOLDIER: return soldier_speed_mult
		CasteDefs.Caste.WORKER: return worker_speed_mult
	return 1.0


## Daño por segundo de una casta contra `threat` (la reina rival recibe el de "Asalto real").
func damage(caste: int, threat) -> float:
	var d := CasteDefs.DAMAGE_PER_S[caste] * damage_mult
	return d * queen_damage_mult if threat is RivalQueen else d
