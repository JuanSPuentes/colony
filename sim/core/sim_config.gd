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
## Filas de aire sobre el suelo por las que pueden caminar las hormigas. 1 alcanza para llegar a
## una planta (`Plant.cell.y = surface_y - 1`, y `pickup_cells` ya cubre tomar la hoja desde el
## suelo sin subir). Con 3 se veían "flotando" varias filas por encima de la tierra al perseguir
## una hoja lejos de cualquier parte sólida visible.
@export var walk_band := 1
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
## Comida que vale cada hoja que una obrera trae al nido (modo clásico; el incremental tiene su
## propio `inc_food_per_leaf`). Reemplaza al Jardín de hongos: ya no hay conversión con ritmo
## propio, la hoja se vuelve comida apenas llega.
@export var leaf_food_value := 1.0
## Punto 4 (saqueo de cadáveres): una obrera puede traer los restos de una hormiga o de una
## amenaza muerta, igual que trae una hoja, y valen más comida que una hoja al llegar. Se agotan
## de un solo viaje y desaparecen solos si nadie los recoge antes de `corpse_decay_s`.
@export var corpse_food_value := 6.0
@export var corpse_food_value_spider := 15.0
@export var corpse_food_value_centipede := 20.0
@export var corpse_food_value_mantis := 18.0
@export var corpse_decay_s := 90.0
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
## Cada zángano vivo acelera la puesta de huevos este tanto (sin tope: liviano a propósito, ver
## README). 0.2 = +20% de velocidad de puesta por zángano.
@export var drone_egg_speed_bonus := 0.2

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

@export_group("Fase 1: feromonas nuevas")
@export var danger_decay_per_s := 0.03
@export var attack_decay_per_s := 0.05
@export var evacuate_decay_per_s := 0.02
@export var danger_flee_threshold := 0.1
@export var evacuate_threshold := 0.1

@export_group("Fase 1: nodrizas y soldados")
## Qué tan lejos del nido (en celdas de camino) sigue contando una nodriza como "cuidando".
@export var nurse_range := 7
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
## Modo incremental: dispara igual que `spider_first_population`, pero con su propio umbral
## porque ese modo arranca y crece con colonias mucho más chicas (ver README sección 9b).
@export var inc_spider_first_population := 15

## Fase 5: segunda amenaza, entra por los túneles ya cavados (a diferencia de la araña, que solo
## caza en superficie). Números sin playtesting todavía, primera estimación (ver README sección
## de simplificaciones deliberadas de esta fase).
@export_group("Fase 5: ciempiés")
@export var centipede_hp := 55.0
@export var centipede_speed := 2.2
@export var centipede_damage_per_s := 9.0
@export var centipede_bite_range := 6.0
## A diferencia de `spider_sight_px`, esto ve hormigas bajo tierra también, no solo en superficie.
@export var centipede_sight_px := 110.0
@export var centipede_flee_hp_pct := 0.3
## Cada cuántos ticks recalcula el camino (BFS de grilla completa) hacia la presa actual, en vez de
## cada tick: el mismo mecanismo que `cmd_move_queen`, pero perseguido en vez de pedido una vez.
@export var centipede_retarget_ticks := 10
## Aparece después que la araña (umbral mayor) para que la amenaza escale con el tiempo.
@export var centipede_first_population := 45
@export var centipede_interval_s := 180.0
@export var centipede_strength_growth := 0.25

## Fase 7: tercera amenaza. A diferencia de la araña (caza activa en superficie) y el ciempiés
## (persigue por los túneles), la mantis se queda quieta y camuflada en un punto fijo: nunca
## persigue, pero si algo se acerca le pega mucho más fuerte. Números sin playtesting todavía.
@export_group("Fase 7: mantis")
@export var mantis_hp := 45.0
## Notablemente más alto que `spider_damage_per_s`/`centipede_damage_per_s`: el golpe de una
## emboscada que no persigue tiene que doler.
@export var mantis_damage_per_s := 16.0
## Corto a propósito: la mantis no "ve" de lejos como la araña, solo reacciona a lo que ya está
## encima suyo.
@export var mantis_strike_range_px := 7.0
@export var mantis_flee_hp_pct := 0.3
## Entre `spider_first_population` y `centipede_first_population`: un peligro de superficie que
## aparece antes de que la colonia cave tan hondo como para toparse con el ciempiés.
@export var mantis_first_population := 32
@export var mantis_interval_s := 165.0
@export var mantis_strength_growth := 0.25

@export_group("Fase 1: eras")
@export var era2_population := 20
@export var era3_population := 60

@export_group("Fase 3: día y noche")
## Duración de un día completo (luz + noche) en segundos de simulación. Un día + una noche = 1 día.
@export var day_length_s := 300.0
## Fracción del ciclo que es de noche (el resto es de día). El ciclo arranca al amanecer.
@export var night_fraction := 0.4

