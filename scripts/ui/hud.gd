class_name Hud
extends CanvasLayer
## Strategy-game interface built in code: top status bar, right tool panel, hints, log,
## toast notifications and the victory/defeat screen. It only reads the simulation and
## issues the same commands the mouse tools use.

signal restart_requested

const PANEL_X := 1296.0
const TOP_H := 44.0

var view: WorldView
var sfx: Sfx

var _theme := Theme.new()
var _top_labels := {}
var _queen_bar: ProgressBar
var _info: RichTextLabel
var _tutorial: RichTextLabel
var _log: RichTextLabel
var _hint_bar: Label
var _toasts: VBoxContainer
var _over_panel: PanelContainer
var _over_title: Label
var _over_text: RichTextLabel
var _buttons := {}  # key -> Button
var _refresh := 0.0
var _tut_step := 0
var _tut_done_at := -1.0
var _tutorial_visible := true
var _tutorial_box: Control


func setup(v: WorldView, sound: Sfx) -> void:
	view = v
	sfx = sound
	_build_theme()
	_build()
	view.tool_changed.connect(_sync_buttons)
	view.selection_changed.connect(_refresh_info)
	bind_sim()


## Called on start and after every restart.
func bind_sim() -> void:
	_tut_step = 0
	_tut_done_at = -1.0
	_over_panel.visible = false
	for c in _toasts.get_children():
		c.queue_free()
	_log.clear()
	view.sim.notified.connect(_on_notified)
	for entry in view.sim.log:
		_on_notified(entry["text"], entry["kind"])
	_sync_buttons()
	_update(0.0, true)


func _build_theme() -> void:
	var text := Color("f1e4c8")
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("1d1510", 0.96)
	panel.border_color = Color("6b4a2a")
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(8)
	_theme.set_stylebox("panel", "PanelContainer", panel)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(4)
		sb.set_content_margin_all(4)
		sb.set_border_width_all(1)
		sb.border_color = Color("6b4a2a")
		match state:
			"normal":
				sb.bg_color = Color("3b2a1d")
			"hover":
				sb.bg_color = Color("55392a")
			"pressed":
				sb.bg_color = Color("a8601f")
				sb.border_color = Color("ffd27a")
			"disabled":
				sb.bg_color = Color("2a2018")
		_theme.set_stylebox(state, "Button", sb)
	_theme.set_color("font_color", "Button", text)
	_theme.set_color("font_hover_color", "Button", Color.WHITE)
	_theme.set_color("font_pressed_color", "Button", Color.WHITE)
	_theme.set_color("font_color", "Label", text)
	_theme.set_color("default_color", "RichTextLabel", text)
	_theme.set_font_size("font_size", "Button", 13)
	_theme.set_font_size("font_size", "Label", 14)
	_theme.set_font_size("normal_font_size", "RichTextLabel", 13)
	_theme.set_font_size("bold_font_size", "RichTextLabel", 13)


func _label(parent: Node, text := "", size := 14, color := Color("f1e4c8")) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


func _section(parent: Node, text: String) -> void:
	var l := _label(parent, text, 12, Color("d9a35a"))
	l.add_theme_constant_override("line_spacing", 0)


func _btn(parent: Node, key: String, text: String, cb: Callable, toggle := true, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 28)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.tooltip_text = tip
	b.pressed.connect(func() -> void:
		if sfx:
			sfx.play("click")
		cb.call())
	parent.add_child(b)
	_buttons[key] = b
	return b


