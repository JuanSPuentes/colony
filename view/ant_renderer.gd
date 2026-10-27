class_name AntRenderer
extends Node2D
## Dibuja todas las hormigas con `MultiMeshInstance2D` (uno por dirección, más el de la hoja
## cargada y el de las alas del Zángano). La posición se interpola entre el tick anterior y el
## actual.
##
## El cuerpo usa el set de sprites de `view/sprites/ant/` (8 direcciones, pixel art en gris,
## 64x64, generado para este juego — ver `A_high-quality_2D_pixel-Idle.zip`), en vez del dibujo
## procedural de antes (3 lóbulos + patas/antenas horneadas a mano). Cada hormiga elige, por
## tick, el sprite de la dirección más cercana a hacia dónde camina (`SpriteDir.index`); un
## `MultiMeshInstance2D` por dirección es más barato que rotar libremente un solo sprite (que
## emborronaría el pixel art) y más simple que un shader de atlas con UV por instancia. El color de
## instancia multiplica al sprite (gris) igual que multiplicaba al color por vértice del mesh viejo,
## así que el tinte por casta/estado sigue funcionando sin cambios en `CasteDefs`/`AntSystem.State`.

## Tamaño en pantalla del sprite (en las mismas unidades que `ants.pos`, pixeles de mundo). Más
## grande que el cuerpo procedural viejo (~4.5 de punta a punta) a propósito: a ese tamaño el
## pixel art se perdía: pedido del usuario tras ver la primera integración.
const BODY_SIZE := Vector2(7.5, 7.5)
const ANT_COLOR := Color("120b08")
## Fase 9: tinte fijo de las hormigas rivales (bando 1), para distinguirlas de las propias durante
## una batalla de fin de estación sin arte nuevo (mismo sprite, otro color de instancia).
const RIVAL_COLOR := Color("8b1a1a")
const LEAF_COLOR := Color("5fe05f")
## Fase 29: color de lo que carga según `AntSystem.carry_kind` (hoja de árbol, restos, hoja caída,
## semilla, fruta). Provisorio: la etapa 2 trae sprites propios con animación.
const CARRY_COLORS: Array[Color] = [LEAF_COLOR, Color("4a2a1f"), LEAF_COLOR, Color("a8743a"), Color("d8402f")]
## Dos alas finas y translúcidas por zángano vivo (ver `CasteDefs`), la única casta con alas: así
## se distingue de un vistazo sin depender solo del color morado.
const WING_COLOR := Color(0.88, 0.8, 0.95, 0.55)
const WING_SIZE := Vector2(2.4, 0.9)

## Orden fijo, en el mismo sentido que crece `Vector2.angle()` (X+ = este, Y+ = hacia abajo/hacia
## adentro de la tierra = "sur"): est, sureste, sur, suroeste, oeste, noroeste, norte, noreste.
## `SpriteDir.index` devuelve un índice a este array (compartido con `ThreatSpriteView`, la base
## de las vistas de araña/ciempiés/mantis).
const DIR_TEXTURES: Array[Texture2D] = [
	preload("res://view/sprites/ant/east.png"),
	preload("res://view/sprites/ant/south-east.png"),
	preload("res://view/sprites/ant/south.png"),
	preload("res://view/sprites/ant/south-west.png"),
	preload("res://view/sprites/ant/west.png"),
	preload("res://view/sprites/ant/north-west.png"),
	preload("res://view/sprites/ant/north.png"),
	preload("res://view/sprites/ant/north-east.png"),
]
const DIR_COUNT := SpriteDir.COUNT

## Umbral de desplazamiento (al cuadrado) para actualizar la dirección: por debajo de esto una
## hormiga casi quieta no cambia de sprite por ruido de redondeo de posición.
const TURN_EPS2 := 0.0004

## El pack solo trae la pose "Idle" (sin fotogramas de caminata todavía): en vez de deslizar el
## sprite quieto de una celda a otra, se le suma un rebotecito vertical mientras se mueve de
## verdad (mismo umbral `TURN_EPS2`), para que al menos se note que camina en vez de flotar. Fase
## (`i * BOB_PHASE_STEP`) por índice de hormiga para que no reboten todas en fase. Atado a
## `sim.tick_count` (no al reloj real) para que no se desincronice en pausa/x2/x4 y sea
## determinístico como el resto de la simulación.
const BOB_AMPLITUDE := 0.55
const BOB_FREQ := 0.9
const BOB_PHASE_STEP := 2.399963

var sim: Simulation
var color_by_state := false
var color_by_caste := false
## Un `MultiMeshInstance2D` de cuerpo por dirección (`DIR_COUNT`).
var _body_mm: Array[MultiMesh] = []
var _leaf_mm: MultiMesh
var _wings_mm: MultiMesh
var _capacity := 0
## Último índice de dirección de cada hormiga (por índice de hormiga, no de instancia del
## MultiMesh), para que una hormiga detenida mantenga el sprite de hacia dónde miraba en vez de
## volver al de "este" por defecto.
var _last_dir := PackedInt32Array()


func setup(s: Simulation) -> void:
	sim = s
	if _body_mm.is_empty():
		var quad := _make_quad_mesh(BODY_SIZE)
		# Alas primero (de atrás hacia adelante), luego cuerpos, luego la hoja cargada; dentro de
		# cada grupo, una dirección detrás de otra no importa (no se superponen entre sí, cada
		# hormiga pinta solo en su propio bucket de dirección).
		_wings_mm = _add_mm_node(_make_quad_mesh(WING_SIZE), null)
		for d in DIR_COUNT:
			_body_mm.append(_add_mm_node(quad, DIR_TEXTURES[d]))
		_leaf_mm = _add_mm_node(_make_quad_mesh(Vector2(1, 1)), null)
	_capacity = 0
	_ensure_capacity(maxi(sim.ants.count, 1))