@export_group("Fase 3: modo incremental")
## Colonia inicial del modo incremental: reina + estas obreras + estos soldados + larvas de obrera.
@export var inc_start_workers := 3
@export var inc_start_soldiers := 1
@export var inc_start_larvae := 1
@export var inc_start_food := 40.0
## Comida que vale cada hoja que una obrera trae al nido. Todo se mide en comida: no hay agua ni
## hongo como recursos aparte en este modo.
@export var inc_food_per_leaf := 4.0
## El jugador compra un huevo (no una casta): precio base, y cada compra multiplica el siguiente
## por `growth`. Qué sale al nacer es al azar (`inc_egg_soldier_chance`), no una elección del
## jugador — ver README sección 9b.
@export var inc_egg_cost := 20.0
@export var inc_egg_cost_growth := 1.07
## Probabilidad de que un huevo nazca soldado; el resto, obrera. Las nodrizas no se compran en
## este modo (sin cambios: ver sección 9b).
@export var inc_egg_soldier_chance := 0.3
## La auto-compra deja siempre esta comida de reserva para no matar de hambre a la reina.
@export var inc_auto_reserve := 10.0
## Multiplica la velocidad de la cría (huevo, larva y pupa) para que una compra no tarde minutos.
@export var inc_brood_speed := 2.0
## Primera lluvia del modo incremental (la de la Fase 1 llega a los 150 s, demasiado pronto para
## una colonia de 5 hormigas que todavía no puede cavar un drenaje). Por defecto: inicio del día 3
## (`day_length_s * 2`; si `day_length_s` cambia, esto hay que recalcularlo a mano).
@export var inc_rain_first_s := 600.0
## Fase 23: en Juego normal llovía cada `rain_interval_s` (200 s, ~1,5 lluvias por día de 300 s): casi
## todos los días, y la supervivencia se volvía muy difícil. Ahora la próxima lluvia llega entre
## estos dos valores (1,5 a 2,5 días), al azar para que no sea predecible.
@export var inc_rain_interval_min_s := 450.0
@export var inc_rain_interval_max_s := 750.0
## Hojas que rebrota cada planta por segundo, solo de día y hasta su máximo.
@export var inc_plant_regrow_per_s := 0.1
## Fase 19: árbol gigante (más hojas, rebrote más rápido). Fase 29: ya no se reparten gigantes por
## el mapa (los reemplaza el árbol madre); quedan estos valores para los de partidas guardadas antes.
@export var giant_leaves_mult := 4.0
@export var giant_regrow_mult := 2.5
## Fase 29: árbol madre, un solo árbol gigante encima del nido (solo "Juego normal" con mapa al
## azar). No se cosecha directo: deja caer hojas, semillas y frutas alrededor del tronco a un ritmo
## fijo (de noche, la mitad) — comida segura pero limitada. Lo que nadie recoge se pudre.
@export var home_tree_drop_interval_s := 6.0
## Hasta cuántas celdas a cada lado del tronco cae lo que suelta (más o menos el ancho de la copa).
@export var home_tree_drop_radius := 26
## Más que esto en el suelo a la vez y deja de soltar (una colonia chica no aprovecha todo).
@export var home_tree_max_drops := 18
## Probabilidad de cada cosa al caer (el resto, hoja) y cuánta comida vale al llegar al nido.
@export var home_tree_seed_chance := 0.28
@export var home_tree_fruit_chance := 0.07
@export var drop_food_leaf := 4.0
@export var drop_food_seed := 10.0
@export var drop_food_fruit := 30.0
@export var drop_decay_s := 120.0
## Los demás árboles quedan lejos del madre (celdas desde su tronco) y son menos. Con 0 no hay otros:
## pedido del jugador, que el árbol madre sea el único (la escala hormiga/árbol se ve de verdad).
@export var home_tree_clear_cells := 16
@export var home_tree_other_trees := 0
## Fase 19: bolsones de hongos en la primera capa de tierra (solo "Juego normal" con mapa al azar).
## Cerrados al empezar: hay que cavar hasta ellos. Rebrotan también de noche.
@export var mushroom_pockets_min := 3
@export var mushroom_pockets_max := 5
@export var mushroom_pieces := 30
@export var mushroom_regrow_per_s := 0.05

## Fase 9: estaciones y colonia rival del modo incremental (reemplaza la condición de victoria de
## la Fase 8, retirada — ver README sección 15/16). 4 estaciones fijas (`SeasonSystem.SEASON_COUNT`);
## derrotar a las 4 colonias rivales, una por estación, es la victoria real de este modo.
@export_group("Fase 9: estaciones y colonia rival")
## Días de simulación (`DayNight.day_number`) que dura cada estación antes de que ataque la
## colonia rival de esa estación.
## Fase 17: una duración por estación (Primavera, Verano, Otoño, Invierno), en días de juego. La
## batalla llega el último día de cada una. Antes era un solo número (5) para las cuatro.
@export var season_days: Array[int] = [20, 15, 25, 15]
## Oleada de la primera estación: esta cantidad de hormigas rivales. Cada estación siguiente suma
## `rival_wave_ants_growth` más.
@export var rival_wave_base_ants := 6
@export var rival_wave_ants_growth := 4
## Vida base de la reina rival (antes de `rival_queen_strength_growth` por estación).
@export var rival_queen_hp_base := 60.0
@export var rival_queen_strength_growth := 0.5
## Qué tan lejos del nido (en celdas) aparece la oleada rival, a izquierda o derecha al azar.
@export var rival_spawn_dist := 45

