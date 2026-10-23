class_name SkyView
extends Node2D
## Fase 16: cielo vivo, dibujado por código (antes un rectángulo celeste plano en `TerrainView`).
## Degradado que cambia con la hora (cálido al amanecer y al atardecer), sol y luna que cruzan el
## cielo, estrellas de noche y nubes que se mueven y se vuelven más grises y numerosas cuando se
## acerca la lluvia (así el aviso de lluvia también se ve, no solo se lee en el panel).
##
## Va primero dentro del SubViewport del mundo (detrás del terreno, las plantas y las hormigas).
## Sol, luna, estrellas y nubes se dibujan contra el rectángulo VISIBLE de la cámara, no contra el
## mundo entero: están "lejos", no se acercan ni se alejan con el zoom ni pasan de largo al mover la
## cámara. La oscuridad de la noche la sigue poniendo `DayNightView` (CanvasModulate) encima.

const DAY_TOP := Color(0.30, 0.55, 0.92)
const DAY_BOTTOM := Color(0.66, 0.84, 0.97)
const WARM_TOP := Color(0.55, 0.45, 0.75)
const WARM_BOTTOM := Color(1.0, 0.60, 0.38)
const STORM_TOP := Color(0.36, 0.40, 0.46)
const STORM_BOTTOM := Color(0.56, 0.60, 0.64)
const SUN := Color(1.0, 0.93, 0.62)
const MOON := Color(0.93, 0.94, 1.0)
const CLOUD := Color(1.0, 1.0, 1.0, 0.9)
const CLOUD_STORM := Color(0.52, 0.55, 0.60, 0.95)
const BANDS := 14
const STAR_COUNT := 60
const CLOUD_COUNT := 12

var sim: Simulation
var _stars := PackedVector3Array()   # x, y normalizados (0..1) + brillo
var _clouds: Array[Vector4] = []     # x, y normalizados, escala, velocidad
## Escala para que sol, nubes y estrellas midan lo mismo en pantalla con cualquier zoom.
var _k := 1.0
var _last_tick := -1
var _still := 0.0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	for k in STAR_COUNT:
		_stars.append(Vector3(rng.randf(), rng.randf_range(0.0, 0.85), rng.randf_range(0.4, 1.0)))
	for k in CLOUD_COUNT:
		_clouds.append(Vector4(rng.randf(), rng.randf_range(0.08, 0.5), rng.randf_range(0.7, 1.4), rng.randf_range(0.004, 0.012)))


func setup(s: Simulation) -> void:
	sim = s
	queue_redraw()


func _process(delta: float) -> void:
	if sim == null:
		return
	queue_redraw()  # la cámara puede moverse aunque el juego esté en pausa
	# En pausa (la simulación no avanzó) las nubes se quedan quietas.
	if sim.tick_count != _last_tick:
		_last_tick = sim.tick_count
		_still = 0.0
	else:
		_still += delta
	if _still > 0.2:
		return
	# Las nubes avanzan más rápido con tormenta (viento). Tiempo real: es solo decoración.
	var wind := 1.0 + 2.5 * storm(sim)
	for k in _clouds.size():
		var c := _clouds[k]
		c.x = fposmod(c.x + c.w * wind * delta, 1.3)
		_clouds[k] = c
	queue_redraw()


## Qué tan "tormentoso" está el cielo, de 0 (despejado) a 1 (lloviendo). Crece durante el aviso y
## se apaga al final de la lluvia, para que el cambio no sea de golpe. Lo leen también `RainView` y
## `DayNightView`.
static func storm(s: Simulation) -> float:
	match s.weather:
		Simulation.Weather.WARNING:
			var eta := s.rain_eta_s()
			return 0.65 * clampf(1.0 - eta / maxf(s.cfg.rain_warning_s, 0.01), 0.0, 1.0)
		Simulation.Weather.RAINING:
			var left := (s.rain_end_tick - s.tick_count) * s.dt
			return clampf(0.65 + left / 3.0, 0.65, 1.0)
	return 0.0


## Hora del día para el cielo: fase (0 amanecer .. 1 fin de la noche) y luz (0..1). Fuera del modo
## incremental no hay ciclo de día y noche (`DayNightView` no tiñe nada): mediodía fijo.
static func sky_time(s: Simulation) -> Vector2:
	if not s.incremental:
		return Vector2(0.3, 1.0)
	return Vector2(DayNight.phase(s.time_s(), s.cfg), DayNight.light(s.time_s(), s.cfg))


