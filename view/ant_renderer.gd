class_name AntRenderer
extends Node2D
## Dibuja todas las hormigas con un único MultiMeshInstance2D (más otro para el píxel verde de la hoja).
## La posición se interpola entre el tick anterior y el actual.

const ANT_COLOR := Color("120b08")
const LEAF_COLOR := Color("5fe05f")

var sim: Simulation
var color_by_state := false
var _ants_mm: MultiMesh
var _leaf_mm: MultiMesh
var _capacity := 0


func setup(s: Simulation) -> void:
	sim = s
	if _ants_mm == null:
		_ants_mm = _make_mm(Vector2(3, 2))
		_leaf_mm = _make_mm(Vector2(1, 1))
		for mm in [_ants_mm, _leaf_mm]:
			var node := MultiMeshInstance2D.new()
			node.multimesh = mm
			add_child(node)
	_capacity = 0
	_ensure_capacity(maxi(sim.ants.count, 1))


func _make_mm(size: Vector2) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = size
	mm.mesh = quad
	return mm


func _ensure_capacity(n: int) -> void:
	if n <= _capacity:
		return
	_capacity = maxi(n, 256) * 2
	_ants_mm.instance_count = _capacity
	_leaf_mm.instance_count = _capacity
	_ants_mm.visible_instance_count = 0
	_leaf_mm.visible_instance_count = 0


## `alpha` (0..1) es qué fracción del tick actual ha transcurrido.
func update(alpha: float) -> void:
	var ants := sim.ants
	_ensure_capacity(ants.count)
	var n := 0
	var leaves := 0
	for i in ants.count:
		if ants.alive[i] == 0:
			continue
		var p := ants.prev[i].lerp(ants.pos[i], alpha)
		_ants_mm.set_instance_transform_2d(n, Transform2D(0.0, p))
		_ants_mm.set_instance_color(n, AntSystem.STATE_COLORS[ants.state[i]] if color_by_state else ANT_COLOR)
		n += 1
		if ants.carry[i] == 1:
			_leaf_mm.set_instance_transform_2d(leaves, Transform2D(0.0, p + Vector2(0, -2.0)))
			_leaf_mm.set_instance_color(leaves, LEAF_COLOR)
			leaves += 1
	_ants_mm.visible_instance_count = n
	_leaf_mm.visible_instance_count = leaves
