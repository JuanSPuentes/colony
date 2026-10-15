extends SceneTree
## Windowed frame-rate check: many ants at 4x speed with the real renderer.
## Usage: Godot --path . --script tools/perf.gd

func _initialize() -> void:
	var m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	_go(m)


func _go(m) -> void:
	for i in 10:
		await process_frame
	var view: WorldView = m.view
	var sim: Simulation = view.sim
	for i in 110:
		sim.spawn_ant(Cfg.Caste.WORKER, Vector2i(30 + i % 20, Cfg.SURFACE + 8))
	view.speed = 4.0
	var t0 := Time.get_ticks_msec()
	var frames := 0
	var worst := 0
	var last := Time.get_ticks_msec()
	while frames < 600:
		await process_frame
		var now := Time.get_ticks_msec()
		worst = maxi(worst, now - last)
		last = now
		frames += 1
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	print("PERF ants=%d simtime=%.0fs frames=%d fps=%.1f worst frame=%d ms (speed 4x)" % [sim.adult_count(), sim.t, frames, frames / secs, worst])
	quit()
