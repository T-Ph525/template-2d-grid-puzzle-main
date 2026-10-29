extends CanvasLayer
## UI continues during tree pause; gameplay nodes inherit the paused tree.
signal upgrade_selected(id: String)
signal resume_requested
signal restart_requested
signal menu_requested
var hp_bar: ProgressBar
var xp_bar: ProgressBar
var status: Label
var upgrades_label: Label
var hint: Label
var overlay: Control
var overlay_kind: String = ""
var offered: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.theme
	add_child(root)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	root.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	panel.add_child(rows)
	status = _label("", 20)
	rows.add_child(status)
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size.y = 18
	hp_bar.show_percentage = false
	rows.add_child(hp_bar)
	xp_bar = ProgressBar.new()
	xp_bar.custom_minimum_size.y = 12
	xp_bar.show_percentage = false
	rows.add_child(xp_bar)
	upgrades_label = _label("", 16)
	upgrades_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	rows.add_child(upgrades_label)
	hint = _label("", 18)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -52
	hint.offset_bottom = -6
	root.add_child(hint)

func refresh(run, enemy_count: int, exit_open: bool) -> void:
	status.text = ("TEST PROFILE   •   " if LevelManager.test_mode else "") + "SURVIVAL   •   FLOOR %d / 3   •   HP %d / %d   •   LV %d   •   XP %d / %d   •   ENEMIES %d" % [run.floor_number, run.hp, run.max_hp, run.player_level, run.xp, run.xp_required(), enemy_count]
	hp_bar.max_value = run.max_hp
	hp_bar.value = run.hp
	xp_bar.max_value = run.xp_required()
	xp_bar.value = run.xp
	var parts: PackedStringArray = []
	for id: String in run.upgrades:
		parts.append("%s ×%d" % [run.UPGRADES[id].title, run.upgrades[id]])
	upgrades_label.text = "UPGRADES  " + (", ".join(parts) if not parts.is_empty() else "Collect blue XP to grow")
	hint.text = ("EXIT OPEN — step onto the green circle" if exit_open else "Clear enemies • Purple tanks guard rooms until approached") + "\nWASD / Arrows • Auto attack • Esc pause • R restart run • Seed %d" % run.seed_value

func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	return label

func _panel(title: String, detail: String) -> VBoxContainer:
	close_overlay()
	overlay = Control.new()
	overlay.name = "Overlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.theme = UITheme.theme
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.03, 0.02, 0.9)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 550
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	column.add_child(_label(title, 38))
	column.add_child(_label(detail, 18))
	return column

func _button(column: VBoxContainer, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.set_script(load("res://scripts/ui/menu_button.gd"))
	button.text = text
	button.custom_minimum_size = Vector2(500, 50)
	button.pressed.connect(callback)
	column.add_child(button)
	return button

func show_upgrades(run, choices: Array[String]) -> void:
	var column := _panel("LEVEL %d — CHOOSE AN UPGRADE" % run.player_level, "The dungeon is paused. Choose one to continue.")
	overlay_kind = "upgrade"
	offered = choices.duplicate()
	for id in choices:
		var button := _button(column, "%s  •  %s" % [run.UPGRADES[id].title, run.UPGRADES[id].detail], func(): upgrade_selected.emit(id))
		button.name = "Upgrade_" + id
		if id == choices[0]:
			button.grab_focus()

func show_pause() -> void:
	var column := _panel("PAUSED", "Take a breath. Your run is safe here.")
	overlay_kind = "pause"
	_button(column, "Resume", func(): resume_requested.emit()).grab_focus()
	_button(column, "Restart this seed", func(): restart_requested.emit())
	_button(column, "Return to Menu", func(): menu_requested.emit())

func show_end(victory: bool, run) -> void:
	var column := _panel("DUNGEON CLEARED" if victory else "RUN ENDED", "Floor %d / 3 • Level %d • Seed %d" % [run.floor_number, run.player_level, run.seed_value])
	overlay_kind = "end"
	_button(column, "Restart this seed", func(): restart_requested.emit()).grab_focus()
	_button(column, "Return to Menu", func(): menu_requested.emit())

func close_overlay() -> void:
	if is_instance_valid(overlay):
		overlay.hide()
		overlay.process_mode = Node.PROCESS_MODE_DISABLED
		overlay.queue_free()
	overlay = null
	overlay_kind = ""
	offered.clear()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and overlay_kind == "pause":
		get_viewport().set_input_as_handled()
		resume_requested.emit()
