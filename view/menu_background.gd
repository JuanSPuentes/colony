class_name MenuBackground
extends Control
## Fondo animado del menú principal: cielo con sol, nubes a la deriva, dos capas de montañas,
## una franja de tierra con un hormiguero y hormigas caminando (algunas cargan una hoja), y
## lluvia que entra y sale cada tanto. Todo dibujado a mano con `_draw()`, sin texturas ni
## assets externos (ver README: "sin descargas, sin red, sin assets externos").

const SKY_TOP := Color("3f6f9e")
const SKY_HORIZON := Color("bcd9e8")
const SUN_COLOR := Color("ffe9a8")
const MOUNTAIN_FAR := Color("6d7a63")
const MOUNTAIN_NEAR := Color("4a5640")
const GROUND_COLOR := Color("6b4a2f")
const GROUND_DARK := Color("4a311e")
const MOUND_COLOR := Color("5a3d26")
const ANT_COLOR := Color("1a120d")
const LEAF_COLOR := Color("5fe05f")
const CLOUD_COLOR := Color(1.0, 1.0, 1.0, 0.85)
const RAIN_COLOR := Color(0.65, 0.78, 0.92, 0.6)

class Cloud:
	var x := 0.0
	var y := 0.0
	var scale := 1.0
	var speed := 0.01

class Walker:
	var x := 0.5
	var dir := 1.0
	var speed := 0.015
	var carrying := false
	var min_x := 0.0
	var max_x := 1.0

## Perfil de cada capa de montaña, normalizado (x 0..1, alto 0..1); se calcula una sola vez en
## `_ready` con una suma de senos (determinista, no aleatorio) para que no "tiemble" cada frame.
var _far_profile: PackedFloat32Array
var _near_profile: PackedFloat32Array
const PROFILE_N := 48

var _clouds: Array[Cloud] = []
var _ants: Array[Walker] = []
var _rain_drops: PackedVector2Array = []
var _raining := false
var _rain_timer := 10.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_far_profile = _make_profile(0.35, 0.5, [1.3, 2.7, 0.6])
	_near_profile = _make_profile(0.22, 0.9, [0.8, 2.1, 3.4])
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261016
	for i in 5:
		var c := Cloud.new()
		c.x = rng.randf_range(0.0, 1.0)
		c.y = rng.randf_range(0.05, 0.28)
		c.scale = rng.randf_range(0.6, 1.3)
		c.speed = rng.randf_range(0.006, 0.016)
		_clouds.append(c)
	# Las franjas [0.03, 0.32] y [0.68, 0.97] dejan libre la columna central, donde van los botones
	# del menú (ver `_option` en main_menu.gd), para que ninguna hormiga quede detrás de un botón.
	for i in 6:
		var w := Walker.new()
		var left_side := i % 2 == 0
		w.min_x = 0.03 if left_side else 0.68
		w.max_x = 0.32 if left_side else 0.97
		w.x = rng.randf_range(w.min_x, w.max_x)
		w.dir = 1.0 if rng.randf() > 0.5 else -1.0
		w.speed = rng.randf_range(0.015, 0.035)
		w.carrying = rng.randf() > 0.55
		_ants.append(w)
	set_process(true)


## Suma unas pocas ondas senoidales para un perfil de montañas que no se ve perfectamente
## periódico. `freqs` son las frecuencias relativas de cada onda.
func _make_profile(base: float, amp: float, freqs: Array) -> PackedFloat32Array:
	var p := PackedFloat32Array()
	p.resize(PROFILE_N + 1)
	for i in p.size():
		var x := float(i) / PROFILE_N
		var h := base
		for k in freqs.size():
			h += amp / (k + 2.0) * sin(x * TAU * freqs[k] + freqs[k])
		p[i] = clampf(h, 0.05, 1.0)
	return p


func _process(delta: float) -> void:
	for c in _clouds:
		c.x += c.speed * delta
		if c.x > 1.2:
			c.x = -0.2
	for w in _ants:
		w.x += w.dir * w.speed * delta
		if w.x > w.max_x:
			w.dir = -1.0
		elif w.x < w.min_x:
			w.dir = 1.0
	_rain_timer -= delta
	if _rain_timer <= 0.0:
		_raining = not _raining
		_rain_timer = 7.0 if _raining else randf_range(12.0, 22.0)
	if _raining and randf() < 0.9:
		_rain_drops.append(Vector2(randf(), 0.0))
	for i in range(_rain_drops.size() - 1, -1, -1):
		_rain_drops[i].y += delta * 1.3
		if _rain_drops[i].y > 1.0:
			_rain_drops.remove_at(i)
	queue_redraw()


