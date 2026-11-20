extends Node2D
## PROTOTIPO: dos vistas del mismo mundo, unidas por las salidas del nido.
##   EXTERIOR: desde arriba (ProtoSurface). NIDO: de lado, el corte bajo la franja (ProtoNest).
## Se empieza en el NIDO: la colonia no tiene salida y hay que cavarla.
##
## Cámara:  clic izquierdo arrastrar / WASD: mover · Rueda: zoom · H: volver al nido
## Pasar de una vista a otra (siempre por una salida, con la misma animación):
##   - Exterior: rueda hacia adelante con el zoom al máximo sobre un orificio (o doble clic en él).
##   - Nido: rueda hacia atrás con el zoom al mínimo (sale por la salida más cercana).
##   - Tab: cambia por la salida más cercana a donde estás mirando.
##   - Clic en una hormiga: la cámara la sigue, y cruza con ella si entra o sale.
## Herramienta (clic derecho arrastrar, Shift = deshacer):
##   Exterior: pintar rastro (solo en lo descubierto) · Nido: marcar tierra para cavar.
## Espacio: pausa · F1/F2/F3: x1/x2/x4 · R: reiniciar · V: ver/ocultar feromonas
## Capturas: -- --shot=ruta.png [--shot_s=60] [--view=ext|nest] [--shot_trans=0.2]

enum { EXT, NEST }

const TICK := 1.0 / 60.0
const ZOOMS := [1.5, 2.0, 3.0, 4.0, 6.0]   # px de pantalla por px del mundo
const PAN_KEYS := 220.0
const TRANS_IN := 0.25                     # s: zoom hacia el orificio + fundido a negro
const TRANS_OUT := 0.32                    # s: aparecer del otro lado
const TRANS_ZOOM := 2.4                    # cuánto se mete la cámara en el orificio
const ENTER_RADIUS := 22.0                 # px del mundo alrededor de un orificio para entrar
const SKY := 60.0                          # px de cielo sobre el corte del nido

var sim: ProtoSurface
var speed := 1
var paused := false
var show_trails := true
var mode := NEST
var cams: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var zooms: Array[int] = [2, 2]
var zoom_mul := 1.0                        # extra durante la transición
var follow := -1
var _busy := false
var _acc := 0.0
var _fog_seen := -1
var _nest_seen := -1
var _press_pos := Vector2.ZERO
var _dragged := false
var _msg_t := 0.0
var _shot := {}

var _ext: Node2D
var _ground: Node2D
var _trail_spr: Sprite2D
var _fog_spr: Sprite2D
var _trail_img: Image
var _fog_img: Image
var _nest: Node2D
var _nest_spr: Sprite2D
var _nest_img: Image
var _label: Label
var _msg: Label
var _fade: ColorRect


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			_shot[kv[0]] = kv[1]
	# Exterior: suelo → rastros → (dibujo de _ext: orificios, hormigas, árbol) → niebla.
	_ext = Node2D.new()
	_ext.draw.connect(_draw_ext)
	add_child(_ext)
	_ground = Node2D.new()
	_ground.z_index = -2
	_ground.draw.connect(_draw_ground)
	_ext.add_child(_ground)
	_trail_spr = _layer(_ext, -1, CanvasItem.TEXTURE_FILTER_NEAREST, ProtoSurface.CELL)
	_fog_spr = _layer(_ext, 1, CanvasItem.TEXTURE_FILTER_LINEAR, ProtoSurface.CELL)
	_trail_img = Image.create(ProtoSurface.W, ProtoSurface.H, false, Image.FORMAT_RGBA8)
	_fog_img = Image.create(ProtoSurface.W, ProtoSurface.H, false, Image.FORMAT_RGBA8)
	# Nido: tierra/túneles (textura) → (dibujo de _nest: cielo, montículos, hormigas).
	_nest = Node2D.new()
	_nest.draw.connect(_draw_nest)
	add_child(_nest)
	_nest_spr = _layer(_nest, -1, CanvasItem.TEXTURE_FILTER_NEAREST, ProtoNest.CELL)
	_nest_img = Image.create(ProtoNest.W, ProtoNest.H, false, Image.FORMAT_RGBA8)
	var ui := CanvasLayer.new()
	add_child(ui)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(_fade)
	_label = _make_label(Vector2(12, 6), 20)
	ui.add_child(_label)
	_msg = _make_label(Vector2(12, 40), 20)
	_msg.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	ui.add_child(_msg)
	_reset()
	if _shot.has("shot"):
		_take_shot()


