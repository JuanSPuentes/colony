class_name RivalQueenView
extends ThreatSpriteView
## Vista de la reina rival (Fase 9, `Simulation.rival_colony.queen`). Reusa el mismo sprite de
## hormiga que `AntRenderer` (`view/sprites/ant/`), escalado como la reina del jugador y teñido de
## rojo oscuro (`AntRenderer.RIVAL_COLOR`) — sin arte nuevo para esta primera entrega, misma idea
## que el tinte de las hormigas rivales. No se mueve ni cambia de dirección en la práctica (no
## tiene pathing, ver `sim/threats/rival_queen.gd`), pero hereda ese soporte gratis de
## `ThreatSpriteView` por si en algún momento se le agrega movimiento.

const SIZE_MULT := 1.0  # ya usa el tamaño de "reina" (ver _body_size), no hace falta agrandarla más.


func _get_threat():
	return sim.rival_colony.queen if sim != null else null


func _dir_textures() -> Array[Texture2D]:
	return AntRenderer.DIR_TEXTURES


func _body_size() -> Vector2:
	return AntRenderer.BODY_SIZE * CasteDefs.VISUAL_SCALE[CasteDefs.Caste.QUEEN] * SIZE_MULT


func _tint() -> Color:
	return AntRenderer.RIVAL_COLOR


## Fase 31: con la rival en el mapa, su reina está en un montículo de tierra (la entrada de su
## nido). Se dibuja debajo de ella, antes que el resto (`super._draw` va después).
const MOUND := Color("6b4429")
const MOUND_DARK := Color("4f3220")
const MOUND_HOLE := Color("1d140d")


func _draw() -> void:
	if sim != null and sim.rival_colony.home:
		var cfg := sim.cfg
		var base := Vector2((sim.rival_colony.home_x + 0.5) * cfg.cell_px, cfg.surface_y * cfg.cell_px)
		# Loma en escalones de pixel: más ancha abajo, con un agujero oscuro al frente.
		for k in 4:
			var w := (7 - k * 1.6) * cfg.cell_px * 0.5
			var c := MOUND if k % 2 == 0 else MOUND_DARK
			draw_rect(Rect2(base.x - w, base.y - (k + 1) * 3.0, w * 2.0, 3.0), c)
		draw_rect(Rect2(base.x - 3.0, base.y - 5.0, 6.0, 5.0), MOUND_HOLE)
	super._draw()
