extends Node2D
## Arranque, entrada del jugador y bucle de ticks. La simulación avanza con un tick fijo
## (cfg.tick_rate por segundo) usando un acumulador; x2/x4 ejecutan más ticks por frame.
## Semilla fija desde la consola:  godot --path . -- --seed=42
##
## Fase 1: las teclas 1 y 2 (Cavar / Feromona) se comportan exactamente igual que en la Fase 0
## cuando la subcasta de feromona es la primera (Comida, el valor por defecto). 3 (Cámara) y 4
## (Borrar) son nuevas. Q/E recorren la subherramienta de 2 o 3.
##
## El mundo (480x270, pixel art) vive dentro de un SubViewport escalado sin filtro, para que se
## vea nítido ampliado. El HUD es hermano de ese SubViewport, fuera de él, así que dibuja su texto
## a la resolución real de la ventana y se ve nítido en vez de borroso/bloqueado. `Main` sigue
## siendo el nodo raíz (para que `sim`, `cfg`, `tool`, etc. sean accesibles igual que antes desde
## las pruebas), pero la entrada de mouse se convierte a mano al espacio del SubViewport.

const CONFIG_PATH := "res://sim/core/default_config.tres"
const SAVE_PATH := "user://save1.json"
const ZOOM_LEVELS: Array[float] = [0.5, 1.0, 2.0, 3.0, 4.0]
const MAX_TICKS_PER_FRAME := 40
const OVERLAY_HZ := 5.0
const WORLD_SIZE := Vector2(480.0, 270.0)
## Traduce clics/trazos a los `cmd_*` de `sim` según la herramienta activa (ver ese archivo).
const InputTools = preload("res://main_input_tools.gd")

## Subtipos de feromona que recorre Q/E con la herramienta 2 (coincide con PHERO_NAMES del HUD).
const PHERO_FIELDS := ["food", "home", "danger", "attack", "evacuate"]
## Subtipos de cámara que recorre Q/E con la herramienta 3.
const ROOM_TYPES: Array[int] = [WorldGrid.Room.NURSERY, WorldGrid.Room.STORAGE, WorldGrid.Room.ROYAL]

## Fase 3 (menú): si `app.gd` instancia esta escena, pone esto en `false` antes de añadirla al
## árbol y arranca la partida él mismo (con el modo que eligió el jugador). Si se abre
## `main.tscn` directo (como hacen `ui_test.gd`/`screenshot.gd`), arranca solo, como siempre.
var auto_start := true
signal menu_requested

var cfg: SimConfig
var sim: Simulation
## En modo `--headless` (usado por las pruebas) la ventana real no existe y `get_tree().root.size`
## siempre da un tamaño ficticio fijo, sin importar lo que el script le asigne: por eso las
## pruebas que necesitan un tamaño concreto para sus clics simulados lo fuerzan aquí en vez de
## tocar `root.size` (que en ese modo no sirve de nada).
var world_size_override := Vector2.ZERO
var world_vp: SubViewport
var world_container: SubViewportContainer
var terrain_view: TerrainView
var plant_view: PlantView
var corpse_view: CorpseView
var overlay: OverlayView
var ant_renderer: AntRenderer
var spider_view: SpiderView
var centipede_view: CentipedeView
var day_night_view: DayNightView
var hud: Hud
var tutorial: TutorialView
var camera: Camera2D

