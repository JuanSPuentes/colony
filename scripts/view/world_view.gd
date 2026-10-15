class_name WorldView
extends Node2D
## Draws the world (sky, soil cross-section, nest, ants, weather, overlays) and turns mouse
## input into simulation commands. It owns the simulation clock (speed / pause).

signal tool_changed
signal selection_changed

enum Tool { INSPECT, DIG, ROOM, PHERO, ERASE }

const PHERO_COLORS := [
	Color("6fe04a"), Color("4aa8ff"), Color("ff3f33"), Color("ffae2b"), Color("fff27a"),
]
const PHERO_HINTS := [
	"Food: drag from the nest TOWARD the food. Workers follow the rising trail.",
	"Home: drag from the food TOWARD the nest. Guides lost ants home (rain washes scent away).",
	"Danger: paint a patch. Workers and nurses avoid it; soldiers ignore it.",
	"Attack: paint where the enemy is. Nearby soldiers rush there.",
	"Evacuate: paint a flooded or threatened area. Ants inside move to safe ground.",
]

var sim: Simulation
var sfx: Sfx
var tool := Tool.INSPECT
var tool_room := Cfg.Room.ROYAL
var tool_phero := Cfg.Phero.FOOD
var speed := 1.0
var paused := false
var selected: Variant = null
var actions := {"food_paint": 0, "home_paint": 0, "danger_paint": 0, "attack_paint": 0, "evac_paint": 0, "dig_cmds": 0, "room_cmds": 0}

var _terrain_img: Image
var _terrain_tex: ImageTexture
var _dirty := {}
var _deco_tex: ImageTexture
var _accum := 0.0
var _time := 0.0
var _particles: Array[Dictionary] = []
var _hover := Vector2i(-1, -1)
var _mouse_local := Vector2(-1000, -1000)
## Screen-space rectangle (inside the HUD frame) in which the world is visible and clickable.
var visible_rect := Rect2(0, 44, 1296, 832)
var zoom := 1.0
var _panning := false
var _painting := false
var _erasing := false
var _last_cell := Vector2i(-1, -1)
var _stroke_n := 0
var _deny_shown := false
var _font: Font = ThemeDB.fallback_font
var _hills_far: PackedVector2Array
var _hills_near: PackedVector2Array
var _clouds: Array[Dictionary] = []
var _prev_rain := 0.0
var _alert_cd := 0.0

var world_size: Vector2:
	get:
		return Vector2(Cfg.W * Cfg.CELL, Cfg.H * Cfg.CELL)


func _ready() -> void:
	_make_scenery()


func start(new_sim: Simulation) -> void:
	sim = new_sim
	selected = null
	_particles.clear()
	_dirty.clear()
	_painting = false
	for k in actions:
		actions[k] = 0
	_terrain_img = Image.create(Cfg.W * Cfg.CELL, Cfg.H * Cfg.CELL, false, Image.FORMAT_RGBA8)
	_terrain_img.fill(Color(0, 0, 0, 0))
	for y in Cfg.H:
		for x in Cfg.W:
			_blit_cell(Vector2i(x, y))
	_terrain_tex = ImageTexture.create_from_image(_terrain_img)
	sim.terrain.cell_changed.connect(func(c: Vector2i) -> void: _dirty[c] = true)
	sim.fx_emitted.connect(_on_fx)
	sim.notified.connect(_on_notified)
	_accum = 0.0


# --- Scenery (static, generated once) ---------------------------------------------------------------

