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
| **3** | Cámara (Q/E cambia el tipo: Guardería, Almacén, Jardín de hongos, Drenaje, Real) |
| **4** | Borrar (quita marca de excavar, cámara y las 5 feromonas bajo el pincel) |
| Clic izquierdo / derecho, arrastrar | Pintar / borrar con la herramienta activa |
| **7** | Comprar una obrera con comida (también con el botón del panel) |
| **8** | Comprar un soldado con comida (también con el botón del panel) |
| **9** | Auto-compra: apagada → obreras → soldados (compra sola en cuanto alcanza, dejando una reserva) |
| **Espacio** | Pausa / reanudar |
| **F1 / F2 / F3** | Velocidad x1 / x2 / x4 |
| **Tab** | Recorre las capas de depuración (feromonas, agua, estados, castas) |
| **WASD** | Mover la cámara |
| Rueda del mouse | Zoom en pasos fijos |
| **H** | Saltar a la reina |
| **L** | Forzar la lluvia |
| **F9** | Agregar 400 hormigas (prueba de carga) |
| **F5** | Reiniciar con el mismo mapa |
| **Shift+F5** | Reiniciar con un mapa nuevo |
| **F6** | Guardar partida |
| **F7** | Cargar la última partida guardada |
| **I** | Plegar / desplegar el panel de estado (también con el botón "ocultar" del panel) |
| Clic medio, arrastrar | Mover la cámara |

## 3. Cómo funciona ahora mismo

### Modo incremental (Fase 3, el que arranca `main.gd`)

`Simulation.spawn_incremental_start()` (`sim/simulation.gd`), economía en
`sim/colony/incremental_economy.gd`, día y noche en `sim/core/day_night.gd`.

- **Colonia inicial:** 1 reina, 3 obreras, 1 soldado y 1 larva (que nace obrera). Sin nodrizas.
- **Todo es comida.** Cada hoja que una obrera trae al nido vale `inc_food_per_leaf` de comida al
  llegar. No hay agua ni hongo como recursos aparte. Todas las adultas comen; si la comida llega
  a 0, la reina y los soldados se debilitan (las obreras no).
- **Comprar hormigas:** 7 (obrera) u 8 (soldado), o los botones del panel. Se paga la comida, la
  reina pone un huevo de esa casta y la cría hace el resto (huevo → larva → pupa, `inc_brood_speed`
  veces más rápido que en la Fase 1 y sin depender de nodrizas). Cada compra multiplica el precio
  de la siguiente de esa casta (`inc_*_cost_growth`).
- **Auto-compra (9):** apagada → obreras → soldados. Compra sola en cuanto alcanza, dejando
  `inc_auto_reserve` de comida para no matar de hambre a la reina.
- **Día y noche:** el ciclo dura `day_length_s` (60 % de luz, 40 % de noche) y arranca al amanecer.
  Un día de luz + una noche = 1 día; el HUD muestra "Día N". De noche el mundo se oscurece y las
  plantas no rebrotan.
- **Plantas:** rebrotan de día (`inc_plant_regrow_per_s`) hasta su máximo, así el juego no se queda
  sin hojas. La colonia recuerda las plantas de las que ya sacó hojas y las obreras en la superficie
  van directo a la conocida más cercana (ver simplificaciones, sección 9b).
- **Sin araña ni eras.** La primera lluvia llega al inicio del día 3 (`inc_rain_first_s`) y la reina
  no se ahoga; el resto de la colonia sí sufre las inundaciones.

### Modo clásico (Fases 1-2; lo usan las pruebas de esas fases)

**Castas** (`sim/colony/caste_defs.gd`): Reina (una sola, vive en la cámara Real, pone huevos si hay comida
suficiente; su muerte termina la partida), Obrera (explora, corta hojas, carga, cava), Nodriza (acelera
el desarrollo de la cría cerca del nido), Soldado (patrulla, responde a la feromona de Ataque y pelea
cuerpo a cuerpo contra la araña).

**Cría** (`sim/colony/brood_system.gd`): huevo → larva → pupa → adulta. Al poner un huevo, la reina le asigna
la casta que más lejos esté del reparto objetivo del jugador (ajustable con 7/8/9). Sin nodrizas cerca
la larva se desarrolla mucho más despacio; sin Guardería válida, algo más despacio y puede morir si el
nido se inunda a fondo.

**Cámaras** (`sim/colony/room_system.gd`): el jugador las designa pintando sobre túneles ya excavados. Cada
tipo necesita un tamaño mínimo y estar conectado al nido para activarse:

| Cámara | Efecto |
|---|---|
| Real | La reina solo pone huevos aquí (la cámara inicial ya viene designada) |
| Guardería | La cría se desarrolla a velocidad completa |
| Almacén | Sube el tope de comida y agua |
| Jardín de hongos | Convierte hojas almacenadas en comida, con el tiempo |
| Drenaje | Absorbe agua de inundación, celda por celda |