var speed := 1
var paused := false
var tool := 1  # 1 = cavar, 2 = feromona, 3 = cámara, 4 = borrar
var phero_index := 0
var room_index := 0
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
## Posiciones de las hormigas justo antes de correr los ticks de este frame real. A velocidad
## x2/x4 varios ticks corren en el mismo frame; `AntSystem.prev` solo guarda el penúltimo de esos
## ticks, así que interpolar desde ahí perdía todo el movimiento anterior y las hormigas se veían
## saltar. Esto guarda el punto de partida real del frame para interpolar el tramo completo.
var _frame_start_pos := PackedVector2Array()
## Transición suave de zoom (punto 3 de fluidez): en vez de aplicar el nivel de `ZOOM_LEVELS` de
## golpe, se anima zoom y posición de cámara desde el valor actual al destino en `ZOOM_DURATION`.
const ZOOM_DURATION := 0.12
var _zoom_t := 1.0
var _zoom_from_z := 1.0
var _zoom_from_pos := Vector2.ZERO
var _zoom_to_z := 1.0
var _zoom_to_pos := Vector2.ZERO
## Tween de cámara para el salto a la reina (tecla H, punto 4 de fluidez): en vez de teletransporte
## instantáneo, se desliza desde donde estaba la cámara hasta la reina en `JUMP_DURATION`.
const JUMP_DURATION := 0.25
var _jump_t := 1.0
var _jump_from := Vector2.ZERO
var _jump_to := Vector2.ZERO
## El pan WASD apuntaba la velocidad directo a -1/0/1 (arranca y frena en seco). `_pan` sigue
## siendo esa dirección objetivo (la fija `_unhandled_key_input`); `_pan_vel` la persigue con
## aceleración limitada para que arrancar/frenar se sienta gradual, no digital.
const PAN_ACCEL := 10.0
var _pan_vel := Vector2.ZERO


func _ready() -> void:
	cfg = load(CONFIG_PATH) as SimConfig if ResourceLoader.exists(CONFIG_PATH) else SimConfig.new()
	seed_value = cfg.world_seed
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.substr(7))
	world_vp = SubViewport.new()
	world_vp.size = Vector2i(WORLD_SIZE.x, WORLD_SIZE.y)
	world_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	world_container = SubViewportContainer.new()
	world_container.stretch = true
	world_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(world_container)
	world_container.add_child(world_vp)
	# Un Control cuyo padre no es otro Control ignora sus anclas (quedaría en tamaño 0): hay que
	# fijar el tamaño a mano, aquí y cada vez que cambie el tamaño de la ventana real.
	_resize_world_container()
	get_tree().root.size_changed.connect(_resize_world_container)
	terrain_view = TerrainView.new()
	plant_view = PlantView.new()
	corpse_view = CorpseView.new()
	overlay = OverlayView.new()
	ant_renderer = AntRenderer.new()
	spider_view = SpiderView.new()
	centipede_view = CentipedeView.new()
	day_night_view = DayNightView.new()
	for n in [terrain_view, plant_view, corpse_view, overlay, ant_renderer, spider_view, centipede_view, day_night_view]:
		world_vp.add_child(n)
	camera = Camera2D.new()
	world_vp.add_child(camera)
	hud = Hud.new()
	hud.gear_pressed.connect(func() -> void: menu_requested.emit())
	add_child(hud)
	tutorial = TutorialView.new()
	add_child(tutorial)
	if auto_start:
		start(seed_value)


## Fase 3 (menú): brillo del mundo, 0.6 (más oscuro) a 1.4 (más claro); 1.0 es el normal.
## Se aplica dentro de `day_night_view` (el único CanvasModulate del mundo) en vez de con uno
## propio: Godot solo deja uno activo por canvas, así que un segundo nodo no tendría ningún efecto.
func set_brightness(b: float) -> void:
	if day_night_view != null:
		day_night_view.set_brightness(b)


## Qué modo arranca `start()` cuando no se pide uno explícito (F5, por ejemplo, reinicia en el
## modo en el que ya se estaba jugando, no siempre en el mismo). `main.tscn` abierto directo (las
## pruebas) arranca en "incremental", igual que antes de que existiera el menú.
var game_mode := "incremental"


