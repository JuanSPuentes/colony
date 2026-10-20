class_name TutorialView
extends CanvasLayer
## Fase 5: pasos contextuales para una persona que nunca vio el juego, en la colonia con reina
## (prompt_fase3_godot.md sección 4.3). No aplica al modo incremental (otra economía, sin araña de
## por medio). Cada paso se cumple solo con lo que el jugador ya hizo, sin botón "siguiente"; el
## jugador puede ignorar la burbuja mientras tanto. Tras el último paso no se muestra nada más.
## Jardín de hongos y Drenaje se quitaron del juego (ver README): la comida llega sola al entregar
## hojas, y el agua solo se maneja esperando a que evapore.

const STEPS: Array[String] = [
	"Pinta un rastro de Comida (tecla 2) hacia una planta",
	"Espera a que una obrera cargada de hojas llegue al nido",
	"Cava (tecla 1) para ampliar el nido",
	"Una araña ronda la superficie: pon soldados de guardia junto a la entrada",
]

var step := 0
var _label: Label


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.08, 0.92)
	style.border_color = Color("ffd43c")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.position = Vector2(-220, -34)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	_label = Label.new()
	_label.custom_minimum_size = Vector2(440, 0)
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color("f4ecd8"))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	panel.add_child(_label)
	panel.visible = false
	_panel = panel


var _panel: PanelContainer


## Llamado una vez por frame desde `main.gd._process`, igual que `Hud.update_info`.
func update(sim: Simulation) -> void:
	if sim.incremental or step >= STEPS.size():
		_panel.visible = false
		return
	var done := false
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
	_panel.visible = step < STEPS.size()
	if _panel.visible:
		_label.text = STEPS[step]