func _draw() -> void:
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	var horizon := s.y * 0.66

	const BANDS := 20
	for b in BANDS:
		var t0 := float(b) / BANDS
		var t1 := float(b + 1) / BANDS
		draw_rect(Rect2(0.0, horizon * t0, s.x, horizon * (t1 - t0) + 1.0), SKY_TOP.lerp(SKY_HORIZON, t1), true)

	var sun_pos := Vector2(s.x * 0.8, s.y * 0.16)
	draw_circle(sun_pos, s.y * 0.075, Color(SUN_COLOR, 0.22))
	draw_circle(sun_pos, s.y * 0.045, SUN_COLOR)

	_draw_mountains(s, horizon, _far_profile, 0.16, MOUNTAIN_FAR)
	_draw_mountains(s, horizon, _near_profile, 0.1, MOUNTAIN_NEAR)

	draw_rect(Rect2(0.0, horizon, s.x, s.y - horizon), GROUND_COLOR, true)
	draw_rect(Rect2(0.0, horizon, s.x, 3.0), GROUND_DARK, true)
	_draw_mound(Vector2(s.x * 0.17, horizon))

	for w in _ants:
		_draw_ant(Vector2(w.x * s.x, horizon + 14.0 + sin(w.x * 30.0) * 2.0), w.dir, w.carrying)
	for c in _clouds:
		_draw_cloud(Vector2(c.x * s.x, c.y * s.y), c.scale * s.y * 0.05)
	for d in _rain_drops:
		var p0 := Vector2(d.x * s.x, d.y * horizon)
		draw_line(p0, p0 + Vector2(-4.0, 12.0), RAIN_COLOR, 1.5)


func _draw_mountains(s: Vector2, horizon: float, profile: PackedFloat32Array, max_h_frac: float, color: Color) -> void:
	var pts := PackedVector2Array()
	pts.append(Vector2(0.0, horizon))
	for i in profile.size():
		var x := s.x * float(i) / PROFILE_N
		var y := horizon - profile[i] * s.y * max_h_frac
		pts.append(Vector2(x, y))
	pts.append(Vector2(s.x, horizon))
	draw_colored_polygon(pts, color)


## Montículo de tierra removida junto a la entrada del hormiguero: un triángulo suavizado con un
## hueco oscuro encima, el mismo motivo que usa `WorldGrid`/`TerrainView` para la entrada del nido.
func _draw_mound(base: Vector2) -> void:
	var w := 26.0
	var h := 16.0
	var pts := PackedVector2Array([
		base + Vector2(-w, 0.0), base + Vector2(-w * 0.5, -h), base + Vector2(0.0, -h * 1.15),
		base + Vector2(w * 0.5, -h), base + Vector2(w, 0.0),
	])
	draw_colored_polygon(pts, MOUND_COLOR)
	draw_circle(base + Vector2(0.0, -h * 0.5), 4.0, GROUND_DARK)


## Silueta chica de 3 lóbulos (igual de espíritu que `AntRenderer.BODY_POINTS`, pero sin
## triangular: a este tamaño un polígono convexo dibujado directo alcanza).
func _draw_ant(pos: Vector2, dir: float, carrying: bool) -> void:
	var pts := PackedVector2Array([
		Vector2(7.0, 0.0), Vector2(4.0, 2.2), Vector2(-1.0, 3.0), Vector2(-5.5, 1.8),
		Vector2(-8.0, 0.0), Vector2(-5.5, -1.8), Vector2(-1.0, -3.0), Vector2(4.0, -2.2),
	])
	if dir < 0.0:
		for i in pts.size():
			pts[i].x = -pts[i].x
	for i in pts.size():
		pts[i] += pos
	draw_colored_polygon(pts, ANT_COLOR)
	if carrying:
		draw_circle(pos + Vector2(0.0, -6.0), 2.2, LEAF_COLOR)


func _draw_cloud(center: Vector2, r: float) -> void:
	for off in [Vector2(-r * 1.1, 0.0), Vector2(r * 1.1, 0.0), Vector2(0.0, -r * 0.4),
			Vector2(-r * 0.4, r * 0.3), Vector2(r * 0.4, r * 0.3)]:
		draw_circle(center + off, r * 0.75, CLOUD_COLOR)