## `loaded_sim`, si se pasa (Fase 2: cargar partida), reemplaza la colonia nueva de siempre.
## `mode` ("historia" o "incremental"): si se omite, se repite el modo con el que se arrancó la
## última vez (F5 reinicia en el mismo modo). Lo fija `app.gd` según lo que elige el jugador en el
## menú; `main.tscn` abierto directo nunca lo pasa, así que conserva el comportamiento de antes.
func start(new_seed: int, loaded_sim: Simulation = null, mode: String = "") -> void:
	seed_value = new_seed
	if mode != "":
		game_mode = mode
	if loaded_sim != null:
		sim = loaded_sim
		game_mode = "test" if loaded_sim.test_mode else ("incremental" if loaded_sim.incremental else "historia")
	else:
		sim = Simulation.new(cfg, seed_value)
		if game_mode == "historia":
			sim.spawn_colony_court()
		elif game_mode == "test":
			sim.spawn_test_start()
		else:
			sim.spawn_incremental_start()
	terrain_view.setup(sim)
	day_night_view.setup(sim)
	plant_view.setup(sim)
	corpse_view.setup(sim)
	overlay.setup(sim)
	ant_renderer.setup(sim)
	spider_view.setup(sim)
	centipede_view.setup(sim)
	_acc = 0.0
	_painting = false
	if sim.queen_id >= 0 and sim.ants.alive[sim.queen_id] == 1:
		camera.position = sim.ants.pos[sim.queen_id]
	else:
		camera.position = Vector2(cfg.nest_x * cfg.cell_px, (cfg.surface_y + 2) * cfg.cell_px)
	_apply_camera()


## Fase 2: guardar y cargar partida.
func save_game() -> void:
	if sim == null:
		return
	var err := SaveSystem.save_file(sim, SAVE_PATH)
	if err == OK:
		sim.notify("Partida guardada.")
	else:
		sim.notify("No se pudo guardar (error %d)." % err)


func load_game() -> void:
	var loaded := SaveSystem.load_file(SAVE_PATH, cfg)
	if loaded == null:
		if sim != null:
			sim.notify("No hay ninguna partida guardada.")
		return
	seed_value = loaded.rng.seed
	start(seed_value, loaded)
	sim.notify("Partida cargada.")


func _resize_world_container() -> void:
	var sz := world_size_override if world_size_override != Vector2.ZERO else Vector2(get_tree().root.size)
	world_container.position = Vector2.ZERO
	world_container.size = sz
	# `stretch=true` hace que el SubViewport interno renderice a la resolución del contenedor,
	# no a la que le pusimos; `stretch_shrink` es lo que de verdad controla la baja resolución
	# interna (el "pixel art" real) antes de ampliarla sin filtro para mostrarla.
	world_container.stretch_shrink = maxi(1, roundi(sz.x / WORLD_SIZE.x))


func _current_phero() -> PheromoneField:
	return InputTools.current_phero(self)


# --- Bucle ----------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if sim == null:
		return
	_resize_world_container()  # barato; `root.size` puede tardar un frame en reflejar el cambio
	if _zoom_t < 1.0:
		_zoom_t = minf(1.0, _zoom_t + delta / ZOOM_DURATION)
		var e := smoothstep(0.0, 1.0, _zoom_t)
		var z := lerpf(_zoom_from_z, _zoom_to_z, e)
		camera.zoom = Vector2(z, z)
		camera.position = _zoom_from_pos.lerp(_zoom_to_pos, e)
		_clamp_camera(z)
	if _jump_t < 1.0:
		_jump_t = minf(1.0, _jump_t + delta / JUMP_DURATION)
		var e2 := smoothstep(0.0, 1.0, _jump_t)
		camera.position = _jump_from.lerp(_jump_to, e2)
		_clamp_camera(camera.zoom.x)
	_pan_vel = _pan_vel.move_toward(_pan, PAN_ACCEL * delta)
	if _pan_vel != Vector2.ZERO:
		camera.position += _pan_vel * (160.0 / camera.zoom.x) * delta
		_clamp_camera(camera.zoom.x)
	if not paused and not sim.game_over:
		_acc += delta
		var tick_dt := sim.dt
		var ran := 0
		if _acc >= tick_dt:
			_frame_start_pos = sim.ants.pos.duplicate()
		while _acc >= tick_dt and ran < MAX_TICKS_PER_FRAME:
			_acc -= tick_dt
			for k in speed:
				sim.tick()
				ran += 1
		if ran >= MAX_TICKS_PER_FRAME:
			_acc = 0.0
	terrain_view.refresh()
	day_night_view.refresh()
	_overlay_acc += delta
	if _overlay_acc >= 1.0 / OVERLAY_HZ:
		_overlay_acc = 0.0
		overlay.refresh()
	# Por defecto las hormigas se ven coloreadas por casta (reina/obrera/nodriza/soldado) todo el
	# tiempo, no solo en la capa de depuración; la capa de Estados la reemplaza mientras está activa.
	ant_renderer.color_by_state = overlay.layer == OverlayView.Layer.STATES
	ant_renderer.color_by_caste = not ant_renderer.color_by_state
	ant_renderer.update(clampf(_acc / sim.dt, 0.0, 1.0) if not paused else 1.0, _frame_start_pos)
	hud.update_info(self)
	tutorial.update(sim)


