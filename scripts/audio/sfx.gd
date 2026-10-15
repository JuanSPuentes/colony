class_name Sfx
extends Node
## Tiny synthesized sound effects (no audio files). Everything is generated at start-up
## as 16-bit mono AudioStreamWAV data, so there is nothing to download or license.

const RATE := 22050

var enabled := true
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _rain: AudioStreamPlayer


func _ready() -> void:
	_streams["click"] = _tone(900.0, 650.0, 0.05, 0.35, 0.0)
	_streams["deny"] = _tone(190.0, 140.0, 0.14, 0.4, 0.15)
	_streams["dig"] = _tone(220.0, 90.0, 0.09, 0.5, 0.75)
	_streams["deliver"] = _tone(660.0, 990.0, 0.09, 0.3, 0.0)
	_streams["alert"] = _tone(520.0, 380.0, 0.35, 0.45, 0.0)
	_streams["hit"] = _tone(160.0, 70.0, 0.1, 0.5, 0.55)
	_streams["birth"] = _tone(500.0, 1100.0, 0.18, 0.3, 0.0)
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.volume_db = -10.0
		add_child(p)
		_players.append(p)
	_rain = AudioStreamPlayer.new()
	_rain.stream = _noise_loop()
	_rain.volume_db = -80.0
	add_child(_rain)
	_rain.play()


func play(sound: String, volume_db: float = -10.0) -> void:
	if not enabled or not _streams.has(sound):
		return
	for p in _players:
		if not p.playing:
			p.stream = _streams[sound]
			p.volume_db = volume_db
			p.play()
			return


func set_rain(intensity: float) -> void:
	_rain.volume_db = -80.0 if intensity < 0.03 or not enabled else linear_to_db(clampf(intensity, 0.0, 1.0) * 0.22)


func _wav(samples: PackedFloat32Array, looped: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if looped:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _tone(f0: float, f1: float, dur: float, vol: float, noise: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f0 * 7.0)
	var lp := 0.0
	for i in n:
		var k := float(i) / n
		phase += TAU * lerpf(f0, f1, k) / RATE
		lp = lerpf(lp, rng.randf() * 2.0 - 1.0, 0.35)
		var s := sin(phase) * (1.0 - noise) + lp * noise
		var env := pow(1.0 - k, 1.6) * minf(1.0, float(i) / 40.0)
		out[i] = s * env * vol
	return _wav(out, false)


func _noise_loop() -> AudioStreamWAV:
	var n := RATE * 2
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var lp := 0.0
	for i in n:
		lp = lerpf(lp, rng.randf() * 2.0 - 1.0, 0.5)
		out[i] = lp * 0.8
	# Cross-fade the seam so the loop does not click.
	var fade := 600
	for i in fade:
		var k := float(i) / fade
		out[i] = lerpf(out[n - fade + i], out[i], k)
	return _wav(out, true)
