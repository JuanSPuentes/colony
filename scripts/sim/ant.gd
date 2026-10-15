class_name Ant
extends RefCounted
## One autonomous ant: caste, state machine state, position, needs and load.
## All behaviour lives in AntBrain; this class is just data.

var id := 0
var caste := Cfg.Caste.WORKER
var state := Cfg.State.IDLE
var pos := Vector2.ZERO
var prev_pos := Vector2.ZERO
var cell := Vector2i.ZERO
var facing := 1
var move_dir := Vector2.RIGHT
var hp := 18.0
var max_hp := 18.0
var speed := 2.6
var damage := 0.8
var carry_capacity := 2.0
## Individual resistance to hunger/thirst: weak ants die first instead of all at once.
var hardiness := 1.0

var path: Array[Vector2i] = []
var path_i := 0

var load_type := Cfg.Load.NONE
var load_amount := 0.0
var timer := 0.0
var think_cd := 0.0
var want := Cfg.Load.FOOD
var heading := 1
var target_src: FoodSource = null
var mem_food: FoodSource = null
var known_water := false
var job_cell := Vector2i(-1, -1)
var brood_target: Brood = null
var carrying_brood: Brood = null
var lost_until := 0.0
var dist_since := 0
var ignore_trail_until := 0.0
var flee_reason := ""
var attack_cd := 0.0
var repath_cd := 0.0
var anim := 0.0
var moving := false
var damage_flash := 0.0
var danger_seen_t := -100.0


func set_path(p: Array[Vector2i]) -> void:
	path = p
	path_i = 1 if p.size() > 1 else p.size()


func clear_path() -> void:
	path = []
	path_i = 0


func has_path() -> bool:
	return path_i < path.size()


func caste_name() -> String:
	return Cfg.CASTE_NAMES[caste]
