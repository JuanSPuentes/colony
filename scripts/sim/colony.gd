class_name Colony
extends RefCounted
## Colony economy: stocks, consumption, egg laying and population limits.

const FOOD_START := 90.0
const WATER_START := 70.0

var food := FOOD_START
var water := WATER_START
var food_cap := 150.0
var water_cap := 120.0
var next_caste := Cfg.Caste.WORKER
var egg_timer := 10.0
var starving_t := 0.0
var thirsty_t := 0.0
var lay_status := "waiting"
var eggs_laid := 0
var food_collected := 0.0
var water_collected := 0.0
var food_hist: Array[float] = []
var water_hist: Array[float] = []
var _hist_t := 0.0
var species: Dictionary

var starving: bool:
	get:
		return food <= 0.01
var thirsty: bool:
	get:
		return water <= 0.01


func _init(species_def: Dictionary) -> void:
	species = species_def


func recompute_caps(storage_cells: int) -> void:
	food_cap = 60.0 + 11.0 * storage_cells
	water_cap = 45.0 + 9.0 * storage_cells
	food = minf(food, food_cap)
	water = minf(water, water_cap)


func food_need() -> float:
	return clampf(1.0 - food / (food_cap * 0.65), 0.12, 1.0)


func water_need() -> float:
	return clampf(1.0 - water / (water_cap * 0.65), 0.0, 1.0)


## Returns the amount actually stored (the rest is lost when storage is full).
func add_food(v: float) -> float:
	var room := maxf(0.0, food_cap - food)
	var got := minf(v, room)
	food += got
	food_collected += got
	return got


func add_water(v: float) -> float:
	var room := maxf(0.0, water_cap - water)
	var got := minf(v, room)
	water += got
	water_collected += got
	return got


func step(dt: float, sim) -> void:
	var counts: Dictionary = sim.counts
	var use_f := 0.0
	var use_w := 0.0
	for caste_id in counts:
		var def: Dictionary = SpeciesDefs.caste(species, caste_id)
		use_f += def["food_use"] * counts[caste_id]
		use_w += def["water_use"] * counts[caste_id]
	food = maxf(0.0, food - use_f * dt)
	water = maxf(0.0, water - use_w * dt)
	starving_t = starving_t + dt if starving else maxf(0.0, starving_t - dt * 2.0)
	thirsty_t = thirsty_t + dt if thirsty else maxf(0.0, thirsty_t - dt * 2.0)
	_hist_t += dt
	if _hist_t >= 5.0:
		_hist_t = 0.0
		food_hist.append(food)
		water_hist.append(water)
		if food_hist.size() > 13:
			food_hist.pop_front()
			water_hist.pop_front()
	egg_timer -= dt
	if egg_timer <= 0.0:
		_try_lay(sim)


## Change of a stock per minute, from the recent history.
func trend(hist: Array[float]) -> float:
	if hist.size() < 2:
		return 0.0
	var span := (hist.size() - 1) * 5.0
	return (hist[hist.size() - 1] - hist[0]) / span * 60.0


func population_cap(tunnel_cells: int) -> int:
	return mini(150, 30 + int(tunnel_cells * 0.5))


func brood_capacity(sim) -> int:
	var n: int = sim.room_list(Cfg.Room.NURSERY).size() + sim.room_list(Cfg.Room.ROYAL).size()
	return maxi(10, n * 2)


func _try_lay(sim) -> void:
	var q: Ant = sim.queen
	var interval: float = species["egg_interval"] * (1.0 + clampf((40.0 - food) / 40.0, 0.0, 1.0) * 1.5)
	if q == null or q.state == Cfg.State.DEAD:
		egg_timer = 5.0
		return
	var reason := ""
	if sim.terrain.room_at(q.cell) != Cfg.Room.ROYAL:
		reason = "Queen is away from the royal chamber"
	elif sim.terrain.water_at(q.cell) > 0.15:
		reason = "Royal chamber is flooded"
	elif q.hp < 40.0:
		reason = "Queen is too weak"
	elif food < 12.0:
		reason = "Not enough food"
	elif water < 6.0:
		reason = "Not enough water"
	elif sim.adult_count() + sim.brood.size() >= population_cap(sim.terrain.tunnel_count):
		reason = "Population limit reached - dig more tunnels"
	elif sim.brood.size() >= brood_capacity(sim):
		reason = "Nursery is full - build a nursery"
	if reason != "":
		lay_status = reason
		egg_timer = 2.0
		return
	food -= species["egg_cost"]
	egg_timer = interval
	eggs_laid += 1
	lay_status = "laying eggs"
	sim.add_brood(q.cell, next_caste)
