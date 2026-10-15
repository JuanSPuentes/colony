class_name SpeciesDefs
extends RefCounted
## Data-driven species and caste definitions. Adding another species later means
## adding another dictionary here (and pointing Simulation at it), not rewriting logic.
## speed is in cells per second; cost is the food invested to raise one adult.

const LEAFCUTTER := {
	"name": "Leafcutter ant (Atta)",
	"castes": {
		Cfg.Caste.QUEEN: {
			"name": "Queen", "speed": 1.2, "hp": 160.0, "carry": 0.0, "damage": 0.0,
			"food_use": 0.05, "water_use": 0.02, "cost": 0.0,
		},
		Cfg.Caste.WORKER: {
			"name": "Worker", "speed": 2.6, "hp": 18.0, "carry": 2.0, "damage": 0.8,
			"food_use": 0.010, "water_use": 0.005, "cost": 5.0,
		},
		Cfg.Caste.NURSE: {
			"name": "Nurse", "speed": 2.0, "hp": 16.0, "carry": 0.0, "damage": 0.3,
			"food_use": 0.012, "water_use": 0.006, "cost": 6.0,
		},
		Cfg.Caste.SOLDIER: {
			"name": "Soldier", "speed": 2.4, "hp": 48.0, "carry": 0.0, "damage": 3.2,
			"food_use": 0.016, "water_use": 0.007, "cost": 10.0,
		},
	},
	# Brood stage durations in seconds at normal care.
	"stage_time": {Cfg.Stage.EGG: 18.0, Cfg.Stage.LARVA: 40.0, Cfg.Stage.PUPA: 26.0},
	"larva_food_use": 0.03,
	"egg_interval": 15.0,
	"egg_cost": 2.0,
}

static func caste(species: Dictionary, caste_id: int) -> Dictionary:
	return species["castes"][caste_id]
