extends Node
## Entry point: creates the simulation, the world view, the HUD and sound, and handles restart.
## A fixed seed can be passed on the command line:  godot --path . -- --seed=42

var seed_value := 20240601
var sim: Simulation
var view: WorldView
var hud: Hud
var sfx: Sfx


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.substr(7))
	sfx = Sfx.new()
	add_child(sfx)
	# The world lives inside a clipping Control so zooming never paints over the HUD.
	var clip := Control.new()
	clip.position = Vector2(0, Hud.TOP_H)
	clip.size = Vector2(Hud.PANEL_X, 832)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clip)
	view = WorldView.new()
	view.sfx = sfx
	view.visible_rect = Rect2(clip.position, clip.size)
	clip.add_child(view)
	hud = Hud.new()
	add_child(hud)
	sim = Simulation.new(seed_value)
	view.start(sim)
	hud.setup(view, sfx)
	hud.restart_requested.connect(restart)


func restart() -> void:
	seed_value += 1
	sim = Simulation.new(seed_value)
	view.start(sim)
	view.paused = false
	view.speed = 1.0
	hud.bind_sim()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_R and k.ctrl_pressed:
		restart()
