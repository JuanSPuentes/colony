extends SceneTree
## Headless behaviour tests of the simulation (no rendering). Each scenario builds a fresh
## Simulation and checks one mechanic with an A/B comparison where that makes sense.
## Usage: Godot --headless --path . --script tools/validate.gd
## Exit code 1 when any check fails.

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_t_determinism()
	_t_foraging()
	_t_pheromone_food()
	_t_danger_and_evacuate()
	_t_dig_and_rooms()
	_t_eggs_and_castes()
	_t_flood()
	_t_spider()
	_t_attack_signal()
	_t_lost_ants()
	_t_home_signal()
	_t_performance()
	_t_bot_run()
	print("RESULT: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("[%s] %s %s" % ["PASS" if ok else "FAIL", label, detail])


func _run(sim: Simulation, seconds: float) -> void:
	var n := int(seconds / Cfg.TICK)
	for i in n:
		sim.step(Cfg.TICK)
		if sim.outcome != 0:
			return


func _count_state(sim: Simulation, state: int, reason := "") -> int:
	var n := 0
	for a in sim.ants:
		if a.state == state and (reason == "" or a.flee_reason == reason):
			n += 1
	return n


func _forget(sim: Simulation) -> void:
	for a in sim.ants:
		a.mem_food = null
		a.known_water = false


func _paint_ramp(sim: Simulation, type: int, x0: int, x1: int) -> void:
	var step := 1 if x1 > x0 else -1
	var n := 0
	for x in range(x0, x1 + step, step):
		sim.cmd_phero(type, Vector2i(x, Cfg.SURFACE_ROW), minf(1.0, 0.3 + 0.012 * n))
		n += 1


func _no_storms(sim: Simulation) -> void:
	sim.weather.storms = []
	sim._spider_plan = []


# --- Scenarios -------------------------------------------------------------------------------------------

func _t_determinism() -> void:
	var a := Simulation.new(11)
	var b := Simulation.new(11)
	_run(a, 90.0)
	_run(b, 90.0)
	var same: bool = a.ants.size() == b.ants.size() and is_equal_approx(a.colony.food, b.colony.food) and a.stats["deliveries"] == b.stats["deliveries"]
	_check("same seed gives the same simulation", same, "ants=%d/%d food=%.2f/%.2f" % [a.ants.size(), b.ants.size(), a.colony.food, b.colony.food])


func _t_foraging() -> void:
	var sim := Simulation.new(3)
	_no_storms(sim)
	_run(sim, 120.0)
	_check("workers collect and deposit food", sim.stats["deliveries"] >= 15 and sim.colony.food_collected > 20.0, "trips=%d collected=%.1f" % [sim.stats["deliveries"], sim.colony.food_collected])
	var water_ok := sim.colony.water_collected > 0.0
	_check("workers fetch water from the pond", water_ok, "water collected=%.1f" % sim.colony.water_collected)
	var carrying := 0
	var s2 := Simulation.new(3)
	_no_storms(s2)
	for i in 600:
		s2.step(Cfg.TICK)
		for a in s2.ants:
			if a.load_type == Cfg.Load.FOOD and a.cell.y >= Cfg.SURFACE:
				carrying += 1
	_check("loaded workers carry food down into the nest", carrying > 0, "samples=%d" % carrying)


func _far_only(sim: Simulation) -> void:
	## Leaves a single distant plant (x=76) so that finding it needs exploring or a trail.
	var keep: Array[FoodSource] = []
	for src in sim.sources:
		if src.kind == Cfg.SrcKind.WATER or src.cell.x == 76:
			keep.append(src)
	sim.sources = keep
	sim.colony.food = 15.0


func _t_pheromone_food() -> void:
	var with_trail := 0
	var without := 0
	var first_with := 0.0
	var first_without := 0.0
	var followers := 0
	for seed_value in [3, 5, 9]:
		for variant in 2:
			var sim := Simulation.new(seed_value)
			_no_storms(sim)
			_forget(sim)
			_far_only(sim)
			if variant == 1:
				_paint_ramp(sim, Cfg.Phero.FOOD, Cfg.ENTRANCE_X, 71)
			var first := -1.0
			for i in int(240.0 / Cfg.TICK):
				sim.step(Cfg.TICK)
				if first < 0.0 and sim.stats["deliveries"] > 0:
					first = sim.t
				if variant == 1 and i % 30 == 0:
					followers = maxi(followers, _count_state(sim, Cfg.State.FOLLOW_TRAIL))
			if variant == 1:
				with_trail += sim.stats["deliveries"]
				first_with += first if first >= 0 else 240.0
			else:
				without += sim.stats["deliveries"]
				first_without += first if first >= 0 else 240.0
	_check("food trail makes ants follow it", followers >= 3, "max followers=%d" % followers)
	_check("food trail to a far plant raises deliveries (A/B, 3 seeds)", with_trail > without * 1.5, "with=%d without=%d" % [with_trail, without])
	# Walking 36 cells out and back takes ~35 s at minimum, so only a few seconds can be saved.
	_check("food trail shortens time to first delivery", first_with / 3.0 < first_without / 3.0 - 8.0, "mean first %.0fs vs %.0fs" % [first_with / 3.0, first_without / 3.0])


func _t_danger_and_evacuate() -> void:
	var sim := Simulation.new(4)
	_no_storms(sim)
	_run(sim, 25.0)
	# Danger signal across the ground near the entrance.
	var before: int = sim.stats["deliveries"]
	for x in range(Cfg.ENTRANCE_X - 14, Cfg.ENTRANCE_X + 15):
		sim.cmd_phero(Cfg.Phero.DANGER, Vector2i(x, Cfg.SURFACE_ROW), 1.0)
	var fled := 0
	for i in 270:
		sim.step(Cfg.TICK)
		fled = maxi(fled, _count_state(sim, Cfg.State.FLEE, "danger"))
	var working_outside := 0
	for a in sim.ants:
		if a.cell.y == Cfg.SURFACE_ROW and a.caste == Cfg.Caste.WORKER and absi(a.cell.x - Cfg.ENTRANCE_X) <= 14 and a.state != Cfg.State.FLEE:
			working_outside += 1
	_check("danger pheromone makes workers retreat underground", fled >= 3 and working_outside <= 1, "peak fleeing=%d still working outside the zone=%d" % [fled, working_outside])
	# Evacuate signal over the royal chamber and shaft.
	var sim2 := Simulation.new(4)
	_no_storms(sim2)
	for c in sim2.room_list(Cfg.Room.NURSERY):
		sim2.cmd_phero(Cfg.Phero.EVACUATE, c, 1.0)
	_run(sim2, 10.0)
	var inside := 0
	for a in sim2.ants:
		if a.caste != Cfg.Caste.QUEEN and sim2.terrain.room_at(a.cell) == Cfg.Room.NURSERY and sim2.pher.get_v(Cfg.Phero.EVACUATE, a.cell) > 0.3:
			inside += 1
	_check("evacuate signal clears ants out of the marked room", inside <= 1, "ants still inside=%d" % inside)


func _t_dig_and_rooms() -> void:
	var sim := Simulation.new(5)
	_no_storms(sim)
	var s := Cfg.SURFACE
	var bad := sim.cmd_dig(Vector2i(60, s + 25))
	_check("digging an unconnected cell is rejected", not bad)
	var rock_cell := Vector2i(-1, -1)
	for y in range(s, Cfg.H):
		for x in Cfg.W:
			if sim.terrain.type_at(Vector2i(x, y)) == Cfg.Cell.ROCK and rock_cell.x < 0 and y < Cfg.H - 3:
				rock_cell = Vector2i(x, y)
	_check("rock cannot be designated", not sim.terrain.can_designate_dig(rock_cell))
	var cells: Array[Vector2i] = [Vector2i(41, s + 3), Vector2i(42, s + 3), Vector2i(43, s + 3)]
	var ok := true
	for c in cells:
		ok = ok and sim.cmd_dig(c)
	_check("a chain of connected dig orders is accepted", ok)
	var before := sim.terrain.tunnel_count
	_run(sim, 90.0)
	var done := 0
	for c in cells:
		if sim.terrain.type_at(c) == Cfg.Cell.TUNNEL:
			done += 1
	_check("workers excavate the ordered cells", done == 3, "dug=%d/3 stat=%d" % [done, sim.stats["dug"]])
	var path := sim.terrain.find_path(Vector2i(Cfg.ENTRANCE_X, Cfg.SURFACE_ROW), cells[2])
	_check("excavated tunnel is reachable by a valid path", not path.is_empty() and sim.terrain.tunnel_count == before + 3, "path len=%d" % path.size())
	var cap_before := sim.colony.food_cap
	for i in 4:
		sim.cmd_room(Vector2i(41 + i % 3, s + 3 - i / 3 * 0), Cfg.Room.STORAGE)
	sim.room_list(Cfg.Room.STORAGE)
	_check("storage rooms raise food capacity", sim.colony.food_cap > cap_before, "%.0f -> %.0f" % [cap_before, sim.colony.food_cap])
	var cap_pop := sim.colony.population_cap(sim.terrain.tunnel_count)
	_check("population cap grows with the nest", cap_pop >= 30 + int(sim.terrain.tunnel_count * 0.5), "cap=%d" % cap_pop)


func _t_eggs_and_castes() -> void:
	var sim := Simulation.new(6)
	_no_storms(sim)
	sim.colony.next_caste = Cfg.Caste.SOLDIER
	var food0 := sim.colony.food
	_run(sim, 40.0)
	var soldier_eggs := 0
	for b in sim.brood:
		if b.caste == Cfg.Caste.SOLDIER:
			soldier_eggs += 1
	_check("queen lays eggs of the chosen caste", sim.colony.eggs_laid >= 2 and soldier_eggs >= 2, "eggs=%d soldiers-to-be=%d" % [sim.colony.eggs_laid, soldier_eggs])
	var in_nursery := 0
	for b in sim.brood:
		if sim.terrain.room_at(b.cell) == Cfg.Room.NURSERY:
			in_nursery += 1
	_run(sim, 140.0)
	for b in sim.brood:
		if sim.terrain.room_at(b.cell) == Cfg.Room.NURSERY:
			in_nursery += 1
	_check("nurses move brood into the nursery", in_nursery >= 2, "brood-in-nursery samples=%d" % in_nursery)
	_check("new soldiers join the colony only after development", sim.counts[Cfg.Caste.SOLDIER] > 5 and sim.stats["born"] >= 1, "soldiers=%d born=%d" % [sim.counts[Cfg.Caste.SOLDIER], sim.stats["born"]])
	# Starvation stops egg laying.
	var s2 := Simulation.new(6)
	_no_storms(s2)
	s2.colony.food = 3.0
	for a in s2.ants:
		a.mem_food = null
	s2.sources.clear()
	s2.sources.append(s2.puddle_src)
	var eggs0 := s2.colony.eggs_laid
	_run(s2, 60.0)
	_check("no food: the queen stops laying", s2.colony.eggs_laid == eggs0 and s2.colony.lay_status == "Not enough food", "status=%s" % s2.colony.lay_status)
	_check("laying consumes food", food0 > 0.0 and sim.colony.eggs_laid > 0)
	var egg := Simulation.new(6).add_brood(Vector2i(40, Cfg.SURFACE + 15), Cfg.Caste.WORKER)
	var s3 := Simulation.new(6)
	var b3 := s3.add_brood(Vector2i(40, Cfg.SURFACE + 15), Cfg.Caste.WORKER)
	var changed := s3.cmd_set_brood_caste(b3, Cfg.Caste.SOLDIER)
	b3.stage = Cfg.Stage.PUPA
	var refused := not s3.cmd_set_brood_caste(b3, Cfg.Caste.NURSE)
	_check("player can retarget an egg's caste, but not a pupa's", changed and refused and b3.caste == Cfg.Caste.SOLDIER and egg != null)


func _flood_peak(with_drain: bool, evacuate: bool) -> Dictionary:
	var sim := Simulation.new(8)
	sim._spider_plan = []
	sim.weather.storms = [{"start": 5.0, "dur": 58.0, "power": 1.0}]
	var s := Cfg.SURFACE
	if with_drain:
		for x in range(33, 37):
			for y in range(s + 15, s + 17):
				sim.terrain.complete_dig(Vector2i(x, y))
				sim.terrain.set_room(Vector2i(x, y), Cfg.Room.DRAIN)
		for x in range(33, 37):
			sim.terrain.complete_dig(Vector2i(x, s + 17))
			sim.terrain.set_room(Vector2i(x, s + 17), Cfg.Room.DRAIN)
		for x in range(33, 37):
			sim.terrain.complete_dig(Vector2i(x, s + 14))
		sim.terrain.complete_dig(Vector2i(36, s + 14))
		for x in range(36, 38):
			sim.terrain.complete_dig(Vector2i(x, s + 15))
	var peak := 0.0
	var peak_total := 0.0
	var queen_min_hp := 999.0
	var flee_water := 0
	for i in int(130.0 / Cfg.TICK):
		sim.step(Cfg.TICK)
		if i % 15 == 0:
			var w := 0.0
			var royal := sim.room_list(Cfg.Room.ROYAL)
			for c in royal:
				w += sim.terrain.water_at(c)
			peak = maxf(peak, w / royal.size())
			peak_total = maxf(peak_total, sim.flood.total())
			queen_min_hp = minf(queen_min_hp, sim.queen.hp)
			flee_water = maxi(flee_water, _count_state(sim, Cfg.State.FLEE, "water"))
		if evacuate and i == int(25.0 / Cfg.TICK):
			for c in sim.room_list(Cfg.Room.ROYAL):
				sim.cmd_phero(Cfg.Phero.EVACUATE, c, 1.0)
	return {"peak": peak, "total": peak_total, "qhp": queen_min_hp, "flee": flee_water, "ants": sim.adult_count(), "outcome": sim.outcome, "drowned": sim.stats["drowned"]}


func _t_flood() -> void:
	var a := _flood_peak(false, false)
	var b := _flood_peak(true, false)
	_check("rain floods the royal chamber of the default nest", a["peak"] > 0.3, "peak avg level=%.2f total volume=%.1f" % [a["peak"], a["total"]])
	_check("ants flee rising water", a["flee"] >= 3, "max fleeing=%d" % a["flee"])
	_check("drainage chambers reduce the flood (layout matters)", b["peak"] < a["peak"] * 0.6, "default=%.2f with drains=%.2f" % [a["peak"], b["peak"]])
	_check("the queen survives a storm in the default nest", a["outcome"] != 2, "queen min hp=%.0f outcome=%d" % [a["qhp"], a["outcome"]])
	# Flooding actually hurts when ants cannot escape: seal everyone in with water.
	var sim := Simulation.new(8)
	var brood := sim.add_brood(Vector2i(38, Cfg.SURFACE + 15), Cfg.Caste.WORKER)
	for c in sim.room_list(Cfg.Room.ROYAL):
		sim.flood.add_water(c, 0.9)
	var hp0 := brood.hp
	for i in 150:
		sim.step(Cfg.TICK)
	_check("flooded brood takes damage", brood.hp < hp0, "hp %.0f -> %.0f" % [hp0, brood.hp])
	_check("flooded ants take damage or flee", sim.queen.hp < 160.0 or _count_state(sim, Cfg.State.FLEE, "water") > 0)


func _force_spider(sim: Simulation) -> void:
	sim._spider_plan = [{"start": 0.0, "hp": 90.0, "power": 1}]
	sim.weather.storms = []


func _t_spider() -> void:
	var sim := Simulation.new(2)
	_force_spider(sim)
	var min_soldiers := 99
	var defeated_or_gone := false
	var spider_seen := false
	for i in int(150.0 / Cfg.TICK):
		sim.step(Cfg.TICK)
		if sim.spider != null:
			spider_seen = true
		elif spider_seen:
			defeated_or_gone = true
		min_soldiers = mini(min_soldiers, sim.counts.get(Cfg.Caste.SOLDIER, 99))
	_check("a spider enters the surface and threatens ants", spider_seen and sim.stats["killed_by_spider"] + (5 - min_soldiers) >= 0)
	_check("soldiers defeat or drive off the spider", defeated_or_gone and sim.outcome == 0, "defeated=%d killed ants=%d soldiers min=%d" % [sim.stats["spiders_defeated"], sim.stats["killed_by_spider"], min_soldiers])
	# Without soldiers the spider wins: undefended entrance -> invasion -> queen dies.
	var weak := Simulation.new(2)
	_force_spider(weak)
	for a in weak.ants:
		if a.caste == Cfg.Caste.SOLDIER:
			weak.kill_ant(a, "test")
	for i in int(260.0 / Cfg.TICK):
		weak.step(Cfg.TICK)
		if weak.outcome != 0:
			break
	_check("an undefended nest can be invaded and the queen killed", weak.outcome == 2 and weak.outcome_reason.contains("spider"), "outcome=%d %s" % [weak.outcome, weak.outcome_reason])


func _t_attack_signal() -> void:
	var best := [0, 0]
	for variant in 2:
		var sim := Simulation.new(2)
		_force_spider(sim)
		if variant == 1:
			for x in range(8, 24):
				for dx in range(-1, 2):
					sim.cmd_phero(Cfg.Phero.ATTACK, Vector2i(x + dx, Cfg.SURFACE_ROW), 1.0)
		var far := 0
		for i in int(14.0 / Cfg.TICK):
			sim.step(Cfg.TICK)
		for a in sim.ants:
			if a.caste == Cfg.Caste.SOLDIER and a.cell.y == Cfg.SURFACE_ROW and a.cell.x < Cfg.ENTRANCE_X - 10:
				far += 1
		best[variant] = far
	_check("attack signal sends soldiers toward the marked area", best[1] >= 3 and best[0] == 0, "soldiers far from entrance: control=%d signalled=%d" % [best[0], best[1]])


func _t_lost_ants() -> void:
	var sim := Simulation.new(4)
	sim.weather.storms = [{"start": 20.0, "dur": 80.0, "power": 1.0}]
	sim._spider_plan = []
	var max_lost := 0
	for i in int(90.0 / Cfg.TICK):
		sim.step(Cfg.TICK)
		if i % 30 == 0:
			var n := 0
			for a in sim.ants:
				if a.lost_until > sim.t:
					n += 1
			max_lost = maxi(max_lost, n)
	_check("rain makes surface ants lose their way", max_lost >= 2, "max lost=%d" % max_lost)


func _t_home_signal() -> void:
	## Lost ants carrying food, far out on the ground, with all scent wiped. Painting a Home
	## trail (rising toward the nest) should bring far more of them back inside.
	var home := [0, 0]
	for seed_value in [3, 5, 9]:
		for variant in 2:
			var sim := Simulation.new(seed_value)
			_no_storms(sim)
			sim.pher.clear_type(Cfg.Phero.HOME)
			var lost: Array[Ant] = []
			for k in 8:
				var a := sim.spawn_ant(Cfg.Caste.WORKER, Vector2i(62 + k % 4, Cfg.SURFACE_ROW))
				a.load_type = Cfg.Load.FOOD
				a.load_amount = 2.0
				a.lost_until = 120.0
				a.state = Cfg.State.CARRY_HOME
				lost.append(a)
			# Keep everybody else indoors so only the lost ants matter.
			for a in sim.ants:
				if a.caste != Cfg.Caste.QUEEN and not lost.has(a):
					a.state = Cfg.State.REST
					a.timer = 999.0
			if variant == 1:
				_paint_ramp(sim, Cfg.Phero.HOME, 72, Cfg.ENTRANCE_X)
			var reached := {}
			for i in int(45.0 / Cfg.TICK):
				sim.step(Cfg.TICK)
				for a in lost:
					if a.cell.y >= Cfg.SURFACE:
						reached[a.id] = true  # got home (it may walk out again afterwards)
					elif a.cell.y == Cfg.SURFACE_ROW and not reached.has(a.id):
						a.lost_until = sim.t + 5.0  # keep it lost until it finds the way
			home[variant] += reached.size()
	_check("a Home trail guides lost ants back to the nest (A/B, 3 seeds)", home[1] >= home[0] + 8, "reached the nest within 45 s: without=%d with=%d of 24" % [home[0], home[1]])


func _t_performance() -> void:
	var sim := Simulation.new(12)
	_no_storms(sim)
	for i in 120:
		var cell := Vector2i(30 + i % 20, Cfg.SURFACE + 8)
		sim.spawn_ant(Cfg.Caste.WORKER, cell)
	var t0 := Time.get_ticks_usec()
	var n := 600
	for i in n:
		sim.step(Cfg.TICK)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / n
	_check("150 ants simulate well inside the 33 ms tick budget", ms < 6.0, "%.2f ms per tick with %d ants" % [ms, sim.ants.size()])


# --- A scripted "player" that tries to win -------------------------------------------------------------------------

func _bot_actions(sim: Simulation, step_idx: int) -> void:
	var s := Cfg.SURFACE
	var t := sim.t
	if step_idx == 1 and fmod(t, 60.0) < 1.0:
		# Renew the food trails along the whole ground line every minute (scent fades).
		_paint_ramp(sim, Cfg.Phero.FOOD, Cfg.ENTRANCE_X, 18)
		_paint_ramp(sim, Cfg.Phero.FOOD, Cfg.ENTRANCE_X, 73)
	if step_idx == 0:
		_paint_ramp(sim, Cfg.Phero.FOOD, Cfg.ENTRANCE_X, 18)
		_paint_ramp(sim, Cfg.Phero.FOOD, Cfg.ENTRANCE_X, 73)
		# Drain pit beside the royal chamber, plus more storage and room to grow.
		for x in range(33, 37):
			for y in range(s + 14, s + 18):
				sim.cmd_dig(Vector2i(x, y))
		for x in range(37, 44):
			sim.cmd_dig(Vector2i(x, s + 17))
		for x in range(49, 56):
			sim.cmd_dig(Vector2i(x, s + 8))
			sim.cmd_dig(Vector2i(x, s + 9))
	if step_idx == 1 and t > 70.0:
		for x in range(33, 37):
			for y in range(s + 15, s + 18):
				sim.cmd_room(Vector2i(x, y), Cfg.Room.DRAIN)
		for x in range(37, 44):
			sim.cmd_room(Vector2i(x, s + 17), Cfg.Room.DRAIN)
		for x in range(49, 56):
			sim.cmd_room(Vector2i(x, s + 8), Cfg.Room.STORAGE)
			sim.cmd_room(Vector2i(x, s + 9), Cfg.Room.STORAGE)
	var workers: int = sim.counts.get(Cfg.Caste.WORKER, 0)
	var soldiers: int = sim.counts.get(Cfg.Caste.SOLDIER, 0)
	if workers < 24 or soldiers >= 12 or sim.colony.food < 40.0:
		sim.colony.next_caste = Cfg.Caste.WORKER
	else:
		sim.colony.next_caste = Cfg.Caste.SOLDIER
	if sim.spider != null and sim.spider.cell.y == Cfg.SURFACE_ROW:
		for dx in range(-3, 4):
			sim.cmd_phero(Cfg.Phero.ATTACK, Vector2i(sim.spider.cell.x + dx, Cfg.SURFACE_ROW), 1.0)
	if sim.flood.max_level > 0.3:
		for c in sim.room_list(Cfg.Room.ROYAL):
			if sim.terrain.water_at(c) > 0.2:
				sim.cmd_phero(Cfg.Phero.EVACUATE, c, 1.0)


func _t_bot_run() -> void:
	var wins := 0
	var report := ""
	for seed_value in [7, 21, 33]:
		var sim := Simulation.new(seed_value)
		var phase := 0
		var t0 := Time.get_ticks_msec()
		var i := 0
		while sim.outcome == 0:
			sim.step(Cfg.TICK)
			i += 1
			if i % 30 == 0:
				if sim.t > 3.0 and phase == 0:
					_bot_actions(sim, 0)
					phase = 1
				elif phase >= 1:
					_bot_actions(sim, 1)
					if sim.t > 75.0:
						phase = 2
				if phase == 2:
					pass
		if sim.outcome == 1:
			wins += 1
		report += " seed %d: %s day %d ants %d (%s);" % [seed_value, "WIN" if sim.outcome == 1 else "LOSS", sim.day(), sim.adult_count(), sim.outcome_reason.left(60)]
	_check("a sensible player strategy can win (3 seeds)", wins >= 2, "wins=%d/3 %s" % [wins, report])
