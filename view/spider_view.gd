class_name SpiderView
extends ThreatSpriteView
## Vista de la araña (`view/sprites/spider/`, 8 direcciones, pixel art en gris, 64x64, generado
## para este juego — ver `A_high-quality_2D_pixel_art_spider_enemy_for_a_dar.zip`). El
## comportamiento compartido (seguir dirección, rebote, barra de vida) vive en `ThreatSpriteView`;
## acá solo el tamaño, las texturas y de dónde sale `Spider` en el tick actual.

## 4 veces el tamaño de la reina (`AntRenderer.BODY_SIZE` × `CasteDefs.VISUAL_SCALE[QUEEN]`, la
## misma cuenta que usa `AntRenderer` para dibujarla — no un número aparte que se podría
## desincronizar si alguno de los dos cambia), siempre, no solo en el modo Test. Pedido explícito
## del usuario tras probar un primer tamaño fijo (11.5) y uno exagerado solo para el modo Test
## (10x), que se descartó.
const SIZE_MULT := 4.0

## Mismo orden que `SpriteDir`: crece con `Vector2.angle()` (0 = este, Y+ = hacia abajo/"sur").
const DIR_TEXTURES: Array[Texture2D] = [
	preload("res://view/sprites/spider/east.png"),
	preload("res://view/sprites/spider/south-east.png"),
	preload("res://view/sprites/spider/south.png"),
	preload("res://view/sprites/spider/south-west.png"),
	preload("res://view/sprites/spider/west.png"),
	preload("res://view/sprites/spider/north-west.png"),
	preload("res://view/sprites/spider/north.png"),
	preload("res://view/sprites/spider/north-east.png"),
]


func _get_threat():
	return sim.spider if sim != null else null


func _dir_textures() -> Array[Texture2D]:
	return DIR_TEXTURES


func _body_size() -> Vector2:
	var queen_size := AntRenderer.BODY_SIZE.x * CasteDefs.VISUAL_SCALE[CasteDefs.Caste.QUEEN]
	return Vector2.ONE * queen_size * SIZE_MULT