func _make_label(p: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = p
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	return l


func _layer(parent: Node2D, z: int, filter: int, cell: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.centered = false
	s.scale = Vector2.ONE * cell
	s.z_index = z
	s.texture_filter = filter
	parent.add_child(s)
	return s


func _reset() -> void:
	sim = ProtoSurface.new(7)
	_fog_seen = -1
	_nest_seen = -1
	follow = -1
	zooms = [2, 3]
	cams[EXT] = sim.nests[0] + Vector2(90, 0)
	cams[NEST] = sim.nest.cell_center(sim.nest.idx(sim.nest.chamber.get_center().x, 16))
	_set_mode(NEST)
	_say("Tu colonia no tiene salida: marca tierra con clic derecho para cavar hasta la superficie.")
	if _shot.has("shot"):
		# Escena de ejemplo: una salida abierta, otra a medio cavar y un rastro hacia el árbol.
		sim.debug_open_entrance()
		var x2 := int(sim.nests[0].x / ProtoSurface.CELL) + 10
		for y in 25:
			sim.nest.set_mark(sim.nest.idx(x2, y), true)
		for x in range(x2 - 4, x2):
			sim.nest.set_mark(sim.nest.idx(x, 24), true)
		var secs := float(_shot.get("shot_s", "60"))
		for k in int(secs / TICK):
			if k % 120 == 0:
				for j in 60:
					sim.paint(sim.nests[0].lerp(sim.tree_center + Vector2(-40, 0), j / 59.0))
			sim.step(TICK)
		if _shot.get("view", "nest") == "ext":
			_set_mode(EXT)
			zooms[EXT] = 0
		if _shot.has("zoom"):
			zooms[mode] = int(_shot["zoom"])
		if _shot.has("cam"):
			var xy: PackedStringArray = _shot["cam"].split(",")
			cams[mode] = Vector2(float(xy[0]), float(xy[1]))
	_ground.queue_redraw()


func _take_shot() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _shot.has("shot_trans"):
		_toggle()
		await get_tree().create_timer(float(_shot["shot_trans"])).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shot["shot"])
	get_tree().quit()


func _process(delta: float) -> void:
	if not paused:
		_acc += delta * speed
		while _acc >= TICK:
			sim.step(TICK)
			_acc -= TICK
	if not _busy:
		_pan_keys(delta)
		_follow_update()
	_apply_camera()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not _busy:
		_use_tool(Input.is_key_pressed(KEY_SHIFT))
	_update_textures()
	_msg_t -= delta
	_msg.visible = _msg_t > 0.0
	var where := "EXTERIOR (desde arriba)" if mode == EXT else "NIDO (de lado)"
	_label.text = "PROTOTIPO · %s   Comida: %d   Rival: %d   Salidas: %d   Explorado: %d%%   x%d%s%s" % [
		where, sim.food[0], sim.food[1], sim.entrances_px.size(), int(sim.revealed_ratio() * 100),
		speed, "  (PAUSA)" if paused else "", "  · siguiendo hormiga" if follow >= 0 else ""]
	_ext.queue_redraw()
	_nest.queue_redraw()


func _say(t: String, secs := 4.0) -> void:
	_msg.text = t
	_msg_t = secs


# --- Cámara y transición ------------------------------------------------------------------

func _root() -> Node2D:
	return _ext if mode == EXT else _nest


func _bounds(m: int) -> Rect2:
	if m == EXT:
		return Rect2(0, 0, ProtoSurface.MAP_W, ProtoSurface.MAP_H)
	return Rect2(0, -SKY, ProtoNest.W * ProtoNest.CELL, ProtoNest.H * ProtoNest.CELL + SKY)


func _z() -> float:
	return ZOOMS[zooms[mode]] * zoom_mul


func _apply_camera() -> void:
	var vs := get_viewport_rect().size
	var z := _z()
	var b := _bounds(mode)
	var half := vs / (2.0 * z)
	var c := cams[mode]
	c.x = b.get_center().x if half.x * 2.0 >= b.size.x else clampf(c.x, b.position.x + half.x, b.end.x - half.x)
	c.y = b.get_center().y if half.y * 2.0 >= b.size.y else clampf(c.y, b.position.y + half.y, b.end.y - half.y)
	if not _busy:
		cams[mode] = c
	var r := _root()
	r.scale = Vector2.ONE * z
	r.position = (vs * 0.5 - c * z).round()


func _set_mode(m: int) -> void:
	mode = m
	_ext.visible = m == EXT
	_nest.visible = m == NEST


## Cruza a la otra vista por la salida en `x` (coordenada compartida por las dos vistas).
## Fase 1: la cámara se mete en el orificio y se funde a negro. Fase 2: aparece del otro lado,
## pegada a la misma salida, y se aleja hasta el zoom normal.
func _go(to: int, x: float) -> void:
	if _busy or to == mode:
		return
	_busy = true
	var here := Vector2(x, ProtoSurface.CUT_Y) if mode == EXT else Vector2(x, 0.0)
	var there := Vector2(x, ProtoSurface.CUT_Y) if to == EXT else Vector2(x, 0.0)
	var settle := there if to == EXT else there + Vector2(0, 28)  # en el nido, baja por el túnel
	var from_m := mode
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD)
	tw.tween_method(func(v: Vector2) -> void: cams[from_m] = v, cams[from_m], here, TRANS_IN)
	tw.tween_property(self, "zoom_mul", TRANS_ZOOM, TRANS_IN).set_ease(Tween.EASE_IN)
	tw.tween_property(_fade, "color:a", 1.0, TRANS_IN).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func() -> void:
		_set_mode(to)
		zooms[to] = 3
		cams[to] = there)
	tw.tween_method(func(v: Vector2) -> void: cams[to] = v, there, settle, TRANS_OUT).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "zoom_mul", 1.0, TRANS_OUT).set_ease(Tween.EASE_OUT)
	tw.tween_property(_fade, "color:a", 0.0, TRANS_OUT).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func() -> void: _busy = false)


