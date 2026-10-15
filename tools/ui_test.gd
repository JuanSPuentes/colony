extends SceneTree
## Drives the real scene with real input events (keyboard + mouse) and checks the UI wiring.
## Usage: Godot --headless --path . --script tools/ui_test.gd

var _pass := 0
var _fail := 0
var _main: Node
var _view: WorldView
var _hud: Hud


func _initialize() -> void:
	# Headless windows are tiny; give the test a real-sized, unscaled viewport so injected
	# mouse positions mean the same thing as on screen.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1680, 900)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_run()


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("[%s] %s %s" % ["PASS" if ok else "FAIL", label, detail])


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _key(code: int, ctrl := false) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		ev.ctrl_pressed = ctrl
		root.push_input(ev)
	await process_frame


func _mouse_at(cell: Vector2i) -> Vector2:
	return _view.get_global_transform() * Vector2((cell.x + 0.5) * Cfg.CELL, (cell.y + 0.5) * Cfg.CELL)


func _drag(from: Vector2i, to: Vector2i, button := MOUSE_BUTTON_LEFT) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = _mouse_at(from)
	root.push_input(mm)
	await process_frame
	var down := InputEventMouseButton.new()
	down.button_index = button
	down.pressed = true
	down.position = _mouse_at(from)
	root.push_input(down)
	await process_frame
	var steps := 6
	for i in range(1, steps + 1):
		var m := InputEventMouseMotion.new()
		var c := Vector2i(roundi(lerpf(from.x, to.x, float(i) / steps)), roundi(lerpf(from.y, to.y, float(i) / steps)))
		m.position = _mouse_at(c)
		root.push_input(m)
		await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = button
	up.pressed = false
	up.position = _mouse_at(to)
	root.push_input(up)
	await process_frame


func _run() -> void:
	await _frames(5)
	_view = _main.view
	_hud = _main.hud
	var sim: Simulation = _view.sim
	_check("scene builds view, HUD and simulation", _view != null and _hud != null and sim != null)
	_check("top bar and tool buttons exist", _hud._buttons.size() >= 20 and _hud._top_labels.has("food"))

	# Pause / speed.
	await _key(KEY_SPACE)
	_check("Space pauses", _view.paused)
	var t_paused := sim.t
	await _frames(30)
	_check("simulation time stops while paused", is_equal_approx(sim.t, t_paused))
	await _key(KEY_SPACE)
	await _frames(30)
	_check("Space resumes", not _view.paused and sim.t > t_paused)
	await _key(KEY_TAB)
	_check("Tab raises the speed to 2x", _view.speed == 2.0)
	await _key(KEY_TAB)
	await _key(KEY_TAB)
	_check("Tab cycles back to 1x", _view.speed == 1.0)

	# Dig with the mouse.
	await _key(KEY_D)
	_check("D selects the dig tool", _view.tool == WorldView.Tool.DIG)
	var s := Cfg.SURFACE
	await _drag(Vector2i(41, s + 4), Vector2i(44, s + 4))
	_check("dragging with the dig tool creates connected dig orders", sim.terrain.dig_jobs.size() >= 3, "orders=%d" % sim.terrain.dig_jobs.size())
	await _drag(Vector2i(70, s + 30), Vector2i(72, s + 30))
	_check("disconnected dig orders are refused", not sim.terrain.dig_jobs.has(Vector2i(70, s + 30)))

	# Zoom and pan keep the world under the HUD frame and keep clicks accurate.
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = _mouse_at(Vector2i(40, s + 5))
	root.push_input(wheel)
	await _frames(2)
	_check("mouse wheel zooms in", _view.zoom > 1.1, "zoom=%.2f" % _view.zoom)
	_check("zoom keeps the world covering the view", _view.position.x <= 0.0 and _view.position.y <= 0.0 and _view.position.x >= _view.visible_rect.size.x - _view.world_size.x * _view.zoom - 0.01)
	await _drag(Vector2i(41, s + 6), Vector2i(43, s + 6))
	_check("digging still lands on the right cell when zoomed", sim.terrain.dig_jobs.has(Vector2i(42, s + 6)), "orders=%d" % sim.terrain.dig_jobs.size())
	await _key(KEY_HOME)
	_check("Home resets the view", is_equal_approx(_view.zoom, 1.0) and _view.position == Vector2.ZERO)

	# Pheromone painting.
	await _key(KEY_Q)
	_check("Q selects food pheromone", _view.tool == WorldView.Tool.PHERO and _view.tool_phero == Cfg.Phero.FOOD)
	await _drag(Vector2i(40, Cfg.SURFACE_ROW), Vector2i(30, Cfg.SURFACE_ROW))
	_check("dragging paints a rising food trail", sim.pher.count(Cfg.Phero.FOOD) >= 8 and sim.pher.get_v(Cfg.Phero.FOOD, Vector2i(31, Cfg.SURFACE_ROW)) > sim.pher.get_v(Cfg.Phero.FOOD, Vector2i(39, Cfg.SURFACE_ROW)), "cells=%d" % sim.pher.count(Cfg.Phero.FOOD))
	await _key(KEY_E)
	await _drag(Vector2i(60, Cfg.SURFACE_ROW), Vector2i(60, Cfg.SURFACE_ROW))
	_check("danger pheromone paints a patch", sim.pher.get_v(Cfg.Phero.DANGER, Vector2i(61, Cfg.SURFACE_ROW)) > 0.9)
	await _drag(Vector2i(59, Cfg.SURFACE_ROW), Vector2i(61, Cfg.SURFACE_ROW), MOUSE_BUTTON_RIGHT)
	_check("right-click erases pheromones", sim.pher.get_v(Cfg.Phero.DANGER, Vector2i(60, Cfg.SURFACE_ROW)) < 0.01)

	# Rooms.
	await _key(KEY_4)
	await _drag(Vector2i(34, s + 8), Vector2i(35, s + 8))
	_check("room tool turns tunnel cells into drainage", sim.terrain.room_at(Vector2i(34, s + 8)) == Cfg.Room.DRAIN)

	# Inspect.
	await _key(KEY_I)
	var ant: Ant = sim.ants[3]
	await _drag(ant.cell, ant.cell)
	_check("Inspect selects what is clicked", _view.selected != null, str(_view.selected))
	_check("selection text describes it", _view.describe_selection().length() > 5)
	_hud._set_caste(Cfg.Caste.SOLDIER)
	_check("caste button sets the next eggs", sim.colony.next_caste == Cfg.Caste.SOLDIER)

	# Outcome screen and restart.
	sim.kill_ant(sim.queen, "spider")
	await _frames(10)
	_check("defeat is detected and explained", sim.outcome == 2 and sim.outcome_reason.length() > 10)
	_check("defeat screen is shown", _hud._over_panel.visible and _hud._over_text.text.contains("spider"))
	var old := sim
	_hud.restart_requested.emit()
	await _frames(5)
	_check("restart creates a fresh simulation", _view.sim != old and _view.sim.t < 1.0 and _view.sim.outcome == 0 and not _hud._over_panel.visible)
	# Victory screen.
	_view.sim.t = Cfg.WIN_DAYS * Cfg.DAY_LENGTH - 0.02
	_view.speed = 1.0
	await _frames(20)
	_check("surviving the final day wins", _view.sim.outcome == 1 and _hud._over_title.text == "VICTORY", "outcome=%d" % _view.sim.outcome)
	print("RESULT: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
