class_name Sfx
extends Node
## Fase 45: reproductor de efectos de sonido. Lo crea `app.gd` una sola vez (grupo `GROUP`); la
## partida lo busca con `Sfx.find()` y, si no está (pruebas, `main.tscn` abierto directo), no suena
## nada. Los sonidos salen de `SoundSynth`; cada vez que suena uno se varía un poco el tono para que
## repetido no canse, y `COOLDOWN` evita que 30 obreras cavando a la vez sean un solo ruido.

const GROUP := "sfx"
const BUS := "SFX"
const VOICES := 10
const PITCH_VARIATION := 0.08

const SOUNDS := {
	"dig": {"wave": "noise", "f0": 2400.0, "f1": 900.0, "dur": 0.07, "vol": 0.18},
	"deliver": {"wave": "triangle", "f0": 660.0, "f1": 990.0, "dur": 0.08, "vol": 0.25},
	"egg": {"wave": "sine", "notes": [523.0, 659.0, 784.0], "dur": 0.24, "vol": 0.35},
	"hatch": {"wave": "triangle", "f0": 880.0, "f1": 1320.0, "dur": 0.1, "vol": 0.22},
	"hit": {"wave": "noise", "f0": 1200.0, "f1": 300.0, "dur": 0.09, "vol": 0.3},
	"death": {"wave": "square", "f0": 420.0, "f1": 120.0, "dur": 0.18, "vol": 0.16},
	"enemy_death": {"wave": "square", "f0": 300.0, "f1": 600.0, "dur": 0.12, "vol": 0.14},
	"alarm": {"wave": "square", "notes": [880.0, 660.0, 880.0, 660.0], "dur": 0.36, "vol": 0.16},
	"raid": {"wave": "saw", "notes": [196.0, 185.0, 175.0, 165.0], "dur": 0.7, "vol": 0.22},
	"threat": {"wave": "saw", "f0": 110.0, "f1": 70.0, "dur": 0.6, "attack": 0.08, "vol": 0.3},
	"queen_kill": {"wave": "noise", "f0": 400.0, "f1": 60.0, "dur": 0.7, "vol": 0.5},
	"season": {"wave": "triangle", "notes": [523.0, 659.0, 784.0, 1047.0], "dur": 0.6, "vol": 0.35},
	"victory": {"wave": "square", "notes": [523.0, 659.0, 784.0, 1047.0, 784.0, 1047.0], "dur": 1.0, "vol": 0.22},
	"defeat": {"wave": "triangle", "notes": [392.0, 349.0, 311.0, 262.0], "dur": 1.2, "vol": 0.35},
	"click": {"wave": "square", "f0": 1000.0, "f1": 1300.0, "dur": 0.04, "vol": 0.1},
}
## Segundos mínimos entre dos veces el mismo sonido (los que no están: sin límite).
const COOLDOWN := {"dig": 0.12, "deliver": 0.15, "hit": 0.2, "death": 0.25, "enemy_death": 0.2,
	"alarm": 4.0, "hatch": 0.3}

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_played := {}
var _rng := RandomNumberGenerator.new()


static func find(tree: SceneTree) -> Sfx:
	return tree.get_first_node_in_group(GROUP) as Sfx if tree != null else null


static func ensure_bus() -> int:
	var idx := AudioServer.get_bus_index(BUS)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS)
		AudioServer.set_bus_send(idx, "Master")
	return idx


func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_bus()
	for key in SOUNDS:
		_streams[key] = SoundSynth.make(SOUNDS[key])
	for k in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		add_child(p)
		_players.append(p)
	# Un clic suave en todos los botones del juego, también los que se crean después.
	get_tree().node_added.connect(_on_node_added)


func play(key: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(key, -100.0)) < float(COOLDOWN.get(key, 0.0)):
		return
	_last_played[key] = now
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _streams[key]
	p.pitch_scale = 1.0 + _rng.randf_range(-PITCH_VARIATION, PITCH_VARIATION)
	p.play()


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		(node as BaseButton).pressed.connect(play.bind("click"))