func _toggle() -> void:
	var k := sim.nearest_entrance(cams[mode].x)
	if k < 0:
		_say("Todavía no hay salida: el nido está cerrado. Cava hasta la superficie.")
		if mode == EXT:
			_go(NEST, sim.nests[0].x)
		return
	_go(NEST if mode == EXT else EXT, sim.entrances_px[k].x)


func _entrance_at(p: Vector2) -> int:
	var k := sim.nearest_entrance(p.x)
	if k >= 0 and sim.entrances_px[k].distance_to(p) <= ENTER_RADIUS:
		return k
	return -1


func _follow_update() -> void:
	if follow < 0:
		return
	if sim.team[follow] == 1 and sim.state[follow] == ProtoSurface.INSIDE:
		follow = -1  # la rival entró a su nido: ese no se ve
		return
	var out := sim.outside(follow)
	if out == (mode == EXT):
		cams[mode] = sim.pos[follow]
	else:
		# Cruzó por una salida: la cámara cruza con ella.
		_go(EXT if out else NEST, sim.pos[follow].x)


func _pan_keys(delta: float) -> void:
	var d := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): d.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): d.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): d.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): d.y += 1
	if d != Vector2.ZERO:
		follow = -1
		var fast := 2.5 if Input.is_key_pressed(KEY_SHIFT) else 1.0
		cams[mode] += d * PAN_KEYS * fast * delta / _z()


func _zoom_at(step: int, screen_p: Vector2) -> void:
	var world_p := _root().get_local_mouse_position()
	# Los bordes del zoom son las puertas entre vistas.
	if step > 0 and mode == EXT and zooms[EXT] == ZOOMS.size() - 1:
		var k := _entrance_at(world_p)
		if k < 0:
			k = _entrance_at(cams[EXT])
		if k >= 0:
			_go(NEST, sim.entrances_px[k].x)
		return
	if step < 0 and mode == NEST and zooms[NEST] == 0:
		_toggle()
		return
	var ni := clampi(zooms[mode] + step, 0, ZOOMS.size() - 1)
	if ni == zooms[mode]:
		return
	zooms[mode] = ni
	if follow < 0:  # el punto bajo el mouse se queda bajo el mouse
		cams[mode] = world_p - (screen_p - get_viewport_rect().size * 0.5) / _z()


