class_name AntRenderer
extends Node2D
## Dibuja todas las hormigas con un único MultiMeshInstance2D (más otro para el píxel verde de la hoja).
## La posición se interpola entre el tick anterior y el actual. El cuerpo (`_make_ant_mesh`) es una
## silueta de 3 lóbulos (cabeza/tórax/abdomen) con patas y antenas horneadas en el mismo contorno
## (ver `_body_outline`), y cada hormiga gira para encarar hacia dónde camina. Las patas no se animan
## por hormiga (quedan fijas, parte de la silueta): un `MultiMesh` solo varía transform y color por
## instancia, así que animar cada pata por separado dispararía el costo de las 500 hormigas; la
## silueta fija ya se nota a partir de zoom medio/alto, que es donde más importa.

const ANT_COLOR := Color("120b08")
const LEAF_COLOR := Color("5fe05f")
## Contorno: la misma malla del cuerpo, un poco más grande y en negro, dibujada detrás. Sin esto el
## cuerpo se fundía con la tierra (tonos parecidos) y la silueta costaba distinguirla del fondo.
const OUTLINE_COLOR := Color("0a0604")
const OUTLINE_SCALE := 1.25
## Un par de ojos chicos cerca de la cabeza, en todas las castas (sin esto se leía como una mancha
## con patas, no como un bicho). Chicos a propósito: a este tamaño un ojo grande se ve como un
## parche en vez de un ojo.
## Rojo oscuro, no negro: el contorno, las patas y las antenas ya son negras, así que un ojo
## negro se pierde contra todo eso. Un color propio se distingue sin importar en qué ángulo quede.
const EYE_COLOR := Color("8b1a1a")
const EYE_SIZE := Vector2(0.35, 0.35)
## Cerca de la punta de la cabeza, no del tórax: ahí es donde se juntan las patas y el contorno.
const EYE_OFFSET := Vector2(1.6, 0.3)
## Dos alas finas y translúcidas por zángano vivo (ver `CasteDefs`), la única casta con alas: así
## se distingue de un vistazo sin depender solo del color morado.
const WING_COLOR := Color(0.88, 0.8, 0.95, 0.55)
const WING_SIZE := Vector2(2.4, 0.9)
## Silueta de hormiga mirando hacia +X, un solo polígono simple (sin huecos) para
## `Geometry2D.triangulate_polygon`. A diferencia de la versión anterior (un óvalo continuo que a
## este tamaño se leía más como cucaracha que como hormiga), el tórax y el gáster están separados
## por un pecíolo bien angosto (`WAIST`): es la "cintura" que de verdad distingue a una hormiga de
## cualquier otro insecto de cuerpo plano. Las 6 patas quedan todas en el tórax (como en una
## hormiga real, no repartidas por todo el cuerpo) y el gáster es más grande y redondo que antes.
## Antenas horneadas como "picos" que salen y vuelven al contorno, misma técnica que las patas.
static func _body_outline() -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(Vector2(1.9, 0.0))  # punta de la cabeza
	# Antena superior: pico fino hacia adelante-arriba desde la cabeza.
	pts.append_array([Vector2(1.7, 0.15), Vector2(2.6, 0.9), Vector2(1.5, 0.35)])
	# Tórax: 3 patas por lado, todas acá (no en el gáster).
	for c in [Vector2(1.3, 0.45), Vector2(0.75, 0.5), Vector2(0.2, 0.45)]:
		pts.append_array(_leg_spike(c, 1.0))
	# Pecíolo: el punto más angosto de todo el contorno, la "cintura" entre tórax y gáster.
	pts.append(Vector2(-0.05, 0.12))
	# Gáster: más ancho que el tórax y redondeado, sin patas.
	pts.append(Vector2(-0.55, 0.6))
	pts.append(Vector2(-1.3, 0.55))
	pts.append(Vector2(-2.1, 0.0))  # punta de la cola
	pts.append(Vector2(-1.3, -0.55))
	pts.append(Vector2(-0.55, -0.6))
	pts.append(Vector2(-0.05, -0.12))
	# Tórax de abajo, mismos puntos reflejados en Y.
	for c in [Vector2(0.2, -0.45), Vector2(0.75, -0.5), Vector2(1.3, -0.45)]:
		pts.append_array(_leg_spike(c, -1.0))
	# Antena inferior: simétrica a la de arriba.
	pts.append_array([Vector2(1.5, -0.35), Vector2(2.6, -0.9), Vector2(1.7, -0.15)])
	return pts


