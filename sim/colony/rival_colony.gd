class_name RivalColony
extends RefCounted
## Fase 9: la oleada de hormigas rivales + su reina al final de cada estación (ver
## `sim/colony/season_system.gd`). No es una segunda `Simulation`/`AntSystem` completa — sin cría,
## sin economía, sin cavar: las hormigas rivales viven en el mismo `AntSystem` que las del
## jugador, bando 1 (`AntSystem.faction`, `AntSystem._tick_rival`), así que heredan gratis el
## movimiento, la interpolación y el render que ya existen. La reina rival (`RivalQueen`) es
## aparte, no está en `AntSystem`: no necesita pathing, solo ser el objetivo a matar.

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


func _init(s: Simulation) -> void:
	sim = s
	queen = RivalQueen.new(s)


## Aparece lejos del nido del jugador, a izquierda o derecha al azar (`cfg.rival_spawn_dist`), en
## la superficie — mismo punto de entrada que usa la araña. `ant_count` hormigas rivales
## (`Caste.SOLDIER`, el mismo daño/HP que ya tiene esa casta) alrededor de la reina rival.
func start_battle(ant_count: int, strength: float) -> void:
	battle_active = true
	battle_won = false
	marching = false
	rally_s = 0.0
	var cfg := sim.cfg
	var side := 1 if sim.rng.randf() < 0.5 else -1
	var x := clampi(cfg.nest_x + side * cfg.rival_spawn_dist, 3, sim.world.w - 4)
	var cell := Vector2i(x, cfg.surface_y - 1)
	var at := Vector2((cell.x + 0.5) * cfg.cell_px, (cell.y + 0.5) * cfg.cell_px)
	queen.spawn(at, strength)
	for k in ant_count:
		var idx := sim.ants.add_ant_at(cell, CasteDefs.Caste.SOLDIER, 1)
		sim.ants.pos[idx] = at + Vector2(sim.rng.randf_range(-10.0, 10.0), sim.rng.randf_range(-6.0, 6.0))
	# Fase 17: con el nido todavía cerrado nadie puede salir a pelear (ni la oleada entrar): sin
	# este aviso la estación quedaba trabada sin que el jugador supiera por qué.
	if sim.ants.rally_cell() < 0:
		sim.notify("¡Tus soldados no pueden salir! Abre el nido cavando hasta la superficie.")


## Llamar cada tick mientras `battle_active`. Se gana al morir la reina rival — no hace falta
## matar a todas sus hormigas (decapitada la colonia rival, lo que quede de la oleada sigue
## peleando pero ya no bloquea la siguiente estación: simplificación deliberada, ver README).
func update() -> void:
	if battle_active and not marching:
		_update_rally()
	if battle_active and not queen.alive:
		battle_active = false
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