func _grid(parent: Node, cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	parent.add_child(g)
	return g


func _build() -> void:
	var root := Control.new()
	root.theme = _theme
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Top bar.
	var top := PanelContainer.new()
	top.position = Vector2.ZERO
	top.size = Vector2(1680, TOP_H)
	root.add_child(top)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 22)
	top.add_child(hb)
	_top_labels["title"] = _label(hb, "COLONY", 15, Color("ffd27a"))
	for k in ["day", "food", "water", "pop"]:
		_top_labels[k] = _label(hb, "")
	var qbox := HBoxContainer.new()
	hb.add_child(qbox)
	_label(qbox, "Queen ", 14)
	_queen_bar = ProgressBar.new()
	_queen_bar.custom_minimum_size = Vector2(90, 16)
	_queen_bar.show_percentage = false
	_queen_bar.max_value = 100.0
	_queen_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var qbg := StyleBoxFlat.new()
	qbg.bg_color = Color("3a1a14")
	qbg.set_corner_radius_all(3)
	var qfill := StyleBoxFlat.new()
	qfill.bg_color = Color("e8b84a")
	qfill.set_corner_radius_all(3)
	_queen_bar.add_theme_stylebox_override("background", qbg)
	_queen_bar.add_theme_stylebox_override("fill", qfill)
	qbox.add_child(_queen_bar)
	for k in ["brood", "weather", "threat"]:
		_top_labels[k] = _label(hb, "")

	# Right panel.
	var side := PanelContainer.new()
	side.position = Vector2(PANEL_X, TOP_H)
	side.size = Vector2(1680.0 - PANEL_X, 900.0 - TOP_H - 24.0)
	root.add_child(side)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	side.add_child(vb)

	_section(vb, "TOOLS")
	var g1 := _grid(vb, 3)
	_btn(g1, "t_inspect", "Inspect [I]", func() -> void: view.set_tool(WorldView.Tool.INSPECT), true, "Click ants, brood, plants or cells to see their state")
	_btn(g1, "t_dig", "Dig [D]", func() -> void: view.set_tool(WorldView.Tool.DIG), true, "Drag from a tunnel into soil. Workers excavate it.")
	_btn(g1, "t_erase", "Erase [X]", func() -> void: view.set_tool(WorldView.Tool.ERASE), true, "Remove pheromones and dig orders (right-click works with any tool)")

	_section(vb, "ROOMS  (paint over tunnels)")
	var g2 := _grid(vb, 3)
	_btn(g2, "r_1", "Royal [1]", func() -> void: view.set_room_tool(Cfg.Room.ROYAL), true, "Safe home of the queen. She lays eggs here.")
	_btn(g2, "r_2", "Nursery [2]", func() -> void: view.set_room_tool(Cfg.Room.NURSERY), true, "Brood develops faster and nurses tend it here.")
	_btn(g2, "r_3", "Storage [3]", func() -> void: view.set_room_tool(Cfg.Room.STORAGE), true, "Each cell raises food and water capacity.")
	_btn(g2, "r_4", "Drain [4]", func() -> void: view.set_room_tool(Cfg.Room.DRAIN), true, "Soaks floodwater away. Build low in the nest.")
	_btn(g2, "r_0", "Tunnel [5]", func() -> void: view.set_room_tool(Cfg.Room.NONE), true, "Turn a room back into a plain tunnel")

	_section(vb, "PHEROMONES  (paint on ground or tunnels)")
	var g3 := _grid(vb, 3)
	var pkeys := ["Q", "W", "E", "R", "T"]
	for i in 5:
		var b := _btn(g3, "p_%d" % i, "%s [%s]" % [Cfg.PHERO_NAMES[i], pkeys[i]], func() -> void: view.set_phero_tool(i), true, WorldView.PHERO_HINTS[i])
		var col: Color = WorldView.PHERO_COLORS[i]
		var sb := b.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
		sb.border_color = col
		sb.set_border_width_all(2)
		b.add_theme_stylebox_override("normal", sb)

	_section(vb, "NEXT EGGS BECOME  (worker 5 food, nurse 6, soldier 10)")
	var g4 := _grid(vb, 3)
	_btn(g4, "c_1", "Worker [7]", func() -> void: _set_caste(Cfg.Caste.WORKER), true, "Forage, carry and dig")
	_btn(g4, "c_2", "Nurse [8]", func() -> void: _set_caste(Cfg.Caste.NURSE), true, "Tend and move brood")
	_btn(g4, "c_3", "Soldier [9]", func() -> void: _set_caste(Cfg.Caste.SOLDIER), true, "Defend against spiders")

	_section(vb, "SIMULATION")
	var g5 := _grid(vb, 3)
	_btn(g5, "s_pause", "Pause [Space]", func() -> void:
		view.paused = not view.paused
		_sync_buttons(), true)
	_btn(g5, "s_1", "1x", func() -> void: _set_speed(1.0), true)
	_btn(g5, "s_2", "2x", func() -> void: _set_speed(2.0), true)
	_btn(g5, "s_4", "4x [Tab]", func() -> void: _set_speed(4.0), true)
	_btn(g5, "s_restart", "Restart", func() -> void: restart_requested.emit(), false)
	_btn(g5, "s_hints", "Hints on/off", func() -> void:
		_tutorial_visible = not _tutorial_visible
		_tutorial_box.visible = _tutorial_visible, false)

	_section(vb, "SELECTION")
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.custom_minimum_size = Vector2(0, 132)
	_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_info)

	var tbox := VBoxContainer.new()
	vb.add_child(tbox)
	_tutorial_box = tbox
	_section(tbox, "HINT")
	_tutorial = RichTextLabel.new()
	_tutorial.bbcode_enabled = true
	_tutorial.custom_minimum_size = Vector2(0, 92)
	tbox.add_child(_tutorial)

	_section(vb, "EVENTS")
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.custom_minimum_size = Vector2(0, 140)
	_log.scroll_following = true
	vb.add_child(_log)

	# Bottom hint bar.
	_hint_bar = _label(root, "", 14, Color("e8d8b0"))
	_hint_bar.position = Vector2(8, 878)
	_hint_bar.size = Vector2(1280, 22)

	# Toasts over the world.
	_toasts = VBoxContainer.new()
	_toasts.position = Vector2(340, TOP_H + 10)
	_toasts.size = Vector2(620, 200)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toasts)

	# Victory / defeat screen.
	_over_panel = PanelContainer.new()
	_over_panel.position = Vector2(400, 270)
	_over_panel.size = Vector2(500, 300)
	_over_panel.visible = false
	root.add_child(_over_panel)
	var ob := VBoxContainer.new()
	ob.add_theme_constant_override("separation", 10)
	_over_panel.add_child(ob)
	_over_title = _label(ob, "", 30, Color("ffd27a"))
	_over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_text = RichTextLabel.new()
	_over_text.bbcode_enabled = true
	_over_text.custom_minimum_size = Vector2(0, 170)
	ob.add_child(_over_text)
	var rb := Button.new()
	rb.text = "Play again"
	rb.focus_mode = Control.FOCUS_NONE
	rb.custom_minimum_size = Vector2(0, 36)
	rb.pressed.connect(func() -> void: restart_requested.emit())
	ob.add_child(rb)