func _make_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var wpx := Cfg.W * Cfg.CELL
	var img := Image.create(wpx, 40, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var ground_y := 37  # row of the soil line inside the strip
	for x in wpx:
		var h := rng.randi_range(3, 8)
		var g := Color("4f9a3c").lerp(Color("8ccf55"), rng.randf())
		for k in h:
			var yy := ground_y - k
			img.set_pixel(x, yy, g.lightened(0.04 * k))
		for k in 3:
			img.set_pixel(x, ground_y + k, Color("3f7f31").darkened(0.08 * k))
	# Taller grass stalks, flowers and stones.
	var x := 6
	while x < wpx - 6:
		x += rng.randi_range(18, 46)
		if x >= wpx - 12:
			break
		var kind := rng.randi() % 4
		if kind == 0:
			var hh := rng.randi_range(14, 26)
			var gc := Color("3f8f3a")
			for k in hh:
				img.set_pixel(clampi(x + int(sin(k * 0.25) * 2.0), 0, wpx - 1), ground_y - k, gc)
			for k in 4:
				img.set_pixel(clampi(x + 1 + k, 0, wpx - 1), ground_y - hh + k, gc.lightened(0.2))
		elif kind == 1:
			var fc: Color = [Color("ffd84a"), Color("ff8fb3"), Color("ffffff"), Color("b58cff")][rng.randi() % 4]
			var fh := rng.randi_range(8, 14)
			for k in fh:
				img.set_pixel(x, ground_y - k, Color("3f8f3a"))
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					if absi(dx) + absi(dy) <= 1:
						img.set_pixel(clampi(x + dx, 0, wpx - 1), ground_y - fh + dy, fc)
			img.set_pixel(x, ground_y - fh, Color("ffe36a"))
		elif kind == 2:
			var rw := rng.randi_range(5, 9)
			var rh := rng.randi_range(3, 5)
			for dx in rw:
				for dy in rh:
					var inside := pow((dx - rw * 0.5) / (rw * 0.5), 2.0) + pow(float(dy) / rh, 2.0) < 1.0
					if inside:
						img.set_pixel(clampi(x + dx, 0, wpx - 1), ground_y - dy, Color("8a8794").lightened(0.04 * dy))
	_deco_tex = ImageTexture.create_from_image(img)
	_hills_far = PackedVector2Array()
	_hills_near = PackedVector2Array()
	var gy := Cfg.SURFACE * Cfg.CELL
	_hills_far.append(Vector2(0, gy))
	_hills_near.append(Vector2(0, gy))
	for i in range(0, wpx + 8, 8):
		_hills_far.append(Vector2(i, gy - 46 - sin(i * 0.011) * 22 - sin(i * 0.031 + 1.0) * 8))
		_hills_near.append(Vector2(i, gy - 22 - sin(i * 0.017 + 2.0) * 12 - sin(i * 0.05) * 4))
	_hills_far.append(Vector2(wpx, gy))
	_hills_near.append(Vector2(wpx, gy))
	for i in 7:
		_clouds.append({"x": rng.randf() * wpx, "y": 20.0 + rng.randf() * 90.0, "s": 0.6 + rng.randf() * 0.9, "v": 4.0 + rng.randf() * 6.0})


func _blit_cell(c: Vector2i) -> void:
	var tr := sim.terrain
	var rect_pos := Vector2i(c.x * Cfg.CELL, c.y * Cfg.CELL)
	var full := Rect2i(0, 0, Cfg.CELL, Cfg.CELL)
	var variant := Sprites._hash(c.x, c.y, 5) % 4
	match tr.type_at(c):
		Cfg.Cell.AIR:
			_terrain_img.fill_rect(Rect2i(rect_pos, Vector2i(Cfg.CELL, Cfg.CELL)), Color(0, 0, 0, 0))
		Cfg.Cell.SOIL:
			var band := clampi((c.y - Cfg.SURFACE) / 10, 0, 3)
			_terrain_img.blit_rect(Sprites.soil_tile(band, variant), full, rect_pos)
		Cfg.Cell.ROCK:
			if c.y >= Cfg.H - 2:
				_terrain_img.blit_rect(Sprites.bedrock_tile(), full, rect_pos)
			else:
				_terrain_img.blit_rect(Sprites.rock_tile(variant % 2), full, rect_pos)
		Cfg.Cell.TUNNEL:
			var mask := 0
			if _solid(tr.type_at(c + Vector2i.UP)):
				mask |= 1
			if _solid(tr.type_at(c + Vector2i.RIGHT)):
				mask |= 2
			if _solid(tr.type_at(c + Vector2i.DOWN)):
				mask |= 4
			if _solid(tr.type_at(c + Vector2i.LEFT)):
				mask |= 8
			_terrain_img.blit_rect(Sprites.tunnel_tile(tr.room_at(c), mask, variant % 2), full, rect_pos)


func _solid(t: int) -> bool:
	return t == Cfg.Cell.SOIL or t == Cfg.Cell.ROCK


# --- Simulation clock ------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if sim == null:
		return
	_time += delta
	if not paused and sim.outcome == 0:
		_accum += delta * speed
		var guard := 0
		while _accum >= Cfg.TICK and guard < 12:
			sim.step(Cfg.TICK)
			_accum -= Cfg.TICK
			guard += 1
		if guard >= 12:
			_accum = 0.0
	if not _dirty.is_empty():
		for c in _dirty:
			_blit_cell(c)
		_dirty.clear()
		_terrain_tex.update(_terrain_img)
	_update_particles(delta)
	if sfx != null:
		sfx.set_rain(sim.weather.rain)
	_alert_cd -= delta
	queue_redraw()


func get_alpha() -> float:
	return clampf(_accum / Cfg.TICK, 0.0, 1.0) if not paused else 1.0


# --- Input -------------------------------------------------------------------------------------------------

func _mouse_cell() -> Vector2i:
	return Cfg.world_to_cell(_mouse_local)


func _unhandled_input(event: InputEvent) -> void:
	if sim == null:
		return
	if event is InputEventMouse:
		_mouse_local = (make_input_local(event) as InputEventMouse).position
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			if visible_rect.has_point(mb.position):
				zoom_at(mb.position, 1.2 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2)
			return
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed and visible_rect.has_point(mb.position)
			return
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				if not _in_world():
					return
				_painting = true
				_erasing = mb.button_index == MOUSE_BUTTON_RIGHT or tool == Tool.ERASE
				_stroke_n = 0
				_deny_shown = false
				_last_cell = Vector2i(-1, -1)
				_apply_at(_mouse_cell(), true)
			else:
				_painting = false
	elif event is InputEventMouseMotion:
		if _panning:
			position += (event as InputEventMouseMotion).relative
			_clamp_view()
		_hover = _mouse_cell()
		if _painting:
			_apply_line(_last_cell, _hover)


func _in_world() -> bool:
	var p := _mouse_local
	if p.x < 0 or p.y < 0 or p.x >= world_size.x or p.y >= world_size.y:
		return false
	return visible_rect.has_point(get_global_transform() * p)


func _clamp_view() -> void:
	zoom = clampf(zoom, 1.0, 2.6)
	scale = Vector2(zoom, zoom)
	position.x = clampf(position.x, minf(0.0, visible_rect.size.x - world_size.x * zoom), 0.0)
	position.y = clampf(position.y, minf(0.0, visible_rect.size.y - world_size.y * zoom), 0.0)


func zoom_at(screen_pos: Vector2, factor: float) -> void:
	var local := (screen_pos - visible_rect.position - position) / zoom
	zoom = clampf(zoom * factor, 1.0, 2.6)
	position = screen_pos - visible_rect.position - local * zoom
	_clamp_view()


func reset_view() -> void:
	zoom = 1.0
	position = Vector2.ZERO
	_clamp_view()


func _apply_line(from: Vector2i, to: Vector2i) -> void:
	if from.x < 0:
		_apply_at(to, false)
		return
	var steps := maxi(absi(to.x - from.x), absi(to.y - from.y))
	for i in range(1, steps + 1):
		var k := float(i) / steps
		_apply_at(Vector2i(roundi(lerpf(from.x, to.x, k)), roundi(lerpf(from.y, to.y, k))), false)


func _surface_snap(c: Vector2i) -> Vector2i:
	if c.y < Cfg.SURFACE:
		return Vector2i(c.x, Cfg.SURFACE_ROW)
	return c


func _apply_at(raw: Vector2i, pressed: bool) -> void:
	var c := Vector2i(clampi(raw.x, 0, Cfg.W - 1), clampi(raw.y, 0, Cfg.H - 1))
	if c == _last_cell and not pressed:
		return
	_last_cell = c
	if _erasing:
		sim.cmd_erase(_surface_snap(c), 1)
		return
	match tool:
		Tool.INSPECT:
			if pressed:
				_select_at(_mouse_local)
		Tool.DIG:
			if sim.cmd_dig(c):
				actions["dig_cmds"] += 1
				_sound("click")
			elif sim.terrain.type_at(c) == Cfg.Cell.SOIL and not sim.terrain.dig_jobs.has(c) and not _deny_shown:
				_deny_shown = true
				_spawn_burst(Cfg.cell_center(c), Color("ff4a3a"), 6, 40.0)
				_sound("deny")
				sim.notify("Dig next to an existing tunnel: new tunnels must connect to the nest.", "warn")
		Tool.ROOM:
			if sim.cmd_room(c, tool_room):
				actions["room_cmds"] += 1
				_sound("click")
		Tool.PHERO:
			_paint_phero(c)
		Tool.ERASE:
			pass


func _paint_phero(c: Vector2i) -> void:
	var t := tool_phero
	var center := _surface_snap(c)
	var radius := 1 if t == Cfg.Phero.FOOD or t == Cfg.Phero.HOME else 2
	var value := 1.0
	if t == Cfg.Phero.FOOD or t == Cfg.Phero.HOME:
		# Ramp upward along the stroke so the trail has a direction.
		value = minf(1.0, 0.3 + 0.012 * _stroke_n)
	var painted := false
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var n := Vector2i(center.x + dx, center.y + dy)
			if sim.terrain.is_walkable(n):
				sim.cmd_phero(t, n, value)
				painted = true
	if painted:
		_stroke_n += 1
		var key: String = ["food_paint", "home_paint", "danger_paint", "attack_paint", "evac_paint"][t]
		actions[key] += 1
		if _stroke_n % 6 == 1:
			_sound("click")


func _sound(name: String) -> void:
	if sfx != null:
		sfx.play(name)


func set_tool(new_tool: int) -> void:
	tool = new_tool
	tool_changed.emit()


func set_room_tool(room: int) -> void:
	tool = Tool.ROOM
	tool_room = room
	tool_changed.emit()


func set_phero_tool(p: int) -> void:
	tool = Tool.PHERO
	tool_phero = p
	tool_changed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or sim == null:
		return
	match k.keycode:
		KEY_I:
			set_tool(Tool.INSPECT)
		KEY_D:
			set_tool(Tool.DIG)
		KEY_X:
			set_tool(Tool.ERASE)
		KEY_1:
			set_room_tool(Cfg.Room.ROYAL)
		KEY_2:
			set_room_tool(Cfg.Room.NURSERY)
		KEY_3:
			set_room_tool(Cfg.Room.STORAGE)
		KEY_4:
			set_room_tool(Cfg.Room.DRAIN)
		KEY_5:
			set_room_tool(Cfg.Room.NONE)
		KEY_Q:
			set_phero_tool(Cfg.Phero.FOOD)
		KEY_W:
			set_phero_tool(Cfg.Phero.HOME)
		KEY_E:
			set_phero_tool(Cfg.Phero.DANGER)
		KEY_R:
			set_phero_tool(Cfg.Phero.ATTACK)
		KEY_T:
			set_phero_tool(Cfg.Phero.EVACUATE)
		KEY_7:
			sim.colony.next_caste = Cfg.Caste.WORKER
			tool_changed.emit()
		KEY_8:
			sim.colony.next_caste = Cfg.Caste.NURSE
			tool_changed.emit()
		KEY_9:
			sim.colony.next_caste = Cfg.Caste.SOLDIER
			tool_changed.emit()
		KEY_HOME:
			reset_view()
		KEY_LEFT:
			position.x += 60.0
			_clamp_view()
		KEY_RIGHT:
			position.x -= 60.0
			_clamp_view()
		KEY_UP:
			position.y += 60.0
			_clamp_view()
		KEY_DOWN:
			position.y -= 60.0
			_clamp_view()
		KEY_SPACE:
			paused = not paused
			tool_changed.emit()
		KEY_TAB:
			speed = 2.0 if speed == 1.0 else (4.0 if speed == 2.0 else 1.0)
			tool_changed.emit()


# --- Selection -------------------------------------------------------------------------------------------------

func _select_at(p: Vector2) -> void:
	var best: Variant = null
	var best_d := 18.0
	if sim.spider != null and sim.spider.pos.distance_to(p) < 34.0:
		best = sim.spider
		best_d = 0.0
	if best == null:
		for a in sim.ants:
			var d := a.pos.distance_to(p)
			if d < best_d:
				best_d = d
				best = a
	if best == null:
		for b in sim.brood:
			var d2 := Cfg.cell_center(b.cell).distance_to(p)
			if d2 < 14.0 and d2 < best_d:
				best_d = d2
				best = b
	if best == null:
		for s in sim.sources:
			var sx := (s.cell.x + 0.5) * Cfg.CELL
			if absf(sx - p.x) < 28.0 and p.y < Cfg.SURFACE * Cfg.CELL + 4 and p.y > Cfg.SURFACE * Cfg.CELL - 50:
				best = s
				break
	if best == null:
		best = Cfg.world_to_cell(p)
	selected = best
	selection_changed.emit()


func describe_selection() -> String:
	if sim == null:
		return ""
	var s: Variant = selected
	if s is Ant:
		var a: Ant = s
		if a.state == Cfg.State.DEAD:
			return "%s (dead)" % a.caste_name()
		var load_txt := "nothing"
		if a.load_type == Cfg.Load.FOOD:
			load_txt = "%.1f leaf food" % a.load_amount
		elif a.load_type == Cfg.Load.WATER:
			load_txt = "%.1f water" % a.load_amount
		var extra := ""
		if a.lost_until > sim.t:
			extra = "\nLost (rain washed the scent away)"
		if a.state == Cfg.State.FLEE:
			extra += "\nFleeing from: " + a.flee_reason
		return "[b]%s[/b] #%d\nTask: %s\nHealth: %d/%d\nCarrying: %s%s" % [a.caste_name(), a.id, Cfg.STATE_NAMES[a.state], a.hp, a.max_hp, load_txt, extra]
	if s is Brood:
		var b: Brood = s
		return "[b]%s[/b] (future %s)\nProgress: %d%%\nCare: %d%%\nHealth: %d\nRoom: %s\n[i]Click a caste button, then re-select to change the target caste while egg/larva.[/i]" % [b.stage_name(), Cfg.CASTE_NAMES[b.caste], b.progress * 100.0, b.care * 100.0, b.hp, Cfg.ROOM_NAMES[sim.terrain.room_at(b.cell)]]
	if s is Spider:
		var sp: Spider = s
		return "[b]Spider[/b] (level %d)\nHealth: %d/%d\nKills: %d\nBehaviour: %s" % [sp.power, sp.hp, sp.max_hp, sp.kills, Spider.S.keys()[sp.state].capitalize()]
	if s is FoodSource:
		var fs: FoodSource = s
		if fs.kind == Cfg.SrcKind.WATER:
			return "[b]Water source[/b]\n%s" % ("Pond: never runs dry" if fs.infinite else "Rain puddle: %.1f left" % fs.amount)
		return "[b]Leaf plant[/b]\nLeaves: %d/%d\nRegrows slowly.\n%s" % [fs.amount, fs.max_amount, "Discovered" if fs.discovered else "Not yet found by ants"]
	if s is Vector2i:
		var c: Vector2i = s
		var tr := sim.terrain
		var name: String = ["Air", "Soil", "Rock", "Tunnel"][tr.type_at(c)]
		var txt := "[b]%s[/b] (%d, %d)" % [name, c.x, c.y]
		if tr.type_at(c) == Cfg.Cell.TUNNEL:
			txt += "\nRoom: %s\nWater: %d%%" % [Cfg.ROOM_NAMES[tr.room_at(c)], tr.water_at(c) * 100.0]
		for t in 5:
			var v := sim.pher.get_v(t, c)
			if v > 0.02:
				txt += "\n%s pheromone: %d%%" % [Cfg.PHERO_NAMES[t], v * 100.0]
		return txt
	return ""


# --- Effects -----------------------------------------------------------------------------------------------------

func _on_notified(_text: String, kind: String) -> void:
	if kind == "danger" and _alert_cd <= 0.0:
		_alert_cd = 2.0
		_sound("alert")


func _on_fx(kind: String, pos: Vector2) -> void:
	if _particles.size() > 400:
		return
	match kind:
		"dust":
			_spawn_burst(pos, Color("a37a52"), 5, 36.0)
			_sound("dig")
		"deliver":
			_spawn_burst(pos + Vector2(0, -8), Color("9be25e"), 5, 26.0)
			_sound("deliver")
		"hit":
			_spawn_burst(pos, Color("fff1c0"), 4, 50.0)
			_sound("hit")
		"bite":
			_spawn_burst(pos, Color("e03a2e"), 6, 50.0)
		"death":
			_spawn_burst(pos, Color("3a2a22"), 7, 40.0)
		"birth":
			_spawn_burst(pos, Color("ffe36a"), 8, 45.0)
			_sound("birth")


func _spawn_burst(pos: Vector2, col: Color, n: int, spd: float) -> void:
	for i in n:
		var ang := randf() * TAU
		var v := Vector2(cos(ang), sin(ang) - 0.5) * spd * randf_range(0.4, 1.0)
		_particles.append({"p": pos, "v": v, "life": randf_range(0.4, 0.9), "max": 0.9, "c": col, "s": randf_range(1.5, 3.0)})


func _update_particles(dt: float) -> void:
	var keep: Array[Dictionary] = []
	for q in _particles:
		q["life"] -= dt
		if q["life"] > 0.0:
			q["v"].y += 90.0 * dt
			q["p"] += q["v"] * dt
			keep.append(q)
	_particles = keep


# --- Drawing -----------------------------------------------------------------------------------------------------

func _light() -> float:
	var f := sim.day_fraction()
	var l := 1.0
	if f < 0.04:
		l = lerpf(0.25, 1.0, f / 0.04)
	elif f < 0.66:
		l = 1.0
	elif f < 0.78:
		l = lerpf(1.0, 0.25, (f - 0.66) / 0.12)
	elif f < 0.96:
		l = 0.25
	else:
		l = lerpf(0.25, 1.0, (f - 0.96) / 0.04)
	return l * (1.0 - 0.3 * sim.weather.rain)


func _draw() -> void:
	if sim == null:
		return
	var alpha := get_alpha()
	var light := _light()
	var gy := float(Cfg.SURFACE * Cfg.CELL)
	var wpx := world_size.x
	_draw_sky(light, gy, wpx)
	if _terrain_tex != null:
		draw_texture(_terrain_tex, Vector2.ZERO)
	draw_texture(_deco_tex, Vector2(0, gy - 37.0))
	_draw_sources(gy)
	_draw_storage()
	_draw_dig_jobs()
	_draw_brood(alpha)
	_draw_water()
	_draw_pheromones()
	_draw_ants(alpha)
	_draw_spider(alpha)
	_draw_weather(gy, wpx)
	# Night / storm tint: strong above ground, gentle underground.
	var dark := (1.0 - light) * 0.55
	draw_rect(Rect2(0, 0, wpx, gy), Color(0.02, 0.04, 0.14, dark))
	draw_rect(Rect2(0, gy, wpx, world_size.y - gy), Color(0.02, 0.03, 0.1, dark * 0.2))
	for q in _particles:
		var c: Color = q["c"]
		c.a = clampf(q["life"] / q["max"], 0.0, 1.0)
		draw_rect(Rect2(q["p"] - Vector2(q["s"], q["s"]) * 0.5, Vector2(q["s"], q["s"])), c)
	_draw_cursor()


func _draw_sky(light: float, gy: float, wpx: float) -> void:
	var f := sim.day_fraction()
	var top := Color("4f9fe0").lerp(Color("0a1030"), 1.0 - light)
	var bottom := Color("c4e6f4").lerp(Color("26325c"), 1.0 - light)
	if f > 0.62 and f < 0.82:
		bottom = bottom.lerp(Color("f2a566"), 0.55 * sin((f - 0.62) / 0.2 * PI))
	var gray := Color("727a86")
	top = top.lerp(gray, sim.weather.rain * 0.7)
	bottom = bottom.lerp(gray.lightened(0.15), sim.weather.rain * 0.6)
	var strips := 28
	for i in strips:
		var y0 := gy * i / strips
		draw_rect(Rect2(0, y0, wpx, gy / strips + 1.0), top.lerp(bottom, float(i) / strips))
	# Sun and moon along an arc.
	var sun_t := clampf((f - 0.02) / 0.74, 0.0, 1.0)
	if f > 0.02 and f < 0.78:
		var sp := Vector2(lerpf(60.0, wpx - 60.0, sun_t), gy - 60.0 - sin(sun_t * PI) * (gy - 90.0))
		draw_circle(sp, 22.0, Color("fff2b0", 0.35 * (1.0 - sim.weather.rain)))
		draw_circle(sp, 14.0, Color("ffe06a", 1.0 - sim.weather.rain * 0.9))
	else:
		var mt := fposmod(f - 0.78, 1.0) / 0.24
		var mp := Vector2(lerpf(100.0, wpx - 100.0, clampf(mt, 0.0, 1.0)), gy - 70.0 - sin(clampf(mt, 0.0, 1.0) * PI) * (gy - 120.0))
		draw_circle(mp, 12.0, Color("e8eefc", 0.9 * (1.0 - sim.weather.rain)))
		draw_circle(mp + Vector2(4, -2), 10.0, Color(top.r, top.g, top.b, 0.85))
	draw_colored_polygon(_hills_far, Color("5d8f78").lerp(Color("141c30"), 1.0 - light))
	draw_colored_polygon(_hills_near, Color("4b8553").lerp(Color("101a24"), 1.0 - light))
	for cl in _clouds:
		cl["x"] = fposmod(cl["x"] + cl["v"] * 0.016, wpx + 200.0)
		var cx: float = cl["x"] - 100.0
		var cy: float = cl["y"]
		var s: float = cl["s"]
		var cc := Color.WHITE.lerp(Color("5c6370"), sim.weather.rain * 0.9).lerp(Color("141a34"), 1.0 - light)
		cc.a = 0.9
		draw_rect(Rect2(cx, cy, 60 * s, 12 * s), cc)
		draw_rect(Rect2(cx + 10 * s, cy - 8 * s, 40 * s, 10 * s), cc)
		draw_rect(Rect2(cx + 22 * s, cy - 14 * s, 18 * s, 8 * s), cc)
		draw_rect(Rect2(cx - 8 * s, cy + 4 * s, 20 * s, 8 * s), cc)


func _draw_sources(gy: float) -> void:
	for s in sim.sources:
		var cx := (s.cell.x + 0.5) * Cfg.CELL
		if s.kind == Cfg.SrcKind.FOOD:
			var frac := s.amount / s.max_amount
			var level := 3 if frac > 0.66 else (2 if frac > 0.33 else (1 if frac > 0.05 else 0))
			var tex := Sprites.bush(level)
			draw_texture(tex, Vector2(cx - tex.get_width() * 0.5, gy - tex.get_height() + 3))
		elif s.infinite:
			var x0 := cx - 56.0
			draw_rect(Rect2(x0, gy - 7, 112, 8), Color("2f6fa8"))
			draw_rect(Rect2(x0 + 8, gy - 9, 96, 4), Color("4f95cc"))
			for i in 5:
				var rx := x0 + 14 + i * 20 + sin(_time * 1.5 + i) * 3.0
				draw_rect(Rect2(rx, gy - 8, 8, 1), Color("a8d8f4"))
			for i in 4:
				var bx := x0 + 4 + i * 34
				draw_line(Vector2(bx, gy), Vector2(bx + 1, gy - 20 - i % 2 * 6), Color("4a7f3a"), 2.0)
				draw_rect(Rect2(bx - 1, gy - 26 - i % 2 * 6, 4, 8), Color("7a5230"))
		elif s.amount > 0.5:
			var r := clampf(s.amount / 14.0, 0.2, 1.0)
			draw_rect(Rect2(cx - 24 * r, gy - 4, 48 * r, 5), Color("4f95cc"))
			draw_rect(Rect2(cx - 20 * r, gy - 5, 40 * r, 2), Color("a8d8f4"))


func _draw_storage() -> void:
	var store := sim.room_list(Cfg.Room.STORAGE)
	if store.is_empty():
		return
	var total := int(sim.colony.food / maxf(sim.colony.food_cap, 1.0) * store.size() * 4.0)
	var leaf := Sprites.leaf_piece()
	for i in mini(total, store.size() * 4):
		var c := store[i % store.size()]
		var k := i / store.size()
		var px := c.x * Cfg.CELL + 2 + (k % 2) * 7
		var py := (c.y + 1) * Cfg.CELL - 8 - (k / 2) * 3
		draw_texture(leaf, Vector2(px, py), Color(1, 1, 1, 1))


func _draw_dig_jobs() -> void:
	for c in sim.terrain.dig_jobs:
		var job: Dictionary = sim.terrain.dig_jobs[c]
		var r := Rect2(c.x * Cfg.CELL, c.y * Cfg.CELL, Cfg.CELL, Cfg.CELL)
		draw_rect(r, Color(1, 0.75, 0.25, 0.18))
		draw_rect(r.grow(-1), Color(1, 0.78, 0.3, 0.9), false, 1.0)
		var frac := clampf(job["progress"] / sim.terrain.hardness(c.y), 0.0, 1.0)
		if frac > 0.0:
			draw_rect(Rect2(r.position.x + 1, r.end.y - 4, (Cfg.CELL - 2) * frac, 3), Color("ffd24a"))


func _draw_brood(_alpha: float) -> void:
	var caste_colors := [Color.WHITE, Color("e0873f"), Color("e8c04a"), Color("c8382a")]
	for b in sim.brood:
		var off := Vector2(float(Sprites._hash(b.id, 1, 2) % 9) - 4.0, 0.0)
		var tex := Sprites.brood_tex(b.stage)
		var pos := Cfg.cell_center(b.cell) + off
		if b.carrier != null:
			pos = b.carrier.pos + Vector2(b.carrier.facing * 6.0, -9.0)
		else:
			pos += Vector2(0, 8.0 - tex.get_height() * 0.5)
		draw_texture(tex, pos - tex.get_size() * 0.5)
		# Dot = the caste this brood will become; bar = development progress.
		var caste_col: Color = caste_colors[b.caste]
		draw_rect(Rect2(pos.x - 1.5, pos.y - tex.get_height() * 0.5 - 4, 3, 3), caste_col)
		draw_rect(Rect2(pos.x - 6, pos.y + tex.get_height() * 0.5 + 1, 12 * b.progress, 1), Color("9be25e"))
		if selected == b:
			draw_arc(pos, 9.0, 0.0, TAU, 16, Color("ffe36a"), 1.5)


func _draw_water() -> void:
	var tr := sim.terrain
	for c in sim.flood.wet:
		var w: float = clampf(tr.water[tr.idx(c)], 0.0, 1.0)
		if w < 0.02:
			continue
		var h := Cfg.CELL * w
		var r := Rect2(c.x * Cfg.CELL, (c.y + 1) * Cfg.CELL - h, Cfg.CELL, h)
		draw_rect(r, Color(0.22, 0.52, 0.92, 0.55))
		draw_rect(Rect2(r.position.x, r.position.y, Cfg.CELL, 2), Color(0.7, 0.88, 1.0, 0.7))


func _draw_pheromones() -> void:
	var tool_active := tool == Tool.PHERO
	for t in 5:
		var a_mul := 0.34 if tool_active and t == tool_phero else (0.2 if tool_active else 0.14)
		if t == Cfg.Phero.HOME and not (tool_active and t == tool_phero):
			a_mul *= 0.35
		var col: Color = PHERO_COLORS[t]
		for c in sim.pher.active[t]:
			var v: float = sim.pher.fields[t][c.y * Cfg.W + c.x]
			var r := Rect2(c.x * Cfg.CELL + 3, c.y * Cfg.CELL + 3, Cfg.CELL - 6, Cfg.CELL - 6)
			draw_rect(r, Color(col.r, col.g, col.b, clampf(v, 0.0, 1.0) * (a_mul + 0.35)))
			# Direction arrow: points toward the stronger neighbouring cell.
			if t != Cfg.Phero.DANGER and t != Cfg.Phero.EVACUATE and (c.x + c.y) % 2 == 0 and v > 0.12:
				var best := Vector2i.ZERO
				var best_v := v + 0.03
				for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var nv := sim.pher.get_v(t, c + d)
					if nv > best_v:
						best_v = nv
						best = d
				if best != Vector2i.ZERO:
					var ctr := Cfg.cell_center(c)
					var dir := Vector2(best)
					var tip := ctr + dir * 5.0
					draw_line(ctr - dir * 4.0, tip, Color(1, 1, 1, 0.8), 1.0)
					draw_line(tip, tip - dir * 3.0 + Vector2(-dir.y, dir.x) * 2.0, Color(1, 1, 1, 0.8), 1.0)
					draw_line(tip, tip - dir * 3.0 - Vector2(-dir.y, dir.x) * 2.0, Color(1, 1, 1, 0.8), 1.0)


func _ant_scale(caste: int) -> float:
	match caste:
		Cfg.Caste.QUEEN:
			return 1.0
		Cfg.Caste.SOLDIER:
			return 0.82
	return 0.78


func _draw_ants(alpha: float) -> void:
	for a in sim.ants:
		if a.state == Cfg.State.DEAD:
			continue
		var p := a.prev_pos.lerp(a.pos, alpha)
		var frames := Sprites.ant_frames(a.caste)
		var tex: Texture2D = frames[int(a.anim) % 4] if a.moving else frames[0]
		var sc := _ant_scale(a.caste)
		var rot := 0.0
		var face := a.facing
		if a.moving and absf(a.move_dir.y) > 0.85:
			rot = -PI * 0.5 if a.move_dir.y < 0 else PI * 0.5
			face = 1
		var foot := Vector2(0, 3.5 if rot == 0.0 else 0.0)
		draw_set_transform(p + foot, rot, Vector2(face * sc, sc))
		var mod := Color(1, 0.55, 0.55) if a.damage_flash > 0.0 else Color.WHITE
		draw_texture(tex, -tex.get_size() * 0.5, mod)
		if a.load_type == Cfg.Load.FOOD:
			var lt := Sprites.leaf_piece()
			draw_texture(lt, Vector2(-lt.get_width() * 0.5 - 2, -tex.get_height() * 0.5 - lt.get_height() + 3))
		elif a.load_type == Cfg.Load.WATER:
			var dt := Sprites.droplet()
			draw_texture(dt, Vector2(-dt.get_width() * 0.5 - 2, -tex.get_height() * 0.5 - dt.get_height() + 3))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_draw_ant_icon(a, p)
		if selected == a:
			draw_arc(p, 13.0, 0.0, TAU, 20, Color("ffe36a"), 1.5)


func _draw_ant_icon(a: Ant, p: Vector2) -> void:
	var icon := ""
	var col := Color.WHITE
	if a.state == Cfg.State.FLEE and a.flee_reason == "danger":
		icon = "!"
		col = Color("ff5040")
	elif a.state == Cfg.State.FLEE:
		icon = "~" if a.flee_reason == "water" else ">"
		col = Color("5fb8f0") if a.flee_reason == "water" else Color("fff27a")
	elif a.state == Cfg.State.FOLLOW_TRAIL:
		icon = "+"
		col = Color("6fe04a")
	elif a.state == Cfg.State.ATTACK and a.caste == Cfg.Caste.SOLDIER:
		icon = "x"
		col = Color("ffae2b")
	elif a.lost_until > sim.t and a.caste != Cfg.Caste.QUEEN:
		icon = "?"
		col = Color("4aa8ff")
	if icon != "":
		draw_string(_font, p + Vector2(-3, -13), icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.BLACK)
		draw_string(_font, p + Vector2(-4, -14), icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)


func _draw_spider(alpha: float) -> void:
	var sp := sim.spider
	if sp == null or sp.state == Spider.S.DEAD:
		return
	var p := sp.prev_pos.lerp(sp.pos, alpha)
	var frames := Sprites.spider_frames()
	var tex: Texture2D = frames[int(sp.anim) % 4] if sp.moving else frames[0]
	var sc := 0.95
	draw_circle(p, 46.0, Color(1, 0.1, 0.05, 0.10 + 0.05 * sin(_time * 6.0)))
	draw_set_transform(p + Vector2(0, -6), 0.0, Vector2(sp.facing * sc, sc))
	draw_texture(tex, -tex.get_size() * 0.5, Color(1, 0.6, 0.6) if sp.flash > 0.0 else Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var bw := 36.0
	draw_rect(Rect2(p.x - bw * 0.5, p.y - 44, bw, 4), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(p.x - bw * 0.5, p.y - 44, bw * clampf(sp.hp / sp.max_hp, 0.0, 1.0), 4), Color("e0452f"))
	if selected == sp:
		draw_arc(p, 36.0, 0.0, TAU, 28, Color("ffe36a"), 1.5)


func _draw_weather(gy: float, wpx: float) -> void:
	var rain := sim.weather.rain
	if rain > 0.03:
		var n := int(rain * 220.0)
		for i in n:
			var x := fposmod(i * 37.7 + _time * 60.0, wpx)
			var y := fposmod(i * 91.3 + _time * 520.0, gy)
			draw_line(Vector2(x, y), Vector2(x - 3, y + 9), Color(0.72, 0.84, 1.0, 0.55), 1.0)
		for i in int(rain * 40.0):
			var sx := fposmod(i * 173.1 + floor(_time * 6.0) * 53.0, wpx)
			draw_rect(Rect2(sx - 2, gy - 2, 5, 1), Color(0.8, 0.9, 1.0, 0.7))
		for o in sim.terrain.openings():
			for k in 3:
				var dy := fposmod(_time * 120.0 + k * 17.0, 60.0)
				draw_rect(Rect2(o.x * Cfg.CELL + 4 + k * 3, gy + dy, 1, 4), Color(0.7, 0.85, 1.0, 0.6))


func _draw_cursor() -> void:
	if not _in_world():
		return
	var c := _mouse_cell()
	var r := Rect2(c.x * Cfg.CELL, c.y * Cfg.CELL, Cfg.CELL, Cfg.CELL)
	match tool:
		Tool.DIG:
			var ok := sim.terrain.can_designate_dig(c)
			draw_rect(r, Color(0.3, 1, 0.4, 0.25) if ok else Color(1, 0.3, 0.3, 0.2))
			draw_rect(r, Color(0.5, 1, 0.5) if ok else Color(1, 0.4, 0.4), false, 1.0)
		Tool.ROOM:
			var ok2 := sim.terrain.type_at(c) == Cfg.Cell.TUNNEL and c.y >= Cfg.SURFACE
			draw_rect(r, Color(0.9, 0.8, 0.4, 0.3) if ok2 else Color(1, 0.3, 0.3, 0.2))
		Tool.PHERO:
			var col: Color = PHERO_COLORS[tool_phero]
			var rad := 1 if tool_phero <= Cfg.Phero.HOME else 2
			var cc := _surface_snap(c)
			draw_rect(Rect2((cc.x - rad) * Cfg.CELL, (cc.y - rad) * Cfg.CELL, (rad * 2 + 1) * Cfg.CELL, (rad * 2 + 1) * Cfg.CELL), Color(col.r, col.g, col.b, 0.2))
			draw_rect(Rect2((cc.x - rad) * Cfg.CELL, (cc.y - rad) * Cfg.CELL, (rad * 2 + 1) * Cfg.CELL, (rad * 2 + 1) * Cfg.CELL), Color(col.r, col.g, col.b, 0.8), false, 1.0)
		Tool.ERASE:
			draw_rect(Rect2((c.x - 1) * Cfg.CELL, (c.y - 1) * Cfg.CELL, 3 * Cfg.CELL, 3 * Cfg.CELL), Color(1, 1, 1, 0.8), false, 1.0)
		_:
			draw_rect(r, Color(1, 1, 1, 0.5), false, 1.0)