func _pick_ant(p: Vector2) -> int:
	var best := -1
	var best_d := 8.0
	for i in sim.count():
		if sim.outside(i) != (mode == EXT) or sim.state[i] == ProtoSurface.INSIDE:
			continue
		var d := sim.pos[i].distance_to(p)
		if d < best_d:
			best = i
			best_d = d
	return best


func _use_tool(undo: bool) -> void:
	var p := _root().get_local_mouse_position()
	if mode == EXT:
		if undo:
			sim.erase(p)
		else:
			sim.paint(p)
		return
	var n := sim.nest
	var c := n.cell_at(p)
	if p.y < 0 or p.y >= ProtoNest.H * ProtoNest.CELL:
		return
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var x := c % ProtoNest.W + dx
			var y := c / ProtoNest.W + dy
			if x >= 0 and y >= 0 and x < ProtoNest.W and y < ProtoNest.H:
				n.set_mark(n.idx(x, y), not undo)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT
			or e.button_mask & MOUSE_BUTTON_MASK_MIDDLE):
		if not _busy:
			if e.position.distance_to(_press_pos) > 4.0:
				_dragged = true
				follow = -1
			if _dragged:
				cams[mode] -= e.relative / _z()
	elif e is InputEventMouseButton:
		if _busy:
			return
		if e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_press_pos = e.position
				_dragged = false
				if e.double_click and mode == EXT:
					var k := _entrance_at(_root().get_local_mouse_position())
					if k >= 0:
						_go(NEST, sim.entrances_px[k].x)
			elif not _dragged:
				follow = _pick_ant(_root().get_local_mouse_position())
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(1, e.position)
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(-1, e.position)
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_SPACE: paused = not paused
			KEY_F1: speed = 1
			KEY_F2: speed = 2
			KEY_F3: speed = 4
			KEY_R: _reset()
			KEY_V: show_trails = not show_trails
			KEY_TAB: _toggle()
			KEY_H:
				follow = -1
				if mode == NEST:
					cams[NEST] = sim.nest.cell_center(sim.nest.idx(sim.nest.chamber.get_center().x,
						sim.nest.chamber.get_center().y))
				else:
					var k := sim.nearest_entrance(sim.nests[0].x)
					cams[EXT] = sim.entrances_px[k] if k >= 0 else sim.nests[0]


# --- Texturas -----------------------------------------------------------------------------

func _update_textures() -> void:
	if mode == EXT:
		_trail_spr.visible = show_trails
		if show_trails:
			var cols := [Color(1.0, 0.85, 0.3), Color(1.0, 0.35, 0.3)]
			_trail_img.fill(Color(0, 0, 0, 0))
			for t in 2:
				var f: PheromoneField = sim.trails[t]
				for i in f.data.size():
					var v := f.data[i]
					if v > 0.02:
						var c: Color = cols[t]
						c.a = v * 0.55
						_trail_img.set_pixel(i % f.w, i / f.w, c)
			_set_tex(_trail_spr, _trail_img)
		if sim.fog_version != _fog_seen:
			_fog_seen = sim.fog_version
			var dark := Color(0.06, 0.07, 0.05, 0.94)
			var clear := Color(0.06, 0.07, 0.05, 0.0)
			for i in sim.revealed.size():
				_fog_img.set_pixel(i % ProtoSurface.W, i / ProtoSurface.W,
					clear if sim.revealed[i] == 1 else dark)
			_set_tex(_fog_spr, _fog_img)
	elif sim.nest.version != _nest_seen:
		_nest_seen = sim.nest.version
		var n := sim.nest
		for i in n.open.size():
			var x := i % ProtoNest.W
			var y := i / ProtoNest.W
			var c: Color
			if n.open[i] == 1:
				c = Color("4a3624") if n.in_chamber(i) else Color("35261a")
			else:
				var h := float(hash(i) % 100) / 100.0
				c = Color("7a5636").lerp(Color("5e4129"), h * 0.5 + y / float(ProtoNest.H) * 0.5)
				if n.mark[i] == 1:
					c = c.lerp(Color(1.0, 0.85, 0.3), 0.45)
			_nest_img.set_pixel(x, y, c)
		_set_tex(_nest_spr, _nest_img)


func _set_tex(s: Sprite2D, img: Image) -> void:
	if s.texture == null:
		s.texture = ImageTexture.create_from_image(img)
	else:
		(s.texture as ImageTexture).update(img)


