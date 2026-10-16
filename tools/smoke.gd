extends SceneTree
func _initialize() -> void:
	var cfg := SimConfig.new()
	var sim := Simulation.new(cfg)
	var t0 := Time.get_ticks_msec()
	var n := 20 * 240
	for i in n:
		sim.tick()
		if i % (20 * 30) == 0:
			print("t=%3.0f ants=%d leaves=%d delivered=%d states=%s foodcells=%d" % [sim.time_s(), sim.ants.alive_count, sim.leaves_stored, sim.delivered, sim.ants.state_counts, sim.food.active])
	print("ms/tick=%.3f stuck=%d maxstuck=%.1f" % [float(Time.get_ticks_msec() - t0) / n, sim.stuck_recoveries, sim.ants.max_stuck_seen])
	quit()
