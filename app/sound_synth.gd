class_name SoundSynth
extends RefCounted
## Fase 45: efectos de sonido generados con código, al estilo de jsfxr: sin archivos de audio ni
## licencias. Cada sonido es una receta (`spec`) que se convierte una sola vez en `AudioStreamWAV`.
##
## Receta (todas las claves opcionales salvo `wave`):
##   wave    "square", "saw", "sine", "triangle" o "noise"
##   f0, f1  frecuencia al empezar y al terminar (Hz): el tono se desliza de una a la otra
##   dur     duración en segundos
##   attack  segundos hasta el volumen máximo; después baja hasta 0 al final
##   vol     volumen (0..1)
##   notes   en vez de un deslizamiento, una secuencia de frecuencias de igual duración (arpegio)

const RATE := 22050


static func make(spec: Dictionary) -> AudioStreamWAV:
	var dur: float = spec.get("dur", 0.15)
	var n := int(dur * RATE)
	var wave: String = spec["wave"]
	var f0: float = spec.get("f0", 440.0)
	var f1: float = spec.get("f1", f0)
	var notes: Array = spec.get("notes", [])
	var attack: float = maxf(spec.get("attack", 0.005), 0.001)
	var vol: float = spec.get("vol", 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(spec)  # el mismo sonido siempre igual
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	var noise := 0.0
	for k in n:
		var t := float(k) / RATE
		var u := float(k) / n
		var f := f0 + (f1 - f0) * u
		if not notes.is_empty():
			f = notes[mini(int(u * notes.size()), notes.size() - 1)]
		var prev_phase := phase
		phase = fmod(phase + f / RATE, 1.0)
		var s := 0.0
		match wave:
			"square":
				s = 1.0 if phase < 0.5 else -1.0
			"saw":
				s = phase * 2.0 - 1.0
			"sine":
				s = sin(phase * TAU)
			"triangle":
				s = 1.0 - 4.0 * absf(phase - 0.5)
			"noise":
				if phase < prev_phase:  # un valor nuevo por ciclo: el tono controla lo "grave" del ruido
					noise = rng.randf_range(-1.0, 1.0)
				s = noise
		var env := minf(t / attack, 1.0) * (1.0 - u) * (1.0 - u)
		data.encode_s16(k * 2, int(clampf(s * env * vol, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream
