# Colony: Under the Earth

A 2D side-view ant-colony survival and management simulator made with **Godot 4.7** (GDScript,
Compatibility renderer) for Windows. You do not command individual ants. You guide a leafcutter
colony (*Atta*-inspired) with **pheromone signals** and **nest design**, and the ants do the work.

> Status: playable prototype / MVP. One species, one scenario (survive 10 days), one enemy (spider).
> Repository: https://github.com/JuanSPuentes/colony

**Design principle:** the player controls the colony through environmental signals and nest design;
the ants do the work themselves. Every new feature should respect this.

## Contents

1. [Play it](#1-play-it)
2. [Controls](#2-controls)
3. [How the game works](#3-how-the-game-works)
4. [Development guide](#4-development-guide) (start here to contribute)
5. [Architecture](#5-architecture)
6. [How to extend it](#6-how-to-extend-it)
7. [Testing](#7-testing)
8. [Art and sound status](#8-art-and-sound-status)
9. [Known limitations and roadmap](#9-known-limitations-and-roadmap)

---

## 1. Play it

1. Install **Godot 4.x**. Developed and tested with **4.7.2 stable** (standard build, not Mono):
   https://godotengine.org/download/windows/
2. Open Godot, **Import** `project.godot`, press **F5**.
   From a terminal: `Godot.exe --path .`
3. Optional fixed seed: `Godot.exe --path . -- --seed=42` (each restart uses seed + 1).

The window is 1680x900 and scales to fit. No downloads, no network, no external assets.

## 2. Controls

| Input | Action |
|---|---|
| **I** | Inspect: click an ant, brood, plant, spider or cell |
| **D** | Dig: drag from an existing tunnel into soil (workers carry the orders out) |
| **1 2 3 4 5** | Paint rooms over tunnels: Royal, Nursery, Storage, Drain, plain Tunnel |
| **Q W E R T** | Pheromones: Food, Home, Danger, Attack, Evacuate |
| **X** or right-click | Erase pheromones and cancel dig orders under the brush |
| **7 8 9** | Next eggs become Worker / Nurse / Soldier (also retargets a selected egg or larva) |
| **Space** | Pause / resume |
| **Tab** | Speed 1x / 2x / 4x |
| Mouse wheel, middle-drag, arrows, **Home** | Zoom, pan, reset the view |
| **Ctrl+R** or *Restart* button | Restart with a new seed |

Everything is also in the right-hand panel (hover for tooltips). A hint box teaches the first steps.

## 3. How the game works

**Goal.** Survive until the end of day 10 with the queen alive and at least 10 other ants. You lose if
the queen dies (spider, drowning, starvation), if there is no food or water for two minutes, or if
every worker, nurse and soldier dies. The defeat screen explains why.

**Castes** (data in `scripts/sim/species_defs.gd`)
- *Queen*: stays in the royal chamber, lays eggs when fed, flees rising water. Her death ends the game.
- *Workers*: forage food and water, carry it home, dig tunnels.
- *Nurses*: move eggs and larvae to the nursery and tend them.
- *Soldiers*: guard the entrance, fight spiders, answer Attack signals.

**Brood.** Egg, larva, pupa, adult (18 s / 40 s / 26 s at normal care). Larvae eat food; a soldier costs
10 food, a nurse 6, a worker 5. Nurseries and nurse care speed development; flooded or starving brood
dies. The population cap grows with the size of the nest.

**Economy.** Food and water are carried physically to storage. Storage cells raise capacity. Everyone
consumes food; without it the queen stops laying and ants weaken at different rates. The top bar shows
stocks and their change per minute.

**Pheromones (the main control).** Five fields with intensity, decay and caste-dependent effects. Rain
washes surface scent away about 10x faster.

| Type | What ants do |
|---|---|
| Food | Workers climb its gradient toward food; returning loaded ants lay their own trail, so good routes reinforce themselves. Drag **from the nest toward the plant**: the stroke ramps up so the trail has a direction. |
| Home | Lost ants (rain makes surface ants lose their way, shown as `?`) follow it back. Drag **from far away toward the nest**. |
| Danger | Workers and nurses retreat underground; soldiers ignore it. |
| Attack | Soldiers in range run to the strongest Attack cells. |
| Evacuate | Ants in marked cells move to the nearest unmarked, dry cell. |

Ants weigh signals against their task, load, path cost (flooded cells are expensive), colony needs and
immediate threats, so a food trail never makes an ant ignore rising water or a spider. Icons above
ants show reactions: `+` following a trail, `!` fleeing danger, `~` fleeing water, `>` evacuating,
`x` attacking, `?` lost.

**Nest building.** A dig order must touch an existing tunnel or order, so new areas are always
connected. Rock cannot be dug. Digging costs worker time plus a little food. Digging up to the surface
opens a new entrance, and a new way for rain. Rooms: Royal (queen lays here), Nursery (faster, tended
brood), Storage (capacity), Drain (soaks floodwater).

**Weather.** Storms are announced 15 s ahead. Rain enters every surface opening; water falls, spreads
sideways and pushes upward when cells are full. It slows and drowns ants, damages brood and can kill the
queen. The default nest funnels water into the royal chamber, so layout matters.

**Spider.** Comes from a map edge, hunts exposed ants, lingers at the entrance, and invades toward the
queen if no soldier guards the entrance for about 22 s. It retreats when badly hurt. Four spiders are
scheduled (days 3, 6, 8, 10) with growing strength.

---

## 4. Development guide

### Requirements
- Godot **4.7.2** (other 4.x versions are untested; GDScript uses typed code, `static var`, lambdas).
- Windows is the target platform. Nothing in the code is Windows-specific.
- Python is **not** needed. All tools are GDScript.

### First steps
```
git clone https://github.com/JuanSPuentes/colony.git
cd colony
Godot.exe --headless --path . --import      # first import, creates .godot/ (ignored by git)
Godot.exe --path .                          # play
```
`.godot/` is generated and ignored by git. Never commit it.

### Repository layout
```
project.godot            Godot config (1680x900, Compatibility renderer, main scene)
scenes/main.tscn         Single scene: one Node running scripts/main.gd
scripts/main.gd          Entry point: builds view, HUD, sound; creates/restarts the Simulation
scripts/sim/             SIMULATION. No drawing, no UI, no Node classes (RefCounted only)
scripts/view/            Rendering and mouse input (world_view.gd), procedural sprites (sprites.gd)
scripts/ui/hud.gd        All UI, built in code
scripts/audio/sfx.gd     Synthesized sound effects
tools/                   Dev and test scripts (see Testing)
```

### Conventions
- **Simulation is separate from presentation.** `scripts/sim/` must never reference `Node`, drawing,
  `Input` or UI. The view reads simulation state; the UI and mouse call `Simulation.cmd_*` methods.
  This keeps the sim testable headless.
- **Fixed tick.** `Cfg.TICK = 1/30 s`. `WorldView` accumulates real time x speed and calls
  `sim.step(Cfg.TICK)`. Never use `delta` of the render frame inside the simulation.
- **Determinism.** All randomness goes through `sim.rng` (seeded). Same seed gives the same game.
  Avoid `randf()` in `scripts/sim/` (it is fine for cosmetic particles in the view).
- **Data over code.** Caste stats, brood times and costs live in `species_defs.gd`; tunable numbers
  such as flood rates and decay rates are named constants at the top of their files.
- **Typed GDScript.** The project treats untyped inferred `:=` from Variant as an error. When `sim` is
  an untyped parameter (as in `AntBrain`), declare types explicitly: `var p: Array[Vector2i] = ...`.
- **Grid coordinates.** x grows right, y grows **down**. Row `Cfg.SURFACE` (14) is the first soil row;
  ants walk on row `Cfg.SURFACE_ROW` (13) above ground and on `TUNNEL` cells below. Convert with
  `Cfg.cell_center()` and `Cfg.world_to_cell()`. One cell is 16 px.
- Keep comments short and explain *why*, not what. Match the surrounding style (tabs, snake_case).

### Workflow
1. Make the change (simulation changes go in `scripts/sim/`).
2. Run the three test scripts below. All must pass.
3. If you changed visuals, run `tools/screenshot.gd` and look at the PNGs.
4. Commit with a short imperative message and open a PR against `main`.

## 5. Architecture

```
main.gd
 |- Sfx                      synthesized audio
 |- WorldView (Node2D)       draws everything, mouse tools, owns the simulation clock
 |    '- reads Simulation, calls sim.cmd_*()
 |- Hud (CanvasLayer)        top bar, tool panel, hints, log, outcome screen
 '- Simulation (RefCounted)  the whole game state and rules
      |- Terrain             cell types, rooms, water array, dig orders, AStarGrid2D, BFS helper
      |- Pheromones          5 sparse-active float fields, decay, gradient helpers
      |- Flood               water cellular automaton (fall, spread, overflow, drain, seep)
      |- Weather             storm schedule, rain intensity, puddle
      |- Colony              food/water stocks, consumption, egg laying, population cap
      |- ants: Array[Ant]    data only; behaviour is in AntBrain
      |- brood: Array[Brood], sources: Array[FoodSource], spider: Spider
      '- AntBrain (static)   per-caste state machines
```

### Tick order (`Simulation.step`)
weather -> puddle -> flood -> pheromone decay -> food regrowth -> spider schedule -> spatial buckets
-> slow stats (every 0.25 s) -> every ant `AntBrain.update` -> spider -> brood -> colony economy ->
remove dead -> win/lose check. Dead ants are only flagged during the loop and removed afterwards.

### Ant behaviour (`scripts/sim/ant_brain.gd`)
`AntBrain.update(ant, sim, dt)` runs once per ant per tick:
1. Environment damage (drowning, starvation), then a hazard check every ~0.3 s (flood, Evacuate,
   Danger). A hazard interrupts the current task and starts `FLEE` toward a safe cell found by BFS.
2. Movement along a precomputed A* path (`_move`). Blocked paths are dropped and the state logic re-plans.
3. The state machine of the caste: `_queen`, `_worker`, `_nurse`, `_soldier`.

Important states (`Cfg.State`): IDLE, EXPLORE, FOLLOW_TRAIL, TO_RESOURCE, COLLECT, CARRY_HOME, TO_DIG,
DIGGING, NURSING, MOVE_BROOD, GUARD, ATTACK, FLEE, REST.

Ground-line pheromone following is `_gradient_dir()`: climb the gradient, keep heading on plateaus, turn
when walking downhill, report `ended` when the trail runs out. Both Food and Home use it.

### Why some things are the way they are
- **No scent next to openings** (`Simulation.near_opening`): without this, returning ants pile pheromone at
  the entrance and trap followers in a local maximum.
- **Paint ramp** (`WorldView._paint_phero`): Food/Home strokes rise 0.012 per cell so a trail has a
  direction and does not saturate quickly.
- **Hunger is staggered** (`Ant.hardiness`): ants weaken at different speeds so a famine is gradual.
- **Surface is one-dimensional**: ants only walk on the ground line. This keeps pathing and pheromones
  simple and is a deliberate MVP simplification.

## 6. How to extend it

**A new species.** Add a dictionary like `SpeciesDefs.LEAFCUTTER` and pass it to `Colony.new()`
in `Simulation`. Castes are looked up with `SpeciesDefs.caste(species, caste_id)`. New caste ids go in
`Cfg.Caste` plus a sprite in `Sprites._make_ant` and a branch in `AntBrain.update`.

**A new room type.** Add it to `Cfg.Room` and `Cfg.ROOM_NAMES`, a colour in `Sprites.ROOM_BASE` and
`ROOM_SPECK`, a button in `Hud._build`, a key in `WorldView._unhandled_key_input`, and implement its
effect where it matters (`Colony`, `Flood`, `AntBrain`). A room without a gameplay effect should not be
added.

**A new pheromone.** Add to `Cfg.Phero`, `PHERO_NAMES`, `Pheromones.DECAY`, `WorldView.PHERO_COLORS` and
`PHERO_HINTS`, then read it in `AntBrain` (see `_hazards` and `_soldier_think` for examples). Add an A/B
test in `tools/validate.gd` proving it changes behaviour.

**A new enemy.** Copy the structure of `scripts/sim/spider.gd` (a `RefCounted` with `step(sim, dt)`,
`take_damage`, an alarm emitter), schedule it in `Simulation._spider_plan`/`_spider_events`, draw it in
`WorldView`, and let soldiers target it in `AntBrain._soldier`.

**New events/weather.** Storms are a list in `Weather._init`. Add fields and handle them in
`Weather.step`.

**Balance.** Main knobs: `species_defs.gd` (costs, speeds), `Colony` (consumption, laying rules),
`FoodSource.regrow` and amounts in `Simulation._make_sources`, `Flood` constants, `Weather.storms`,
`Simulation._spider_plan`, `Spider.damage_per_hit`. After changing any, rerun `tools/validate.gd`: the
scripted-player test is an early warning that the game became too hard or too easy.

## 7. Testing

All tests are GDScript run through Godot. Use the console build on Windows
(`Godot_v4.7.2-stable_win64_console.exe`) to see output. They exit with code 1 on failure.

| Command | What it checks |
|---|---|
| `Godot --headless --path . --script tools/validate.gd` | Simulation behaviour: determinism, foraging, A/B tests for each pheromone, digging and room rules, eggs and castes, flooding with and without drains, spider fights and invasion, lost ants, performance, and a scripted player that must win 2 of 3 seeds. **36 checks.** |
| `Godot --headless --path . --script tools/ui_test.gd` | The real scene driven with injected keyboard and mouse events: pause, speed, tools, dragging, erase, inspect, zoom, caste buttons, defeat, restart, victory. **26 checks.** |
| `Godot --path . --script tools/perf.gd` | (Needs a window.) Frame rate with 140 ants at 4x speed. Expected 60 FPS. |
| `Godot --headless --path . --script tools/sim_test.gd -- 7` | Prints a report every 30 simulated seconds for a full game without player input. Useful for balance. |
| `Godot --path . --resolution 1680x900 --script tools/screenshot.gd -- <out_dir> 45 150 250` | (Needs a window.) Fast-forwards to the given sim seconds with a scripted player and saves PNGs, plus zoomed shots. |

Notes for writing tests
- Disable random events with `_no_storms(sim)` when you test something else; force one with
  `sim._spider_plan = [...]` or `sim.weather.storms = [...]`.
- Prefer A/B tests (same seed with and without the player action) to prove a mechanic matters.
- Headless windows are tiny; `ui_test.gd` sets the root window size and disables content scaling so
  injected mouse positions match the screen. Do the same for new UI tests.
- Harmless warnings at exit ("resources still in use") appear in headless runs.

## 8. Art and sound status

| Item | Status |
|---|---|
| Ants (4 castes x 4 walk frames), spider, brood, leaves, plants | Procedural pixel art generated at start-up in `sprites.gd`. Coherent but **provisional**. |
| Soil, rock, tunnel and room tiles | Procedural, variants per depth band and room type. |
| Sky, sun/moon, hills, clouds, grass, rain | Procedural, drawn in `world_view.gd`. |
| UI | Godot theme styled in code, default font. |
| Sound | Synthesized placeholders (`sfx.gd`). |

There are no third-party assets and no licences to track. Replacing a procedural sprite with a PNG only
requires returning a `Texture2D` from the matching function in `sprites.gd`.

## 9. Known limitations and roadmap

**Known limitations**
- Never played by a human: difficulty is tuned against a scripted player (wins 3/3 seeds; doing nothing
  loses around day 7-9).
- Ants only mirror/rotate (no proper wall-climbing orientation); one spider design.
- Surface movement is one-dimensional; pheromones do not diffuse; water is a grid approximation.
- Caste handling is a gameplay simplification (choose what the next eggs become).
- One species, one enemy, one scenario; no save/load; the world does not scroll beyond zoom/pan.

**Suggested next steps (highest value first)**
1. Art and animation pass: hand-drawn directional ant sheets, tile variety, a second enemy design.
2. Real playtesting: tune difficulty, add difficulty levels, turn hints into a guided first storm and spider.
3. Content using the existing data model: more species/castes, seasons, rival colonies, scent diffusion.
4. Save/load of a colony (all state is plain data in `Simulation`, so serialising it is feasible).

**Ideas deliberately not built yet:** multiplayer, accounts, monetisation, diplomacy, tech tree.
