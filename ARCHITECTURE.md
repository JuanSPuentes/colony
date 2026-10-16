# Arquitectura y convenciones entre fases

Este documento existe para que el proyecto **no se vuelva espagueti** a medida que avanza de fase
en fase. Es la referencia que cualquier agente o persona debe releer antes de empezar una fase
nueva. Las reglas de estilo del día a día (tick fijo, datos en `SimConfig`, GDScript tipado, etc.)
siguen en `README.md` sección 4; esto es sobre **cómo se organiza el código**, no cómo se escribe.

## 1. `sim/` está organizado por dominio, no por fase

```
sim/
  core/       Terreno, feromonas, agua, campos de distancia, configuración. No sabe qué es una
              casta, una cámara ni un enemigo. Si lo borraras, cualquier juego 2D de hormigas
              simples (como la Fase 0) seguiría funcionando.
  colony/     La colonia como organismo: castas, hormigas, cría, cámaras, economía. Depende de
              `core/`, nunca al revés.
  threats/    Amenazas externas a la colonia (hoy la araña). Cada una es una clase independiente
              con su propio `step()`; no comparten código entre sí más allá de leer `core/`.
  simulation.gd   El único archivo que conoce TODOS los dominios: los crea, fija el orden del
              tick y expone los `cmd_*` que llama la UI. No le pongas reglas de juego aquí:
              `tick()` debe seguir leyéndose como una lista de pasos, no como lógica.
  save_system.gd  (Fase 2) Convierte una Simulation completa a/desde un Dictionary de solo tipos
              simples. Vive aquí, no en una subcarpeta, por la misma razón que `simulation.gd`:
              necesita leer y escribir TODOS los dominios a la vez. Si agregas un campo nuevo a
              cualquier sistema que deba sobrevivir a un guardado, también hay que sumarlo aquí
              (y a `tools/test_phase2.gd`); si no, se pierde silenciosamente al cargar.
```

## 1b. `app/` es la capa por encima de `sim/`+`view/`: decide qué pantalla se ve

```
app/
  app.gd / app.tscn    Punto de entrada real del juego (`project.godot` -> `run/main_scene`).
                       Decide si se ve el menú, Opciones o la partida; no sabe nada de reglas de
                       juego (eso es `sim/`) ni de cómo se dibuja el mundo (eso es `view/`).
  main_menu.gd         Juego normal / Modo infinito / Opciones / Salir.
  options_screen.gd    Controles (reusa `Hud.CONTROLS`, no mantiene su propia lista), volumen,
                       brillo y un botón de "Salir del juego".
  app_settings.gd       Volumen/brillo persistidos en user://app_settings.json. No es parte de una
                       partida (por eso no vive en `sim/save_system.gd`): es una preferencia de la
                       aplicación, sobrevive a reiniciar y a cargar partidas distintas.
```

`main.tscn` (con `main.gd`) sigue siendo bootable solo y arranca en modo Infinito sin pasar por el
menú: así lo abren `tools/ui_test.gd` y `tools/screenshot.gd`, sin que el menú les importe. `app.gd`
lo instancia con `auto_start = false` y lo arranca él mismo en el modo que eligió el jugador
(`main.gd.start(seed, loaded_sim, mode)`). La tuerca del HUD (`Hud.gear_pressed`) viaja hacia
arriba por las capas (`Hud` -> `main.gd.menu_requested` -> `app.gd`), nunca al revés: `main.gd`
no conoce a `app.gd` ni lo necesita.

**Regla al agregar una fase nueva:** antes de escribir una línea, pregúntate en qué carpeta vive
lo nuevo.
- ¿Es parte del mundo físico (terreno, clima, un recurso del entorno)? → `core/`.
- ¿Es parte de la colonia (una casta, una cámara, una mecánica de cría o economía)? → `colony/`.
- ¿Es un enemigo o evento que la colonia sufre desde afuera? → `threats/` (o `events/` si en algún
  momento hay tantos que amerite separarlos de los enemigos con cuerpo físico).
- ¿Ninguna de las anteriores encaja? Probablemente necesitas una carpeta nueva, no forzar una
  existente. Créala y documenta el porqué en este archivo.

Mover un archivo de carpeta es seguro: Godot resuelve `class_name` por nombre, no por ruta, así
que nada que use `WorldGrid`, `Spider`, etc. se entera del cambio. Solo hay que corregir las
**rutas de texto explícitas** (`res://sim/...`), que hoy son nada más:
`main.gd` (`CONFIG_PATH`), `tools/make_default_config.gd` y `sim/core/default_config.tres`.
Un `grep -rn "res://sim/"` antes de mover algo te dice si hay alguna más.

