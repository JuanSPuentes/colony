class_name CentipedeView
extends ThreatSpriteView
## Vista del ciempiés (`view/sprites/centipede/`, 8 direcciones, pixel art en gris, 100x100,
## generado para este juego — mismo origen que `view/sprites/ant/` y `view/sprites/spider/`). El
## comportamiento compartido vive en `ThreatSpriteView`; acá solo el tamaño, las texturas y de
## dónde sale `Centipede` en el tick actual. La dirección se sigue por la posición del frame
## anterior (en la base), no por el estado interno (`State.CHASE`/`RETREAT`): da el mismo
## resultado porque la posición ya se mueve hacia donde sea que el ciempiés esté yendo.

## 5 veces el tamaño de una hormiga obrera (`AntRenderer.BODY_SIZE`, escala 1.0 — a diferencia de
## la araña, acá el usuario pidió la referencia de la hormiga, no de la reina). Pedido explícito
## del usuario tras probar un tamaño fijo (11.5) y uno exagerado solo para el modo Test (20x la
## reina), que se descartó.
const SIZE_MULT := 5.0

## Mismo orden que `SpriteDir`/`SpiderView.DIR_TEXTURES`.
const DIR_TEXTURES: Array[Texture2D] = [
	preload("res://view/sprites/centipede/east.png"),
	preload("res://view/sprites/centipede/south-east.png"),
	preload("res://view/sprites/centipede/south.png"),
	preload("res://view/sprites/centipede/south-west.png"),
	preload("res://view/sprites/centipede/west.png"),
	preload("res://view/sprites/centipede/north-west.png"),
	preload("res://view/sprites/centipede/north.png"),
	preload("res://view/sprites/centipede/north-east.png"),
]


func _get_threat():
	return sim.centipede if sim != null else null


func _dir_textures() -> Array[Texture2D]:
	return DIR_TEXTURES


func _body_size() -> Vector2:
	return Vector2.ONE * AntRenderer.BODY_SIZE.x * SIZE_MULT
