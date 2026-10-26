class_name FogView
extends Node2D
## Fase 24: dibuja la niebla bajo tierra (`Simulation.fog`): oscuridad sobre lo que la colonia todavía
## no descubrió, con bordes suaves. Encima de todo el mundo (terreno, hongos, contadores), así que
## un bolsón sin descubrir no se ve. La única pista: un destello tenue del color del bolsón cuando
## algún túnel ya pasa a `HINT_RADIUS` celdas o menos — para que cavar en esa dirección tenga
## sentido. Sin niebla (otros modos, pruebas) no dibuja nada.

const DARK := Color(0.05, 0.035, 0.025)
const ALPHA := 1.0
const HINT_RADIUS := 5

var sim: Simulation
var _img: Image
var _sprite: Sprite2D
var _drawn_version := -1
var _drawn_jobs := -1
## Bolsones sin descubrir pero con un túnel cerca (se recalcula cuando cambia la niebla).
var _hinted: Array[Plant] = []


func setup(s: Simulation) -> void:
	sim = s
	_drawn_version = -1
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.centered = false
		# Filtro lineal: el borde de la niebla se ve difuminado, no en escalones de celda.
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		# La oscuridad va detrás de lo que dibuja este nodo (el destello de los bolsones va encima).
		_sprite.show_behind_parent = true
		add_child(_sprite)
	_sprite.visible = sim.fog != null
	if sim.fog != null:
		_img = Image.create(sim.world.w, sim.world.h, false, Image.FORMAT_RGBA8)
		_sprite.scale = Vector2(sim.cfg.cell_px, sim.cfg.cell_px)
	_refresh()


func _process(_delta: float) -> void:
	if sim == null or sim.fog == null:
		return
	if sim.fog.version != _drawn_version or sim.world.jobs_version != _drawn_jobs:
		_refresh()
	queue_redraw()


func _refresh() -> void:
	if sim.fog == null:
		return
	_drawn_version = sim.fog.version
	_drawn_jobs = sim.world.jobs_version
	var fog := sim.fog
	var w := sim.world.w
	for i in fog.revealed.size():
		# Lo marcado para cavar se ve siempre, aunque esté bajo la niebla: el jugador tiene que ver
		# qué marcó.
		var seen := fog.revealed[i] == 1 or sim.world.cells[i] == WorldGrid.Cell.MARKED
		_img.set_pixel(i % w, i / w, Color(DARK, 0.0 if seen else ALPHA))
	_sprite.texture = ImageTexture.create_from_image(_img)
	_hinted.clear()
	for p in sim.plants:
		if p.is_mushroom() and not sim.is_discovered(p) and _near_revealed(p):
			_hinted.append(p)


func _near_revealed(p: Plant) -> bool:
	var w := sim.world.w
	for c in p.pocket:
		for dy in range(-HINT_RADIUS, HINT_RADIUS + 1):
			for dx in range(-HINT_RADIUS, HINT_RADIUS + 1):
				var x := c.x + dx
				var y := c.y + dy
				if sim.world.in_bounds(x, y) and y >= sim.cfg.surface_y + Fog.SURFACE_ROWS and sim.fog.revealed[y * w + x] == 1:
					return true
	return false


## El destello: unos puntitos del color del bolsón que titilan sobre la niebla.
func _draw() -> void:
	if sim == null or sim.fog == null:
		return
	var cpx := float(sim.cfg.cell_px)
	var t := Time.get_ticks_msec() / 1000.0
	for p in _hinted:
		var col: Color = PlantView.MUSHROOM_HUES[p.hue % PlantView.MUSHROOM_HUES.size()]
		for k in mini(5, p.pocket.size()):
			var c: Vector2i = p.pocket[(k * 7) % p.pocket.size()]
			var a := 0.3 + 0.25 * sin(t * 2.0 + k * 1.7)
			var pos := (Vector2(c) + Vector2(0.5, 0.5)) * cpx
			draw_circle(pos, cpx * 0.7, Color(col, a * 0.25))
			draw_circle(pos, cpx * 0.38, Color(col, a * 0.45))
			draw_circle(pos, cpx * 0.14, Color(col.lightened(0.4), a))
