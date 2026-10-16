extends SceneTree
## Herramienta de desarrollo: ejecuta el juego real en una ventana y guarda PNG.
## Uso: Godot --path . --script tools/screenshot.gd -- <carpeta> <seg_sim> [seg_sim ...] [zoomN] [capaN]
## Avanza la simulación hasta cada tiempo y captura. "zoomN" fija el nivel de zoom, "capaN" la capa.

var _main: Node


func _initialize() -> void:
	_main = load("res://main.tscn").instantiate()
	root.add_child(_main)
	_run(OS.get_cmdline_user_args())


func _run(args: PackedStringArray) -> void:
	var out := args[0] if args.size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	for _i in 10:
		await process_frame
	var suffix := ""
	for i in range(1, args.size()):
		var a := args[i]
		if a.begins_with("zoom"):
			_main.zoom_index = int(a.substr(4))
			_main._apply_camera()
			suffix = "_z" + a.substr(4)
			continue
		if a.begins_with("capa"):
			_main.overlay.layer = int(a.substr(4))
			suffix += "_c" + a.substr(4)
			continue
		var target := float(a)
		while _main.sim.time_s() < target:
			for _k in 40:
				_main.sim.tick()
		for _j in 8:
			await process_frame
		_main.overlay.refresh()
		await process_frame
		var img := root.get_texture().get_image()
		img.save_png("%s/t%d%s.png" % [out, int(target), suffix])
		print("saved t", int(target), suffix, " ", img.get_size())
	quit()
