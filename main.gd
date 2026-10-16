extends Node2D
## Arranque, entrada del jugador y bucle de ticks. La simulación avanza con un tick fijo
## (cfg.tick_rate por segundo) usando un acumulador; x2/x4 ejecutan más ticks por frame.
## Semilla fija desde la consola:  godot --path . -- --seed=42

const CONFIG_PATH := "res://sim/default_config.tres"
const ZOOM_LEVELS: Array[float] = [0.5, 1.0, 2.0, 3.0, 4.0]
const MAX_TICKS_PER_FRAME := 40
const OVERLAY_HZ := 5.0

var cfg: SimConfig
var sim: Simulation
var terrain_view: TerrainView
var plant_view: PlantView
var overlay: OverlayView
var ant_renderer: AntRenderer
var hud: Hud
var camera: Camera2D

var speed := 1
var paused := false
var tool := 1  # 1 = cavar, 2 = feromona de comida
var zoom_index := 1
var seed_value := 12345

var _acc := 0.0
var _overlay_acc := 0.0
var _painting := false
var _erasing := false
var _panning := false
var _stroke_n := 0
var _last_cell := Vector2i(-1, -1)
var _pan := Vector2.ZERO


func _ready() -> void:
	cfg = load(CONFIG_PATH) as SimConfig if ResourceLoader.exists(CONFIG_PATH) else SimConfig.new()
	seed_value = cfg.world_seed
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.substr(7))
	terrain_view = TerrainView.new()
	plant_view = PlantView.new()
	overlay = OverlayView.new()
	ant_renderer = AntRenderer.new()
	for n in [terrain_view, plant_view, overlay, ant_renderer]:
		add_child(n)
	camera = Camera2D.new()
	add_child(camera)
	hud = Hud.new()
	add_child(hud)
	start(seed_value)


func start(new_seed: int) -> void:
	seed_value = new_seed
	sim = Simulation.new(cfg, seed_value)
	terrain_view.setup(sim)
	plant_view.setup(sim)
	overlay.setup(sim)
	ant_renderer.setup(sim)
	_acc = 0.0
	_painting = false
	camera.position = Vector2(cfg.nest_x * cfg.cell_px, (cfg.surface_y + 2) * cfg.cell_px)
	_apply_camera()


# --- Bucle ----------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if sim == null:
		return
	if _pan != Vector2.ZERO:
		camera.position += _pan * (160.0 / ZOOM_LEVELS[zoom_index]) * delta
		_apply_camera()
	if not paused:
		_acc += delta
		var tick_dt := sim.dt
		var ran := 0
		while _acc >= tick_dt and ran < MAX_TICKS_PER_FRAME:
			_acc -= tick_dt
			for k in speed:
				sim.tick()
				ran += 1
		if ran >= MAX_TICKS_PER_FRAME:
			_acc = 0.0
	terrain_view.refresh()
	_overlay_acc += delta
	if _overlay_acc >= 1.0 / OVERLAY_HZ:
		_overlay_acc = 0.0
		overlay.refresh()
	ant_renderer.color_by_state = overlay.layer == OverlayView.Layer.STATES
	ant_renderer.update(clampf(_acc / sim.dt, 0.0, 1.0) if not paused else 1.0)
	hud.update_info(sim, speed, paused, tool, overlay.layer, ZOOM_LEVELS[zoom_index])


func _apply_camera() -> void:
	var z := ZOOM_LEVELS[zoom_index]
	camera.zoom = Vector2(z, z)
	var half := Vector2(480.0, 270.0) / (2.0 * z)
	var world := Vector2(sim.world.w, sim.world.h) * cfg.cell_px
	camera.position.x = clampf(camera.position.x, minf(half.x, world.x * 0.5), maxf(world.x - half.x, world.x * 0.5))
	camera.position.y = clampf(camera.position.y, minf(half.y, world.y * 0.5), maxf(world.y - half.y, world.y * 0.5))


