extends SceneTree
func _initialize() -> void:
	var cfg := SimConfig.new()
	cfg.initial_ants = 0
	cfg.rain_auto = false
	var sim := Simulation.new(cfg)
	sim.cmd_force_rain()
	var sy := cfg.surface_y
	for i in 20 * 80:
		sim.tick()
		if i % 100 == 0:
			var surf_max := 0.0
			for x in cfg.grid_w:
				surf_max = maxf(surf_max, sim.water.level[(sy - 1) * cfg.grid_w + x])
			var shaft := 0.0
			var chamber := 0.0
			for y in range(sy, sy + cfg.shaft_depth):
				shaft += sim.water.level[y * cfg.grid_w + cfg.nest_x]
			for c in sim.world.nest_cells:
				chamber += sim.water.level[c]
			print("t=%.0f rain=%s surfmax=%.2f shaft=%.2f chamber=%.2f total=%.2f max=%.2f" % [sim.time_s(), sim.water.raining, surf_max, shaft, chamber, sim.water.volume, sim.water.max_level])
	quit()
