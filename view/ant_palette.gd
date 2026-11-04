class_name AntPalette
extends RefCounted
## Fase 39: colores de las hormigas (por casta), de las rivales y de los huevos, elegidos por el
## jugador en Opciones («Colores»). Toda la vista los lee de acá en vez de constantes sueltas
## (`CasteDefs.COLORS`, el antiguo `AntRenderer.RIVAL_COLOR`), así que un cambio se ve en el
## mundo y en el HUD sin reiniciar. Es estado estático: hay una sola paleta para toda la app.
## Se guarda en `AppSettings.colors` (solo lo que difiere de lo original, como "#rrggbb").

## Todas las claves; las de casta, en el orden de `CasteDefs.Caste`.
const KEYS: Array[String] = ["queen", "worker", "nurse", "soldier", "drone", "rival", "egg"]
## Las que se eligen en Opciones, en ese orden. Sin "nurse": la Nodriza solo existe en el Modo
## infinito, que es una herramienta de desarrollo (no sale en las builds exportadas).
const SHOWN: Array[String] = ["queen", "worker", "soldier", "drone", "rival", "egg"]
const LABELS: Array[String] = ["Reina", "Obreras", "Soldados", "Zánganos", "Hormigas rivales", "Huevos"]
const RIVAL_DEFAULT := Color("c22a2a")
## El sprite del huevo ya trae su color: blanco = sin teñir.
const EGG_DEFAULT := Color.WHITE

static var _colors := {}


static func default_color(key: String) -> Color:
	var k := KEYS.find(key)
	if k >= 0 and k < CasteDefs.COLORS.size():
		return CasteDefs.COLORS[k]
	return RIVAL_DEFAULT if key == "rival" else EGG_DEFAULT


static func get_color(key: String) -> Color:
	return _colors.get(key, default_color(key))


static func caste(c: int) -> Color:
	return get_color(KEYS[c])


static func rival() -> Color:
	return get_color("rival")


static func egg() -> Color:
	return get_color("egg")


static func set_color(key: String, c: Color) -> void:
	if key in KEYS:
		_colors[key] = c


## Vuelve a los colores originales.
static func reset() -> void:
	_colors.clear()


## Carga lo guardado (`{clave: "#rrggbb"}`). Claves desconocidas o colores inválidos se ignoran.
static func apply(saved: Dictionary) -> void:
	_colors.clear()
	for key in saved:
		var html := str(saved[key])
		if key in KEYS and Color.html_is_valid(html):
			_colors[key] = Color.html(html)


## Lo que difiere de lo original, listo para guardar.
static func to_dict() -> Dictionary:
	var out := {}
	for key in _colors:
		if not (_colors[key] as Color).is_equal_approx(default_color(key)):
			out[key] = "#" + (_colors[key] as Color).to_html(false)
	return out
