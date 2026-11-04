extends SceneTree
## Pruebas de la Fase 39: colores de las hormigas elegidos en Opciones (`AntPalette`).
## Que el mundo y el HUD usen la paleta se verificó con capturas: sin pantalla (headless) Godot no
## guarda los colores de instancia de los `MultiMesh`, así que no se puede medir desde acá.
## Uso: godot --headless --path . --script tools/test_phase39.gd      (código de salida 1 si algo falla)

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_t_defaults()
	_t_change_and_reset()
	_t_save_format()
	AntPalette.reset()
	print("RESULTADO: %d correctas, %d fallidas" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("[%s] %s %s" % ["OK " if ok else "FALLA", label, detail])


func _t_defaults() -> void:
	AntPalette.reset()
	var same := true
	for c in CasteDefs.COLORS.size():
		same = same and AntPalette.caste(c) == CasteDefs.COLORS[c]
	_check("sin cambios, cada casta tiene su color original", same)
	_check("una clave desconocida no toma el color de otra", AntPalette.get_color("nada") == AntPalette.EGG_DEFAULT)
	_check("la rival es roja y el huevo sin teñir", AntPalette.rival() == AntPalette.RIVAL_DEFAULT and AntPalette.egg() == Color.WHITE)
	_check("una clave por casta, más rival y huevos", AntPalette.KEYS.size() == CasteDefs.COLORS.size() + 2)
	_check("Opciones no muestra las nodrizas (solo existen en el Modo infinito)", not "nurse" in AntPalette.SHOWN and AntPalette.SHOWN.size() == AntPalette.LABELS.size())


func _t_change_and_reset() -> void:
	AntPalette.reset()
	AntPalette.set_color("soldier", Color("3498db"))
	AntPalette.set_color("rival", Color("00ff00"))
	_check("cambiar el color de una casta", AntPalette.caste(CasteDefs.Caste.SOLDIER) == Color("3498db"))
	_check("y no toca las demás", AntPalette.caste(CasteDefs.Caste.WORKER) == CasteDefs.COLORS[CasteDefs.Caste.WORKER])
	_check("cambiar el de las rivales", AntPalette.rival() == Color("00ff00"))
	AntPalette.reset()
	_check("Restablecer vuelve a los originales", AntPalette.caste(CasteDefs.Caste.SOLDIER) == CasteDefs.COLORS[CasteDefs.Caste.SOLDIER] and AntPalette.rival() == AntPalette.RIVAL_DEFAULT)


func _t_save_format() -> void:
	AntPalette.reset()
	AntPalette.set_color("egg", Color("ffd43c"))
	AntPalette.set_color("queen", CasteDefs.COLORS[CasteDefs.Caste.QUEEN])  # igual al original
	var d := AntPalette.to_dict()
	_check("se guarda solo lo que difiere del original", d.size() == 1 and d.get("egg", "") == "#ffd43c", str(d))
	AntPalette.apply({"worker": "#123456", "nada": "#ffffff", "soldier": "no-es-un-color"})
	_check("al cargar, aplica lo válido e ignora lo desconocido o inválido",
		AntPalette.caste(CasteDefs.Caste.WORKER) == Color("123456") and AntPalette.caste(CasteDefs.Caste.SOLDIER) == CasteDefs.COLORS[CasteDefs.Caste.SOLDIER]
		and AntPalette.egg() == Color.WHITE)
	var s := AppSettings.new()
	s.colors = {"drone": "#abcdef"}
	var parsed = JSON.parse_string(JSON.stringify({"colors": s.colors}))
	_check("las preferencias guardan los colores como JSON", parsed["colors"]["drone"] == "#abcdef")

