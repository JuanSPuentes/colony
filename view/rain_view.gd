class_name RainView
extends Node2D
## Fase 16: la lluvia se ve caer. Antes, dentro de la partida no había ninguna gota: solo el aviso
## del panel y el agua acumulándose en los túneles. Gotas en diagonal que caen hasta el pasto, una
## salpicadura chica al tocarlo y algún relámpago con la lluvia fuerte.
##
## Va delante de las plantas y las hormigas (la lluvia pasa por encima de todo lo que hay en la
## superficie) y detrás de `DayNightView`, que la oscurece de noche como al resto del mundo. Pura
## decoración, en tiempo real: no toca la simulación ni la hace menos determinista.

const DROP := Color(0.72, 0.82, 0.95, 0.65)
const SPLASH := Color(0.80, 0.88, 1.0, 0.7)
const DROPS_PER_S := 260.0
const FALL_SPEED := 170.0   # px de pantalla por segundo
const SLANT := 0.35         # cuánto se inclina (viento)
const SPLASH_LIFE := 0.18
const FLASH_LIFE := 0.22
## Fase 26: en invierno la lluvia cae como nieve (solo se ve distinto: el agua sigue igual).
const FLAKE := Color(0.97, 0.98, 1.0, 0.9)
const FLAKE_SPEED := 38.0
const FLAKE_SLANT := 0.12

var sim: Simulation
var _sky: SkyView
var _drops := PackedVector2Array()      # posiciones en el mundo
var _splashes := PackedVector3Array()   # x, y del mundo + tiempo restante
var _spawn_acc := 0.0
var _flash := 0.0
var _bolt := PackedVector2Array()
var _rng := RandomNumberGenerator.new()
var _last_tick := -1
var _still := 0.0


func setup(s: Simulation, sky: SkyView) -> void:
	sim = s
	_sky = sky
	_drops.clear()
	_splashes.clear()
	_flash = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if sim == null or _sky == null:
		return
	queue_redraw()
	# En pausa (la simulación no avanzó) las gotas se quedan congeladas en el aire.
	if sim.tick_count != _last_tick:
		_last_tick = sim.tick_count
		_still = 0.0
	else:
		_still += delta
	if _still > 0.2:
		return
	var vr := _sky.visible_world_rect()
	var k := vr.size.x / 480.0  # mismo tamaño y velocidad en pantalla con cualquier zoom
	var ground_y := float(sim.cfg.surface_y * sim.cfg.cell_px)
	var raining := sim.weather == Simulation.Weather.RAINING
	var intensity := SkyView.storm(sim) if raining else 0.0

	if intensity > 0.0 and vr.position.y < ground_y:
		# La nieve cae ~4 veces más lento: con menos copos por segundo se ve igual de cargada.
		_spawn_acc += DROPS_PER_S * intensity * delta * (0.3 if SeasonStyle.snows(sim) else 1.0)
		while _spawn_acc >= 1.0:
			_spawn_acc -= 1.0
			# Un poco más a la izquierda del borde: el viento las trae en diagonal hacia la derecha.
			var x := _rng.randf_range(vr.position.x - vr.size.x * SLANT, vr.end.x)
			_drops.append(Vector2(x, vr.position.y - _rng.randf() * 20.0 * k))
	else:
		_spawn_acc = 0.0

	var snow := SeasonStyle.snows(sim)
	var step := Vector2(SLANT, 1.0) * FALL_SPEED * k * delta
	if snow:
		step = Vector2(FLAKE_SLANT, 1.0) * FLAKE_SPEED * k * delta
	var t := Time.get_ticks_msec() / 1000.0
	for i in range(_drops.size() - 1, -1, -1):
		var d := _drops[i] + step
		if snow:
			d.x += sin(t * 1.7 + float(i) * 0.9) * 6.0 * k * delta  # vaivén de copo
		if d.y >= ground_y:
			if not snow and _rng.randf() < 0.5:
				_splashes.append(Vector3(d.x, ground_y, SPLASH_LIFE))
			_drops.remove_at(i)
		elif d.y > vr.end.y + 10.0 * k:
			_drops.remove_at(i)
		else:
			_drops[i] = d
	for i in range(_splashes.size() - 1, -1, -1):
		var s := _splashes[i]
		s.z -= delta
		if s.z <= 0.0:
			_splashes.remove_at(i)
		else:
			_splashes[i] = s

	# Relámpago de vez en cuando, solo con la lluvia ya fuerte.
	_flash = maxf(0.0, _flash - delta)
	if not snow and intensity > 0.8 and _rng.randf() < delta * 0.07:
		_flash = FLASH_LIFE
		_make_bolt(vr, ground_y)
	queue_redraw()


func _make_bolt(vr: Rect2, ground_y: float) -> void:
	_bolt.clear()
	var x := _rng.randf_range(vr.position.x + vr.size.x * 0.15, vr.end.x - vr.size.x * 0.15)
	var y := vr.position.y
	var seg := (ground_y - y) / 7.0
	_bolt.append(Vector2(x, y))
	for k in 7:
		x += _rng.randf_range(-0.04, 0.04) * vr.size.x
		y += seg
		_bolt.append(Vector2(x, minf(y, ground_y)))


func _draw() -> void:
	if sim == null or _sky == null:
		return
	var vr := _sky.visible_world_rect()
	var k := vr.size.x / 480.0
	if SeasonStyle.snows(sim):
		for d in _drops:
			draw_rect(Rect2(d, Vector2.ONE * 1.3 * k), FLAKE)
	else:
		var tail := Vector2(SLANT, 1.0) * 6.0 * k
		for d in _drops:
			draw_line(d - tail, d, DROP, maxf(0.6, 0.7 * k))
	for s in _splashes:
		var f := s.z / SPLASH_LIFE
		var r := (1.0 - f) * 3.0 * k
		var p := Vector2(s.x, s.y)
		draw_line(p, p + Vector2(-r, -r * 0.8), Color(SPLASH, SPLASH.a * f), 0.6 * k)
		draw_line(p, p + Vector2(r, -r * 0.8), Color(SPLASH, SPLASH.a * f), 0.6 * k)
	if _flash > 0.0:
		var a := _flash / FLASH_LIFE
		draw_rect(vr, Color(1, 1, 1, 0.28 * a))
		if _bolt.size() > 1:
			draw_polyline(_bolt, Color(1, 1, 0.92, a), 1.2 * k)
