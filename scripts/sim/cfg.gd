class_name Cfg
extends RefCounted
## Global constants and enums shared by the simulation, the view and the UI.
## Grid: x grows right, y grows DOWN. Rows < SURFACE are sky; SURFACE is the first soil row.

const CELL := 16
const W := 81
const H := 52
const SURFACE := 14
const SURFACE_ROW := SURFACE - 1  # the row ants walk on above ground
const ENTRANCE_X := 40
const TICK := 1.0 / 30.0
const DAY_LENGTH := 90.0
const WIN_DAYS := 10

enum Cell { AIR, SOIL, ROCK, TUNNEL }
enum Room { NONE, ROYAL, NURSERY, STORAGE, DRAIN }
enum Caste { QUEEN, WORKER, NURSE, SOLDIER }
enum Phero { FOOD, HOME, DANGER, ATTACK, EVACUATE }
enum Load { NONE, FOOD, WATER }
enum Stage { EGG, LARVA, PUPA }
enum SrcKind { FOOD, WATER }
enum State {
	IDLE, EXPLORE, FOLLOW_TRAIL, TO_RESOURCE, COLLECT, CARRY_HOME, TO_DIG, DIGGING,
	NURSING, MOVE_BROOD, GUARD, ATTACK, FLEE, REST, DEAD,
}

const STATE_NAMES := {
	State.IDLE: "idle", State.EXPLORE: "exploring", State.FOLLOW_TRAIL: "following trail",
	State.TO_RESOURCE: "heading to resource", State.COLLECT: "collecting",
	State.CARRY_HOME: "carrying home", State.TO_DIG: "going to dig", State.DIGGING: "digging",
	State.NURSING: "nursing brood", State.MOVE_BROOD: "moving brood", State.GUARD: "guarding",
	State.ATTACK: "attacking", State.FLEE: "fleeing to safety", State.REST: "resting",
	State.DEAD: "dead",
}

const PHERO_NAMES := ["Food", "Home", "Danger", "Attack", "Evacuate"]
const ROOM_NAMES := ["Tunnel", "Royal chamber", "Nursery", "Food storage", "Drainage"]
const CASTE_NAMES := ["Queen", "Worker", "Nurse", "Soldier"]


static func cell_center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CELL, (c.y + 0.5) * CELL)


static func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


static func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H
