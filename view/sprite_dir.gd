class_name SpriteDir
extends RefCounted
## Sector de 45° más cercano a un ángulo de movimiento (`Vector2.angle()`: 0 = este, crece hacia
## +Y = "sur" — ver el orden de `DIR_TEXTURES` en cada vista que usa esto). Compartido por
## `AntRenderer` y `ThreatSpriteView` (araña/ciempiés/mantis): antes era la misma función de 3
## líneas copiada 4 veces.

const COUNT := 8


static func index(angle: float) -> int:
	var a := fposmod(angle, TAU)
	return int(round(a / (PI / 4.0))) % COUNT