func _apply_camera() -> void:
	camera.zoom = Vector2(ZOOM_LEVELS[zoom_index], ZOOM_LEVELS[zoom_index])
	_clamp_camera(ZOOM_LEVELS[zoom_index])


## Separado de `_apply_camera` para que la animación de zoom (`_zoom_t` en `_process`) pueda
## clamplear la cámara con el zoom intermedio de cada frame sin pisar `camera.zoom` con el valor
## final todavía no alcanzado.
func _clamp_camera(z: float) -> void:
	var half := Vector2(480.0, 270.0) / (2.0 * z)
	var world := Vector2(sim.world.w, sim.world.h) * cfg.cell_px
	camera.position.x = clampf(camera.position.x, minf(half.x, world.x * 0.5), maxf(world.x - half.x, world.x * 0.5))
	camera.position.y = clampf(camera.position.y, minf(half.y, world.y * 0.5), maxf(world.y - half.y, world.y * 0.5))


# --- Entrada ------------------------------------------------------------------------------------------

func _world_cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / cfg.cell_px), floori(p.y / cfg.cell_px))


## Factor para pasar de píxeles de la ventana real (donde vive `Main`) a píxeles lógicos del
## SubViewport del mundo (480x270). En el juego real son 3 (ventana 1440x810); en las pruebas,
## que fuerzan `root.size = Vector2i(480, 270)`, es 1 (el contenedor llena esa ventana reducida).
func _outer_to_inner_scale() -> Vector2:
	var cs := world_container.size
	if cs.x <= 0.0 or cs.y <= 0.0:
		return Vector2.ONE
	return WORLD_SIZE / cs


## Convierte una posición de evento de mouse (en píxeles de la ventana real) a coordenadas del
## mundo en píxeles, ya pasando por el zoom y la posición de la cámara.
func _to_world(screen_pos: Vector2) -> Vector2:
	var inner := screen_pos * _outer_to_inner_scale()
	return world_vp.get_canvas_transform().affine_inverse() * inner