**Economía** (`sim/colony/colony.gd`): las obreras cortan hojas y las traen al nido (igual que en la Fase 0);
el Jardín de hongos las convierte en comida. El agua entra despacio mientras hay charcos tras la
lluvia (ver simplificaciones). Todas las adultas consumen comida y agua; sin jardín de hongos, la
colonia no repone comida sola. La falta de comida o agua no afecta a la obrera (compatibilidad con la
Fase 0), pero sí debilita a la reina, las nodrizas y los soldados hasta matarlos.

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
(Jardín de hongos, soldados, primera lluvia) y Colonia madura (Drenaje, Peligro, Ataque, Evacuar, la
araña).

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
  threats/              Enemigos (hoy, la araña)
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
      |- WaterSim              agua: caída, esparcido, evaporación, drenaje
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
clima → agua + drenaje → decaimiento de las 5 feromonas → recálculo de campos si cambió el terreno →
cámaras (`rooms.maybe_recompute`) → `AntSystem.tick()` → si hay reina: economía → cría → era →
araña (cada 3 ticks) → revisión de derrota.

## 6. Pruebas

Todas las pruebas son GDScript corrido a través de Godot. Usa el build de consola
(`Godot_v4.7.2-stable_win64_console.exe`) para ver la salida. Terminan con código 1 si algo falla.

| Comando | Qué comprueba |
|---|---|
| `Godot --headless --path . --script tools/test_phase0.gd` | Regresión de la Fase 0: determinismo, forrajeo, feromonas, excavación, lluvia/drenaje, huida/muerte, rendimiento. **34 pruebas.** |
| `Godot --headless --path . --script tools/test_phase1.gd` | Criterios de la Fase 1: reina y puesta de huevos, las 4 etapas de cría, reparto de castas, cámaras (válidas/inválidas), economía del jardín de hongos, Peligro/Evacuar, Drenaje, la araña (caza, la espantan, causa bajas sin soldados), eras, derrota, determinismo con colonia completa, rendimiento. **25 pruebas.** |
| `Godot --headless --path . --script tools/ui_test.gd` | La escena real con eventos inyectados: arranque con reina+nodrizas, pausa, compras 7/8/9 y botones, panel de estado plegable (I), herramientas, cámara, capas, F9, reinicio. **26 pruebas.** |
| `Godot --headless --path . --script tools/test_phase2.gd` | Guardado y carga: la huella no cambia al guardar y cargar (en memoria y desde un archivo real), la partida sigue igual tras cargar como si nunca se hubiera guardado, un archivo inexistente no revienta, funciona con y sin reina, las cámaras y la lluvia en curso sobreviven. **10 pruebas.** |
| `Godot --headless --path . --script tools/test_phase3.gd` | Modo incremental: colonia inicial exacta, sin araña ni eras, día y noche, hojas → comida, compras y precios crecientes, el huevo comprado nace de esa casta, auto-compra con reserva, rebrote solo de día, la colonia crece sola 6 min con lluvia sin morir, guardado y carga (también por JSON), determinismo. **28 pruebas.** |
| `Godot --headless --path . --script tools/test_app_menu.gd` | El menú (`app/`): arranca mostrando el menú, Opciones desde el menú vuelve al menú, Opciones desde la tuerca en partida vuelve a la partida (pausada) y no al menú, Juego normal arranca en modo incremental (comida/compra), Modo infinito arranca en modo Historia con la colonia completa, F5 conserva el modo, volumen/brillo se guardan, Salir pide confirmación en vez de cerrar directo. **11 pruebas.** |
| `Godot --path . --script tools/screenshot.gd -- <carpeta>` | (Necesita ventana.) Guarda capturas PNG. |

**Última ejecución verificada (2026-10-16, Godot 4.7.2):** las seis suites en 34/34 (Fase 0),
25/25 (Fase 1), 10/10 (Fase 2), 28/28 (Fase 3), 26/26 (ui_test) y 11/11 (menú).

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
- **La cría no tiene posición física ni la cargan las nodrizas.** Vive conceptualmente en el nido;
  lo que sí importa (nodrizas presentes, Guardería válida, inundación) tiene efecto real.
- **La araña no encuentra camino real por los túneles.** Si nadie la detiene en la entrada por un
  tiempo, se modela como un golpe directo a la reina ("asedio"), no como una invasión celda por celda.
- **El reparto de castas se ajusta con tres teclas (7/8/9)**, no con controles deslizantes en
  pantalla.
- **No hay herramienta de inspección por pasar el mouse** sobre hormigas o cámaras; la capa de
  depuración y los colores cumplen ese papel por ahora.

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
- **La reina no se ahoga en este modo**, y la primera lluvia llega el día 3: una colonia de 5
  hormigas no alcanza a cavar un drenaje antes de la lluvia de los 150 s de la Fase 1.
- **No se compran nodrizas** y la cría no depende de ellas en este modo.
- **Las cámaras siguen existiendo** pero solo el Almacén importa para la economía (sube el tope de
  comida). El Jardín de hongos no hace nada: las hojas ya son comida al llegar.

## 10. Hoja de ruta: qué falta de la Fase 2

- Arte final: hormigas y araña dibujadas a mano, animaciones direccionales, variedad de tiles.
- Interfaz pulida: controles deslizantes para el reparto de castas, tooltips al pasar el mouse,
  tutorial guiado.
- Playtesting real con una persona (hasta ahora el balance solo se validó con las pruebas
  automatizadas).
- Mejoras y progresión entre partidas (vuelo nupcial, eras avanzadas): ver el documento de diseño
  del proyecto para el detalle (Fase 4 del plan original).

**Ideas deliberadamente no construidas:** multiplayer, cuentas, monetización, diplomacia, árbol
tecnológico elaborado, otras especies.
