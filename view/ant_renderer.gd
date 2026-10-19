class_name AntRenderer
extends Node2D
## Dibuja todas las hormigas con un único MultiMeshInstance2D (más otro para el píxel verde de la hoja).
## La posición se interpola entre el tick anterior y el actual. El cuerpo (`_make_ant_mesh`) es una
## silueta de 3 lóbulos (cabeza/tórax/abdomen) en vez del rectángulo plano de antes, y cada hormiga
## gira para encarar hacia dónde camina (no hacia dónde cargan las piernas: no las dibujamos, un
## `MultiMesh` no puede animar cada una por separado sin disparar el costo de las 500 hormigas).

const ANT_COLOR := Color("120b08")
const LEAF_COLOR := Color("5fe05f")
## Silueta de hormiga mirando hacia +X: cabeza puntiaguda, tórax ancho, abdomen redondeado y
## alargado atrás. Mismo tamaño aproximado que el rectángulo 3x2 anterior.
const BODY_POINTS: PackedVector2Array = [
	Vector2(1.8, 0.0), Vector2(1.0, 0.55), Vector2(-0.2, 0.75), Vector2(-1.3, 0.45),
	Vector2(-1.9, 0.0), Vector2(-1.3, -0.45), Vector2(-0.2, -0.75), Vector2(1.0, -0.55),
]
## Umbral de desplazamiento (al cuadrado) para actualizar el ángulo: por debajo de esto una
## hormiga casi quieta no gira hacia ruido de redondeo de posición.
const TURN_EPS2 := 0.0004

var sim: Simulation
var color_by_state := false
var color_by_caste := false
var _ants_mm: MultiMesh
var _leaf_mm: MultiMesh
var _capacity := 0
## Último ángulo de cada hormiga (por índice de hormiga, no de instancia del MultiMesh), para que
## una hormiga detenida no vuelva a mirar hacia +X en vez de mantener hacia dónde miraba.
var _last_angle := PackedFloat32Array()


func setup(s: Simulation) -> void:
	sim = s
	if _ants_mm == null:
		_ants_mm = _make_mm(_make_ant_mesh())
		_leaf_mm = _make_mm(_make_quad_mesh(Vector2(1, 1)))
		for mm in [_ants_mm, _leaf_mm]:
			var node := MultiMeshInstance2D.new()
			node.multimesh = mm
			add_child(node)
	_capacity = 0
	_ensure_capacity(maxi(sim.ants.count, 1))


func _make_quad_mesh(size: Vector2) -> Mesh:
	var quad := QuadMesh.new()
	quad.size = size
	return quad


## Triangula `BODY_POINTS` una sola vez al arrancar; las 500 hormigas comparten este mismo Mesh,
## el MultiMesh solo varía transform y color por instancia.
func _make_ant_mesh() -> Mesh:
	var indices := Geometry2D.triangulate_polygon(BODY_POINTS)
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = BODY_POINTS
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_mm(mesh: Mesh) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = mesh
	return mm


func _ensure_capacity(n: int) -> void:
	if n <= _capacity:
		return
	_capacity = maxi(n, 256) * 2
	_ants_mm.instance_count = _capacity
	_leaf_mm.instance_count = _capacity
	_ants_mm.visible_instance_count = 0
	_leaf_mm.visible_instance_count = 0
	if _last_angle.size() < _capacity:
		_last_angle.resize(_capacity)


## `alpha` (0..1) es qué fracción del tick actual ha transcurrido. `frame_start_pos`, si viene con
## tamaño suficiente, es de dónde partió cada hormiga al inicio de este frame real (puede cubrir
## varios ticks a velocidad x2/x4); una hormiga nacida después de capturarlo cae al `ants.prev` de
## siempre.
func update(alpha: float, frame_start_pos: PackedVector2Array = PackedVector2Array()) -> void:
	var ants := sim.ants
	_ensure_capacity(ants.count)
	var has_frame_start := frame_start_pos.size() >= ants.count
	var n := 0
	var leaves := 0
	for i in ants.count:
		if ants.alive[i] == 0:
			continue
		var from := frame_start_pos[i] if has_frame_start else ants.prev[i]
		var p := from.lerp(ants.pos[i], alpha)
		var delta := ants.pos[i] - ants.prev[i]
		var angle := _last_angle[i]
		if delta.length_squared() > TURN_EPS2:
			angle = delta.angle()
			_last_angle[i] = angle
		_ants_mm.set_instance_transform_2d(n, Transform2D(angle, p))
		var c := ANT_COLOR
		if color_by_state:
			c = AntSystem.STATE_COLORS[ants.state[i]]
		elif color_by_caste:
			c = CasteDefs.COLORS[ants.caste[i]]
		_ants_mm.set_instance_color(n, c)
		n += 1
		if ants.carry[i] == 1:
			_leaf_mm.set_instance_transform_2d(leaves, Transform2D(0.0, p + Vector2(0, -2.0)))
			_leaf_mm.set_instance_color(leaves, LEAF_COLOR)
			leaves += 1
	_ants_mm.visible_instance_count = n
	_leaf_mm.visible_instance_count = leaves
