class_name CasteDefs
extends RefCounted
## Datos de cada casta (no lógica). Añadir una casta nueva solo requiere ampliar estos arrays,
## no tocar `ant_system.gd`. Orden fijo: Reina, Obrera, Nodriza, Soldado, Zángano.
## Los multiplicadores de la Obrera son 1.0 a propósito: así el comportamiento de la Fase 0
## (donde todas las hormigas son obreras) no cambia ni un bit.
##
## Zángano (liviano a propósito, ver README): no explora, no caza, no cava — se queda donde nace
## (igual que la reina sin orden de moverse) y mientras esté vivo acelera la puesta de huevos
## (`Colony.tick`, `cfg.drone_egg_speed_bonus`). Sin vuelo nupcial ni otras colonias con las que
## cruzarse todavía, así que su única función hoy es esa, no la reproducción real de la especie.

enum Caste { QUEEN, WORKER, NURSE, SOLDIER, DRONE }

const NAMES: Array[String] = ["Reina", "Obrera", "Nodriza", "Soldado", "Zángano"]
## La reina era 0.0 porque nunca se movía sola; ahora puede caminar cuando el jugador la manda
## (`cmd_move_queen`), más lenta que el resto por ser la más grande/pesada de las 5 castas.
const SPEED_MULT: Array[float] = [0.5, 1.0, 0.9, 0.95, 0.0]
const HP_MULT: Array[float] = [3.0, 1.0, 1.0, 1.8, 0.8]
## Comida y agua que consume cada adulta por segundo.
const FOOD_PER_S: Array[float] = [0.045, 0.018, 0.018, 0.024, 0.02]
const WATER_PER_S: Array[float] = [0.03, 0.012, 0.012, 0.018, 0.012]
## Daño cuerpo a cuerpo por segundo (solo el soldado pelea).
const DAMAGE_PER_S: Array[float] = [0.0, 0.0, 0.0, 6.0, 0.0]
## Comida que cuesta criar un huevo hasta adulta, por casta objetivo.
const EGG_FOOD_COST: Array[float] = [0.0, 4.0, 5.0, 8.0, 5.0]
## Multiplicador de velocidad de desarrollo de la larva (el soldado tarda más).
const DEV_SPEED_MULT: Array[float] = [0.0, 1.0, 1.0, 0.8, 1.0]
## Tamaño visual relativo (1.0 = el de siempre). Solo la reina se ve distinta de tamaño: una
## "hormiga reina real" bien grande frente al resto (ver `AntRenderer.update`).
const VISUAL_SCALE: Array[float] = [1.8, 1.0, 1.0, 1.0, 1.0]
## Colores por casta: se ven siempre (no solo en la capa de depuración "Castas"), así que cada
## uno debe notarse de verdad contra la tierra, no solo el de la reina/nodriza/soldado. La reina
## es un tono "puro" (perla/marfil) bien distinto del ámbar sucio de la obrera; el zángano, morado,
## para que no se confunda con ninguna otra casta.
const COLORS: Array[Color] = [
	Color("fdf6ec"),  # Reina
	Color("e8a33d"),  # Obrera
	Color("4fd4e0"),  # Nodriza
	Color("c0392b"),  # Soldado
	Color("9b59b6"),  # Zángano
]
