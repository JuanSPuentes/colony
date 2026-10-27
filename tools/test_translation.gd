extends SceneTree
## Pruebas de la Fase 27: traducción. Revisa que todo `tr("...")` del código tenga su fila en
## `translations/strings.csv` y que, con el juego en inglés, las pantallas ya pasadas a la tabla no
## muestren ningún texto sin traducir. Las pantallas que todavía no se pasaron no se revisan acá
## (se agregan a `SCREENS` a medida que se traducen).
## Uso: godot --headless --path . --script tools/test_translation.gd      (código de salida 1 si algo falla)

const CSV := "res://translations/strings.csv"
const SCREENS := ["res://app/main_menu.gd", "res://app/options_screen.gd", "res://app/guide_screen.gd"]
## Textos que se muestran tal cual en cualquier idioma.
const SAME_IN_ALL := ["Colony: Under the Earth", "Español", "English", "•"]

var _pass := 0
var _fail := 0
var _keys := {}


func _initialize() -> void:
	_load_keys()
	_t_tr_calls_have_rows()
	_t_screens_in_english()
	_t_lessons_have_rows()
	await _t_hud_in_english("incremental")
	await _t_hud_in_english("test")
	_t_notes()
	_t_language_setting()
	TranslationServer.set_locale("es")
	print("RESULTADO: %d correctas, %d fallidas" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("[%s] %s %s" % ["OK " if ok else "FALLA", label, detail])


func _load_keys() -> void:
	var f := FileAccess.open(CSV, FileAccess.READ)
	f.get_csv_line()  # encabezado
	var dupes: Array[String] = []
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 2 or row[0] == "":
			continue
		if _keys.has(row[0]):
			dupes.append(row[0])
		_keys[row[0]] = row[1]
	_check("el CSV no repite claves", dupes.is_empty(), str(dupes))
	var empty: Array[String] = []
	for k in _keys:
		if str(_keys[k]).strip_edges() == "":
			empty.append(k)
	_check("toda fila tiene su inglés", empty.is_empty(), str(empty))


func _t_tr_calls_have_rows() -> void:
	# tr("..."), avisos (notify("...")) y motivos de fin de partida: todos se muestran traducidos.
	var re := RegEx.create_from_string("(?:\\btr\\(|\\bnotify\\(|game_over_reason = )\"((?:[^\"\\\\]|\\\\.)*)\"")
	var missing: Array[String] = []
	for path in _scripts("res://"):
		var text := FileAccess.get_file_as_string(path)
		for m in re.search_all(text):
			var key := m.get_string(1).c_unescape()
			if not _keys.has(key):
				missing.append("%s: %s" % [path.get_file(), key])
	_check("todo tr/notify/motivo del código está en el CSV", missing.is_empty(), "\n  " + "\n  ".join(missing))


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with(".") and d != "tools" and d != "addons":
			out.append_array(_scripts(dir.path_join(d)))
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	return out


func _t_screens_in_english() -> void:
	TranslationServer.set_locale("en")
	for path in SCREENS:
		var screen: Node = load(path).new()
		root.add_child(screen)
		var untranslated: Array[String] = []
		_collect_untranslated(screen, untranslated)
		_check("%s en inglés sin textos sueltos" % path.get_file(), untranslated.is_empty(), "\n  " + "\n  ".join(untranslated))
		screen.free()


func _collect_untranslated(node: Node, out: Array[String]) -> void:
	var text := ""
	if node is Label or node is Button:
		text = node.text
	if text != "" and node.can_auto_translate() and not _ok_in_english(text):
		out.append(text)
	for child in node.get_children():
		_collect_untranslated(child, out)


## Un texto se ve bien en inglés si tiene fila en el CSV, es igual en todo idioma o no tiene letras
## (números, porcentajes, flechas).
func _ok_in_english(text: String) -> bool:
	if _keys.has(text) or text in SAME_IN_ALL:
		return true
	return RegEx.create_from_string("[A-Za-zÁÉÍÓÚáéíóúñÑ]").search(text) == null


## Palabras que solo aparecen en un texto si quedó en español (los textos del HUD se arman con
## `tr()` y formato, así que no se pueden buscar por clave como los botones fijos).
const SPANISH_WORDS := ["de", "la", "el", "en", "y", "las", "los", "del", "por", "sin", "con", "hormigas",
	"comida", "reina", "obreras", "soldados", "día", "noche", "lluvia", "pausa", "velocidad", "vida"]


## Juega unos cuadros con el HUD en inglés y busca textos (también BBCode) que sigan en español.
func _t_hud_in_english(mode: String) -> void:
	TranslationServer.set_locale("en")
	var m: Node = load("res://main.tscn").instantiate()
	m.auto_start = false
	m.fresh_layout_enabled = mode == "incremental"
	m.coach_enabled = mode == "incremental"  # que también se vea la guía en partida
	root.add_child(m)
	await process_frame
	m.start(5, null, mode)
	for k in 5:
		await process_frame
	var found: Array[String] = []
	_collect_spanish(m, found)  # HUD, guía en partida y pistas
	_check("partida (%s) en inglés sin español" % mode, found.is_empty(), "\n  " + "\n  ".join(found))
	m.free()


func _collect_spanish(node: Node, out: Array[String]) -> void:
	var text := ""
	if node is Label or node is Button:
		text = TranslationServer.translate(node.text) if node.can_auto_translate() else node.text
	elif node is RichTextLabel:
		text = node.get_parsed_text()
	if text != "" and node is CanvasItem and node.is_visible_in_tree():
		var words := text.to_lower().replace("\n", " ").split(" ", false)
		for w in words:
			if w.strip_edges().trim_suffix(":").trim_suffix(",") in SPANISH_WORDS or RegEx.create_from_string("[áéíóúñ¿¡]").search(w) != null:
				out.append(text.replace("\n", " / "))
				break
	for child in node.get_children():
		_collect_spanish(child, out)


func _t_language_setting() -> void:
	var s := AppSettings.new()
	s.language = "en"
	s.apply_language()
	_check("aplicar el idioma cambia la traducción", TranslationServer.translate("Opciones") == "Options")
	s.language = "es"
	s.apply_language()
	_check("en español queda el texto original", TranslationServer.translate("Opciones") == "Opciones")


## Un aviso con datos se traduce entero, también el nombre de la estación que lleva adentro.
func _t_notes() -> void:
	TranslationServer.set_locale("en")
	var sim := Simulation.new(SimConfig.new(), 1)
	sim.notify("¡La colonia rival de %s ataca!", ["Verano"])
	var hud := Hud.new()
	var text := hud.note_text(sim.notifications[-1])
	_check("un aviso con datos sale traducido", text == "The Summer rival colony attacks!", text)
	_check("un aviso viejo (sin datos) también", hud.note_text("La reina murió.") == "The queen died.")
	hud.free()


## La guía en partida (`CoachView`) y las pistas del Nivel 0 (`TutorialView`) guardan sus textos en
## diccionarios y listas: los busca en el código (título, texto, objetivo, botón y cada pista).
func _t_lessons_have_rows() -> void:
	var missing: Array[String] = []
	var coach := FileAccess.get_file_as_string("res://view/coach_view.gd")
	var re := RegEx.create_from_string("\"(?:title|text|goal|button)\":\\s*\"((?:[^\"\\\\]|\\\\.)*)\"")
	for m in re.search_all(coach):
		missing.append(m.get_string(1).c_unescape())
	var pheromones := RegEx.create_from_string("PHEROMONES_TEXT := \"((?:[^\"\\\\]|\\\\.)*)\"").search(coach)
	missing.append(pheromones.get_string(1).c_unescape())
	var steps := RegEx.create_from_string("(?m)^\\s*\"([^\"]+)\",?\\s*$")
	for m in steps.search_all(FileAccess.get_file_as_string("res://view/tutorial_view.gd")):
		missing.append(m.get_string(1))
	var total := missing.size()
	missing = missing.filter(func(k: String) -> bool: return not _keys.has(k))
	_check("las %d lecciones y pistas están en el CSV" % total, missing.is_empty(), "\n  " + "\n  ".join(missing))
