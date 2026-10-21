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


func _init(s: Simulation) -> void:
	sim = s
	queen = RivalQueen.new(s)


## Aparece lejos del nido del jugador, a izquierda o derecha al azar (`cfg.rival_spawn_dist`), en
## la superficie — mismo punto de entrada que usa la araña. `ant_count` hormigas rivales
## (`Caste.SOLDIER`, el mismo daño/HP que ya tiene esa casta) alrededor de la reina rival.
func start_battle(ant_count: int, strength: float) -> void:
	battle_active = true
	battle_won = false
	var cfg := sim.cfg
	var side := 1 if sim.rng.randf() < 0.5 else -1
	var x := clampi(cfg.nest_x + side * cfg.rival_spawn_dist, 3, sim.world.w - 4)
	var cell := Vector2i(x, cfg.surface_y - 1)
	var at := Vector2((cell.x + 0.5) * cfg.cell_px, (cell.y + 0.5) * cfg.cell_px)
	queen.spawn(at, strength)
	for k in ant_count:
		var idx := sim.ants.add_ant_at(cell, CasteDefs.Caste.SOLDIER, 1)
		sim.ants.pos[idx] = at + Vector2(sim.rng.randf_range(-10.0, 10.0), sim.rng.randf_range(-6.0, 6.0))


## Llamar cada tick mientras `battle_active`. Se gana al morir la reina rival — no hace falta
## matar a todas sus hormigas (decapitada la colonia rival, lo que quede de la oleada sigue
## peleando pero ya no bloquea la siguiente estación: simplificación deliberada, ver README).
func update() -> void:
	if battle_active and not queen.alive:
		battle_active = false
		battle_won = true
