class_name MantisView
extends ThreatSpriteView
## Vista de la mantis (`view/sprites/mantis/`, 8 direcciones, pixel art en gris, generado para
## este juego — mismo origen que `view/sprites/ant/`, `spider/` y `centipede/`). El comportamiento
## compartido vive en `ThreatSpriteView`; acá solo el tamaño, las texturas y de dónde sale
## `Mantis` en el tick actual. Casi nunca cambia de dirección (`Mantis.State.HIDDEN`/`ATTACK` no
## mueven su posición a propósito, ver `sim/threats/mantis.gd`): solo huyendo (`State.RETREAT`) se
## nota, y el seguimiento por posición de la base ya lo resuelve solo.

## 2 veces el tamaño de la reina (misma referencia en vivo que `SpiderView.SIZE_MULT`, ver ahí).
const SIZE_MULT := 2.0

## Mismo orden que `SpriteDir`/`SpiderView.DIR_TEXTURES`/`CentipedeView.DIR_TEXTURES`.
const DIR_TEXTURES: Array[Texture2D] = [
	preload("res://view/sprites/mantis/east.png"),
	preload("res://view/sprites/mantis/south-east.png"),
	preload("res://view/sprites/mantis/south.png"),
	preload("res://view/sprites/mantis/south-west.png"),
	preload("res://view/sprites/mantis/west.png"),
	preload("res://view/sprites/mantis/north-west.png"),
	preload("res://view/sprites/mantis/north.png"),
	preload("res://view/sprites/mantis/north-east.png"),
]


func _get_threat():
	return sim.mantis if sim != null else null


func _dir_textures() -> Array[Texture2D]:
	return DIR_TEXTURES


func _body_size() -> Vector2:
	var queen_size := AntRenderer.BODY_SIZE.x * CasteDefs.VISUAL_SCALE[CasteDefs.Caste.QUEEN]
	return Vector2.ONE * queen_size * SIZE_MULT


## Fase 16: color propio (el sprite viene en gris): verde hoja, camuflada entre las plantas.
func _tint() -> Color:
	return Color(0.55, 0.95, 0.4)
