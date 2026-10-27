class_name AppSettings
extends RefCounted
## Preferencias del jugador para la aplicación completa (volumen, brillo, idioma): no son parte de la
## simulación de una partida, así que viven en `app/`, no en `sim/` (ver ARCHITECTURE.md). Se
## guardan en `user://app_settings.json`, separado de `user://save1.json` (esa es la partida).

const PATH := "user://app_settings.json"
const VOLUME_MIN := 0.0
const VOLUME_MAX := 1.0
const BRIGHTNESS_MIN := 0.6
const BRIGHTNESS_MAX := 1.4
## Fase 27: idiomas del juego. Los textos se escriben en español en el código y son la clave de
## `translations/strings.csv`, que tiene la traducción al inglés (ver README, Fase 27).
const LANGUAGES: Array[String] = ["es", "en"]
const LANGUAGE_NAMES: Array[String] = ["Español", "English"]

var volume := 0.8
var brightness := 1.0
## Sin preferencia guardada: el idioma del sistema si es español, si no inglés.
var language := "es" if OS.get_locale_language() == "es" else "en"


static func load_settings() -> AppSettings:
	var s := AppSettings.new()
	if not FileAccess.file_exists(PATH):
		return s
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return s
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		s.volume = clampf(float(parsed.get("volume", s.volume)), VOLUME_MIN, VOLUME_MAX)
		s.brightness = clampf(float(parsed.get("brightness", s.brightness)), BRIGHTNESS_MIN, BRIGHTNESS_MAX)
		var lang := str(parsed.get("language", s.language))
		if lang in LANGUAGES:
			s.language = lang
	return s


func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"volume": volume, "brightness": brightness, "language": language}))
	f.close()


## Aplica el volumen al bus Master. No hay efectos de sonido todavía (ver README), pero el control
## queda listo para cuando los haya: en 0 silencia el bus entero.
func apply_volume() -> void:
	var idx := AudioServer.get_bus_index("Master")
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, volume <= 0.001)
	if volume > 0.001:
		AudioServer.set_bus_volume_db(idx, linear_to_db(volume))


## Fase 27: cambia el idioma de todo el juego. Los botones y etiquetas con texto fijo se traducen
## solos (Godot vuelve a traducir su `text`); lo que se arma con `tr()` se actualiza al redibujarse.
func apply_language() -> void:
	TranslationServer.set_locale(language)