func _set_caste(c: int) -> void:
	view.sim.colony.next_caste = c
	var sel: Variant = view.selected
	if sel is Brood:
		if view.sim.cmd_set_brood_caste(sel, c):
			view.sim.notify("Brood #%d will become a %s." % [sel.id, Cfg.CASTE_NAMES[c].to_lower()], "info")
	_sync_buttons()


func _set_speed(s: float) -> void:
	view.speed = s
	view.paused = false
	_sync_buttons()


func _sync_buttons() -> void:
	var tool := view.tool
	_buttons["t_inspect"].set_pressed_no_signal(tool == WorldView.Tool.INSPECT)
	_buttons["t_dig"].set_pressed_no_signal(tool == WorldView.Tool.DIG)
	_buttons["t_erase"].set_pressed_no_signal(tool == WorldView.Tool.ERASE)
	for r in 5:
		_buttons["r_%d" % r].set_pressed_no_signal(tool == WorldView.Tool.ROOM and view.tool_room == r)
	for p in 5:
		_buttons["p_%d" % p].set_pressed_no_signal(tool == WorldView.Tool.PHERO and view.tool_phero == p)
	for c in [1, 2, 3]:
		_buttons["c_%d" % c].set_pressed_no_signal(view.sim.colony.next_caste == c)
	_buttons["s_pause"].set_pressed_no_signal(view.paused)
	_buttons["s_1"].set_pressed_no_signal(not view.paused and view.speed == 1.0)
	_buttons["s_2"].set_pressed_no_signal(not view.paused and view.speed == 2.0)
	_buttons["s_4"].set_pressed_no_signal(not view.paused and view.speed == 4.0)
	_hint_bar.text = _tool_hint()
	_refresh_info()


