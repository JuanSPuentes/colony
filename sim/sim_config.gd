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
