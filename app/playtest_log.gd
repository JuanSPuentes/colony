class_name PlaytestLog
extends RefCounted
## Fase 42: registro del playtest (decidir el rendimiento con datos, no a ojo). Por cada partida
## guarda en `user://playtest/` un JSON chico con: la colonia más grande, cuánto se jugó a cada
## velocidad, hasta qué estación se llegó, cómo terminó y cuándo el juego no pudo mantener la
## velocidad pedida (o se trabó un frame). Solo local: no se envía a ningún lado; quien prueba
## manda el archivo a mano. No escribe nada sin ventana (las pruebas corren `--headless`).
##
## `main.gd` llama `sample` cada frame y `save` al terminar; también se guarda cada `SAVE_EVERY_S`
## para no perder la sesión si el juego se cierra de golpe.

const DIR := "user://playtest"
const SAVE_EVERY_S := 30.0
## Un frame más largo que esto cuenta como trabón (se ve como un salto).
const HITCH_S := 0.1
## Los primeros frames de cada partida son la carga: no cuentan como trabones.
const WARMUP_S := 2.0

var enabled := DisplayServer.get_name() != "headless"
var path := ""
var data := {
	"version": 1,
	"mode": "",
	"started": "",
	"played_s": 0.0,         # tiempo de juego sin pausa (segundos reales)
	"speed_s": {"1": 0.0, "2": 0.0, "4": 0.0},
	"max_ants": 0,           # hormigas propias vivas, el máximo
	"max_season": 0,
	"behind_s": 0.0,         # tiempo en que la simulación no llegó a la velocidad pedida
	"behind_max_ants": 0,    # con cuántas hormigas pasó eso por última vez (lo más alto)
	"hitches": 0,            # frames de más de HITCH_S
	"worst_frame_ms": 0.0,
	"result": "en curso",
}
var _since_save := 0.0
var _age := 0.0


func _init(mode: String) -> void:
	data["mode"] = mode
	data["started"] = Time.get_datetime_string_from_system().replace(":", "-")
	path = "%s/%s_%s.json" % [DIR, data["started"], mode]


## Un frame de juego. `behind`: la simulación descartó tiempo porque no daba abasto
## (`main.MAX_TICKS_PER_FRAME`).
func sample(delta: float, sim: Simulation, speed: int, paused: bool, behind: bool) -> void:
	if not enabled:
		return
	_age += delta
	if _age > WARMUP_S:
		data["worst_frame_ms"] = maxf(data["worst_frame_ms"], delta * 1000.0)
		if delta > HITCH_S:
			data["hitches"] += 1
	var ants := sim.ants.count_by_caste([CasteDefs.Caste.WORKER, CasteDefs.Caste.SOLDIER, CasteDefs.Caste.DRONE])
	var n: int = ants.values().reduce(func(a: int, b: int) -> int: return a + b, 0)
	data["max_ants"] = maxi(data["max_ants"], n)
	data["max_season"] = maxi(data["max_season"], sim.season_index)
	if not paused and not sim.game_over:
		data["played_s"] += delta
		var key := str(speed)
		data["speed_s"][key] = data["speed_s"].get(key, 0.0) + delta
		if behind:
			data["behind_s"] += delta
			data["behind_max_ants"] = maxi(data["behind_max_ants"], n)
	if sim.game_over:
		data["result"] = "victoria" if sim.victory else "derrota"
	_since_save += delta
	if _since_save >= SAVE_EVERY_S:
		save()


func save() -> void:
	if not enabled:
		return
	_since_save = 0.0
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	SaveSystem.write_text_atomic(path, JSON.stringify(data, "\t"))
