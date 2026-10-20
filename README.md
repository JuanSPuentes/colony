# Colony: Under the Earth

Simulador de supervivencia y gestión de una colonia de hormigas en 2D lateral, hecho con **Godot 4.7**
(GDScript, renderer de Compatibilidad) para Windows. No controlas hormigas individuales: guías una
colonia de arrieras (inspirada en *Atta*) con **señales de feromonas** y **diseño del nido**, y las
hormigas hacen el trabajo.

> Estado: **menú principal con dos modos de juego**, verificado. Papeles invertidos a propósito
> (pensando en que "normal" sea lo que la mayoría juega primero): **Juego normal** es el de la
> Fase 3: colonia mínima, todo se mide en **comida**, el jugador **compra** obreras y soldados
> (cada una más cara que la anterior) o activa la **auto-compra**, las plantas rebrotan de día, hay
> **día y noche**, y no hay araña ni final. **Modo infinito** es la colonia completa de la Fase 1
> (reina, 4 castas, cámaras, araña, eras, puede ganarse o perderse). **Opciones** (desde el menú o
> la tuerca ⚙ de la esquina superior derecha durante la partida) tiene volumen, brillo y los
> controles. Guardado F6/F7 funciona en los dos modos.
> Repositorio: https://github.com/JuanSPuentes/colony

**Principio de diseño:** el jugador controla la colonia mediante señales ambientales y el diseño del
nido; las hormigas hacen el trabajo. Toda función nueva debe respetar esto.

**Antes de empezar una fase nueva, lee [`ARCHITECTURE.md`](ARCHITECTURE.md):** cómo está organizado
`sim/` por dominio (no por fase), cómo aislar el código nuevo para no romper fases anteriores, y la
convención de una prueba por fase. Existe justo para que el proyecto no se vuelva espagueti.

## Contenido

