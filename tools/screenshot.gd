extends SceneTree
## Dev tool: renders the real game in a window and saves PNGs.
## Usage: Godot --path . --resolution 1600x900 --script tools/screenshot.gd -- <out_dir> <sim_seconds> [sim_seconds ...]
## Fast-forwards the simulation to each given time (in sim seconds) and captures a frame.

const V := preload("res://tools/validate.gd")
const DEMO := true  # let the scripted player act so the shots show trails, rooms and fights
var _main: Node


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_run(OS.get_cmdline_user_args())


func _run(args: PackedStringArray) -> void:
	var out := args[0] if args.size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	await _frames(20)
	var view: WorldView = _main.view
	_shot(out, "t0")
	var bot := V.new()
	var ticks := 0
	for i in range(1, args.size()):
		var target := float(args[i])
		view.speed = 1.0
		while view.sim.t < target and view.sim.outcome == 0:
			for k in 20:
				view.sim.step(Cfg.TICK)
				ticks += 1
				if ticks % 30 == 0 and DEMO:
					bot._bot_actions(view.sim, 0 if ticks == 30 * 4 else 1)
		await _frames(6)
		_shot(out, "t%d" % int(target))
		view.zoom_at(Vector2(660, 330), 2.4)
		await _frames(4)
		_shot(out, "t%d_zoom" % int(target))
		view.reset_view()
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(dir: String, shot_name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, shot_name])
	print("saved ", shot_name, " ", img.get_size())