## Pico fino de "entra-sale" en el punto `center` del contorno, hacia afuera en Y (signo `out_y`):
## entra por el lado de mayor |x| cuando se viene desde la cabeza (`out_y>0`, arriba) o desde la
## cola (`out_y<0`, abajo), sale por el otro lado, para no cruzar el resto del contorno.
static func _leg_spike(center: Vector2, out_y: float) -> PackedVector2Array:
	const WIDTH := 0.12
	const LEN := 0.5
	var near_x := center.x + (WIDTH if out_y > 0.0 else -WIDTH)
	var far_x := center.x - (WIDTH if out_y > 0.0 else -WIDTH)
	return PackedVector2Array([
		Vector2(near_x, center.y), Vector2(center.x, center.y + out_y * LEN), Vector2(far_x, center.y),
	])


## Umbral de desplazamiento (al cuadrado) para actualizar el ángulo: por debajo de esto una
## hormiga casi quieta no gira hacia ruido de redondeo de posición.
const TURN_EPS2 := 0.0004

var sim: Simulation
var color_by_state := false
var color_by_caste := false
var _ants_mm: MultiMesh
var _outline_mm: MultiMesh
var _eyes_mm: MultiMesh
var _leaf_mm: MultiMesh
var _wings_mm: MultiMesh
var _capacity := 0
## Último ángulo de cada hormiga (por índice de hormiga, no de instancia del MultiMesh), para que
## una hormiga detenida no vuelva a mirar hacia +X en vez de mantener hacia dónde miraba.
var _last_angle := PackedFloat32Array()


func setup(s: Simulation) -> void:
	sim = s
	if _ants_mm == null:
		var body_mesh := _make_ant_mesh()
		# El contorno reusa la misma malla del cuerpo (no una nueva): como el color de instancia
		# multiplica al de vértice, pintándolo de un color casi negro (`OUTLINE_COLOR`, ver
		# `update()`) el sombreado por segmento queda invisible y se ve de un solo tono oscuro.
		_outline_mm = _make_mm(body_mesh)
		_ants_mm = _make_mm(body_mesh)
		_eyes_mm = _make_mm(_make_quad_mesh(EYE_SIZE))
		_leaf_mm = _make_mm(_make_quad_mesh(Vector2(1, 1)))
		_wings_mm = _make_mm(_make_quad_mesh(WING_SIZE))
		# Orden de dibujo (de atrás hacia adelante): contorno, alas, cuerpo, ojos, hoja cargada.
		for mm in [_outline_mm, _wings_mm, _ants_mm, _eyes_mm, _leaf_mm]:
			var node := MultiMeshInstance2D.new()
			node.multimesh = mm
			add_child(node)
	_capacity = 0
	_ensure_capacity(maxi(sim.ants.count, 1))


func _make_quad_mesh(size: Vector2) -> Mesh:
	var quad := QuadMesh.new()
	quad.size = size
	return quad


