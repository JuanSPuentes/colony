class_name TutorialView
extends CanvasLayer
## Fase 5: pasos contextuales para una persona que nunca vio el juego, en la colonia con reina
## ("Modo infinito", `prompt_fase3_godot.md` sección 4.3). Fase 10: mismo mecanismo, pasos propios
## para "Juego normal" (modo incremental) — es el modo que arranca primero en el menú desde la
## Fase 9 y hasta ahora no tenía ninguna guía, a pesar de ser bastante más que "cavar y pintar
## comida" (comprar huevos, mejoras, las estaciones). No se muestra en el modo Test (`test_mode`):
## ese modo ya tiene su propio panel de controles (`Hud._build_test_panel`), una burbuja de
## tutorial ahí solo estorbaría.
## Cada paso se cumple solo con lo que el jugador ya hizo, sin botón "siguiente"; el jugador puede
## ignorar la burbuja mientras tanto. Tras el último paso de la lista que le toque, no se muestra
## nada más. Jardín de hongos y Drenaje se quitaron del juego (ver README): la comida llega sola
## al entregar hojas, y el agua solo se maneja esperando a que evapore.

const STEPS: Array[String] = [
	"Pinta un rastro de Comida (tecla 2) hacia una planta",
	"Espera a que una obrera cargada de hojas llegue al nido",
	"Cava (tecla 1) para ampliar el nido",
	"Una araña ronda la superficie: pon soldados de guardia junto a la entrada",
]

## "Juego normal" (modo incremental): cavar, conseguir comida, comprar cría y mejoras. Sin reparto
## de castas manual (la cría comprada sale obrera o soldado al azar, ver `cmd_buy_egg`) ni araña
## con asedio directo (las amenazas llegan solas con la era, y la verdadera prueba es la colonia
## rival de fin de estación — avisada aparte por `SeasonSystem.notify`, no hace falta un paso más
## acá para no competir con esa alerta).
const STEPS_INCREMENTAL: Array[String] = [
	"Cava (tecla 1) para ampliar el nido",
	"Pinta un rastro de Comida (tecla 2) hacia una planta",
	"Compra un huevo con comida (botón [7] del panel)",
	"Compra una mejora de colonia con comida (sección Mejoras del panel)",
]

var step := 0
var _label: Label


func _ready() -> void:
	var style := PixelUI.frame(4)  # Fase 28: marco de madera como el HUD

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.position = Vector2(-220, -34)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	_label = Label.new()
	_label.custom_minimum_size = Vector2(440, 0)
	_label.add_theme_font_override("font", PixelUI.font())
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color("f4ecd8"))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	panel.add_child(_label)
	panel.visible = false
	_panel = panel


var _panel: PanelContainer


## Llamado una vez por frame desde `main.gd._process`, igual que `Hud.update_info`.
func update(sim: Simulation) -> void:
	if sim.test_mode:
		_panel.visible = false
		return
	var steps := STEPS_INCREMENTAL if sim.incremental else STEPS
	if step >= steps.size():
		_panel.visible = false
		return
	var done := false
	if sim.incremental:
		match step:
			0:
				done = sim.dug > 0
			1:
				done = sim.food_painted
			2:
				done = sim.eggs_bought > 0
			3:
				done = sim.upgrades_bought > 0
	else:
		match step:
			0:
				done = sim.food_painted
			1:
				done = sim.delivered > 0
			2:
				done = sim.dug > 0
			3:
				done = sim.spiders_spawned > 0
	if done:
		step += 1
	_panel.visible = step < steps.size()
	if _panel.visible:
		_label.text = steps[step]
