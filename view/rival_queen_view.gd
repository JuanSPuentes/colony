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
