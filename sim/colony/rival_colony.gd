class_name RivalColony
extends RefCounted
## La colonia rival. No es una segunda `Simulation`/`AntSystem` completa — sin cría, sin economía,
## sin cavar: las hormigas rivales viven en el mismo `AntSystem` que las del jugador, bando 1
## (`AntSystem.faction`, `AntSystem._tick_rival`), así que heredan gratis el movimiento, la
## interpolación y el render. La reina rival (`RivalQueen`) es aparte, no está en `AntSystem`: no
## necesita pathing, solo ser el objetivo a matar.
##
## Dos formas de aparecer:
## - Fase 9: una oleada al final de la estación (`start_battle`), lejos del nido. Es lo que usan el
##   Nivel 0 y el mapa fijo de las pruebas.
## - Fase 31 (etapa A del núcleo, NUCLEO.md): en "Juego normal" la rival vive en el mapa desde el
##   principio (`home`), en un montículo del otro lado del árbol madre. Crece con el tiempo, manda
##   incursiones y se gana la estación cuando muere su reina — cuando el jugador decide atacar
##   (`player_attack`). El último día de la estación sigue llegando la oleada final como red de
##   seguridad, para que una estación nunca dure para siempre.

var sim: Simulation
var queen: RivalQueen
var battle_active := false
var battle_won := false
## Fase 17: formación de los soldados del jugador. Al empezar la batalla se juntan en la entrada
## del nido (`AntSystem.rally_cell`); cuando están casi todos, o pasado `cfg.rally_max_s`, salen
## JUNTOS hacia la reina rival (`marching`). Antes cada soldado seguía patrullando solo y llegaba de
## a uno al grupo rival, que lo mataba en un segundo sin que nadie llegara nunca a la reina.
var marching := false
var rally_s := 0.0

## Fase 31: la rival vive en el mapa (montículo en la columna `home_x`).
var home := false
var home_x := 0
var grow_acc := 0.0
var raid_acc := 0.0
## El jugador pidió atacar ("¡Atacar!"): sus soldados se reúnen y marchan como en una batalla.
var player_attack := false


func _init(s: Simulation) -> void:
	sim = s
	queen = RivalQueen.new(s)


## ¿Los soldados del jugador están en modo batalla (reunirse y marchar a la reina)?
func fighting() -> bool:
	return battle_active or player_attack


# --- Fase 31: la rival en el mapa desde el principio ----------------------------------------------

## Elige el lado del montículo (a izquierda o derecha del nido, al azar). Se llama antes de plantar
## el árbol madre, que va en el medio de los dos nidos.
func choose_home() -> void:
	var cfg := sim.cfg
	var side := 1 if sim.rng.randf() < 0.5 else -1
	home_x = clampi(cfg.nest_x + side * cfg.rival_spawn_dist, 4, sim.world.w - 5)
	home = true


## Columna del medio entre los dos nidos (donde va el árbol madre).
func midpoint_x() -> int:
	return (sim.cfg.nest_x + home_x) / 2


## Columnas que patrullan los soldados del jugador sin la orden de atacar: su mitad del mapa, hasta
## el árbol (x = mínimo, y = máximo). Sin esto patrullaban todo el mapa, llegaban solos al
## montículo y mataban a la reina antes de que el jugador decidiera atacar (rompía la carrera).
## Sin rival en el mapa, todo el ancho.
func player_patrol_range() -> Vector2i:
	var w := sim.world.w
	if not home or fighting():
		return Vector2i(3, w - 4)
	var mid := midpoint_x()
	return Vector2i(mid + 2, w - 4) if home_x < sim.cfg.nest_x else Vector2i(3, mid - 2)


## La reina en su montículo y las primeras guardias. La reina es más fuerte en cada estación.
func spawn_home() -> void:
	var cfg := sim.cfg
	queen.spawn(home_pos(), 1.0 + cfg.rival_queen_strength_growth * sim.season_index)
	for k in cfg.rival_start_ants:
		_add_ant()


func home_pos() -> Vector2:
	var cfg := sim.cfg
	return Vector2((home_x + 0.5) * cfg.cell_px, (cfg.surface_y - 0.5) * cfg.cell_px)


## Cada tick en "Juego normal": crece, manda incursiones. No hace nada si su reina ya murió.
func update_home(dt: float) -> void:
	if not home or not queen.alive:
		return
	var cfg := sim.cfg
	var grow_s: float = cfg.rival_grow_s[clampi(sim.season_index, 0, cfg.rival_grow_s.size() - 1)]
	grow_acc += dt
	while grow_acc >= grow_s:
		grow_acc -= grow_s
		if alive_count() < cfg.rival_max_ants:
			_add_ant()
	raid_acc += dt
	if raid_acc >= cfg.rival_raid_s:
		raid_acc = 0.0
		_send_raid()


## Segundos hasta la próxima incursión.
func raid_eta_s() -> float:
	return maxf(0.0, sim.cfg.rival_raid_s - raid_acc)


