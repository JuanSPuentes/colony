class_name Colony
extends RefCounted
## Economía de la colonia (Fase 1): hojas -> hongo (comida) en el Jardín de hongos, agua de
## charcos, consumo por casta y puesta de huevos de la reina.
##
## Simplificación deliberada: el daño por hambre/sed NO afecta a la Obrera, para que el
## comportamiento de la Fase 0 (donde todas las hormigas son obreras) no cambie en absoluto.
## Reina, nodrizas y soldados sí sufren si la colonia pasa hambre.

var cfg: SimConfig
var food := 0.0
var water := 0.0
var food_cap := 0.0
var water_cap := 0.0
var food_trend := 0.0  # unidades por minuto, para el HUD
var water_trend := 0.0
var egg_cooldown := 0.0
var target_pct := {}
var starving := false
var thirsty := false

var _last_food := 0.0
var _last_water := 0.0
var _trend_timer := 0.0


func _init(c: SimConfig) -> void:
	cfg = c
	food = cfg.start_food
	water = cfg.start_water
	_last_food = food
	_last_water = water
	target_pct = {
		CasteDefs.Caste.WORKER: 0.7,
		CasteDefs.Caste.NURSE: 0.15,
		CasteDefs.Caste.SOLDIER: 0.15,
	}


## Mueve el objetivo de una casta (positivo o negativo) y renormaliza para que sumen 1.0.
func nudge_target(caste: int, amount: float) -> void:
	if not target_pct.has(caste):
		return
	target_pct[caste] = clampf(target_pct[caste] + amount, 0.05, 0.9)
	var total := 0.0
	for k in target_pct:
		total += target_pct[k]
	for k in target_pct:
		target_pct[k] /= total


## Casta (obrera/nodriza/soldado) cuyo porcentaje actual está más por debajo de su objetivo.
func furthest_from_target(sim: Simulation) -> int:
	var counts := {CasteDefs.Caste.WORKER: 0, CasteDefs.Caste.NURSE: 0, CasteDefs.Caste.SOLDIER: 0}
	var total := 0
	var ants := sim.ants
	for i in ants.count:
		if ants.alive[i] == 1 and ants.caste[i] != CasteDefs.Caste.QUEEN:
			counts[ants.caste[i]] += 1
			total += 1
	if total == 0:
		return CasteDefs.Caste.WORKER
	var best: int = CasteDefs.Caste.WORKER
	var best_gap := -INF
	for k in counts:
		var gap: float = target_pct[k] - float(counts[k]) / float(total)
		if gap > best_gap:
			best_gap = gap
			best = k
	return best


func tick(sim: Simulation, dt: float) -> void:
	var rooms := sim.rooms
	food_cap = cfg.base_food_cap + rooms.capacity(WorldGrid.Room.STORAGE, cfg.storage_food_per_cell)
	water_cap = cfg.base_water_cap + rooms.capacity(WorldGrid.Room.STORAGE, cfg.storage_water_per_cell)
	# Jardín de hongos: convierte hojas almacenadas en comida (limitado por hojas, tope y ritmo).
	var fungus_rate := rooms.capacity(WorldGrid.Room.FUNGUS, cfg.fungus_rate_per_cell)
	var convert := minf(fungus_rate * dt, float(sim.leaves_stored))
	convert = minf(convert, maxf(food_cap - food, 0.0))
	if convert > 0.0:
		sim.leaves_stored -= int(ceil(convert))
		food = minf(food_cap, food + convert)
	# Agua: entra despacio mientras haya charcos tras la lluvia (simplificación de la Fase 1;
	# no hay una tarea dedicada de "traer agua").
	var gain := cfg.water_regen_wet if sim.water.volume > 0.0 else cfg.water_regen_dry
	water = minf(water_cap, water + gain * dt)
	# Consumo por casta.
	var consumed_food := 0.0
	var consumed_water := 0.0
	var ants := sim.ants
	for i in ants.count:
		if ants.alive[i] == 0:
			continue
		consumed_food += CasteDefs.FOOD_PER_S[ants.caste[i]] * dt
		consumed_water += CasteDefs.WATER_PER_S[ants.caste[i]] * dt
	food = maxf(0.0, food - consumed_food)
	water = maxf(0.0, water - consumed_water)
	starving = food <= 0.0
	thirsty = water <= 0.0
	if starving or thirsty:
		for i in ants.count:
			if ants.alive[i] == 1 and ants.caste[i] != CasteDefs.Caste.WORKER:
				ants.hp[i] -= cfg.hunger_damage_per_s * dt
				if ants.hp[i] <= 0.0:
					ants._kill(i, false)
	# Puesta de huevos: solo si hay una Real válida y comida suficiente.
	egg_cooldown -= dt
	if egg_cooldown <= 0.0 and sim.queen_id >= 0 and ants.alive[sim.queen_id] == 1 \
			and rooms.valid[WorldGrid.Room.ROYAL] and food >= cfg.egg_food_threshold:
		food -= cfg.egg_lay_cost
		sim.brood.lay_egg(furthest_from_target(sim))
		egg_cooldown = cfg.egg_interval_s
	_trend_timer += dt
	if _trend_timer >= 5.0:
		food_trend = (food - _last_food) / _trend_timer * 60.0
		water_trend = (water - _last_water) / _trend_timer * 60.0
		_last_food = food
		_last_water = water
		_trend_timer = 0.0
