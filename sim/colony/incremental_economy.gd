class_name IncrementalEconomy
extends RefCounted
## Economía del modo incremental (Fase 3). Reemplaza a `Colony.tick` cuando `sim.incremental` es
## true; la Fase 1 (`Colony`) queda intacta y sus pruebas no se enteran de que esto existe.
##
## Todo se mide en COMIDA (la guarda `sim.colony.food`, para que HUD y guardado la sigan leyendo
## del mismo lugar): las hojas que traen las obreras se convierten en comida al llegar al nido,
## las adultas la consumen, y el jugador la gasta en comprar obreras o soldados. Cada compra
## encarece la siguiente de esa casta (precio base × crecimiento^compradas). La auto-compra, si
## está activa, compra sola la casta elegida en cuanto alcanza, dejando una reserva.

enum Auto { OFF, WORKER, SOLDIER }
const AUTO_NAMES: Array[String] = ["apagada", "obreras", "soldados"]

var sim: Simulation
var bought := {CasteDefs.Caste.WORKER: 0, CasteDefs.Caste.SOLDIER: 0}
var auto_mode := Auto.OFF
## Comida que entró por hojas en total (para pruebas y estadísticas).
var food_earned := 0.0
## Plantas de las que la colonia ya sacó alguna hoja (1 = conocida), en el orden de `sim.plants`.
## Las obreras en la superficie van directo a la conocida más cercana que tenga hojas (ver
## `AntSystem._remembered_plant`).
var known_plants := PackedByteArray()

## Para el HUD: comida que entra por hojas y que consume la colonia, por minuto. Se muestran por
## separado porque la tendencia neta mezcla las compras y engaña ("−118 por minuto" al comprar).
var income_per_min := 0.0
var upkeep_per_min := 0.0

var _trend_timer := 0.0
var _last_food := 0.0
var _income_timer := 0.0
var _income_acc := 0.0


func _init(s: Simulation) -> void:
	sim = s
	known_plants.resize(sim.plants.size())


func is_buyable(caste: int) -> bool:
	return bought.has(caste)


func cost(caste: int) -> float:
	var cfg := sim.cfg
	match caste:
		CasteDefs.Caste.WORKER:
			return roundf(cfg.inc_worker_cost * pow(cfg.inc_worker_cost_growth, bought[caste]))
		CasteDefs.Caste.SOLDIER:
			return roundf(cfg.inc_soldier_cost * pow(cfg.inc_soldier_cost_growth, bought[caste]))
	return INF


func can_buy(caste: int) -> bool:
	return is_buyable(caste) and _queen_alive() and sim.colony.food >= cost(caste)


## Paga la comida y la reina pone un huevo de esa casta (la cría hace el resto). Devuelve si pudo.
func buy(caste: int) -> bool:
	if not can_buy(caste):
		return false
	sim.colony.food -= cost(caste)
	bought[caste] += 1
	sim.brood.lay_egg(caste)
	return true


func cycle_auto() -> void:
	auto_mode = ((auto_mode + 1) % Auto.size()) as Auto


func tick(dt: float) -> void:
	var cfg := sim.cfg
	var colony := sim.colony
	colony.food_cap = cfg.base_food_cap + sim.rooms.capacity(WorldGrid.Room.STORAGE, cfg.storage_food_per_cell)
	# Hojas -> comida, en el momento en que llegan al nido.
	if sim.leaves_stored > 0:
		var gain := sim.leaves_stored * cfg.inc_food_per_leaf
		sim.leaves_stored = 0
		food_earned += gain
		_income_acc += gain
		colony.food = minf(colony.food_cap, colony.food + gain)
	# Consumo: solo comida (el agua no es un recurso en este modo).
	var consumed := 0.0
	var ants := sim.ants
	for i in ants.count:
		if ants.alive[i] == 1:
			consumed += CasteDefs.FOOD_PER_S[ants.caste[i]] * dt
	colony.food = maxf(0.0, colony.food - consumed)
	upkeep_per_min = consumed / dt * 60.0
	_income_timer += dt
	if _income_timer >= 20.0:
		income_per_min = _income_acc / _income_timer * 60.0
		_income_acc = 0.0
		_income_timer = 0.0
	colony.starving = colony.food <= 0.0
	colony.thirsty = false
	if colony.starving:
		for i in ants.count:
			if ants.alive[i] == 1 and ants.caste[i] != CasteDefs.Caste.WORKER:
				ants.hp[i] -= cfg.hunger_damage_per_s * dt
				if ants.hp[i] <= 0.0:
					ants._kill(i, false)
	# Auto-compra.
	if auto_mode != Auto.OFF:
		var caste := CasteDefs.Caste.WORKER if auto_mode == Auto.WORKER else CasteDefs.Caste.SOLDIER
		if colony.food >= cost(caste) + cfg.inc_auto_reserve:
			buy(caste)
	_trend_timer += dt
	if _trend_timer >= 5.0:
		colony.food_trend = (colony.food - _last_food) / _trend_timer * 60.0
		_last_food = colony.food
		_trend_timer = 0.0


## Las plantas rebrotan de día, hasta su máximo (si no, el modo incremental se quedaría sin hojas).
func regrow_plants(dt: float) -> void:
	if DayNight.is_night(sim.time_s(), sim.cfg):
		return
	for p in sim.plants:
		if p.leaves >= p.max_leaves:
			continue
		p.regrow_acc += sim.cfg.inc_plant_regrow_per_s * dt
		if p.regrow_acc >= 1.0:
			p.regrow_acc -= 1.0
			p.leaves += 1
			sim.total_leaves_left += 1


func _queen_alive() -> bool:
	return sim.queen_id >= 0 and sim.ants.alive[sim.queen_id] == 1
