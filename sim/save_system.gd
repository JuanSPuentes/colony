class_name SaveSystem
extends RefCounted
## Guarda y carga una partida completa (Fase 2). Vive en la raíz de `sim/`, junto a
## `simulation.gd`, porque igual que el orquestador necesita conocer todos los dominios a la vez
## (ver ARCHITECTURE.md). No cambia ninguna regla de juego: solo convierte el estado de una
## `Simulation` a JSON y de vuelta.
##
## Formato: un Dictionary de solo tipos simples (int, float, bool, String, Array, Dictionary),
## para poder usar `JSON.stringify`/`JSON.parse_string` tal cual. Los `Packed*Array` de la
## simulación se convierten con `Array(x)` / `PackedXArray(array)`, que GDScript ya sabe hacer;
## los `Vector2`/`Vector2i` se aplanan a `[x, y]` a mano porque el JSON de Godot no los entiende.

const SAVE_VERSION := 1


# --- Serializar -----------------------------------------------------------------------------------

static func to_dict(sim: Simulation) -> Dictionary:
	var d := {}
	d["version"] = SAVE_VERSION
	d["seed"] = sim.rng.seed
	# Como texto: JSON guarda los números como double y redondearía este entero de 64 bits, así
	# que la partida cargada desde un archivo divergía a los pocos ticks.
	d["rng_state"] = str(sim.rng.state)
	d["tick_count"] = sim.tick_count
	d["leaves_stored"] = sim.leaves_stored
	d["corpse_parts_stored"] = sim.corpse_parts_stored
	d["delivered"] = sim.delivered
	d["deaths"] = sim.deaths
	d["dug"] = sim.dug
	d["dig_violations"] = sim.dig_violations
	d["stuck_recoveries"] = sim.stuck_recoveries
	d["total_leaves_left"] = sim.total_leaves_left
	d["weather"] = sim.weather
	d["rain_start_tick"] = sim.rain_start_tick
	d["rain_end_tick"] = sim.rain_end_tick
	d["rains_started"] = sim.rains_started
	d["queen_id"] = sim.queen_id
	d["era"] = sim.era
	d["game_over"] = sim.game_over
	d["game_over_reason"] = sim.game_over_reason
	d["victory"] = sim.victory
	d["mature_since_s"] = sim._mature_since_s
	d["spiders_spawned"] = sim.spiders_spawned
	d["spider_next_s"] = sim.spider_next_s
	d["notifications"] = sim.notifications.duplicate()
	# Fase 3: modo incremental.
	d["incremental"] = sim.incremental
	# Fase 6: modo Test (sandbox, sin victoria/derrota).
	d["test_mode"] = sim.test_mode
	# Fase 14: Nivel 0.
	d["tutorial_level"] = sim.tutorial_level
	d["fog"] = sim.fog != null
	d["tutorial_battle_started"] = sim.tutorial_battle_started
	d["econ"] = {
		"bought_eggs": sim.econ.bought_eggs,
		"auto_mode": sim.econ.auto_mode,
		"food_earned": sim.econ.food_earned,
		"known_plants": Array(sim.econ.known_plants),
	}

	d["world"] = {
		"w": sim.world.w, "h": sim.world.h,
		"cells": Array(sim.world.cells),
		"room": Array(sim.world.room),
		"job_claim": Array(sim.world.job_claim),
		"job_progress": Array(sim.world.job_progress),
		"marked_count": sim.world.marked_count,
		"jobs_version": sim.world.jobs_version,
		"passable_version": sim.world.passable_version,
		"rooms_version": sim.world.rooms_version,
		"nest_cells": sim.world.nest_cells.duplicate(),
	}

	for name in ["food", "home", "danger", "attack", "evacuate"]:
		var field: PheromoneField = sim.get(name)
		d[name] = Array(field.data)
		# Fase 14: piso pintado por el jugador (ver `PheromoneField.paint`), solo si existe.
		if not field.floor_v.is_empty():
			d[name + "_floor"] = Array(field.floor_v)

	d["water"] = {
		"level": Array(sim.water.level),
		"raining": sim.water.raining,
		"max_level": sim.water.max_level,
		"volume": sim.water.volume,
	}

	d["colony"] = {
		"food": sim.colony.food, "water": sim.colony.water,
		"food_cap": sim.colony.food_cap, "water_cap": sim.colony.water_cap,
		"food_trend": sim.colony.food_trend, "water_trend": sim.colony.water_trend,
		"egg_cooldown": sim.colony.egg_cooldown,
		"starving": sim.colony.starving, "thirsty": sim.colony.thirsty,
		"target_pct": _int_keys_to_str(sim.colony.target_pct),
	}

	d["brood"] = {
		"stage": Array(sim.brood.stage), "timer": Array(sim.brood.timer),
		"caste": Array(sim.brood.caste), "alive": Array(sim.brood.alive),
		"pos": _v2_arr(sim.brood.pos), "claimed": Array(sim.brood.claimed),
		"hatched": sim.brood.hatched, "died": sim.brood.died,
	}

	d["spider"] = {
		"pos": _v2(sim.spider.pos), "state": sim.spider.state,
		"hp": sim.spider.hp, "max_hp": sim.spider.max_hp,
		"target_ant": sim.spider.target_ant, "siege_t": sim.spider.siege_t,
		"alive": sim.spider.alive,
	}

	# Fase 5: segunda amenaza. `_path_dist`/`_path_target_cell`/`_retarget_at` no se guardan: son
	# caché de pathing, se recalculan solos en el primer tick tras cargar (igual que los campos de
	# distancia del mundo, más abajo).
	d["centipede"] = {
		"pos": _v2(sim.centipede.pos), "state": sim.centipede.state,
		"hp": sim.centipede.hp, "max_hp": sim.centipede.max_hp,
		"target_ant": sim.centipede.target_ant, "alive": sim.centipede.alive,
	}
	d["centipedes_spawned"] = sim.centipedes_spawned
	d["centipede_next_s"] = sim.centipede_next_s

	# Fase 7: tercera amenaza. Nunca se mueve sola (sin pathing, sin caché que guardar).
	d["mantis"] = {
		"pos": _v2(sim.mantis.pos), "state": sim.mantis.state,
		"hp": sim.mantis.hp, "max_hp": sim.mantis.max_hp,
		"target_ant": sim.mantis.target_ant, "alive": sim.mantis.alive,
	}
	d["mantises_spawned"] = sim.mantises_spawned
	d["mantis_next_s"] = sim.mantis_next_s

	# Fase 9: estaciones + colonia rival (reemplaza lo que guardaba la Fase 8).
	d["season_index"] = sim.season_index
	d["season_start_day"] = sim.season_start_day
	d["rival_colony"] = {
		"battle_active": sim.rival_colony.battle_active,
		"battle_won": sim.rival_colony.battle_won,
		"queen_pos": _v2(sim.rival_colony.queen.pos),
		"queen_hp": sim.rival_colony.queen.hp,
		"queen_max_hp": sim.rival_colony.queen.max_hp,
		"queen_alive": sim.rival_colony.queen.alive,
		"marching": sim.rival_colony.marching, "rally_s": sim.rival_colony.rally_s,
	}

	var ants := sim.ants
	d["ants"] = {
		"count": ants.count, "alive_count": ants.alive_count,
		"pos": _v2_arr(ants.pos), "prev": _v2_arr(ants.prev), "heading": _v2_arr(ants.heading),
		"target": _v2_arr(ants.target), "last_check": _v2_arr(ants.last_check),
		"state": Array(ants.state), "caste": Array(ants.caste),
		"next_think": Array(ants.next_think), "last_think": Array(ants.last_think),
		"trip_steps": Array(ants.trip_steps), "job": Array(ants.job),
		"last_cell": Array(ants.last_cell), "ignore_until": Array(ants.ignore_until),
		"alive": Array(ants.alive), "carry": Array(ants.carry), "carry_kind": Array(ants.carry_kind),
		"carry_egg": Array(ants.carry_egg), "patrol_x": Array(ants.patrol_x),
		"hp": Array(ants.hp), "timer": Array(ants.timer),
		"stuck_t": Array(ants.stuck_t), "check_acc": Array(ants.check_acc),
		"max_stuck_seen": ants.max_stuck_seen,
		"faction": Array(ants.faction),  # Fase 9: 0 jugador, 1 rival.
	}

	var plants := []
	for p in sim.plants:
		plants.append({"cell": [p.cell.x, p.cell.y], "leaves": p.leaves, "max_leaves": p.max_leaves, "regrow_acc": p.regrow_acc, "kind": p.kind, "hue": p.hue,
			"pocket": p.pocket.map(func(c: Vector2i) -> Array: return [c.x, c.y])})
	d["plants"] = plants

	var corpses := []
	for c in sim.corpses:
		corpses.append({"pos": _v2(c.pos), "food_value": c.food_value, "age": c.age})
	d["corpses"] = corpses
	return d