## Rectángulo del mundo que se ve en pantalla ahora mismo.
func visible_world_rect() -> Rect2:
	return get_canvas_transform().affine_inverse() * get_viewport_rect()


func _draw() -> void:
	if sim == null:
		return
	var cpx := sim.cfg.cell_px
	var vr := visible_world_rect()
	var ground_y := float(sim.cfg.surface_y * cpx)
	_k = vr.size.x / 480.0
	var top := vr.position.y
	var bottom := minf(ground_y, vr.end.y)
	if bottom <= top:
		return  # la cámara mira solo bajo tierra
	var t := sky_time(sim)
	var light := t.y
	var st := storm(sim)
	var warm := 4.0 * light * (1.0 - light)  # pico en mitad del amanecer/atardecer

	# Degradado: el alto de referencia es el del cielo visible completo hasta el suelo.
	var sky_h := ground_y - top
	for b in BANDS:
		var f0 := float(b) / BANDS
		var f1 := float(b + 1) / BANDS
		var y0 := top + sky_h * f0
		var y1 := top + sky_h * f1
		if y0 >= bottom:
			break
		var c := DAY_TOP.lerp(DAY_BOTTOM, f1)
		c = c.lerp(WARM_TOP.lerp(WARM_BOTTOM, f1), minf(1.0, warm * 1.3))
		c = c.lerp(STORM_TOP.lerp(STORM_BOTTOM, f1), st * 0.8)
		draw_rect(Rect2(vr.position.x, y0, vr.size.x, minf(y1, bottom) - y0 + 1.0), c)

	# Estrellas: solo de noche y con el cielo despejado.
	var star_a := (1.0 - light) * (1.0 - st)
	if star_a > 0.02:
		for s in _stars:
			var p := Vector2(vr.position.x + s.x * vr.size.x, top + s.y * sky_h)
			if p.y < bottom - 2.0:
				draw_rect(Rect2(p, Vector2.ONE * 1.2 * _k), Color(1, 1, 1, star_a * s.z))

	_draw_sun_moon(vr, top, sky_h, bottom, t, st)

	# Nubes.
	var n := 4 + int(round(st * (CLOUD_COUNT - 4)))
	var cloud_c := CLOUD.lerp(CLOUD_STORM, st)
	for k in n:
		var c := _clouds[k]
		var center := Vector2(vr.position.x + (c.x - 0.15) * vr.size.x, top + c.y * sky_h * (1.0 - 0.25 * st))
		if center.y < bottom - 4.0:
			_draw_cloud(center, c.z * (7.0 + 3.0 * st) * _k, cloud_c)


func _draw_sun_moon(vr: Rect2, top: float, sky_h: float, bottom: float, t: Vector2, st: float) -> void:
	var dusk := 1.0 - sim.cfg.night_fraction
	var p := t.x
	var is_day := p < dusk
	var prog := p / dusk if is_day else (p - dusk) / sim.cfg.night_fraction
	# Arco: sale por la izquierda, sube hasta arriba al medio y baja por la derecha.
	var x := vr.position.x + lerpf(0.06, 0.94, prog) * vr.size.x
	var y := top + sky_h * (0.24 + 0.45 * pow(2.0 * prog - 1.0, 2.0))
	if y > bottom - 3.0:
		return
	var a := 1.0 - 0.85 * st  # la tormenta tapa el sol
	if is_day:
		draw_circle(Vector2(x, y), 9.0 * _k, Color(SUN, 0.18 * a))
		draw_circle(Vector2(x, y), 6.5 * _k, Color(SUN, 0.3 * a))
		draw_circle(Vector2(x, y), 4.5 * _k, Color(SUN, a))
	else:
		draw_circle(Vector2(x, y), 6.0 * _k, Color(MOON, 0.12 * a))
		draw_circle(Vector2(x, y), 3.8 * _k, Color(MOON, a))
		draw_circle(Vector2(x + 1.2 * _k, y - 0.8 * _k), 0.9 * _k, Color(0.75, 0.77, 0.85, a))
		draw_circle(Vector2(x - 1.3 * _k, y + 1.0 * _k), 0.6 * _k, Color(0.75, 0.77, 0.85, a))


func _draw_cloud(center: Vector2, r: float, c: Color) -> void:
	for off in [Vector2(-r * 1.1, 0.0), Vector2(r * 1.1, 0.0), Vector2(0.0, -r * 0.45),
			Vector2(-r * 0.4, r * 0.25), Vector2(r * 0.45, r * 0.25)]:
		draw_circle(center + off, r * 0.72, c)