func alive_count() -> int:
	var n := 0
	var ants := sim.ants
	for i in ants.count:
		if ants.alive[i] == 1 and ants.faction[i] == 1:
			n += 1
	return n


## La mitad de las guardias (al menos una) sale contra el nido del jugador.
func _send_raid() -> void:
	var ants := sim.ants
	var guards: Array[int] = []
	for i in ants.count:
		if ants.alive[i] == 1 and ants.faction[i] == 1 and ants.raiding[i] == 0:
			guards.append(i)
	if guards.is_empty():
		return
	var n := maxi(1, int(round(guards.size() * sim.cfg.rival_raid_fraction)))
	for k in n:
		ants.raiding[guards[k]] = 1
	sim.notify("¡Incursión rival: %s hormigas vienen hacia tu nido!", [n])


func _add_ant() -> int:
	var cfg := sim.cfg
	var cell := Vector2i(home_x, cfg.surface_y - 1)
	var idx := sim.ants.add_ant_at(cell, CasteDefs.Caste.SOLDIER, 1)
	sim.ants.pos[idx] = home_pos() + Vector2(sim.rng.randf_range(-8.0, 8.0), 0.0)
	return idx


## "¡Atacar!": los soldados del jugador se reúnen en la salida y marchan juntos a la reina rival.
func cmd_attack() -> bool:
	if not home or not queen.alive or fighting():
		return false
	player_attack = true
	marching = false
	rally_s = 0.0
	sim.notify("¡Tus soldados se reúnen para atacar a la reina rival!")
	_warn_if_sealed()
	return true


# --- Fase 9: la oleada final ---------------------------------------------------------------------

## Oleada de `ant_count` soldados rivales alrededor de la reina. Sin montículo (Nivel 0, pruebas)
## aparece lejos del nido, a izquierda o derecha al azar (`cfg.rival_spawn_dist`), en la
## superficie. Con montículo (Fase 31) sale de él, con la reina que ya está ahí, y TODAS las
## rivales van contra el nido del jugador.
func start_battle(ant_count: int, strength: float) -> void:
	battle_active = true
	battle_won = false
	marching = false
	rally_s = 0.0
	var cfg := sim.cfg
	if home:
		for k in ant_count:
			sim.ants.raiding[_add_ant()] = 1
		for i in sim.ants.count:
			if sim.ants.alive[i] == 1 and sim.ants.faction[i] == 1:
				sim.ants.raiding[i] = 1
	else:
		var side := 1 if sim.rng.randf() < 0.5 else -1
		var x := clampi(cfg.nest_x + side * cfg.rival_spawn_dist, 3, sim.world.w - 4)
		var cell := Vector2i(x, cfg.surface_y - 1)
		var at := Vector2((cell.x + 0.5) * cfg.cell_px, (cell.y + 0.5) * cfg.cell_px)
		queen.spawn(at, strength)
		for k in ant_count:
			var idx := sim.ants.add_ant_at(cell, CasteDefs.Caste.SOLDIER, 1)
			sim.ants.pos[idx] = at + Vector2(sim.rng.randf_range(-10.0, 10.0), sim.rng.randf_range(-6.0, 6.0))
			sim.ants.raiding[idx] = 1
	_warn_if_sealed()


## Fase 17: con el nido todavía cerrado nadie puede salir a pelear (ni la oleada entrar): sin este
## aviso la estación quedaba trabada sin que el jugador supiera por qué.
func _warn_if_sealed() -> void:
	if sim.ants.rally_cell() < 0:
		sim.notify("¡Tus soldados no pueden salir! Abre el nido cavando hasta la superficie.")


## Llamar cada tick mientras haya pelea (`fighting()`). Se gana al morir la reina rival — no hace
## falta matar a todas sus hormigas (decapitada la colonia rival, lo que quede sigue peleando pero
## ya no bloquea la siguiente estación: simplificación deliberada, ver README).
func update() -> void:
	if fighting() and not marching:
		_update_rally()
	if fighting() and not queen.alive:
		battle_active = false
		player_attack = false
		battle_won = true


## Pasa a `marching` cuando ~3/4 de los soldados ya están en el punto de reunión, o al agotarse el
## tiempo de espera (también si no hay soldados, o si el nido todavía está cerrado y no hay salida).
func _update_rally() -> void:
	var cfg := sim.cfg
	rally_s += sim.dt
	var rc := sim.ants.rally_cell()
	var total := 0
	var near := 0
	if rc >= 0:
		var rp := sim.ants._center(rc % sim.world.w, rc / sim.world.w)
		for i in sim.ants.count:
			if sim.ants.alive[i] == 1 and sim.ants.faction[i] == 0 and sim.ants.caste[i] == CasteDefs.Caste.SOLDIER:
				total += 1
				if sim.ants.pos[i].distance_to(rp) <= cfg.rally_radius_cells * cfg.cell_px:
					near += 1
	if rc < 0 or total == 0 or rally_s >= cfg.rally_max_s or near * 4 >= total * 3:
		marching = true