static func save_file(sim: Simulation, path: String) -> Error:
	var text := JSON.stringify(to_dict(sim))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.close()
	return OK


# --- Cargar -----------------------------------------------------------------------------------

## Reconstruye una Simulation desde un Dictionary ya cargado. `cfg` debe ser la misma
## configuración (o una compatible: mismo tamaño de mundo) con la que se guardó la partida.
static func from_dict(d: Dictionary, cfg: SimConfig) -> Simulation:
	# `Simulation.new` ya hace un mundo, hormigas y plantas "de prueba": los pisamos todos abajo.
	# Es algo de trabajo de más, pero evita tener un segundo camino de construcción sin colonia
	# que mantener aparte (ver ARCHITECTURE.md: menos caminos de construcción, menos espagueti).
	var sim := Simulation.new(cfg, int(d["seed"]))
	sim.rng.state = String(d["rng_state"]).to_int() if d["rng_state"] is String else int(d["rng_state"])
	sim.tick_count = int(d["tick_count"])
	sim.leaves_stored = int(d["leaves_stored"])
	sim.corpse_parts_stored = int(d.get("corpse_parts_stored", 0))
	sim.delivered = int(d["delivered"])
	sim.deaths = int(d["deaths"])
	sim.dug = int(d["dug"])
	sim.dig_violations = int(d["dig_violations"])
	sim.stuck_recoveries = int(d["stuck_recoveries"])
	sim.total_leaves_left = int(d["total_leaves_left"])
	sim.weather = int(d["weather"])
	sim.rain_start_tick = int(d["rain_start_tick"])
	sim.rain_end_tick = int(d["rain_end_tick"])
	sim.rains_started = int(d["rains_started"])
	sim.queen_id = int(d["queen_id"])
	sim.era = int(d["era"])
	sim.game_over = d["game_over"]
	sim.game_over_reason = d["game_over_reason"]
	# Fase 4: ausentes en guardados de antes de la condición de victoria; -1.0 reproduce "nunca
	# llegó a Colonia madura" y false "no ganó", igual que si la partida nunca hubiera tenido esta
	# bandera.
	sim.victory = bool(d.get("victory", false))
	sim._mature_since_s = float(d.get("mature_since_s", -1.0))
	sim.spiders_spawned = int(d["spiders_spawned"])
	sim.spider_next_s = float(d["spider_next_s"])
	sim.notifications.clear()
	for n in d["notifications"]:
		sim.notifications.append(String(n))
	# Fase 3. Un guardado de antes de la Fase 3 no trae estas llaves: queda en modo clásico.
	sim.incremental = bool(d.get("incremental", false))
	# Fase 6. Ausente en guardados de antes de esta fase: no es un guardado de un entorno de pruebas.
	sim.test_mode = bool(d.get("test_mode", false))
	# Fase 14. Ausente en guardados viejos: no es una partida del Nivel 0.
	sim.tutorial_level = bool(d.get("tutorial_level", false))
	sim.tutorial_battle_started = bool(d.get("tutorial_battle_started", false))
	if d.has("econ"):
		var ed: Dictionary = d["econ"]
		sim.econ.bought_eggs = int(ed.get("bought_eggs", 0))
		sim.econ.auto_mode = int(ed["auto_mode"]) as IncrementalEconomy.Auto
		sim.econ.food_earned = float(ed["food_earned"])
		sim.econ.known_plants = PackedByteArray(ed["known_plants"])

	var wd: Dictionary = d["world"]
	sim.world.cells = PackedByteArray(wd["cells"])
	sim.world.room = PackedByteArray(wd["room"])
	sim.world.job_claim = PackedInt32Array(wd["job_claim"])
	sim.world.job_progress = PackedFloat32Array(wd["job_progress"])
	sim.world.marked_count = int(wd["marked_count"])
	sim.world.jobs_version = int(wd["jobs_version"])
	sim.world.passable_version = int(wd["passable_version"])
	sim.world.rooms_version = int(wd["rooms_version"])
	sim.world.nest_cells.clear()
	for c in wd["nest_cells"]:
		sim.world.nest_cells.append(int(c))
	sim.world.changed.clear()

	for name in ["food", "home", "danger", "attack", "evacuate"]:
		var field: PheromoneField = sim.get(name)
		field.data = PackedFloat32Array(d[name])
		field.floor_v = PackedFloat32Array(d.get(name + "_floor", []))

	var wtd: Dictionary = d["water"]
	sim.water.level = PackedFloat32Array(wtd["level"])
	sim.water.raining = wtd["raining"]
	sim.water.max_level = float(wtd["max_level"])
	sim.water.volume = float(wtd["volume"])
	sim.water.wet.clear()
	for i in sim.water.level.size():
		if sim.water.level[i] > 0.0:
			sim.water.wet[i] = true

	var cd: Dictionary = d["colony"]
	sim.colony.food = float(cd["food"])
	sim.colony.water = float(cd["water"])
	sim.colony.food_cap = float(cd["food_cap"])
	sim.colony.water_cap = float(cd["water_cap"])
	sim.colony.food_trend = float(cd["food_trend"])
	sim.colony.water_trend = float(cd["water_trend"])
	sim.colony.egg_cooldown = float(cd["egg_cooldown"])
	sim.colony.starving = cd["starving"]
	sim.colony.thirsty = cd["thirsty"]
	sim.colony.target_pct = _str_keys_to_int(cd["target_pct"])

	var bd: Dictionary = d["brood"]
	sim.brood.stage = _to_typed_int(bd["stage"])
	sim.brood.timer = _to_typed_float(bd["timer"])
	sim.brood.caste = _to_typed_int(bd["caste"])
	sim.brood.alive = _to_typed_bool(bd["alive"])
	# `d.get(..., default)`: un guardado de antes de esta función no trae estas dos llaves (sin
	# versionado de compatibilidad todavía, ver README sección 9).
	sim.brood.pos = _to_v2_arr(bd.get("pos", []))
	if sim.brood.pos.size() != sim.brood.stage.size():
		sim.brood.pos.resize(sim.brood.stage.size())  # guardado viejo: posiciones en (0,0)
	var claimed_in: Array = bd.get("claimed", [])
	sim.brood.claimed = _to_typed_int(claimed_in) if claimed_in.size() == sim.brood.stage.size() else []
	if sim.brood.claimed.size() != sim.brood.stage.size():
		sim.brood.claimed.resize(sim.brood.stage.size())
		sim.brood.claimed.fill(-1)
	sim.brood.hatched = int(bd["hatched"])
	sim.brood.died = int(bd["died"])

	var sd: Dictionary = d["spider"]
	sim.spider.pos = _to_v2(sd["pos"])
	sim.spider.state = int(sd["state"])
	sim.spider.hp = float(sd["hp"])
	sim.spider.max_hp = float(sd["max_hp"])
	sim.spider.target_ant = int(sd["target_ant"])
	sim.spider.siege_t = float(sd["siege_t"])
	sim.spider.alive = sd["alive"]

	# Fase 5: ausente en guardados de antes de esta fase; el ciempiés queda "nunca apareció",
	# igual que si la partida nunca hubiera tenido esta amenaza (ver README sección 5/9).
	sim.centipedes_spawned = int(d.get("centipedes_spawned", 0))
	sim.centipede_next_s = float(d.get("centipede_next_s", 0.0))
	if d.has("centipede"):
		var ccd: Dictionary = d["centipede"]
		sim.centipede.pos = _to_v2(ccd["pos"])
		sim.centipede.state = int(ccd["state"])
		sim.centipede.hp = float(ccd["hp"])
		sim.centipede.max_hp = float(ccd["max_hp"])
		sim.centipede.target_ant = int(ccd["target_ant"])
		sim.centipede.alive = ccd["alive"]

	# Fase 7: ausente en guardados de antes de esta fase; igual patrón que el ciempiés arriba.
	sim.mantises_spawned = int(d.get("mantises_spawned", 0))
	sim.mantis_next_s = float(d.get("mantis_next_s", 0.0))
	if d.has("mantis"):
		var mnd: Dictionary = d["mantis"]
		sim.mantis.pos = _to_v2(mnd["pos"])
		sim.mantis.state = int(mnd["state"])
		sim.mantis.hp = float(mnd["hp"])
		sim.mantis.max_hp = float(mnd["max_hp"])
		sim.mantis.target_ant = int(mnd["target_ant"])
		sim.mantis.alive = mnd["alive"]

	# Fase 9: ausente en guardados de antes de esta fase; queda en "estación 0, sin batalla en
	# curso", igual que si la partida nunca hubiera tenido este sistema.
	sim.season_index = int(d.get("season_index", 0))
	# Fase 17: ausente en guardados viejos; el inicio del ciclo de 5 días en curso, que es lo que
	# esos guardados usaban (todas las estaciones duraban 5 días).
	var day := sim.day_number()
	sim.season_start_day = int(d.get("season_start_day", day - (day - 1) % 5))
	if d.has("rival_colony"):
		var rcd: Dictionary = d["rival_colony"]
		sim.rival_colony.battle_active = rcd.get("battle_active", false)
		sim.rival_colony.battle_won = rcd.get("battle_won", false)
		sim.rival_colony.queen.pos = _to_v2(rcd["queen_pos"])
		sim.rival_colony.queen.hp = float(rcd["queen_hp"])
		sim.rival_colony.queen.max_hp = float(rcd["queen_max_hp"])
		sim.rival_colony.queen.alive = rcd["queen_alive"]
		# Fase 17: ausente en guardados viejos; la formación arranca de nuevo (reunión).
		sim.rival_colony.marching = bool(rcd.get("marching", false))
		sim.rival_colony.rally_s = float(rcd.get("rally_s", 0.0))

	var ad: Dictionary = d["ants"]
	var ants := sim.ants
	ants.count = int(ad["count"])
	ants.alive_count = int(ad["alive_count"])
	ants.pos = _to_v2_arr(ad["pos"])
	ants.prev = _to_v2_arr(ad["prev"])
	ants.heading = _to_v2_arr(ad["heading"])
	ants.target = _to_v2_arr(ad["target"])
	ants.last_check = _to_v2_arr(ad["last_check"])
	ants.state = PackedInt32Array(ad["state"])
	ants.caste = PackedInt32Array(ad["caste"])
	ants.next_think = PackedInt32Array(ad["next_think"])
	ants.last_think = PackedInt32Array(ad["last_think"])
	ants.trip_steps = PackedInt32Array(ad["trip_steps"])
	ants.job = PackedInt32Array(ad["job"])
	ants.last_cell = PackedInt32Array(ad["last_cell"])
	ants.ignore_until = PackedInt32Array(ad["ignore_until"])
	ants.alive = PackedByteArray(ad["alive"])
	ants.carry = PackedByteArray(ad["carry"])
	var carry_kind_in: Array = ad.get("carry_kind", [])
	ants.carry_kind = PackedByteArray(carry_kind_in) if carry_kind_in.size() == ants.count else PackedByteArray()
	if ants.carry_kind.size() != ants.count:
		ants.carry_kind.resize(ants.count)  # 0 por defecto: hoja, igual que antes de que esto existiera
	var carry_egg_in: Array = ad.get("carry_egg", [])
	ants.carry_egg = PackedInt32Array(carry_egg_in) if carry_egg_in.size() == ants.count else PackedInt32Array()
	if ants.carry_egg.size() != ants.count:
		ants.carry_egg.resize(ants.count)
		ants.carry_egg.fill(-1)
	# Fase 14: ausente en guardados viejos; -1 = el soldado elige un punto nuevo al pensar.
	var patrol_in: Array = ad.get("patrol_x", [])
	ants.patrol_x = PackedInt32Array(patrol_in)
	if ants.patrol_x.size() != ants.count:
		ants.patrol_x.resize(ants.count)
		ants.patrol_x.fill(-1)
	ants.hp = PackedFloat32Array(ad["hp"])
	ants.timer = PackedFloat32Array(ad["timer"])
	ants.stuck_t = PackedFloat32Array(ad["stuck_t"])
	ants.check_acc = PackedFloat32Array(ad["check_acc"])
	ants.max_stuck_seen = float(ad["max_stuck_seen"])
	# Fase 9: ausente en guardados de antes de esta fase: todas quedan de bando 0 (jugador), igual
	# que si esta fase nunca hubiera existido (no había hormigas rivales que guardar).
	var faction_in: Array = ad.get("faction", [])
	ants.faction = PackedByteArray(faction_in) if faction_in.size() == ants.count else PackedByteArray()
	if ants.faction.size() != ants.count:
		ants.faction.resize(ants.count)  # 0 por defecto: bando jugador
	ants._members_dirty = true  # los bandos cambiaron por fuera de `_grow`: rehacer la lista

	sim.plants.clear()
	for pd in d["plants"]:
		var cell: Array = pd["cell"]
		var p := Plant.new(Vector2i(int(cell[0]), int(cell[1])), int(pd["max_leaves"]))
		p.leaves = int(pd["leaves"])
		p.regrow_acc = float(pd.get("regrow_acc", 0.0))
		p.kind = int(pd.get("kind", Plant.Kind.TREE)) as Plant.Kind
		p.hue = int(pd.get("hue", 0))
		for c in pd.get("pocket", []):
			p.pocket.append(Vector2i(int(c[0]), int(c[1])))
		sim.plants.append(p)

	sim.corpses.clear()
	for corpse_d in d.get("corpses", []):
		var c := Corpse.new(_to_v2(corpse_d["pos"]), float(corpse_d["food_value"]))
		c.age = float(corpse_d.get("age", 0.0))
		sim.corpses.append(c)

	# Los campos de distancia y las cámaras son derivados: se recalculan en vez de guardarse.
	sim.fields.recompute_terrain()
	sim.fields.recompute_dig()
	sim._terrain_seen = sim.world.passable_version
	sim._jobs_seen = sim.world.jobs_version
	sim._dig_dirty = false
	sim.rooms._seen_rooms_version = -1
	sim.rooms._seen_terrain_recomputes = -1
	sim.rooms.maybe_recompute()
	# Fase 24: la niebla también es derivada del terreno.
	if bool(d.get("fog", false)):
		sim.enable_fog()
	ants._recount()
	return sim


static func load_file(path: String, cfg: SimConfig) -> Simulation:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return from_dict(parsed, cfg)


# --- Conversiones (Vector2 <-> Array, Dictionary con llaves int <-> String) --------------------

static func _v2(v: Vector2) -> Array:
	return [v.x, v.y]


static func _to_v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


static func _v2_arr(arr: PackedVector2Array) -> Array:
	var out := []
	out.resize(arr.size())
	for i in arr.size():
		out[i] = [arr[i].x, arr[i].y]
	return out


static func _to_v2_arr(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(arr.size())
	for i in arr.size():
		var p: Array = arr[i]
		out[i] = Vector2(float(p[0]), float(p[1]))
	return out


static func _int_keys_to_str(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[str(k)] = d[k]
	return out


static func _str_keys_to_int(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[int(k)] = float(d[k])
	return out


static func _to_typed_int(a: Array) -> Array[int]:
	var out: Array[int] = []
	for v in a:
		out.append(int(v))
	return out


static func _to_typed_float(a: Array) -> Array[float]:
	var out: Array[float] = []
	for v in a:
		out.append(float(v))
	return out


static func _to_typed_bool(a: Array) -> Array[bool]:
	var out: Array[bool] = []
	for v in a:
		out.append(bool(v))
	return out
