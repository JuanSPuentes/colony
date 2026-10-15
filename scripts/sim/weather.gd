class_name Weather
extends RefCounted
## Scheduled rain storms. `rain` is the current intensity (0..1) and eases in and out.

## Each storm: start (seconds), duration, peak intensity.
var storms: Array[Dictionary] = []
var rain := 0.0
var _target := 0.0
var _warned := {}
var puddle := 0.0  # standing water on the surface near the entrance


func _init() -> void:
	var d := Cfg.DAY_LENGTH
	storms = [
		{"start": 1.45 * d, "dur": 32.0, "power": 0.45},
		{"start": 4.2 * d, "dur": 46.0, "power": 0.75},
		{"start": 6.8 * d, "dur": 58.0, "power": 1.0},
		{"start": 8.9 * d, "dur": 50.0, "power": 0.9},
	]


## Returns an announcement string when a warning/start/stop event just happened.
func step(dt: float, t: float) -> String:
	var msg := ""
	_target = 0.0
	for i in storms.size():
		var s: Dictionary = storms[i]
		if t >= s["start"] and t <= s["start"] + s["dur"]:
			_target = s["power"]
		var key_w := "w%d" % i
		if not _warned.has(key_w) and t >= s["start"] - 15.0 and t < s["start"]:
			_warned[key_w] = true
			msg = "Dark clouds gather - rain in 15 s. Check your drainage and escape routes."
		var key_s := "s%d" % i
		if not _warned.has(key_s) and t >= s["start"]:
			_warned[key_s] = true
			msg = "Rain begins!"
		var key_e := "e%d" % i
		if not _warned.has(key_e) and t >= s["start"] + s["dur"]:
			_warned[key_e] = true
			msg = "The rain is easing. Water will drain slowly."
	rain = move_toward(rain, _target, dt * 0.12)
	if rain > 0.2:
		puddle = minf(14.0, puddle + rain * 0.8 * dt)
	return msg


func next_storm(t: float) -> Dictionary:
	for s in storms:
		if t < s["start"] + s["dur"]:
			return s
	return {}
