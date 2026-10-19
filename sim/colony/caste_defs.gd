class_name CasteDefs
extends RefCounted
## Datos de cada casta (no lógica). Añadir una casta nueva solo requiere ampliar estos arrays,
## no tocar `ant_system.gd`. Orden fijo: Reina, Obrera, Nodriza, Soldado.
## Los multiplicadores de la Obrera son 1.0 a propósito: así el comportamiento de la Fase 0
## (donde todas las hormigas son obreras) no cambia ni un bit.

enum Caste { QUEEN, WORKER, NURSE, SOLDIER }

const NAMES: Array[String] = ["Reina", "Obrera", "Nodriza", "Soldado"]
## La reina era 0.0 porque nunca se movía sola; ahora puede caminar cuando el jugador la manda
## (`cmd_move_queen`), más lenta que el resto por ser la más grande/pesada de las 4 castas.
const SPEED_MULT: Array[float] = [0.5, 1.0, 0.9, 0.95]
const HP_MULT: Array[float] = [3.0, 1.0, 1.0, 1.8]
## Comida y agua que consume cada adulta por segundo.
const FOOD_PER_S: Array[float] = [0.045, 0.018, 0.018, 0.024]
const WATER_PER_S: Array[float] = [0.03, 0.012, 0.012, 0.018]
## Daño cuerpo a cuerpo por segundo (solo el soldado pelea).
const DAMAGE_PER_S: Array[float] = [0.0, 0.0, 0.0, 6.0]
## Comida que cuesta criar un huevo hasta adulta, por casta objetivo.
const EGG_FOOD_COST: Array[float] = [0.0, 4.0, 5.0, 8.0]
## Multiplicador de velocidad de desarrollo de la larva (el soldado tarda más).
const DEV_SPEED_MULT: Array[float] = [0.0, 1.0, 1.0, 0.8]
## Colores por casta: se ven siempre (no solo en la capa de depuración "Castas"), así que cada
## uno debe notarse de verdad contra la tierra, no solo el de la reina/nodriza/soldado.
const COLORS: Array[Color] = [
	Color("ffd43c"),  # Reina
	Color("e8a33d"),  # Obrera
	Color("4fd4e0"),  # Nodriza
	Color("c0392b"),  # Soldado
]
