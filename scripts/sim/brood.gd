class_name Brood
extends RefCounted
## An egg, larva or pupa. Develops over time; the speed depends on care and the room.

var id := 0
var cell := Vector2i.ZERO
var stage := Cfg.Stage.EGG
var progress := 0.0  # 0..1 within the current stage
var caste := Cfg.Caste.WORKER
var care := 0.6  # 0..1, raised by nurses, decays when untended
var hp := 100.0
var tender: Ant = null
var mover: Ant = null  # nurse assigned to relocate it
var carrier: Ant = null
var starving := false


func stage_name() -> String:
	return ["Egg", "Larva", "Pupa"][stage]