func _tool_hint() -> String:
	match view.tool:
		WorldView.Tool.INSPECT:
			return "Inspect: click an ant, egg, plant or cell.   Right-click erases.  Wheel zoom, middle-drag or arrows pan, Home resets.  Space pause, Tab speed."
		WorldView.Tool.DIG:
			return "Dig: drag from a tunnel into soil. Idle workers excavate it. Rocks cannot be dug."
		WorldView.Tool.ROOM:
			return "%s: paint over existing tunnel cells to turn them into this room." % Cfg.ROOM_NAMES[view.tool_room]
		WorldView.Tool.PHERO:
			return WorldView.PHERO_HINTS[view.tool_phero]
		WorldView.Tool.ERASE:
			return "Erase: drag to remove pheromones and cancel dig orders."
	return ""


func _refresh_info() -> void:
	_info.text = view.describe_selection() if view.selected != null else "Select Inspect and click something.\n\n[i]Ants decide for themselves. You shape the colony with pheromones and nest design.[/i]"


func _on_notified(text: String, kind: String) -> void:
	var col: String = {"info": "#d8c8a8", "warn": "#ffcc66", "danger": "#ff6a5a", "good": "#8fe070"}.get(kind, "#d8c8a8")
	_log.append_text("[color=%s]%s[/color]\n" % [col, text])
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _label(panel, text, 14, Color(col))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(560, 0)
	_toasts.add_child(panel)
	while _toasts.get_child_count() > 4:
		_toasts.get_child(0).queue_free()
		_toasts.remove_child(_toasts.get_child(0))
	var tw := panel.create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(panel, "modulate:a", 0.0, 1.0)
	tw.tween_callback(panel.queue_free)


func _process(delta: float) -> void:
	if view == null or view.sim == null:
		return
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.2
		_update(0.2, false)
	if view.sim.outcome != 0 and not _over_panel.visible:
		_show_outcome()
	if _hint_bar != null and view.tool == WorldView.Tool.INSPECT:
		pass


func _fmt_time(sim: Simulation) -> String:
	var hours := fposmod(6.0 + sim.day_fraction() * 24.0, 24.0)
	return "%02d:%02d" % [int(hours), int((hours - int(hours)) * 60.0)]


func _update(_dt: float, _force: bool) -> void:
	var sim := view.sim
	var col := sim.colony
	_top_labels["title"].text = "COLONY"
	_top_labels["day"].text = "Day %d/%d  %s" % [mini(sim.day(), Cfg.WIN_DAYS), Cfg.WIN_DAYS, _fmt_time(sim)]
	var ft := col.trend(col.food_hist)
	_top_labels["food"].text = "Food %d/%d (%+.0f/min)" % [col.food, col.food_cap, ft]
	_top_labels["food"].add_theme_color_override("font_color", Color("ff6a5a") if col.food < col.food_cap * 0.15 else Color("a8e07a"))
	var wt := col.trend(col.water_hist)
	_top_labels["water"].text = "Water %d/%d (%+.0f/min)" % [col.water, col.water_cap, wt]
	_top_labels["water"].add_theme_color_override("font_color", Color("ff6a5a") if col.water < col.water_cap * 0.15 else Color("7fc8ff"))
	var c: Dictionary = sim.counts
	if c.is_empty():
		c = {Cfg.Caste.WORKER: 0, Cfg.Caste.NURSE: 0, Cfg.Caste.SOLDIER: 0, Cfg.Caste.QUEEN: 1}
	_top_labels["pop"].text = "Ants %d  (W %d  N %d  S %d)  cap %d" % [sim.adult_count(), c[Cfg.Caste.WORKER], c[Cfg.Caste.NURSE], c[Cfg.Caste.SOLDIER], col.population_cap(sim.terrain.tunnel_count)]
	var eggs := 0
	var larvae := 0
	var pupae := 0
	for b in sim.brood:
		match b.stage:
			Cfg.Stage.EGG:
				eggs += 1
			Cfg.Stage.LARVA:
				larvae += 1
			_:
				pupae += 1
	_top_labels["brood"].text = "Brood: %de %dl %dp - %s" % [eggs, larvae, pupae, col.lay_status]
	if sim.queen != null:
		_queen_bar.value = maxf(0.0, sim.queen.hp / sim.queen.max_hp * 100.0)
	var weather := "Clear"
	var rain := sim.weather.rain
	var storm := sim.weather.next_storm(sim.t)
	if rain > 0.05:
		weather = "RAIN %d%%" % (rain * 100.0)
	elif not storm.is_empty() and storm["start"] - sim.t < 40.0 and storm["start"] > sim.t:
		weather = "Storm in %ds" % int(storm["start"] - sim.t)
	var flood_lvl := sim.flood.max_level
	if flood_lvl > 0.05:
		weather += "  Flood %d%%" % (flood_lvl * 100.0)
	_top_labels["weather"].text = weather
	_top_labels["weather"].add_theme_color_override("font_color", Color("ff9a5a") if flood_lvl > 0.3 else (Color("8fc8ff") if rain > 0.05 else Color("f1e4c8")))
	_top_labels["threat"].text = "SPIDER!" if sim.spider != null else ""
	_top_labels["threat"].add_theme_color_override("font_color", Color("ff5040"))
	if view.selected != null:
		_refresh_info()
	_update_tutorial()