## Crea el `MultiMeshInstance2D` (la textura vive en el nodo `CanvasItem`, no en el `MultiMesh` —
## Godot 4 no tiene textura por `MultiMesh`) y devuelve el `MultiMesh` para guardarlo.
func _add_mm_node(mesh: Mesh, tex: Texture2D) -> MultiMesh:
	var mm := _make_mm(mesh)
	var node := MultiMeshInstance2D.new()
	node.multimesh = mm
	node.texture = tex
	add_child(node)
	return mm


func _make_quad_mesh(size: Vector2) -> Mesh:
	var quad := QuadMesh.new()
	quad.size = size
	return quad


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
	for mm in _body_mm:
		mm.instance_count = _capacity
		mm.visible_instance_count = 0
	_leaf_mm.instance_count = _capacity
	_leaf_mm.visible_instance_count = 0
	_wings_mm.instance_count = _capacity * 2  # 2 alas por zángano vivo, caso extremo "todos zánganos"
	_wings_mm.visible_instance_count = 0
	if _last_dir.size() < _capacity:
		_last_dir.resize(_capacity)


## `alpha` (0..1) es qué fracción del tick actual ha transcurrido. `frame_start_pos`, si viene con
## tamaño suficiente, es de dónde partió cada hormiga al inicio de este frame real (puede cubrir
## varios ticks a velocidad x2/x4); una hormiga nacida después de capturarlo cae al `ants.prev` de
## siempre.
func update(alpha: float, frame_start_pos: PackedVector2Array = PackedVector2Array()) -> void:
	var ants := sim.ants
	_ensure_capacity(ants.count)
	var has_frame_start := frame_start_pos.size() >= ants.count
	var body_n := PackedInt32Array()
	body_n.resize(DIR_COUNT)
	var leaves := 0
	var wings := 0
	for i in ants.count:
		if ants.alive[i] == 0:
			continue
		var from := frame_start_pos[i] if has_frame_start else ants.prev[i]
		var p := from.lerp(ants.pos[i], alpha)
		var delta := ants.pos[i] - ants.prev[i]
		var moving := delta.length_squared() > TURN_EPS2
		var dir := _last_dir[i]
		if moving:
			dir = SpriteDir.index(delta.angle())
			_last_dir[i] = dir
		# Tamaño por casta (hoy solo la reina, bien más grande que el resto: ver CasteDefs.VISUAL_SCALE).
		var scale := CasteDefs.VISUAL_SCALE[ants.caste[i]]
		if moving:
			# Sin fotogramas de caminata (ver nota de BOB_AMPLITUDE arriba): un rebotecito
			# mientras se mueve de verdad, para que al menos se note que camina.
			p.y -= absf(sin(float(sim.tick_count) * BOB_FREQ + float(i) * BOB_PHASE_STEP)) * BOB_AMPLITUDE * scale
		var c := ANT_COLOR
		if color_by_state:
			c = AntSystem.STATE_COLORS[ants.state[i]]
		elif color_by_caste:
			c = CasteDefs.COLORS[ants.caste[i]]
		# Fase 9: una hormiga rival se tiñe siempre igual (sin importar casta/estado activo), para
		# distinguirla de las propias a simple vista durante una batalla de fin de estación.
		if ants.faction[i] == 1:
			c = RIVAL_COLOR
		var idx := body_n[dir]
		# `t.x`/`t.y` en vez de `Transform2D.scaled()`: construido a mano para que el escalado sea
		# de la hormiga alrededor de su propio centro, no de la traslación (mismo truco que ya
		# usaba el mesh procedural para la reina). `t.y *= -1.0` siempre: `QuadMesh` es una malla
		# pensada para 3D (Y+ arriba) y su UV queda invertido al usarla tal cual en 2D (Y+ abajo);
		# sin este flip el sprite se veía al revés (antenas abajo, patas arriba).
		var t := Transform2D(0.0, p)
		t.y *= -1.0
		if scale != 1.0:
			t.x *= scale
			t.y *= scale
		_body_mm[dir].set_instance_transform_2d(idx, t)
		_body_mm[dir].set_instance_color(idx, c)
		body_n[dir] += 1
		if ants.carry[i] == 1:
			_leaf_mm.set_instance_transform_2d(leaves, Transform2D(0.0, p + Vector2(0, -2.0)))
			_leaf_mm.set_instance_color(leaves, CARRY_COLORS[mini(ants.carry_kind[i], CARRY_COLORS.size() - 1)])
			leaves += 1
		if ants.caste[i] == CasteDefs.Caste.DRONE:
			var fwd := Vector2(cos(delta.angle()), sin(delta.angle())) if delta.length_squared() > TURN_EPS2 else Vector2.RIGHT
			var perp := fwd.orthogonal()
			for side in [-1.0, 1.0]:
				_wings_mm.set_instance_transform_2d(wings, Transform2D(side * 0.45, p + perp * side * 0.9))
				_wings_mm.set_instance_color(wings, WING_COLOR)
				wings += 1
	for d in DIR_COUNT:
		_body_mm[d].visible_instance_count = body_n[d]
	_leaf_mm.visible_instance_count = leaves
	_wings_mm.visible_instance_count = wings