func _unhandled_input(event: InputEvent) -> void:
	if sim == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_set_zoom(zoom_index + 1, mb.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_set_zoom(zoom_index - 1, mb.position)
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					_painting = true
					_erasing = mb.button_index == MOUSE_BUTTON_RIGHT
					_stroke_n = 0
					_last_cell = Vector2i(-1, -1)
					_apply_at(_world_cell(_to_world(mb.position)))
				else:
					_painting = false
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning:
			camera.position -= mm.relative * _outer_to_inner_scale() / ZOOM_LEVELS[zoom_index]
			_apply_camera()
		elif _painting:
			var cell := _world_cell(_to_world(mm.position))
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
		KEY_3:
			tool = 3
		KEY_4:
			tool = 4
		KEY_5:
			tool = 5
		KEY_Q:
			if tool == 2:
				phero_index = (phero_index - 1 + PHERO_FIELDS.size()) % PHERO_FIELDS.size()
			elif tool == 3:
				room_index = (room_index - 1 + ROOM_TYPES.size()) % ROOM_TYPES.size()
		KEY_E:
			if tool == 2:
				phero_index = (phero_index + 1) % PHERO_FIELDS.size()
			elif tool == 3:
				room_index = (room_index + 1) % ROOM_TYPES.size()
		# Fase 3 (modo incremental): 7 compra un huevo (la casta que nace es al azar, ya no la
		# elige el jugador) y 9 cambia la auto-compra; 8 no hace nada en este modo (antes compraba
		# soldado directo). En una partida clásica (cargada de un guardado viejo) 7/8/9 siguen
		# ajustando el reparto de castas.
		KEY_7:
			if sim.incremental:
				sim.cmd_buy_egg()
			else:
				sim.cmd_nudge_caste(CasteDefs.Caste.WORKER, 0.08)
		KEY_8:
			if not sim.incremental:
				sim.cmd_nudge_caste(CasteDefs.Caste.NURSE, 0.08)
		KEY_9:
			if sim.incremental:
				sim.cmd_cycle_auto_buy()
			else:
				sim.cmd_nudge_caste(CasteDefs.Caste.SOLDIER, 0.08)
		KEY_SPACE:
			paused = not paused
		KEY_F1:
			speed = 1
		KEY_F2:
			speed = 2
		KEY_F3:
			speed = 4
		KEY_F10:
			sim.cmd_force_spider()
		KEY_F11:
			sim.cmd_force_centipede()
		KEY_H:
			if sim.queen_id >= 0:
				_jump_from = camera.position
				_jump_to = sim.ants.pos[sim.queen_id]
				_jump_t = 0.0
		KEY_F5:
			if k.shift_pressed:
				var rng := RandomNumberGenerator.new()
				rng.randomize()
				start(rng.randi() % 1000000)
			else:
				start(seed_value)
		KEY_I:
			hud.toggle_status()
		KEY_F6:
			save_game()
		KEY_F7:
			load_game()


## `anchor_screen_pos`, si se pasa, es el punto de pantalla (mouse) que debe quedar fijo en el
## mundo tras el cambio de zoom (en vez de que todo se corra alrededor del centro de cámara).
## El cambio no se aplica de golpe: arranca una transición corta (`_zoom_t` en `_process`) desde
## el zoom/posición actuales (que pueden venir a mitad de una transición anterior) al destino.
func _set_zoom(i: int, anchor_screen_pos: Vector2 = Vector2.INF) -> void:
	var new_index := clampi(i, 0, ZOOM_LEVELS.size() - 1)
	if new_index == zoom_index:
		return
	var has_anchor := is_finite(anchor_screen_pos.x) and sim != null
	var before := _to_world(anchor_screen_pos) if has_anchor else Vector2.ZERO
	_zoom_from_z = camera.zoom.x
	_zoom_from_pos = camera.position
	zoom_index = new_index
	_zoom_to_z = ZOOM_LEVELS[zoom_index]
	if has_anchor:
		camera.zoom = Vector2(_zoom_to_z, _zoom_to_z)
		var after := _to_world(anchor_screen_pos)
		_zoom_to_pos = _zoom_from_pos + (before - after)
		camera.zoom = Vector2(_zoom_from_z, _zoom_from_z)  # restaurar: el frame animará desde acá
	else:
		_zoom_to_pos = _zoom_from_pos
	_zoom_t = 0.0


func _apply_line(from: Vector2i, to: Vector2i) -> void:
	InputTools.apply_line(self, from, to)


func _apply_at(c: Vector2i) -> void:
	InputTools.apply_at(self, c)


## Un clic en el cielo pinta sobre la fila del suelo.
func _snap(c: Vector2i) -> Vector2i:
	return InputTools.snap(self, c)