# --- Dibujo: exterior ---------------------------------------------------------------------

func _draw_ground() -> void:
	_ground.draw_rect(Rect2(0, 0, ProtoSurface.MAP_W, ProtoSurface.MAP_H), Color("5d7a3a"))
	var r := RandomNumberGenerator.new()
	r.seed = 1
	for k in 260:
		_ground.draw_circle(Vector2(r.randf_range(16, ProtoSurface.MAP_W - 16), r.randf_range(16, ProtoSurface.MAP_H - 16)),
			r.randf_range(4, 16), Color("6b8a44") if k % 2 == 0 else Color("52703a"))
	# Franja del corte: debajo de esta tierra removida está tu nido (lo que se ve en la vista NIDO).
	_ground.draw_rect(Rect2(0, ProtoSurface.CUT_Y - 5, ProtoSurface.MAP_W * 0.5 - 80, 10),
		Color(0.45, 0.33, 0.2, 0.22))
	for b in sim.bushes:
		_ground.draw_circle(Vector2(b.x, b.y), b.z, Color("3f6a2c"))
		_ground.draw_circle(Vector2(b.x - 2, b.y - 2), b.z * 0.7, Color("4c7d34"))
	for rk in sim.rocks:
		_ground.draw_circle(Vector2(rk.x, rk.y + 2), rk.z, Color(0, 0, 0, 0.25))
		_ground.draw_circle(Vector2(rk.x, rk.y), rk.z, Color("8a8478"))
		_ground.draw_circle(Vector2(rk.x - rk.z * 0.3, rk.y - rk.z * 0.3), rk.z * 0.4, Color("a29c90"))


func _mound_r(use: int) -> float:
	return 5.0 + minf(use, 60) * 0.12


func _draw_ext() -> void:
	# Tus salidas: orificio con montículo que crece con el uso.
	for k in sim.entrances_px.size():
		var p := sim.entrances_px[k]
		var r := _mound_r(sim.entrance_use[k])
		_ext.draw_circle(p, r + 3, Color("8b6a45"))
		_ext.draw_circle(p, r, Color("a07c52"))
		_ext.draw_circle(p, 2.5, Color("1a120b"))
		_ext.draw_arc(p, r + 5, 0, TAU, 24, Color(0.4, 0.9, 1.0, 0.8), 1.0)
	for k in sim.item_pos.size():
		_draw_item(_ext, sim.item_pos[k], sim.item_kind[k],
			float(sim.item_left[k]) / ProtoSurface.KIND_PIECES[sim.item_kind[k]])
	var rv := sim.nests[1]
	_ext.draw_circle(rv, 13, Color("8b6a45"))
	_ext.draw_circle(rv, 9, Color("a07c52"))
	_ext.draw_circle(rv, 4, Color("2a1d12"))
	_ext.draw_arc(rv, 15, 0, TAU, 24, Color(1.0, 0.4, 0.4), 1.0)
	for i in sim.count():
		if sim.outside(i) and sim.state[i] != ProtoSurface.INSIDE:
			_draw_ant(_ext, i)
	_ext.draw_circle(sim.tree_center, ProtoSurface.CANOPY, Color(0.18, 0.38, 0.16, 0.5))
	_ext.draw_circle(sim.tree_center + Vector2(-12, -9), 46, Color(0.22, 0.45, 0.2, 0.4))
	_ext.draw_circle(sim.tree_center, sim.trunk_radius, Color("5a3d24"))


func _draw_ant(canvas: Node2D, i: int) -> void:
	var p := sim.pos[i]
	var d := Vector2.from_angle(sim.ang[i])
	var body := Color("1c1410") if sim.team[i] == 0 else Color("6e1e14")
	canvas.draw_circle(p - d * 2.0, 1.4, body)
	canvas.draw_circle(p, 0.9, body)
	canvas.draw_circle(p + d * 1.6, 1.0, body)
	if sim.carry[i] >= 0:
		# El trozo va en la boca, delante de la cabeza.
		canvas.draw_circle(p + d * 3.2, 1.3, KIND_COLOR[sim.carry[i]])
	elif sim.state[i] == ProtoSurface.CUT:
		# Cortando: las mandíbulas se abren y cierran.
		var o := 0.6 + 0.6 * absf(sin(sim.time * 14.0 + i))
		var side := d.orthogonal() * o
		canvas.draw_line(p + d * 2.2 + side, p + d * 3.4, body, 0.5)
		canvas.draw_line(p + d * 2.2 - side, p + d * 3.4, body, 0.5)
	if i == follow:
		canvas.draw_arc(p, 6.0, 0, TAU, 20, Color(1, 1, 1, 0.9), 0.8)


