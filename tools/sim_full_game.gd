extends SceneTree
## Fase 44: partida completa simulada. Un jugador automático juega Juego normal de punta a punta
## (4 estaciones, mudanzas, batallas) para encontrar errores que rompan la partida y medir el ritmo:
## en qué día se gana cada estación. Corre una partida en menos de un minuto, así que sirve para
## medir cada cambio de balance. No es una prueba (no falla): es una herramienta de medición.
##
## El jugador: abre el nido, compra huevos dejando reserva, compra la mejora más barata, y ataca a
## la reina rival con ventaja clara o al final de la estación. Al empezar cada estación guarda y
## vuelve a cargar, y avisa si eso cambia la partida. No pinta feromonas: junta menos comida que una
## persona.
##
## Uso:   godot --headless --path . --script tools/sim_full_game.gd
## Variables de entorno opcionales (para probar ajustes sin tocar la configuración):
##   SEEDS=11,12,13        semillas de los mapas
##   RIVAL_START=6         cfg.rival_start_ants
##   RIVAL_PER_SEASON=4    cfg.rival_start_ants_per_season
##   VERBOSE=1             una línea por día de juego

const SeasonSystem := preload("res://sim/colony/season_system.gd")
const MAX_DAYS := 95
const THINK_EVERY := 100  # ticks entre decisiones del jugador (5 s de juego)
const EGG_RESERVE := 30.0
const UPGRADE_RESERVE := 40.0

var sim: Simulation
var verbose := OS.get_environment("VERBOSE") == "1"


func _initialize() -> void:
	var seeds := [11, 12, 13]
	if OS.has_environment("SEEDS"):
		seeds = Array(OS.get_environment("SEEDS").split(",")).map(func(s: String) -> int: return int(s))
	print("semilla | resultado          | día en que se ganó cada estación | días | problemas")
	for s in seeds:
		print(_play_game(s))
	quit()


func _config() -> SimConfig:
	var cfg: SimConfig = load("res://sim/core/default_config.tres").duplicate()
	if OS.has_environment("RIVAL_START"):
		cfg.rival_start_ants = int(OS.get_environment("RIVAL_START"))
	if OS.has_environment("RIVAL_PER_SEASON"):
		cfg.rival_start_ants_per_season = int(OS.get_environment("RIVAL_PER_SEASON"))
	return cfg


func _play_game(seed_value: int) -> String:
	var cfg := _config()
	sim = Simulation.new(cfg, seed_value)
	sim.spawn_incremental_start(true)
	for y in range(cfg.surface_y, cfg.surface_y + cfg.shaft_depth):
		sim.cmd_mark(cfg.nest_x, y)  # abrir el nido
	var per_day := int(cfg.day_length_s / sim.dt)
	var problems: Array[String] = []
	var won_on: Array[int] = []
	var last_season := -1
	var t := 0
	while not sim.game_over and sim.day_number() <= MAX_DAYS:
		if sim.season_index != last_season:
			last_season = sim.season_index
			var p := _save_roundtrip()
			if p != "":
				problems.append(p)
		sim.tick()
		t += 1
		if sim.migration_pending:
			won_on.append(sim.day_number())
			sim = Migration.migrate(sim, sim.rng.randi())
			if sim.ants.rally_cell() < 0:
				problems.append("nido cerrado tras la mudanza %d" % won_on.size())
		if t % THINK_EVERY == 0:
			_play()
		if verbose and t % per_day == 0:
			_report_day()
	if sim.game_over and sim.victory:
		won_on.append(sim.day_number())
	var result := "SIN TERMINAR" if not sim.game_over else ("VICTORIA" if sim.victory else "DERROTA (est. %d)" % (sim.season_index + 1))
	return "%7d | %-18s | %-32s | %4d | %s" % [seed_value, result, str(won_on), sim.day_number(),
		"ninguno" if problems.is_empty() else ", ".join(problems)]


## Una decisión del jugador.
func _play() -> void:
	var econ := sim.econ
	if econ.can_buy_egg() and sim.colony.food >= econ.egg_cost() + EGG_RESERVE:
		sim.cmd_buy_egg()
	var best := -1
	for id in Upgrades.NODES.size():
		if sim.upgrades.can_buy(id) and sim.colony.food >= sim.upgrades.cost(id) + UPGRADE_RESERVE:
			if best < 0 or sim.upgrades.cost(id) < sim.upgrades.cost(best):
				best = id
	if best >= 0:
		sim.cmd_buy_upgrade(best)
	var rival := sim.rival_colony
	if rival.queen.alive and not rival.fighting():
		var mine: int = sim.ants.count_by_caste([CasteDefs.Caste.SOLDIER])[CasteDefs.Caste.SOLDIER]
		var left: int = SeasonSystem.season_length(sim) - 1 - SeasonSystem.day_in_season(sim)
		if mine >= rival.alive_count() + 4 or (left <= 1 and mine >= 3):
			sim.cmd_attack_rival()


## Guarda y vuelve a cargar; devuelve el problema encontrado o "".
func _save_roundtrip() -> String:
	var parsed = JSON.parse_string(JSON.stringify(SaveSystem.to_dict(sim)))
	if not (parsed is Dictionary) or not SaveSystem.is_loadable(parsed):
		return "el guardado de la estación %d no se puede cargar" % (sim.season_index + 1)
	var loaded := SaveSystem.from_dict(SaveSystem.migrate(parsed), sim.cfg)
	if loaded.checksum() != sim.checksum():
		return "guardar/cargar cambia la partida en la estación %d" % (sim.season_index + 1)
	sim = loaded
	return ""


func _report_day() -> void:
	var c := sim.ants.count_by_caste([CasteDefs.Caste.WORKER, CasteDefs.Caste.SOLDIER, CasteDefs.Caste.DRONE])
	var rival := sim.rival_colony
	print("   día %2d est.%d | comida %4.0f | obreras %3d soldados %3d zánganos %2d | rival %2d, reina %3.0f/%3.0f%s" % [
		sim.day_number(), sim.season_index + 1, sim.colony.food,
		c[CasteDefs.Caste.WORKER], c[CasteDefs.Caste.SOLDIER], c[CasteDefs.Caste.DRONE],
		rival.alive_count(), rival.queen.hp, rival.queen.max_hp, " PELEA" if rival.fighting() else ""])