## Fase 31 (etapa A del núcleo, ver NUCLEO.md): en "Juego normal" la colonia rival está en el mapa
## desde el principio, en un montículo a `rival_spawn_dist` celdas del nido; el árbol madre queda
## en el medio. Crece sola (una hormiga cada `rival_grow_s[estación]` segundos, hasta
## `rival_max_ants`) y cada `rival_raid_s` manda a la mitad (`rival_raid_fraction`) contra tu
## nido. Se gana la estación matando a su reina cuando el jugador quiera ("¡Atacar!").
## Apagarla deja la rival como antes (solo la oleada final); lo usan pruebas de otras cosas.
@export var rival_home := true
@export var rival_start_ants := 3
@export var rival_grow_s: Array[float] = [45.0, 38.0, 32.0, 26.0]
@export var rival_max_ants := 40
@export var rival_raid_s := 150.0
@export var rival_raid_fraction := 0.5
## Qué tan lejos de su montículo deambulan las guardias rivales (celdas).
@export var rival_guard_radius := 6

## Mejoras de la colonia (`sim/colony/upgrades.gd`), compradas con comida: solo afectan a las
## hormigas nuevas desde que se compran. Mismo costo creciente que un huevo (`inc_egg_cost*growth`).
@export var inc_upgrade_base_cost := 40.0
@export var inc_upgrade_cost_growth := 1.12
@export var inc_upgrade_damage_step := 0.15
@export var inc_upgrade_hp_step := 0.15
@export var inc_upgrade_speed_step := 0.08
@export var inc_upgrade_work_step := 0.12

## Fase 14: Nivel 0 (tutorial jugable, ver `sim/colony/tutorial_level.gd`).
## Fase 14: patrulla del soldado (ver `AntCasteAI.patrol`).
@export_group("Fase 14: patrulla y zánganos")
## Probabilidad de que, al elegir el siguiente punto de patrulla, el soldado vaya a revisar el nido.
@export var soldier_nest_check_chance := 0.2
@export var soldier_nest_check_s := 6.0
## Si no llega a su punto de patrulla en este tiempo (algo en el camino), elige otro.
@export var soldier_patrol_timeout_s := 40.0
## Probabilidad de que un huevo comprado en Juego normal nazca zángano (sale de la parte de
## obrera: `inc_egg_soldier_chance` no cambia).
@export var inc_egg_drone_chance := 0.12
## Si las obreras (vivas + cría) son menos que esta fracción de obreras+soldados+zánganos, el huevo
## sale obrera con `inc_egg_worker_boost_chance`; el resto se reparte entre soldado y zángano.
@export var inc_egg_worker_min_share := 0.6
@export var inc_egg_worker_boost_chance := 0.85
## Zángano guardián: si una amenaza llega a esta distancia (px) de la reina o de un huevo, los
## zánganos van a pelear ahí; más lejos no persiguen (su lugar es junto a la reina).
@export var drone_guard_px := 64.0
## Fase 17: además, la amenaza tiene que estar a esta cantidad de celdas de la reina POR LOS TÚNELES.
@export var drone_guard_cells := 12
## Fase 17: formación de batalla (ver `RivalColony._update_rally`): cuánto esperan los soldados
## en la entrada a que lleguen los demás antes de marchar, y qué tan cerca cuenta como "llegó".
@export var rally_max_s := 25.0
@export var rally_radius_cells := 4.0

@export_group("Fase 14: Nivel 0")
## Comida inicial: más que `inc_start_food` para que el primer huevo se pueda comprar pronto.
@export var tut_start_food := 60.0
## Ejército rival del final del nivel: chico a propósito, es una demostración.
@export var tut_rival_ants := 3
@export var tut_rival_strength := 0.4
## Soldados que nacen al empezar esa batalla para que siempre se pueda ganar.
@export var tut_bonus_soldiers := 3

@export_group("Fase 4: victoria")
## Cuánto tiempo de simulación hay que sobrevivir en Colonia madura (con la reina viva) para ganar.
## Valor inicial sin playtesting real todavía (ver README sección 9c): 3 minutos de simulación
## después de llegar a Colonia madura, encima de los 10-15 minutos que ya toma llegar ahí.
@export var victory_survive_s := 180.0

## Fase 6: composición fija del modo Test (sandbox, sin victoria/derrota), cada vez que se
## reinicia desde el panel de pruebas. La reina se agrega aparte, siempre es 1.
@export_group("Fase 6: modo Test")
@export var test_start_workers := 20
@export var test_start_soldiers := 20
@export var test_start_drones := 9