## 2. El código de una fase nunca debe "contaminar" a la anterior

La regla concreta que ya sigue el proyecto (ver README sección 5, "Por qué `queen_id` puede ser
-1"): **todo lo que una fase agregue debe poder estar ausente sin romper lo que ya funcionaba.**

En la práctica:
- `Simulation.new(cfg, seed)` por sí sola sigue dando el comportamiento de la Fase 0 exacto
  (sin reina, solo obreras). Las fases nuevas se activan con un método explícito
  (`spawn_colony_court()`) o quedan detrás de una condición clara (`if queen_id >= 0`), nunca
  activadas "porque sí" dentro del constructor.
- Cuando una fase agrega datos a una clase vieja (como `caste` en `AntSystem`), el valor por
  defecto debe reproducir el comportamiento viejo al 100 % (`CasteDefs.SPEED_MULT[WORKER] == 1.0`,
  etc.), no una aproximación.
- Si agregar algo rompe una prueba de una fase anterior, la prioridad es **aislar mejor lo nuevo**,
  no relajar la prueba vieja. Solo se toca una prueba anterior cuando el juego cambió de verdad a
  propósito (por ejemplo: la Fase 1 añadió una reina al arranque real del juego, así que
  `tools/ui_test.gd` tuvo que dejar de esperar exactamente 100 hormigas) — y eso se documenta en el
  propio commit/mensaje, no se hace en silencio.

## 3. Una prueba por fase, nunca una prueba que reemplaza a la anterior

```
tools/
  test_phase0.gd   Regresión de la Fase 0. No crece: si algo de la Fase 0 cambia a propósito, se
                   edita aquí con una nota explicando por qué.
  test_phase1.gd   Criterios de aceptación de la Fase 1 únicamente.
  test_phase2.gd   Criterios de la Fase 2 empezados por guardado/carga; se le suma lo que falte
                   de la fase (tutorial, interfaz) a medida que se construya.
  test_phase3.gd   Modo incremental (`spawn_incremental_start`): economía de comida, compras,
                   auto-compra, día y noche, sin araña.
  test_phaseN.gd   (la que corresponda cuando llegue)
  test_app_menu.gd Flujo del menú (app/): qué pantalla se ve tras cada botón, que la tuerca
                   durante la partida vuelva al juego (no al menú), que Salir pida confirmación.
  ui_test.gd       La única que SÍ se actualiza fase a fase: prueba la escena real completa, y la
                   escena real completa cambia en cada fase (nuevas teclas, nuevo HUD, etc.).
```

Antes de cerrar una fase: las pruebas de **todas** las fases anteriores deben seguir en verde,
más la prueba nueva de la fase actual, más `ui_test.gd`. Si una fase vieja falla, no se sigue
hasta arreglarla.

## 4. `main.gd` y `view/` crecen por archivo nuevo, no por archivo más largo

Cada pieza visual nueva es su propia clase en `view/` (ya pasa: `TerrainView`, `AntRenderer`,
`SpiderView`, `OverlayView`...). `main.gd` solo arma esas piezas, lee entrada y avanza el reloj;
si `main.gd` empieza a tener lógica de juego de verdad (reglas, condiciones de victoria, cálculos
de daño), esa lógica se mudó al lugar equivocado — pertenece a `sim/`.

`Hud` sigue el mismo principio puertas adentro: cada sección (Colonia/Clima/Amenazas, ver
`view/hud.gd`) es un bloque de texto propio con su propio encabezado, no una sola cadena gigante.
Al agregar una sección nueva (por ejemplo, cuando haya sequías o un segundo enemigo), se agrega su
propio `Label`/sección, no se concatena a una ya existente.

## 5. Antes de empezar una fase nueva

1. Lee este archivo y la sección 8 del README ("Simplificaciones deliberadas") de la fase
   anterior: dice qué quedó a propósito simplificado y qué de verdad falta.
2. Decide en qué carpeta(s) de `sim/` vive cada sistema nuevo (sección 1 de aquí arriba).
3. Escribe primero qué se vuelve `-1`/`null`/`false` por defecto para que las fases viejas no se
   enteren de que existe, igual que `queen_id`.
4. Crea `tools/test_phaseN.gd` desde el primer día, no al final.
5. Al terminar, actualiza README (secciones 3, 5, 8 y 9) y este archivo si la organización cambió.