func _update_tutorial() -> void:
	var sim := view.sim
	var a := view.actions
	var steps: Array[Dictionary] = [
		{"text": "[b]1. Find food.[/b] Green leaf plants feed the colony. Pick Inspect [I] and click one.", "done": view.selected is FoodSource},
		{"text": "[b]2. Make a food trail.[/b] Press [b]Q[/b] and drag from the nest entrance toward a plant. Workers follow the rising trail (+ icons).", "done": a["food_paint"] >= 8},
		{"text": "[b]3. Route home.[/b] Press [b]W[/b] and drag from the plant back to the nest. Home scent guides lost ants (rain makes them lose their way).", "done": a["home_paint"] >= 6 or sim.stats["deliveries"] >= 15},
		{"text": "[b]4. Grow the nest.[/b] Press [b]D[/b] and drag from a tunnel into soil, then [b]3[/b] to paint Storage so you can hold more food.", "done": sim.stats["dug"] >= 1},
		{"text": "[b]5. Prepare for rain.[/b] Water pours down the shaft. Press [b]4[/b] and paint a Drain chamber low in the nest. Use Evacuate [T] if water rises.", "done": sim.terrain.room_cells(Cfg.Room.DRAIN).size() > 0},
		{"text": "[b]6. Defend.[/b] Keep soldiers near the entrance. When a spider comes, press [b]R[/b] and paint Attack on it.", "done": sim.stats["spiders_defeated"] >= 1},
	]
	var text := ""
	var storm := sim.weather.next_storm(sim.t)
	if sim.spider != null:
		text = "[b]Spider![/b] Soldiers fight it near the entrance. Paint Attack [R] on it, and Danger [E] to keep workers away. Check the colony's soldiers."
	elif sim.weather.rain > 0.05 or (not storm.is_empty() and storm["start"] - sim.t < 20.0 and storm["start"] > sim.t):
		text = "[b]Storm![/b] Water enters through the entrance. Drain chambers [4] soak it up. Paint Evacuate [T] over flooded rooms; protect the queen."
	elif _tut_step < steps.size():
		if steps[_tut_step]["done"]:
			_tut_step += 1
		if _tut_step < steps.size():
			text = steps[_tut_step]["text"]
	if text == "":
		if _tut_done_at < 0.0:
			_tut_done_at = sim.t
		text = "[b]You know the basics.[/b] Keep the queen alive, keep food and water up, and survive %d days." % Cfg.WIN_DAYS
	_tutorial.text = text


func _show_outcome() -> void:
	var sim := view.sim
	_over_panel.visible = true
	_over_title.text = "VICTORY" if sim.outcome == 1 else "THE COLONY FELL"
	_over_title.add_theme_color_override("font_color", Color("8fe070") if sim.outcome == 1 else Color("ff6a5a"))
	var s := sim.stats
	_over_text.text = "%s\n\nDay reached: %d\nAnts alive: %d   born: %d   lost: %d (drowned %d, spider %d)\nFood delivered: %d trips   Cells dug: %d\nSpiders defeated: %d" % [
		sim.outcome_reason, mini(sim.day(), Cfg.WIN_DAYS), sim.adult_count(), s["born"], s["ants_lost"], s["drowned"], s["killed_by_spider"], s["deliveries"], s["dug"], s["spiders_defeated"]]