1. [Jugarlo](#1-jugarlo)
2. [Controles](#2-controles)
3. [Cómo funciona ahora mismo](#3-cómo-funciona-ahora-mismo)
4. [Guía de desarrollo](#4-guía-de-desarrollo)
5. [Arquitectura](#5-arquitectura)
6. [Pruebas](#6-pruebas)
7. [Estado del arte y el sonido](#7-estado-del-arte-y-el-sonido)
8. [Simplificaciones deliberadas de la Fase 1](#8-simplificaciones-deliberadas-de-la-fase-1)
9. [Simplificaciones deliberadas del guardado (Fase 2)](#9-simplificaciones-deliberadas-del-guardado-fase-2)
10. [Hoja de ruta: qué falta de la Fase 2](#10-hoja-de-ruta-qué-falta-de-la-fase-2)
11. [Fase 4: condición de victoria](#11-fase-4-condición-de-victoria)
12. [Fase 5: el ciempiés](#12-fase-5-el-ciempiés)
13. [Fase 6: el modo Test](#13-fase-6-el-modo-test)
14. [Fase 7: la mantis](#14-fase-7-la-mantis)

---

## 1. Jugarlo

1. Instala **Godot 4.7.2** (build estándar, no Mono):
   https://godotengine.org/download/windows/
2. Abre Godot, **Importa** `project.godot`, pulsa **F5**. Arranca en el **menú principal**:
   *Juego normal* (Fase 3, comida/compra), *Modo infinito* (Fase 1, reina/castas/araña), *Opciones*
   o *Salir*.
   Desde una terminal: `Godot.exe --path .`
3. Semilla fija opcional: `Godot.exe --path . -- --seed=42` (cada reinicio usa semilla + 1). Solo
   aplica a la partida, no al menú.

La ventana base es 480x270 escalada por entero a 1440x810. Sin descargas, sin red, sin assets
externos. `main.tscn` abierto directo (sin pasar por el menú) arranca solo en el modo de
comida/compra (hoy "Juego normal" en el menú, internamente `incremental` en el código): así lo
usan las pruebas automatizadas (ver sección 6), no es un atajo pensado para jugar.

## 2. Controles

Durante la partida, la **tuerca ⚙** en la esquina superior derecha abre Opciones (controles,
volumen, brillo) o te deja salir, sin perder la partida (vuelve exactamente a donde estabas).

| Tecla | Acción |
|---|---|
| **1** | Cavar: arrastra desde un túnel existente hacia tierra |
| **2** | Feromona (Q/E cambia el tipo: Comida, Hogar, Peligro, Ataque, Evacuar) |
| **3** | Cámara (Q/E cambia el tipo: Guardería, Almacén, Real) |
| **4** | Borrar (quita marca de excavar, cámara y las 5 feromonas bajo el pincel) |
| **5** | Mover reina: clic izquierdo la manda a caminar hasta esa celda, clic derecho cancela la orden |
| Clic izquierdo / derecho, arrastrar | Pintar / borrar con la herramienta activa |
| **7** | Modo normal: comprar un huevo con comida (también con el botón del panel; qué nace es al azar) |
| **9** | Modo normal: auto-compra de huevos, apagada/encendida (compra sola en cuanto alcanza, dejando una reserva) |
| **Espacio** | Pausa / reanudar |
| **F1 / F2 / F3** | Velocidad x1 / x2 / x4 |
| **WASD** | Mover la cámara |
| Rueda del mouse | Zoom en pasos fijos |
| **H** | Saltar a la reina |
| **F5** | Reiniciar con el mismo mapa |
| **Shift+F5** | Reiniciar con un mapa nuevo |
| **F6** | Guardar partida |
| **F7** | Cargar la última partida guardada |
| **I** | Plegar / desplegar el panel de estado (también con el botón "ocultar" del panel) |
| Clic medio, arrastrar | Mover la cámara |

Herramientas de depuración/prueba (forzar lluvia, recorrer capas de feromonas y estados, agregar
400 hormigas) se quitaron de las teclas del juego y de esta lista a propósito: son para desarrollo,
no para jugar. Las funciones siguen existiendo (`Simulation.cmd_force_rain`/`cmd_add_ants`,
`OverlayView.cycle_layer`) y las usan `tools/screenshot.gd` y `tools/ui_test.gd` directamente.

## 3. Cómo funciona ahora mismo

### Modo incremental (Fase 3, el que arranca `main.gd`)

`Simulation.spawn_incremental_start()` (`sim/simulation.gd`), economía en
`sim/colony/incremental_economy.gd`, día y noche en `sim/core/day_night.gd`.

- **Colonia inicial:** 1 reina, 3 obreras, 1 soldado y 1 larva (que nace obrera). Sin nodrizas.
- **Todo es comida.** Cada hoja que una obrera trae al nido vale `inc_food_per_leaf` de comida al
  llegar. No hay agua ni hongo como recursos aparte. Todas las adultas comen; si la comida llega
  a 0, la reina y los soldados se debilitan (las obreras no).
- **Comprar un huevo (7), o el botón del panel.** Se paga la comida y la reina pone un huevo; qué
  casta nace (obrera o soldado) es al azar (`inc_egg_soldier_chance`), no la elige el jugador — ver
  sección 9b. La cría hace el resto (huevo → larva → pupa, `inc_brood_speed` veces más rápido que
  en la Fase 1 y sin depender de nodrizas). Cada compra multiplica el precio del siguiente huevo
  (`inc_egg_cost_growth`).
- **Auto-compra (9):** apagada / encendida. Compra un huevo sola en cuanto alcanza, dejando
  `inc_auto_reserve` de comida para no matar de hambre a la reina.
- **Día y noche:** el ciclo dura `day_length_s` (60 % de luz, 40 % de noche) y arranca al amanecer.
  Un día de luz + una noche = 1 día; el HUD muestra "Día N". De noche el mundo se oscurece y las
  plantas no rebrotan.
- **Plantas:** rebrotan de día (`inc_plant_regrow_per_s`) hasta su máximo, así el juego no se queda
  sin hojas. La colonia recuerda las plantas de las que ya sacó hojas y las obreras en la superficie
  van directo a la conocida más cercana (ver simplificaciones, sección 9b).
- **Sin eras, pero con araña.** No hay Fundación/Colonia joven/madura como en el modo clásico; la
  araña aparece por población sola (`cfg.inc_spider_first_population`, más baja que
  `spider_first_population` porque este modo arranca y crece con colonias chicas), mismo
  comportamiento que en el modo clásico (caza obreras sueltas, asedia la entrada, la reina puede
  morir si nadie la para con soldados). Sigue sin condición de victoria propia (ver sección 9c).
  La primera lluvia llega al inicio del día 3 (`inc_rain_first_s`) y la reina no se ahoga; el resto
  de la colonia sí sufre las inundaciones.

### Modo clásico (Fases 1-2; lo usan las pruebas de esas fases)

**Castas** (`sim/colony/caste_defs.gd`): Reina (una sola, pone huevos si hay comida suficiente y una
cámara Real válida en algún lado; su muerte termina la partida — se ve bien más grande que el resto
y de un tono marfil "puro", distinto del ámbar de la Obrera), Obrera (explora, corta hojas, carga,
cava), Nodriza (acelera el desarrollo de la cría cerca del nido, no pelea), Soldado (ronda libre
por el nido y la superficie, no se queda plantado; responde a la feromona de Ataque, el mayor daño
cuerpo a cuerpo), Zángano (morado, con alas — no explora ni pelea activo, pero sí camina para
cargar huevos hasta la Guardería, su única tarea; mientras esté vivo también acelera la puesta de
huevos de la reina: `cfg.drone_egg_speed_bonus` por cada uno, sin tope).

**Defensa de la colmena:** ante una amenaza real (araña, y lo que se sume después) toda la colonia
pelea, no solo el Soldado — cada casta con su propio daño cuerpo a cuerpo
(`CasteDefs.DAMAGE_PER_S`): Obrera 3, Soldado 8, Zángano 1 (la Nodriza nunca pelea). La Obrera se
acerca y ataca igual que el Soldado (tiene prioridad sobre huir de la feromona de Peligro, que
sigue existiendo tal cual para avisos del jugador sin amenaza real detrás); el Zángano pelea
*pasivo*, sin moverse ni decidir ir a buscar pelea — solo devuelve el golpe si la amenaza lo
alcanza donde está parado, consistente con que sigue siendo la casta "liviana". Una colonia sin
soldados ya no es presa fácil: un grupo de obreras puede espantar o matar a la araña entre todas.

**Saqueo de cadáveres** (`sim/core/corpse.gd`): cualquier hormiga o amenaza (araña, y lo que se
sume después) deja restos recolectables al morir, en el lugar exacto donde murió. Una obrera los
recoge igual que recoge una hoja (mismo pickup, mismo viaje a casa) y se vuelven comida al llegar,
pero valen más (`cfg.corpse_food_value`, el de la araña más todavía:
`cfg.corpse_food_value_spider`). Un cadáver se agota de un solo viaje (no hay "varias partes" por
cuerpo) y desaparece solo si nadie lo recoge antes de `cfg.corpse_decay_s`.

**Mover a la reina (tecla 5):** no decide ni camina sola — el jugador la manda a una celda cavada y
conectada al nido (clic derecho cancela la orden en curso) para alejarla de la araña o acercarla a
una cámara nueva. Camina más lento que el resto (`CasteDefs.SPEED_MULT`) y sigue poniendo huevos
igual mientras viaja: dónde esté parada no afecta la cría, a propósito (ver sección 8).

**Cría** (`sim/colony/brood_system.gd`): huevo → larva → pupa → adulta. Al poner un huevo, la reina le asigna
la casta que más lejos esté del reparto objetivo del jugador (ajustable con 7/8/9), y nace en la
posición donde ella esté parada. El Zángano lo puede cargar hasta una celda de Guardería (ver
sección de castas, arriba); una vez que pasa a larva ya no se mueve más, quede donde quede. Sin
nodrizas cerca la larva se desarrolla mucho más despacio; sin Guardería válida en algún lado, algo
más despacio y puede morir si el nido se inunda a fondo.

**Cámaras** (`sim/colony/room_system.gd`): el jugador las designa pintando sobre túneles ya excavados. Cada
tipo necesita un tamaño mínimo y estar conectado al nido para activarse:

| Cámara | Efecto |
|---|---|
| Real | La reina solo pone huevos aquí (la cámara inicial ya viene designada) |
| Guardería | La cría se desarrolla a velocidad completa |
| Almacén | Sube el tope de comida y agua |

El Jardín de hongos y el Drenaje se quitaron del juego (ver sección 8): ya no hace falta designar
ninguna cámara para reponer comida ni para lidiar con una inundación.

**Economía** (`sim/colony/colony.gd`): las obreras cortan hojas y las traen al nido (igual que en la
Fase 0); la hoja se vuelve comida apenas llega, sin cámara que designar ni espera de por medio
(`cfg.leaf_food_value`). El agua entra despacio mientras hay charcos tras la lluvia y sale sola por
evaporación (ver simplificaciones) — no hay forma activa de drenarla. Todas las adultas consumen
comida y agua; la falta de comida o agua no afecta a la obrera (compatibilidad con la Fase 0), pero
sí debilita a la reina, las nodrizas y los soldados hasta matarlos.

**Feromonas.** A las dos de la Fase 0 (Comida, Hogar) se suman:

| Tipo | Qué hacen las hormigas |
|---|---|
| Peligro | Todas menos el soldado huyen de la zona (el soldado la ignora) |
| Ataque | Los soldados en rango van hacia la señal más fuerte |
| Evacuar | Las hormigas en la zona marcada se alejan hacia donde la señal sea más débil |

**Araña** (`sim/threats/spider.gd`): aparece en la superficie cuando la población llega a cierto umbral, caza
obreras sueltas y, si nadie la detiene en la entrada por un tiempo, hiere a la reina. Huye si queda
débil o si varios soldados la rodean; vuelve otra más fuerte pasado un intervalo.

**Eras:** la población desbloquea contenido — Fundación (excavar, Comida, Hogar), Colonia joven
(soldados, primera lluvia) y Colonia madura (Peligro, Ataque, Evacuar, la araña).

**Derrota:** la partida termina cuando muere la reina (ahogada, por la araña o por hambre/sed
prolongadas); el HUD muestra la causa y F5 reinicia.

**Guardar y cargar** (`sim/save_system.gd`, Fase 2): F6 guarda toda la partida en
`user://save1.json` (terreno, cámaras, feromonas, agua, economía, cría, la araña y cada hormiga);
F7 la recupera tal cual, lista para seguir jugando desde donde quedó.

---

## 4. Guía de desarrollo

### Requisitos
- Godot **4.7.2** (otras versiones 4.x no están probadas).
- Windows es la plataforma objetivo. Nada en el código es específico de Windows.
- No se necesita Python. Todas las herramientas son GDScript.

### Primeros pasos
```
git clone https://github.com/JuanSPuentes/colony.git
cd colony
Godot_v4.7.2-stable_win64_console.exe --headless --path . --import
Godot_v4.7.2-stable_win64_console.exe --path .
```
`.godot/` se genera solo y está ignorado por git. Nunca lo subas.

**Importante:** cada vez que agregues un script nuevo con `class_name`, corre `--import` antes de
`--script` o de abrir el editor; si no, los scripts que lo referencian fallan con
"Could not find type X in the current scope" aunque el código esté bien.

### Estructura del repositorio
```
project.godot        Configuración de Godot (480x270 interno, escalado a 1440x810)
ARCHITECTURE.md       Cómo organizar el código de cada fase nueva (léelo antes de empezar una)
app/                  Punto de entrada real (`run/main_scene`): menú, Opciones, selector de modo
main.tscn            Escena de la partida en sí: un Node que corre main.gd
main.gd              Arma la vista, el HUD, crea/reinicia la Simulation; bootable solo (sección 1)
sim/                  SIMULACIÓN. Sin dibujo, sin UI, sin clases Node (solo RefCounted)
  core/                 Terreno, feromonas, agua, campos de distancia, configuración
  colony/               Castas, hormigas, cría, cámaras, economía (clásica e incremental)
  threats/              Enemigos (araña, ciempiés)
  simulation.gd         El orquestador: conoce todos los dominios, fija el orden del tick
  save_system.gd        Guardado/carga (Fase 2): convierte la Simulation a/desde JSON
view/                 Render, HUD y entrada de mouse
tools/                Scripts de desarrollo y pruebas (ver sección 6)
```

### Convenciones
- **La simulación va separada de la presentación.** `sim/` nunca debe referenciar `Node`, dibujo,
  `Input` ni UI.
- **Tick fijo.** `SimConfig.tick_rate` (20/s). Nunca uses el `delta` del frame de render dentro de la
  simulación.
- **Determinismo.** Toda la aleatoriedad pasa por `sim.rng` (con semilla).
- **Datos en vez de código.** Los números ajustables viven en `SimConfig`, agrupados por
  `@export_group`; los datos de cada casta, en `CasteDefs` (arrays paralelos, no Resources: ver
  sección 8).
- **GDScript tipado.** El proyecto trata la inferencia no tipada de `Variant` como un problema.
- Comentarios cortos que expliquen el *porqué*, no el *qué*.

### Flujo de trabajo
1. Haz el cambio (los cambios de simulación van en `sim/`).
2. Corre las seis suites de la sección 6. Las seis deben pasar.
3. Si cambiaste algo visual, corre `tools/screenshot.gd` y mira los PNG.
4. Commit con un mensaje corto en modo imperativo y abre un PR contra `main`.

## 5. Arquitectura

**Cómo está organizado `sim/` en carpetas (`core/`, `colony/`, `threats/`) y las reglas para no
romper fases anteriores al agregar una nueva: ver [`ARCHITECTURE.md`](ARCHITECTURE.md).** Lo de
aquí abajo es sobre el render y el orden del tick, no sobre dónde vive cada archivo.

### Render: mundo en pixel art + HUD nítido

El mundo (480x270, pixel art) vive dentro de un `SubViewport` propio que `main.gd` escala con
`SubViewportContainer.stretch_shrink` y sin filtro (`TEXTURE_FILTER_NEAREST`), para que se vea
grande y nítido en vez de borroso. El `Hud` (`CanvasLayer`) es hermano de ese `SubViewport`, fuera
de él, así que dibuja su texto directo a la resolución real de la ventana (nítido de verdad, no
una imagen de baja resolución ampliada).

`Main` sigue siendo el nodo raíz (para que `sim`, `cfg`, `tool`, `camera`, etc. se lean igual que
antes desde `Hud` y desde las pruebas), pero como ya no vive en el mismo viewport que la cámara del
mundo, la entrada de mouse se convierte a mano: `main.gd._to_world()` pasa la posición del evento
por el tamaño real del contenedor y por `world_vp.get_canvas_transform()` (que sí conoce la cámara).

**Nota para quien escriba pruebas:** en `--headless`, `get_tree().root.size` queda fijo en un
tamaño ficticio sin importar lo que el script le asigne (`root.size = ...` no tiene efecto real).
Por eso existe `main.world_size_override`: una prueba que necesite clics de mouse predecibles debe
fijarlo (ver `tools/ui_test.gd`) en vez de confiar en `root.size`.

```
main.gd
 |- SubViewportContainer (sin filtro, stretch_shrink dinámico)
 |    '- SubViewport (480x270)
 |         '- TerrainView / AntRenderer / PlantView / SpiderView / OverlayView / Camera2D
 |- Hud (CanvasLayer, fuera del SubViewport: dibuja a resolución real)
 '- Simulation (RefCounted)   todo el estado y las reglas del juego
      |- WorldGrid             terreno, excavación, cámaras designadas (Fase 1)
      |- PheromoneField x5     Comida, Hogar, Peligro, Ataque, Evacuar
      |- WaterSim              agua: caída, esparcido, evaporación
      |- NestDistanceField     campo de distancias al nido (BFS)
      |- RoomSystem            cuenta cámaras válidas y su capacidad (Fase 1)
      |- Colony                comida, agua, consumo, puesta de huevos (Fase 1)
      |- BroodSystem           huevo/larva/pupa (Fase 1)
      |- Spider                el intruso (Fase 1)
      |- AntSystem             datos de las hormigas y su lógica de decisión por casta
      '- plants: Array[Plant]

sim/save_system.gd  (Fase 2) convierte una Simulation completa a/desde un Dictionary de solo
                    tipos simples (JSON). Vive junto a simulation.gd, no dentro de core/colony/
                    threats, porque igual que el orquestador necesita ver todos los dominios a
                    la vez (ver ARCHITECTURE.md).
```

### Por qué `queen_id` puede ser -1
`Simulation.new(cfg, seed)` por sí sola crea una colonia **sin reina**, exactamente como en la Fase 0.
Solo `spawn_colony_court()` (llamado por `main.gd.start()`) añade la reina y las nodrizas iniciales.
Esto fue deliberado: así las pruebas de la Fase 0 (`tools/test_phase0.gd`, que nunca llaman a
`spawn_colony_court()`) siguen comprobando exactamente el mismo comportamiento de obrera que antes,
sin que la economía, la cría o la araña interfieran. El código revisa `queen_id >= 0` antes de correr
cualquier sistema de la Fase 1.

### Orden del tick (`Simulation.tick`)
clima → agua → decaimiento de las 5 feromonas → recálculo de campos si cambió el terreno →
cámaras (`rooms.maybe_recompute`) → `AntSystem.tick()` → si hay reina: economía → cría → era →
araña (cada 3 ticks) → revisión de derrota.

## 6. Pruebas

Todas las pruebas son GDScript corrido a través de Godot. Usa el build de consola
(`Godot_v4.7.2-stable_win64_console.exe`) para ver la salida. Terminan con código 1 si algo falla.

| Comando | Qué comprueba |
|---|---|
| `Godot --headless --path . --script tools/test_phase0.gd` | Regresión de la Fase 0: determinismo, forrajeo, feromonas, excavación, lluvia/drenaje, huida/muerte, rendimiento. **34 pruebas.** |
| `Godot --headless --path . --script tools/test_phase1.gd` | Criterios de la Fase 1: reina y puesta de huevos, zánganos (acelerar puesta, cargar huevos a la Guardería), las 4 etapas de cría, reparto de castas, cámaras (válidas/inválidas), hojas que se vuelven comida al llegar, Peligro/Evacuar, la araña (caza, la espantan, defensa de toda la colonia sin soldados), saqueo de cadáveres, movimiento de la reina, eras, derrota, determinismo con colonia completa, rendimiento. **44 pruebas.** |
| `Godot --headless --path . --script tools/ui_test.gd` | La escena real con eventos inyectados: arranque con reina+nodrizas, pausa, compras 7/8/9 y botones, panel de estado plegable (I), herramientas, cámara, las funciones de depuración (lluvia forzada, capas, agregar hormigas, ya sin tecla propia), reinicio. **26 pruebas.** |
| `Godot --headless --path . --script tools/test_phase2.gd` | Guardado y carga: la huella no cambia al guardar y cargar (en memoria y desde un archivo real), la partida sigue igual tras cargar como si nunca se hubiera guardado, un archivo inexistente no revienta, funciona con y sin reina, las cámaras y la lluvia en curso sobreviven, la posición del huevo y quién lo está cargando sobreviven. **12 pruebas.** |
| `Godot --headless --path . --script tools/test_phase3.gd` | Modo incremental: colonia inicial exacta, sin araña ni eras, día y noche, hojas → comida, compras y precios crecientes, el huevo comprado nace de esa casta, auto-compra con reserva, rebrote solo de día, la colonia crece sola 6 min con lluvia sin morir, guardado y carga (también por JSON), determinismo. **28 pruebas.** |
| `Godot --headless --path . --script tools/test_phase4.gd` | Condición de victoria de la colonia con reina (sección 11): gana al sobrevivir `victory_survive_s` en Colonia madura con la reina viva, no gana antes de tiempo, morir la reina antes del umbral sigue siendo derrota (no victoria), el modo incremental nunca la dispara, guardar/cargar conserva el progreso hacia la victoria. **7 pruebas.** |
| `Godot --headless --path . --script tools/test_phase5.gd` | El ciempiés, segunda amenaza (sección 12): no aparece antes del umbral de población, aparece al cruzarlo, encuentra y daña una hormiga bajo tierra (no solo en superficie, a diferencia de la araña), toda la colonia lo ataca igual que a la araña, muere y deja cadáver recolectable, huye y desaparece con poca vida, el modo incremental nunca lo dispara, guardar/cargar conserva su estado. |
| `Godot --headless --path . --script tools/test_phase6.gd` | El modo Test (sección 13): composición fija de 50 hormigas al arrancar, empieza de día, la reina puede morir sin terminar la partida, los comandos de lluvia/araña/ciempiés del panel de pruebas, agregar hormigas de cualquier casta a voluntad, los otros dos modos no se ven afectados, guardar/cargar conserva `test_mode`. |
| `Godot --headless --path . --script tools/test_phase7.gd` | La mantis, tercera amenaza (sección 14): no aparece antes del umbral, aparece al cruzarlo, nunca se mueve, no reacciona a una hormiga lejos pero sí a una que entra en `mantis_strike_range_px`, pega más fuerte que la araña, toda la colonia la ataca igual, muere y deja cadáver, huye con poca vida, el modo incremental nunca la dispara, guardar/cargar conserva su estado. |
| `Godot --headless --path . --script tools/test_app_menu.gd` | El menú (`app/`): arranca mostrando el menú, Opciones desde el menú vuelve al menú, Opciones desde la tuerca en partida vuelve a la partida (pausada) y no al menú, Juego normal arranca en modo incremental (comida/compra), Modo infinito arranca en modo Historia con la colonia completa, Test arranca el modo sandbox con 50 hormigas, F5 conserva el modo, volumen/brillo se guardan, Salir pide confirmación en vez de cerrar directo. |
| `Godot --path . --script tools/screenshot.gd -- <carpeta>` | (Necesita ventana.) Guarda capturas PNG. |

**Última ejecución verificada (2026-10-20, Godot 4.7.2):** las siete suites en 34/34 (Fase 0),
44/44 (Fase 1), 12/12 (Fase 2), 30/30 (Fase 3), 7/7 (Fase 4), 26/26 (ui_test) y 11/11 (menú).

### Notas para escribir pruebas
- Si tallas túneles a mano con un helper tipo `_carve()`, llama también a
  `sim.fields.recompute_terrain()` (o `sim.tick()`) antes de comprobar cámaras: si no, `nest_dist`
  queda desactualizado y toda cámara nueva se ve "desconectada".
- Una cámara de prueba debe tocar el nido existente (o un túnel ya conectado a él); un bolsillo de
  túnel aislado en mitad de la tierra nunca cuenta como válido, a propósito.
- Prefiere pruebas A/B (misma semilla con y sin la acción del jugador).
- Advertencias inofensivas al salir ("resources still in use", "ObjectDB instances leaked") no
  indican un fallo del juego.
- El presupuesto de rendimiento con 500 hormigas se mide con wall-clock; si hay otro proceso de Godot
  corriendo en paralelo en la misma máquina, el número sale inflado por pura contención de CPU. Mide
  con un solo proceso a la vez si el resultado parece alto.

## 7. Estado del arte y el sonido

| Elemento | Estado |
|---|---|
| Hormigas (color por casta o por estado en las capas de depuración), araña, plantas | Pixel art / formas procedurales. Coherente pero **provisional**. |
| Cámaras designadas | Tinte de color por tipo sobre el túnel, más intenso si la cámara es válida. |
| Suelo, roca, túnel | Procedural, variantes por profundidad. |
| UI | Tema de Godot en código, fuente por defecto. |
| Sonido | No implementado todavía. |

## 8. Simplificaciones deliberadas de la Fase 1

Documentadas a propósito, para que quien siga el proyecto sepa qué es a propósito y qué falta de
verdad:

- **Datos de casta como arrays paralelos (`CasteDefs`), no `Resource`/`.tres`.** Más rápido de
  escribir y de leer para 4 castas fijas; el prompt original pedía Resources para facilitar especies
  nuevas más adelante. Migrar es mecánico cuando llegue una segunda especie.
- **Las cámaras son un recuento global por tipo, no una forma contigua validada.** Una cámara es
  "todas las celdas de túnel con esa etiqueta que están conectadas al nido"; importa el tamaño total
  y la conexión, no la forma. Se simplificó así para no tener que detectar componentes conexos por
  separado.
- **El agua como recurso no tiene una tarea dedicada de "traer agua".** Entra sola, despacio,
  mientras haya charcos tras la lluvia. No hay una obrera que cargue una gota físicamente.
- **El hambre y la sed no dañan a la obrera**, solo a reina, nodrizas y soldados. Así el
  comportamiento de obrera de la Fase 0 queda intacto byte a byte, sin importar la economía.
- **El huevo sí tiene posición física; larva y pupa no se mueven más después de eso.** Nace donde
  esté parada la reina (`BroodSystem.pos`) y el Zángano lo puede cargar hasta una celda de
  Guardería (`AntSystem._think_drone`, ver más abajo). Una vez que pasa a larva, la posición queda
  fija donde haya quedado — no hay una tarea de "reacomodar" larvas ya nacidas. La velocidad de
  desarrollo sigue siendo global por colonia (nodrizas presentes, Guardería válida en algún lado),
  no por la posición de cada huevo en particular: cargarlo hasta la Guardería no lo hace
  desarrollarse más rápido por sí solo, es una tarea del Zángano, no un requisito de balance.
- **El Zángano carga como mucho un huevo a la vez y va al primero libre más cercano**, no al que
  más lo necesite ni en ningún orden particular. Sin Guardería designada se queda esperando junto
  al huevo en vez de insistir o volver a dejarlo donde estaba.
- **La araña no encuentra camino real por los túneles.** Si nadie la detiene en la entrada por un
  tiempo, se modela como un golpe directo a la reina ("asedio"), no como una invasión celda por celda.
- **El reparto de castas se ajusta con tres teclas (7/8/9)**, no con controles deslizantes en
  pantalla.
- **No hay herramienta de inspección por pasar el mouse** sobre hormigas o cámaras; la capa de
  depuración y los colores cumplen ese papel por ahora.
- **Mover a la reina no recalcula el camino si el terreno cambia a mitad de viaje.** `cmd_move_queen`
  calcula una BFS contra la celda destino una sola vez; si alguien tapa el túnel que estaba usando
  mientras camina, la orden se cancela sola en vez de buscar una ruta nueva (no se queda caminando
  contra una pared: `is_passable` se revisa en cada paso).
- **La puesta de huevos no depende de dónde esté parada la reina**, solo de que exista una cámara
  Real válida en algún lado. Mover a la reina es para protegerla de la araña, no para reubicar la
  cría; si en el futuro se quiere esa relación, hay que decidir qué pasa si no queda ninguna Real
  donde la reina termine (ver conversación de diseño, no construido a propósito por ahora).
- **El Zángano no tiene vuelo nupcial ni se reproduce de verdad** (no hay otras colonias con las que
  cruzarse todavía). Su función principal es acelerar la puesta de huevos mientras esté vivo
  (`Colony.tick`, sin tope por cantidad: liviano a propósito, ver sección 3); desde que toda la
  colonia defiende la colmena (ver más abajo) también devuelve un golpe chico si una amenaza lo
  alcanza donde está parado, pero sigue sin explorar ni decidir nada por su cuenta.
- **El Zángano no se compra en el modo incremental** (`Juego normal`), igual que la Nodriza: ese
  modo sigue siendo solo obrera/soldado al azar (ver sección 9b).
- **Toda la colonia defiende la colmena ante una amenaza real, no solo el Soldado** (Obrera 3 de
  daño, Soldado 8, Zángano 1 pasivo; la Nodriza nunca pelea). Tiene prioridad sobre huir de la
  feromona de Peligro pintada por el jugador, que sigue funcionando igual para avisos sin amenaza
  real detrás. `AntSystem._nearest_threat()` es el único lugar que hay que tocar cuando se sumen
  más insectos, ya que el resto de la lógica de combate es genérica.
- **El Soldado ronda libre cuando no hay amenaza** en vez de volver a pararse junto a la entrada:
  explora igual que una obrera (sin cortar hojas ni cavar), así no queda "guardia inmóvil" todo
  el juego.
- **Se quitaron el Jardín de hongos y el Drenaje.** La hoja se vuelve comida apenas llega al nido
  (`cfg.leaf_food_value`, sin cámara que designar ni espera); el Almacén conserva su función de
  subir los topes de comida y agua. El agua de inundación ya no tiene una forma activa de drenarse,
  solo evapora sola con el tiempo — una colonia que se inunda a fondo depende de que pase, no de
  que el jugador construya algo para apurarlo.
- **Un cadáver vale un valor fijo, no varias "partes" recolectables por separado.** La primera
  obrera que llega se lo lleva entero de un viaje; es la misma simplificación que ya tenían las
  hojas (sin tarea de "cargar de a poco"). Tampoco importa qué mató a la hormiga (ahogo, araña,
  hambre): siempre deja el mismo valor (`cfg.corpse_food_value`), salvo la araña, que deja más
  (`cfg.corpse_food_value_spider`) por ser más grande.
- **`AntSystem._kill()` es el único lugar donde una hormiga deja restos**, y `Spider.take_damage()`
  el de la araña: cuando se sumen más amenazas, ahí es donde hay que agregar la llamada a
  `Simulation.spawn_corpse()`, no en ningún otro lado.

## 9. Simplificaciones deliberadas del guardado (Fase 2)

- **Un solo espacio de guardado** (`user://save1.json`, siempre se sobrescribe). Varias partidas
  guardadas en paralelo es una extensión mecánica (parametrizar la ruta), no construida todavía.
- **Formato JSON, no binario.** Pesa más y carga un poco más lento que un formato compacto, pero
  es legible para depurar y no depende de que las clases de Godot no cambien de forma entre
  versiones. Si el tamaño del archivo se vuelve un problema real, migrar a `var_to_bytes` es
  mecánico (ver `sim/save_system.gd`).
- **No hay versionado de compatibilidad todavía.** `SaveSystem.SAVE_VERSION` existe pero nada lo
  revisa aún; cargar un guardado de una versión vieja del juego con campos nuevos puede fallar.
  Construir esa migración es trabajo de cuando de verdad haya versiones distintas en el mundo.
- **Cargar reconstruye y luego pisa.** `SaveSystem.from_dict` arma una colonia nueva normal y
  después sobreescribe cada campo con lo guardado, en vez de tener un segundo camino de
  construcción "en blanco". Es algo de trabajo de más en cada carga, pero evita mantener dos
  formas de construir una `Simulation` (ver ARCHITECTURE.md, sección 2).

## 9b. Simplificaciones deliberadas del modo incremental (Fase 3)

- **La colonia recuerda las plantas visitadas** (`IncrementalEconomy.known_plants`) y las obreras
  en la superficie van directo a la más cercana con hojas. Con 3-10 obreras los rastros de
  feromona no se refrescan lo bastante: se desgastaban por la punta de la planta y terminaban
  justo fuera del alcance de vista, así que las obreras daban vueltas junto al nido hasta que la
  reina moría de hambre. Solo pasa en este modo; las Fases 0-2 siguen usando solo los rastros.
- **La reina no se ahoga en este modo**, y la primera lluvia llega el día 3 en vez de a los 150 s
  de la Fase 1: una colonia de 5 hormigas no tendría forma de defenderse de una inundación tan
  pronto (ni esta ni la Fase 1 tienen ya una cámara de Drenaje que cavar; antes era la razón del
  retraso, ahora es solo darle tiempo a la colonia a crecer un poco primero).
- **No se compran nodrizas** y la cría no depende de ellas en este modo.
- **El jugador compra un huevo, no una casta.** Qué nace (obrera o soldado) se sortea al comprar
  (`IncrementalEconomy.buy_egg`, `cfg.inc_egg_soldier_chance`), no al nacer: la casta ya queda fija
  en `BroodSystem.caste` desde el huevo, así que el punto de color del HUD no es una predicción,
  es el resultado real. Reemplaza los precios separados de obrera/soldado de antes de esta sesión;
  las nodrizas nunca fueron parte del sorteo (siguen sin comprarse en este modo).
- **Las cámaras siguen existiendo** pero solo el Almacén importa para la economía (sube el tope de
  comida); las hojas ya son comida al llegar, igual que en el modo clásico desde que se quitó el
  Jardín de hongos (ver sección 8).
- **El reloj no arranca en `tick_count = 0`**, sino ya pasado el amanecer
  (`DayNight.FADE * day_length_s`, ver `spawn_incremental_start`): a tick 0 el mundo se ve casi
  negro un instante por la transición de `DayNight.light()`, aunque `is_night()` ya diga "de día";
  así la partida se ve a pleno día desde el primer frame en vez de a mitad de esa animación.

## 9c. Simplificaciones deliberadas de la Fase 4 (victoria)

- **`victory_survive_s` (180 s por defecto) es una primera estimación, sin playtesting real
  todavía** — igual que el resto del balance del proyecto (ver sección 10). Ajustarlo es cambiar un
  número en `SimConfig`, no lógica.
- **Solo la colonia con reina (`Modo infinito` en el menú de hoy) puede ganar.** El modo de
  comida/compra (`Juego normal`) ya tiene una amenaza real (la araña, agregada después de esta
  fase — ver sección 3) y la reina ya podía morir antes de eso (de hambre/sed prolongadas, igual
  que en el modo clásico), pero sigue sin condición de victoria propia. Queda pendiente a
  propósito: agregarla es la continuación obvia ahora que hay una amenaza, no se hizo todavía.
- **El cronómetro de victoria no se reinicia si la población baja de Colonia madura.** Una vez que
  la colonia llega ahí por primera vez (`Simulation._mature_since_s`), el reloj corre aunque
  mueran hormigas después; bajar de era no existe hoy (las eras solo suben), así que esto no se
  puede probar todavía, pero quede documentado por si `_update_era` cambia en el futuro.

## 10. Hoja de ruta: qué falta de la Fase 2

- Arte final: hormigas y araña dibujadas a mano, animaciones direccionales, variedad de tiles.
- Interfaz pulida: controles deslizantes para el reparto de castas, tooltips al pasar el mouse,
  tutorial guiado.
- Playtesting real con una persona (hasta ahora el balance solo se validó con las pruebas
  automatizadas).
- Mejoras y progresión entre partidas (vuelo nupcial, eras avanzadas): ver el documento de diseño
  del proyecto para el detalle (Fase 4 del plan original). La condición de victoria que esa misma
  fase también incluía (`prompt_fase3_godot.md` sección 4.1, nunca construida porque la Fase 3 real
  terminó siendo el modo incremental) ya se hizo — ver sección 11.

**Ideas deliberadamente no construidas:** multiplayer, cuentas, monetización, diplomacia, árbol
tecnológico elaborado, otras especies.

## 11. Fase 4: condición de victoria

Hasta esta fase ninguno de los dos modos tenía forma de **ganar** (la colonia con reina solo podía
perder, y el modo de comida/compra no tenía final de ningún tipo). Esto retoma la sección 4.1 de
`prompt_fase3_godot.md` (el plan original), que especificaba una victoria para la colonia con reina
y nunca se construyó porque la Fase 3 real terminó siendo el modo incremental.

- **Condición:** sobrevivir `cfg.victory_survive_s` segundos de simulación (180 s por defecto)
  DESPUÉS de llegar a Colonia madura, con la reina viva. El plan original decía "sobrevivir hasta
  el día 10"; como este modo no tiene día/noche (eso es solo del modo incremental), se adaptó a
  segundos de simulación tras la última era en vez de un número de día de calendario.
- **Dónde vive:** `Simulation._mature_since_s` (cuándo se llegó a Colonia madura por primera vez,
  -1.0 si nunca) y `Simulation._check_victory()`, llamada junto a `_check_game_over()` solo en la
  rama `elif queen_id >= 0:` de `tick()` — el modo incremental nunca entra ahí, así que nunca puede
  ganar (confirmado en `tools/test_phase4.gd`).
- **`sim.victory: bool`** distingue cuál de las dos pantallas mostrar; `sim.game_over` sigue siendo
  la única bandera que detiene `tick()` (ganar y perder paran la partida igual). `Hud` muestra
  "¡LA COLONIA PROSPERÓ!" en verde o "LA COLONIA CAYÓ" en rojo según corresponda, en el mismo lugar
  de pantalla.
- **Guardado:** `victory` y `_mature_since_s` se guardan y cargan como `incremental` en la Fase 3
  (con `d.get(..., default)`), así que cargar una partida guardada antes de esta fase sigue
  funcionando exactamente igual que antes (nunca llegó a "Colonia madura" según el guardado viejo,
  nunca ganó).

Ver sección 9c para lo que se dejó deliberadamente simplificado.

## 12. Fase 5: el ciempiés

Segunda amenaza de la colonia con reina (`sim/threats/centipede.gd`). A diferencia de la araña
(`Spider`, que solo caza en la superficie y asedia la entrada desde afuera), el ciempiés **entra
por los túneles ya cavados** y puede alcanzar hormigas bajo tierra — es su único rasgo realmente
distinto, pensado así a propósito para no ser "la araña con otro sprite".

- **Aparición:** igual mecanismo que la araña (`cfg.centipede_first_population`,
  `cfg.centipede_interval_s`, `cfg.centipede_strength_growth`), con un umbral de población mayor
  para que aparezca después y la amenaza escale con el tiempo. Solo en la colonia con reina (no en
  el modo incremental, igual que la condición de victoria de la Fase 4): `Simulation.tick()` llama
  `_update_centipede()` en la misma rama `elif queen_id >= 0:`.
- **Persecución:** reusa `NestDistanceField.bfs_from()` (el mismo BFS que ya usaba
  `cmd_move_queen`/`AntCasteAI.think_queen` para que la reina camine hasta donde la manda el
  jugador) para encontrar un camino real por los túneles hasta la hormiga más cercana. Se recalcula
  cada `cfg.centipede_retarget_ticks` ticks, no cada tick (es un BFS de grilla completa).
- **Huida:** cuando su vida baja de `cfg.centipede_flee_hp_pct`, sigue `sim.fields.surface_dist` (ya
  mantenido solo, sin BFS propio) de vuelta a la superficie y desaparece al llegar — sin estado de
  asedio como la araña, porque ya entró, no necesita quedarse rondando la entrada.
- **Defensa de la colmena, gratis:** `AntSystem._nearest_threat()` (el único punto que hacía falta
  tocar, como ya preveía el comentario de esa función) ahora compara la araña y el ciempiés y
  devuelve la más cercana; el resto del combate (`_think_defend`, `_think_soldier`) no se tocó, ya
  era genérico. El saqueo de cadáveres tampoco (`cfg.corpse_food_value_centipede`, reusa
  `spawn_corpse`).
- **HUD:** la línea de "Amenazas" ahora puede mostrar las dos a la vez, separadas por " · ".
- **Guardado:** `d["centipede"]` análogo a `d["spider"]`; `d.get(..., default)` para que un
  guardado de antes de esta fase cargue con el ciempiés en "nunca apareció", igual que si la
  partida nunca hubiera tenido esta amenaza.
- **Simplificación deliberada:** los números de balance (`cfg.centipede_*`) son una primera
  estimación sin playtesting, igual que pasó con `victory_survive_s` en la Fase 4 — ajustarlos es
  cambiar un número en `SimConfig`, no lógica.

## 13. Fase 6: el modo Test

Cuarta opción del menú principal: un sandbox para probar funcionalidades (amenazas, castas, clima)
sin jugar una partida completa cada vez. **No tiene condición de victoria ni derrota**: la reina
puede morir y la partida sigue (`Simulation.test_mode` envuelve `_check_game_over`/`_check_victory`
en `tick()`).

- **Composición fija al arrancar** (`Simulation.spawn_test_start()`): 1 reina, 20 obreras, 20
  guerreras (soldados) y 9 zánganos — 50 hormigas, siempre la misma receta cada vez que se
  reinicia. Arranca ya a pleno día (mismo truco de reloj que `spawn_incremental_start`). Sin
  lluvia automática: en este modo solo la dispara el jugador.
- **Panel de pruebas** (`Hud._build_test_panel`, arriba a la derecha, visible solo con
  `sim.test_mode`): reiniciar con una colonia nueva, poner/quitar lluvia, hacer aparecer o
  desaparecer la araña y el ciempiés a demanda, y agregar 5 hormigas de cualquier casta
  (obrera/guerrera/zángano/nodriza) de una.
- **Comandos nuevos, todos en `simulation.gd`:** `cmd_stop_rain()` (lo contrario de
  `cmd_force_rain`), `cmd_remove_spider()`/`cmd_remove_centipede()` (las hacen desaparecer sin
  dejar cadáver — es una acción de depuración, no un evento de juego real), y
  `cmd_add_caste_ants(caste, n)` (cualquier casta menos la reina, que ya tiene la suya).
- **Simplificación deliberada:** araña y ciempiés siguen siendo una sola instancia a la vez por
  tipo, igual que en el resto del juego (no se agregó soporte para "2 arañas a la vez" de verdad,
  que habría significado convertirlas a listas y tocar `AntSystem._nearest_threat`, el guardado,
  las vistas y las pruebas de las Fases 1/4/5). El botón "Aparecer araña" no hace nada si ya hay
  una viva, igual que la tecla F10 de siempre.
- **Guardado:** `d["test_mode"]` con `d.get(..., false)`, igual patrón que `incremental` en la
  Fase 3.

## 14. Fase 7: la mantis

Tercera amenaza de la colonia con reina (`sim/threats/mantis.gd`). A diferencia de la araña (caza
activa en superficie) y el ciempiés (persigue por los túneles), la mantis **se queda quieta y
camuflada** en un punto fijo de la superficie — nunca se mueve, nunca persigue — y si una hormiga
pasa lo bastante cerca, pega mucho más fuerte que las otras dos (`cfg.mantis_damage_per_s`).

- **Aparición:** mismo mecanismo que la araña y el ciempiés (`cfg.mantis_first_population`,
  `cfg.mantis_interval_s`, `cfg.mantis_strength_growth`), con un umbral entre el de la araña y el
  del ciempiés: un peligro de superficie que aparece antes de que la colonia cave tan hondo. Solo
  en la colonia con reina, igual que las otras dos.
- **Sin pathing de ningún tipo:** `spawn()` elige una celda de superficie fija cerca del nido
  (mismo rango que usa `_place_plants()` para las plantas) una sola vez; mientras está `HIDDEN` o
  `ATTACK` nunca cambia de posición. Solo reacciona (`_find_prey`) a una obrera que entra en
  `cfg.mantis_strike_range_px` — corto a propósito, no "ve" de lejos como la araña.
- **Huida:** si la hieren hasta bajar de `cfg.mantis_flee_hp_pct`, sí puede escapar — reusa la
  misma huida simple de `Spider.State.RETREAT` (camina hacia el borde del mapa y desaparece). No
  persigue nunca, pero tampoco se queda a morir si la descubren.
- **Defensa de la colmena y saqueo, gratis:** `AntSystem._nearest_threat()` ahora compara las tres
  amenazas (`cfg.corpse_food_value_mantis` para el cadáver); nada más se tocó.
- **HUD:** la línea de "Amenazas" puede mostrar las tres a la vez, separadas por " · ".
- **Guardado:** `d["mantis"]` análogo a `d["spider"]`/`d["centipede"]`.
- **Simplificación deliberada:** números de balance sin playtesting todavía, igual que las otras
  dos amenazas. Sigue sin soporte para "2 mantis a la vez" (una instancia por tipo, ver sección
  13).
