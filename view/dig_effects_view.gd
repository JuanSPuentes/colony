class_name DigEffectsView
extends Node2D
## Fase 20: la tierra se "desgasta" al cavarla, estilo Terraria. Sobre cada celda marcada aparecen
## grietas en 3 etapas según el avance de la excavación (`WorldGrid.job_progress`), y al terminar
## la celda se desprende en un puñado de partículas de tierra que caen.
##
## Pura decoración: solo lee la simulación. Va justo después de `TerrainView` (encima del terreno y
## debajo de plantas y hormigas). Las celdas marcadas se buscan de nuevo solo cuando cambia
## `jobs_version` (marcar, desmarcar o terminar una celda), no en cada cuadro.

const STAGES: Array[float] = [0.2, 0.5, 0.8]  # avance desde el que se ve cada etapa de grietas
const CRACK := Color(0.12, 0.07, 0.04, 0.85)
const PARTICLES_PER_CELL := 7
const PARTICLE_LIFE := 0.7
const GRAVITY := 140.0
## Grietas de cada etapa, en coordenadas de la celda (0..1). Cada etapa suma las de la anterior.
const CRACK_LINES := [
	[[Vector2(0.5, 0.15), Vector2(0.42, 0.5)], [Vector2(0.42, 0.5), Vector2(0.58, 0.82)]],
	[[Vector2(0.42, 0.5), Vector2(0.15, 0.62)], [Vector2(0.5, 0.15), Vector2(0.8, 0.3)]],
	[[Vector2(0.58, 0.82), Vector2(0.85, 0.7)], [Vector2(0.8, 0.3), Vector2(0.88, 0.55)], [Vector2(0.15, 0.62), Vector2(0.2, 0.9)]],
]

var sim: Simulation
var _marked: Array[int] = []
var _jobs_version := -1
## Partículas: posición, velocidad, vida restante y color.
var _particles: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _last_tick := -1
var _still := 0.0


func setup(s: Simulation) -> void:
	sim = s
	_particles.clear()
	_jobs_version = -1
	_marked.clear()
	_rebuild_marked()


func _process(delta: float) -> void:
	if sim == null:
		return
	if sim.world.jobs_version != _jobs_version:
		_rebuild_marked()
	# En pausa (la simulación no avanzó un rato) las partículas se quedan quietas.
	if sim.tick_count != _last_tick:
		_last_tick = sim.tick_count
		_still = 0.0
	else:
		_still += delta
	if _still <= 0.2:
		_step_particles(delta)
	queue_redraw()


## Vuelve a buscar las celdas marcadas. Las que estaban marcadas y ahora son túnel se acaban de
## cavar: ahí sale la tierra que se desprende.
func _rebuild_marked() -> void:
	var world := sim.world
	_jobs_version = world.jobs_version
	for i in _marked:
		if world.cells[i] == WorldGrid.Cell.TUNNEL:
			_burst(i)
	_marked.clear()
	for i in world.cells.size():
		if world.cells[i] == WorldGrid.Cell.MARKED:
			_marked.append(i)


func _burst(i: int) -> void:
	var cpx := float(sim.cfg.cell_px)
	var w := sim.world.w
	var center := Vector2((i % w + 0.5) * cpx, (i / w + 0.5) * cpx)
	var depth := float(i / w - sim.cfg.surface_y) / float(sim.world.h - sim.cfg.surface_y)
	var base: Color = TerrainStyle.DIRT_BASE[TerrainStyle.dirt_mat(i % w, i / w, depth) - TerrainStyle.Mat.DIRT_1]
	for k in PARTICLES_PER_CELL:
		_particles.append({
			"pos": center + Vector2(_rng.randf_range(-3, 3), _rng.randf_range(-3, 3)),
			"vel": Vector2(_rng.randf_range(-30, 30), _rng.randf_range(-45, -5)),
			"life": PARTICLE_LIFE * _rng.randf_range(0.6, 1.0),
			"color": base.lightened(_rng.randf_range(-0.15, 0.15)),
		})


func _step_particles(delta: float) -> void:
	for k in range(_particles.size() - 1, -1, -1):
		var p := _particles[k]
		p["life"] -= delta
		if p["life"] <= 0.0:
			_particles.remove_at(k)
			continue
		p["vel"] += Vector2(0, GRAVITY * delta)
		p["pos"] += p["vel"] * delta


func _draw() -> void:
	if sim == null:
		return
	var world := sim.world
	var cpx := float(sim.cfg.cell_px)
	for i in _marked:
		if world.cells[i] != WorldGrid.Cell.MARKED:
			continue
		var progress := world.job_progress[i] / sim.cfg.dig_seconds
		var origin := Vector2((i % world.w) * cpx, (i / world.w) * cpx)
		for s in STAGES.size():
			if progress < STAGES[s]:
				break
			for seg in CRACK_LINES[s]:
				draw_line(origin + seg[0] * cpx, origin + seg[1] * cpx, CRACK, 1.0)
	for p in _particles:
		var a := clampf(p["life"] / PARTICLE_LIFE * 1.5, 0.0, 1.0)
		var c: Color = p["color"]
		draw_rect(Rect2(p["pos"], Vector2(1.5, 1.5)), Color(c, a))
