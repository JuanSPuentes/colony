class_name FoodSource
extends RefCounted
## A harvestable surface resource: a leafy plant (food) or a pond/puddle (water).

var id := 0
var kind := Cfg.SrcKind.FOOD
var cell := Vector2i.ZERO
var amount := 60.0
var max_amount := 60.0
var regrow := 0.08
var infinite := false
var discovered := false
var temporary := false


func available() -> bool:
	return infinite or amount > 0.25


func take(want: float) -> float:
	if infinite:
		return want
	var got := minf(want, amount)
	amount -= got
	return got


func step(dt: float) -> void:
	if not infinite and not temporary:
		amount = minf(max_amount, amount + regrow * dt)
