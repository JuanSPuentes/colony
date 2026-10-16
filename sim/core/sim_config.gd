class_name SimConfig
extends Resource
## Todos los números ajustables de la simulación. Nada de números mágicos fuera de aquí.
## Las velocidades de hormiga están en celdas por segundo; los tiempos, en segundos de simulación.

@export_group("Mundo")
@export var grid_w := 120
@export var grid_h := 70
@export var cell_px := 8
## Primera fila de tierra. Todo lo de arriba es aire.
@export var surface_y := 22
## Filas de aire sobre el suelo por las que pueden caminar las hormigas.
@export var walk_band := 3
@export var rock_clusters := 16
@export var nest_x := 60
@export var shaft_depth := 7
@export var chamber_w := 7
@export var chamber_h := 3

@export_group("Simulación")
@export var world_seed := 12345
@export var tick_rate := 20
@export var initial_ants := 100
@export var stress_ants := 400

@export_group("Plantas")
@export var plant_count := 7
@export var plant_min_dist := 12
@export var plant_max_dist := 52
@export var leaves_per_plant := 45

@export_group("Hormigas")
@export var ant_speed := 3.4
@export var carry_speed_mult := 0.85
@export var water_speed_mult := 0.6
@export var think_ticks_min := 3
@export var think_ticks_max := 5
@export var sight_cells := 4.0
@export var pickup_cells := 1.6
@export var ant_hp := 10.0
@export var rest_seconds_min := 1.0
@export var rest_seconds_max := 4.0
@export var stuck_seconds := 3.0
@export var stuck_min_move_px := 2.0
## Pesos de la puntuación de pasos (EXPLORE / GO_TO_FOOD).
@export var w_persist := 0.5
@export var w_food := 8.0
@export var w_home_repel := 1.5
@export var w_noise := 1.4
@export var w_outward := 0.9
@export var food_follow_threshold := 0.05
@export var ignore_trail_seconds := 12.0
@export var max_diggers_fraction := 0.35

@export_group("Feromonas")
@export var food_decay_per_s := 0.012
@export var home_decay_per_s := 0.010
@export var rain_decay_mult := 4.0
@export var food_deposit := 0.35
@export var food_trail_range := 90
@export var home_deposit := 0.18
@export var home_range := 70
@export var paint_start := 0.30
@export var paint_ramp := 0.012
@export var pheromone_step_ticks := 5

@export_group("Excavación")
@export var dig_seconds := 2.4
@export var field_refresh_ticks := 4

@export_group("Lluvia y agua")
@export var rain_auto := true
@export var rain_first_s := 150.0
@export var rain_interval_s := 200.0
@export var rain_duration_s := 30.0
@export var rain_warning_s := 10.0
## Agua que entra por segundo por cada columna de captación de una abertura al exterior.
@export var rain_rate := 0.10
## Columnas a cada lado de una abertura cuya lluvia se encauza hacia ella.
@export var rain_funnel := 3
@export var evap_per_s := 0.006
@export var water_step_ticks := 2
## Máximo de celdas que visita la búsqueda de la celda seca más cercana al huir.
@export var flee_search_cells := 700
@export var flee_level := 0.25
@export var safe_level := 0.05
@export var deep_level := 0.5
@export var drown_damage_per_s := 1.5

@export_group("Fase 1: castas iniciales")
## Nodrizas con las que arranca la colonia (además de la reina y las obreras de `initial_ants`).
@export var initial_nurses := 4
@export var queen_hp_base := 10.0

@export_group("Fase 1: economía")
@export var start_food := 400.0
@export var start_water := 400.0
@export var base_food_cap := 300.0
@export var base_water_cap := 300.0
## Comida que convierte en hongo cada celda válida de Jardín de hongos, por segundo.
@export var fungus_rate_per_cell := 0.08
@export var storage_food_per_cell := 15.0
@export var storage_water_per_cell := 15.0
## Simplificación de la Fase 1: el agua entra despacio mientras haya charcos tras la lluvia
## (no hay una tarea específica de "traer agua"). `water_regen_dry` es el goteo base.
@export var water_regen_wet := 0.6
@export var water_regen_dry := 0.08
## Daño por segundo cuando falta comida o agua. No afecta a la obrera (compatibilidad con la
## Fase 0): solo reina, nodrizas y soldados sufren hambre en este MVP.
@export var hunger_damage_per_s := 0.18
@export var egg_food_threshold := 60.0
@export var egg_lay_cost := 8.0
@export var egg_interval_s := 14.0

@export_group("Fase 1: cría")
@export var egg_time_s := 18.0
@export var larva_time_s := 40.0
@export var pupa_time_s := 26.0
## Probabilidad por segundo de que una cría muera si está en agua profunda sin guardería válida.
@export var brood_flood_death_chance := 0.08

@export_group("Fase 1: cámaras")
@export var room_min_royal := 9
@export var room_min_nursery := 6
@export var room_min_storage := 6
@export var room_min_fungus := 12
@export var room_min_drain := 4
## Cuánta agua absorbe cada celda válida de Drenaje, por segundo (se resta del nivel de agua).
@export var drain_rate_per_cell := 0.05

@export_group("Fase 1: feromonas nuevas")
@export var danger_decay_per_s := 0.03
@export var attack_decay_per_s := 0.05
@export var evacuate_decay_per_s := 0.02
@export var danger_flee_threshold := 0.1
@export var evacuate_threshold := 0.1
@export var danger_deposit := 0.6

@export_group("Fase 1: nodrizas y soldados")
## Qué tan lejos del nido (en celdas de camino) sigue contando una nodriza como "cuidando".
@export var nurse_range := 7
@export var soldier_guard_range := 10
@export var soldier_melee_range_px := 10.0
@export var soldier_sight_px := 70.0

@export_group("Fase 1: araña")
@export var spider_hp := 40.0
@export var spider_speed := 2.6
@export var spider_damage_per_s := 7.0
@export var spider_bite_range := 6.0
@export var spider_sight_px := 90.0
@export var spider_flee_hp_pct := 0.3
@export var spider_flee_soldiers := 4
@export var spider_siege_guard_range := 14.0
@export var spider_siege_time_s := 22.0
@export var spider_invasion_damage := 2.0
## Primera araña cuando la población llega a esto; luego cada `spider_interval_s`, algo más fuerte.
@export var spider_first_population := 20
@export var spider_interval_s := 150.0
@export var spider_strength_growth := 0.25

@export_group("Fase 1: eras")
@export var era2_population := 20
@export var era3_population := 60