## Triangula `_body_outline()` una sola vez al arrancar; las 500 hormigas comparten este mismo Mesh,
## el MultiMesh solo varía transform y color por instancia. El color por vértice (`_body_shading`)
## es el mismo estilo de 3 lóbulos del menú (cabeza más oscura, gáster con un brillo cálido), pero
## horneado en la malla en vez de 3 óvalos separados: a la escala de una hormiga en partida (unas
## pocas decenas de píxeles) no se nota la diferencia y así sigue siendo una sola malla, un solo
## dibujo por hormiga, el mismo costo de siempre para 500. Godot multiplica este color de vértice
## por el color de instancia (`set_instance_color`), así que la casta/estado se sigue viendo con
## su propio tono — solo se le suma el sombreado por segmento encima.
func _make_ant_mesh() -> Mesh:
	var pts := _body_outline()
	var indices := Geometry2D.triangulate_polygon(pts)
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pts
	arrays[Mesh.ARRAY_COLOR] = _body_shading(pts)
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Un tono por vértice de `pts` (cabeza x>0.7 más oscura, gáster x<-0.3 más clara/cálida —ya del
## otro lado del pecíolo—, tórax en el medio) para que el cuerpo se lea segmentado en vez de un
## solo color plano, sin agregar geometría ni un segundo dibujo.
func _body_shading(pts: PackedVector2Array) -> PackedColorArray:
	var colors := PackedColorArray()
	for p in pts:
		if p.x > 0.7:
			colors.append(Color(0.6, 0.57, 0.55))
		elif p.x < -0.3:
			colors.append(Color(1.0, 0.93, 0.84))
		else:
			colors.append(Color(0.8, 0.78, 0.75))
	return colors


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
	_outline_mm.instance_count = _capacity
	_eyes_mm.instance_count = _capacity * 2  # 2 ojos por hormiga, todas las castas
	_leaf_mm.instance_count = _capacity
	_wings_mm.instance_count = _capacity * 2  # 2 alas por zángano vivo, caso extremo "todos zánganos"
	_ants_mm.visible_instance_count = 0
	_outline_mm.visible_instance_count = 0
	_eyes_mm.visible_instance_count = 0
	_leaf_mm.visible_instance_count = 0
	_wings_mm.visible_instance_count = 0
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
	var wings := 0
	var eyes := 0
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
		# Tamaño por casta (hoy solo la reina, bien más grande que el resto: ver CasteDefs.VISUAL_SCALE).
		var scale := CasteDefs.VISUAL_SCALE[ants.caste[i]]
		var t := Transform2D(angle, p)
		if scale != 1.0:
			t.x *= scale
			t.y *= scale
		_ants_mm.set_instance_transform_2d(n, t)
		var c := ANT_COLOR
		if color_by_state:
			c = AntSystem.STATE_COLORS[ants.state[i]]
		elif color_by_caste:
			c = CasteDefs.COLORS[ants.caste[i]]
		_ants_mm.set_instance_color(n, c)
		# Contorno: mismo transform que el cuerpo pero un poco más grande, para que asome por detrás.
		var ot := Transform2D(angle, p)
		ot.x *= scale * OUTLINE_SCALE
		ot.y *= scale * OUTLINE_SCALE
		_outline_mm.set_instance_transform_2d(n, ot)
		_outline_mm.set_instance_color(n, OUTLINE_COLOR)
		n += 1
		if ants.carry[i] == 1:
			_leaf_mm.set_instance_transform_2d(leaves, Transform2D(0.0, p + Vector2(0, -2.0)))
			_leaf_mm.set_instance_color(leaves, LEAF_COLOR)
			leaves += 1
		if ants.caste[i] == CasteDefs.Caste.DRONE:
			var fwd := Vector2(cos(angle), sin(angle))
			var perp := fwd.orthogonal()
			for side in [-1.0, 1.0]:
				_wings_mm.set_instance_transform_2d(wings, Transform2D(angle + side * 0.45, p + perp * side * 0.9))
				_wings_mm.set_instance_color(wings, WING_COLOR)
				wings += 1
		# Ojos: dos puntos chicos cerca de la cabeza, en todas las castas (escalan con `scale`
		# igual que el cuerpo, para que en la reina no queden chicos en proporción).
		for sgn in [-1.0, 1.0]:
			var local_off := Vector2(EYE_OFFSET.x, EYE_OFFSET.y * sgn) * scale
			_eyes_mm.set_instance_transform_2d(eyes, Transform2D(angle, p + local_off.rotated(angle)))
			_eyes_mm.set_instance_color(eyes, EYE_COLOR)
			eyes += 1
	_ants_mm.visible_instance_count = n
	_outline_mm.visible_instance_count = n
	_leaf_mm.visible_instance_count = leaves
	_wings_mm.visible_instance_count = wings
	_eyes_mm.visible_instance_count = eyes