const KIND_COLOR := [Color("7cc24a"), Color("c8a060"), Color("e2553a"), Color("5a4a6a")]


## Un objeto del suelo. `left` (0..1) achica lo que queda a medida que se lo llevan en trozos.
func _draw_item(canvas: Node2D, p: Vector2, kind: int, left: float) -> void:
	var r: float = ProtoSurface.KIND_SIZE[kind] * (0.45 + 0.55 * left)
	var c: Color = KIND_COLOR[kind]
	match kind:
		ProtoSurface.Kind.LEAF:
			canvas.draw_circle(p + Vector2(-r * 0.35, 0), r * 0.7, c)
			canvas.draw_circle(p + Vector2(r * 0.35, 0), r * 0.7, c)
			canvas.draw_line(p - Vector2(r, 0), p + Vector2(r, 0), c.darkened(0.4), 0.4)
		ProtoSurface.Kind.SEED:
			canvas.draw_circle(p, r, c)
		ProtoSurface.Kind.FRUIT:
			canvas.draw_circle(p + Vector2(0, 0.6), r, c.darkened(0.35))
			canvas.draw_circle(p, r, c)
			canvas.draw_circle(p + Vector2(-r * 0.35, -r * 0.35), r * 0.3, c.lightened(0.4))
		ProtoSurface.Kind.BUG:
			for s in [-1.0, 1.0]:
				for j in 3:
					var base := p + Vector2((j - 1) * r * 0.5, 0)
					canvas.draw_line(base, base + Vector2((j - 1) * 0.6, s * r * 0.9), c.darkened(0.3), 0.4)
			canvas.draw_circle(p + Vector2(-r * 0.6, 0), r * 0.55, c)
			canvas.draw_circle(p + Vector2(r * 0.3, 0), r * 0.4, c)
			canvas.draw_circle(p + Vector2(r * 0.8, 0), r * 0.25, c)


# --- Dibujo: nido -------------------------------------------------------------------------

func _draw_nest() -> void:
	var w := ProtoNest.W * ProtoNest.CELL
	_nest.draw_rect(Rect2(0, -SKY, w, SKY), Color("8fb7c9"))
	_nest.draw_rect(Rect2(0, -3, w, 3), Color("5d7a3a"))
	for k in sim.entrances_px.size():
		var x := sim.entrances_px[k].x
		var r := _mound_r(sim.entrance_use[k])
		_nest.draw_circle(Vector2(x - r * 0.9, -1), r * 0.55, Color("8b6a45"))
		_nest.draw_circle(Vector2(x + r * 0.9, -1), r * 0.55, Color("8b6a45"))
		_nest.draw_rect(Rect2(x - 2, -3, 4, 3), Color("35261a"))
		_nest.draw_arc(Vector2(x, -2), r + 4, PI, TAU, 16, Color(0.4, 0.9, 1.0, 0.8), 1.0)
	var ch := sim.nest.chamber
	_nest.draw_string(ThemeDB.fallback_font, Vector2(ch.position.x * ProtoNest.CELL, ch.position.y * ProtoNest.CELL - 3),
		"Cámara", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(1, 1, 1, 0.6))
	# Reservas: cada trozo que llegó queda apilado en el piso de la cámara.
	var n := 0
	var floor_y := ch.end.y * ProtoNest.CELL - 1.5
	var x0 := ch.position.x * ProtoNest.CELL + 2.0
	var per_row := int((ch.size.x * ProtoNest.CELL - 4.0) / 2.6)
	for kind in sim.stock.size():
		for j in mini(sim.stock[kind], 200 - n):
			_nest.draw_circle(Vector2(x0 + (n % per_row) * 2.6, floor_y - (n / per_row) * 2.4), 1.2,
				KIND_COLOR[kind])
			n += 1
	for i in sim.count():
		if sim.team[i] == 0 and not sim.outside(i):
			_draw_ant(_nest, i)
