class_name AmbientView
extends Node2D
## Fase 26: partículas de ambiente según la estación (`SeasonStyle.AMBIENT`), solo decoración:
## pétalos que caen de las copas (primavera), luciérnagas cerca del pasto de noche (verano), hojas
## que caen de las copas (otoño) y una nevada suave (invierno). Solo sobre la superficie y en lo que
## se ve en pantalla. Se congela en pausa, igual que la lluvia.

const MAX_PARTICLES := 140
const PETAL_COLORS: Array[Color] = [Color(1.0, 0.78, 0.86), Color(1.0, 0.90, 0.94), Color(0.98, 0.66, 0.78)]
const LEAF_COLORS: Array[Color] = [Color(0.92, 0.48, 0.16), Color(0.82, 0.28, 0.14), Color(0.95, 0.72, 0.22)]
const FIREFLY := Color(0.95, 1.0, 0.55)
const FLAKE := Color(0.97, 0.98, 1.0, 0.8)
## Partículas nuevas por segundo para cada `SeasonStyle.Ambient`.
const RATE: Array[float] = [5.0, 3.0, 7.0, 14.0]

var sim: Simulation
var _sky: SkyView
## x, y (mundo), semilla (forma, color, fase del vaivén), edad en segundos.
var _parts: Array[Vector4] = []
var _spawn_acc := 0.0
var _rng := RandomNumberGenerator.new()
var _last_tick := -1
var _still := 0.0


func setup(s: Simulation, sky: SkyView) -> void:
	sim = s
	_sky = sky
	_parts.clear()
	_spawn_acc = 0.0


func _process(delta: float) -> void:
	if sim == null or _sky == null:
		return
	queue_redraw()
	if sim.tick_count != _last_tick:
		_last_tick = sim.tick_count
		_still = 0.0
	else:
		_still += delta
	if _still > 0.2:
		return
	var kind: int = SeasonStyle.AMBIENT[SeasonStyle.of(sim)]
	var vr := _sky.visible_world_rect()
	var k := vr.size.x / 480.0
	var ground_y := float(sim.cfg.surface_y * sim.cfg.cell_px)
	if vr.position.y < ground_y and _active(kind):
		_spawn_acc += RATE[kind] * delta
		while _spawn_acc >= 1.0 and _parts.size() < MAX_PARTICLES:
			_spawn_acc -= 1.0
			_spawn(kind, vr, ground_y)
	for i in range(_parts.size() - 1, -1, -1):
		var p := _parts[i]
		p.w += delta
		match kind:
			SeasonStyle.Ambient.FIREFLIES:
				p.x += sin(p.w * 0.9 + p.z * 6.0) * 7.0 * delta
				p.y += cos(p.w * 1.3 + p.z * 4.0) * 4.0 * delta
			SeasonStyle.Ambient.SNOW:
				p.x += (3.0 + sin(p.w * 1.5 + p.z * 6.0) * 6.0) * delta
				p.y += 14.0 * delta
			_:  # pétalos y hojas: caen meciéndose
				p.x += (5.0 + sin(p.w * 2.2 + p.z * 6.0) * 14.0) * delta
				p.y += (9.0 + p.z * 5.0) * delta
		var dead := p.y >= ground_y or p.x > vr.end.x + 20.0 * k
		if kind == SeasonStyle.Ambient.FIREFLIES:
			dead = p.w > 9.0 or not _active(kind)
		if dead:
			_parts.remove_at(i)
		else:
			_parts[i] = p


## Las luciérnagas solo salen de noche; lo demás, siempre.
func _active(kind: int) -> bool:
	if kind == SeasonStyle.Ambient.FIREFLIES:
		return sim.is_night()
	return true


func _spawn(kind: int, vr: Rect2, ground_y: float) -> void:
	var seed_v := _rng.randf()
	match kind:
		SeasonStyle.Ambient.SNOW:
			_parts.append(Vector4(_rng.randf_range(vr.position.x - 20.0, vr.end.x), vr.position.y - 4.0, seed_v, 0.0))
		SeasonStyle.Ambient.FIREFLIES:
			var y := ground_y - _rng.randf_range(4.0, 34.0)
			_parts.append(Vector4(_rng.randf_range(vr.position.x, vr.end.x), y, seed_v, 0.0))
		_:
			# Caen de la copa de algún árbol que se vea en pantalla.
			var trees: Array[Plant] = []
			var cpx := sim.cfg.cell_px
			for pl in sim.plants:
				var x := (pl.cell.x + 0.5) * cpx
				if not pl.is_mushroom() and pl.leaves > 0 and x > vr.position.x and x < vr.end.x:
					trees.append(pl)
			if trees.is_empty():
				return
			var t: Plant = trees[_rng.randi() % trees.size()]
			var cx := (t.cell.x + 0.5) * cpx + _rng.randf_range(-14.0, 14.0)
			_parts.append(Vector4(cx, ground_y - _rng.randf_range(18.0, 40.0), seed_v, 0.0))


func _draw() -> void:
	if sim == null or _parts.is_empty():
		return
	var kind: int = SeasonStyle.AMBIENT[SeasonStyle.of(sim)]
	for p in _parts:
		var pos := Vector2(p.x, p.y)
		match kind:
			SeasonStyle.Ambient.PETALS:
				draw_rect(Rect2(pos, Vector2(3.0, 2.0)), PETAL_COLORS[int(p.z * 30.0) % PETAL_COLORS.size()])
			SeasonStyle.Ambient.LEAVES:
				# El ancho cambia con el vaivén: parece que la hoja gira al caer.
				var w := 1.2 + absf(sin(p.w * 3.0 + p.z * 6.0)) * 2.4
				draw_rect(Rect2(pos, Vector2(w, 2.4)), LEAF_COLORS[int(p.z * 30.0) % LEAF_COLORS.size()])
			SeasonStyle.Ambient.SNOW:
				draw_rect(Rect2(pos, Vector2.ONE * 1.8), FLAKE)
			SeasonStyle.Ambient.FIREFLIES:
				var blink := maxf(0.0, sin(p.w * 2.4 + p.z * 9.0))
				var fade := minf(1.0, p.w) * minf(1.0, 9.0 - p.w)
				var a := blink * fade
				draw_circle(pos, 3.5, Color(FIREFLY, 0.18 * a))
				draw_circle(pos, 1.1, Color(FIREFLY, 0.9 * a))
