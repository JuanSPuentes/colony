extends SceneTree
## Headless run of the pure simulation with a daily report (no rendering, no player input).
## Usage: Godot --headless --path . --script tools/sim_test.gd -- [seed]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value := int(args[0]) if args.size() > 0 else 7
	var sim := Simulation.new(seed_value)
	var steps := 0
	var t0 := Time.get_ticks_msec()
	var next_report := 0.0
	while sim.outcome == 0 and sim.t < Cfg.WIN_DAYS * Cfg.DAY_LENGTH + 5.0:
		sim.step(Cfg.TICK)
		steps += 1
		if sim.t >= next_report:
			next_report += Cfg.DAY_LENGTH / 3.0
			var c := sim.counts
			print("t=%4.0f day %d | ants %3d (W%d N%d S%d) brood %2d | food %5.1f/%3.0f water %5.1f | flood %.2f queenHP %3.0f | rain %.2f spider %s | trips %d" % [
				sim.t, sim.day(), sim.adult_count(), c.get(Cfg.Caste.WORKER, 0), c.get(Cfg.Caste.NURSE, 0), c.get(Cfg.Caste.SOLDIER, 0),
				sim.brood.size(), sim.colony.food, sim.colony.food_cap, sim.colony.water, sim.flood.max_level, sim.queen.hp,
				sim.weather.rain, "yes" if sim.spider != null else "-", sim.stats["deliveries"]])
	var ms := Time.get_ticks_msec() - t0
	print("END outcome=%d (%s) t=%.0f ms/tick=%.3f" % [sim.outcome, sim.outcome_reason, sim.t, float(ms) / steps])
	print("stats=", sim.stats)
	quit()
