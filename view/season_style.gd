class_name SeasonStyle
extends RefCounted
## Fase 26: el ambiente de cada estación (solo visual: no cambia reglas). Una sola tabla que leen
## las vistas — cielo (`SkyView`), pasto (`TerrainView`), copas de los árboles (`PlantView`), lluvia
## o nieve (`RainView`) y partículas de ambiente (`AmbientView`). Como la colonia se muda al cambiar
## de estación (`Migration`), cada mapa nace con su estación: no hace falta transición.
##
## En Historia y el Nivel 0 siempre es Primavera, que es el aspecto de antes. En el modo Test se
## cambia con el botón "Siguiente estación" del panel de pruebas.

enum Season { SPRING, SUMMER, AUTUMN, WINTER }
enum Ambient { PETALS, FIREFLIES, LEAVES, SNOW }

const SKY_TOP: Array[Color] = [Color(0.30, 0.55, 0.92), Color(0.22, 0.52, 0.95), Color(0.42, 0.52, 0.78), Color(0.52, 0.62, 0.76)]
const SKY_BOTTOM: Array[Color] = [Color(0.66, 0.84, 0.97), Color(0.80, 0.90, 0.96), Color(0.96, 0.80, 0.62), Color(0.84, 0.88, 0.93)]
const GRASS: Array[Color] = [Color("4c9a3a"), Color("7fa23a"), Color("a3862f"), Color("eef3f7")]
const GRASS_DARK: Array[Color] = [Color("3a7a2c"), Color("5f7f2a"), Color("7a5f22"), Color("b9c7d4")]
## Tonos de copa por estación (uno por árbol, elegido por la celda como antes).
const LEAF_TINTS: Array = [
	[Color(0.36, 0.72, 0.30), Color(0.25, 0.58, 0.26), Color(0.48, 0.78, 0.28), Color(0.20, 0.48, 0.30), Color(0.62, 0.74, 0.26), Color(0.86, 0.56, 0.20)],
	[Color(0.22, 0.60, 0.22), Color(0.30, 0.66, 0.20), Color(0.18, 0.50, 0.24), Color(0.40, 0.70, 0.22)],
	# Otoño más oscuro que el color final: el shader aclara las luces (×1.25) y todo tiraba a amarillo.
	[Color(0.80, 0.34, 0.10), Color(0.68, 0.18, 0.10), Color(0.84, 0.56, 0.14), Color(0.58, 0.26, 0.10), Color(0.76, 0.42, 0.12)],
	[Color(0.40, 0.52, 0.42), Color(0.34, 0.46, 0.40), Color(0.46, 0.56, 0.48)],
]
const GIANT_TINT: Array[Color] = [Color(0.24, 0.6, 0.27), Color(0.18, 0.52, 0.22), Color(0.84, 0.42, 0.14), Color(0.32, 0.46, 0.38)]
## Cuánta nieve hay sobre las copas (0..1, lo usa `tree_color.gdshader`).
const SNOW_ON_TREES: Array[float] = [0.0, 0.0, 0.0, 0.75]
const AMBIENT: Array[int] = [Ambient.PETALS, Ambient.FIREFLIES, Ambient.LEAVES, Ambient.SNOW]


static func of(sim: Simulation) -> int:
	if sim == null or not (sim.incremental or sim.test_mode):
		return Season.SPRING
	return clampi(sim.season_index, 0, Season.WINTER)


static func snows(sim: Simulation) -> bool:
	return of(sim) == Season.WINTER


static func leaf_tint(sim: Simulation, cell: Vector2i) -> Color:
	var tints: Array = LEAF_TINTS[of(sim)]
	return tints[absi(cell.x * 1103515245 + cell.y * 12345 + 7) % tints.size()]