# --- Entrada ------------------------------------------------------------------------------------------

func _world_cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / cfg.cell_px), floori(p.y / cfg.cell_px))


func _unhandled_input(event: InputEvent) -> void:
	if sim == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_set_zoom(zoom_index + 1)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_set_zoom(zoom_index - 1)
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					_painting = true
					_erasing = mb.button_index == MOUSE_BUTTON_RIGHT
					_stroke_n = 0
					_last_cell = Vector2i(-1, -1)
					_apply_at(_world_cell((make_input_local(mb) as InputEventMouseButton).position))
				else:
					_painting = false
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning:
			camera.position -= mm.relative / ZOOM_LEVELS[zoom_index]
			_apply_camera()
		elif _painting:
			var cell := _world_cell((make_input_local(mm) as InputEventMouseMotion).position)
			_apply_line(_last_cell, cell)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or k.echo:
		return
	var down := k.pressed
	match k.keycode:
		KEY_W:
			_pan.y = -1.0 if down else (0.0 if _pan.y < 0.0 else _pan.y)
		KEY_S:
			_pan.y = 1.0 if down else (0.0 if _pan.y > 0.0 else _pan.y)
		KEY_A:
			_pan.x = -1.0 if down else (0.0 if _pan.x < 0.0 else _pan.x)
		KEY_D:
			_pan.x = 1.0 if down else (0.0 if _pan.x > 0.0 else _pan.x)
	if not down or sim == null:
		return
	match k.keycode:
		KEY_1:
			tool = 1
		KEY_2:
			tool = 2
		KEY_SPACE:
			paused = not paused
		KEY_F1:
			speed = 1
		KEY_F2:
			speed = 2
		KEY_F3:
			speed = 4
		KEY_L:
			sim.cmd_force_rain()
		KEY_TAB:
			overlay.cycle_layer()
		KEY_F9:
			sim.cmd_add_ants(cfg.stress_ants)
		KEY_F5:
			if k.shift_pressed:
				var rng := RandomNumberGenerator.new()
				rng.randomize()
				start(rng.randi() % 1000000)
			else:
				start(seed_value)


func _set_zoom(i: int) -> void:
	zoom_index = clampi(i, 0, ZOOM_LEVELS.size() - 1)
	_apply_camera()


func _apply_line(from: Vector2i, to: Vector2i) -> void:
	if from.x < 0:
		_apply_at(to)
		return
	var steps := maxi(absi(to.x - from.x), absi(to.y - from.y))
	for i in range(1, steps + 1):
		var t := float(i) / steps
		_apply_at(Vector2i(roundi(lerpf(from.x, to.x, t)), roundi(lerpf(from.y, to.y, t))))


func _apply_at(c: Vector2i) -> void:
	if c == _last_cell:
		return
	_last_cell = c
	if _erasing:
		if tool == 2:
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var n := _snap(Vector2i(c.x + dx, c.y + dy))
					if sim.world.in_bounds(n.x, n.y):
						sim.food.data[n.y * sim.world.w + n.x] = 0.0
		else:
			sim.cmd_unmark(c.x, c.y)
		return
	if tool == 1:
		sim.cmd_mark(c.x, c.y)
	else:
		# La rampa crece a lo largo del trazo: arrastra desde el nido hacia la planta.
		var value := minf(1.0, cfg.paint_start + cfg.paint_ramp * _stroke_n)
		var painted := false
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n := _snap(Vector2i(c.x + dx, c.y + dy))
				painted = sim.cmd_paint_food(n.x, n.y, value) or painted
		if painted:
			_stroke_n += 1


## Un clic en el cielo pinta sobre la fila del suelo.
func _snap(c: Vector2i) -> Vector2i:
	if c.y < cfg.surface_y - cfg.walk_band:
		return Vector2i(c.x, cfg.surface_y - 1)
	return c
