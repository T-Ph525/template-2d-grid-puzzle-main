extends CanvasLayer
## Native-Control dark-fantasy HUD. Public signals and fields are unchanged for RunController.
signal upgrade_selected(id: String)
signal resume_requested
signal restart_requested
signal menu_requested

const GOLD := Color("#d5b471")
const PALE := Color("#e7dfcf")
const MUTED := Color("#9d9a91")
const TEAL := Color("#67e5d9")
const CRIMSON := Color("#c24d58")
const DARK := Color("#090c12")
const PANEL := Color(0.035, 0.045, 0.06, 0.94)

var hp_bar: ProgressBar
var xp_bar: ProgressBar
var status: Label
var upgrades_label: Label
var hint: Label
var overlay: Control
var overlay_kind: String = ""
var offered: Array[String] = []
var floor_label: Label
var level_label: Label
var threat_label: Label
var hp_value: Label
var xp_value: Label
var _font: SystemFont
var _theme: Theme
var _hp_fill: StyleBoxFlat
var _xp_fill: StyleBoxFlat

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Cinzel", "Palatino Linotype", "Georgia", "Times New Roman"])
	_theme = _build_theme()
	var root := Control.new()
	root.name = "HudRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme
	add_child(root)
	_build_top_bar(root)
	_build_bottom_hint(root)

func _build_top_bar(root: Control) -> void:
	var bar := PanelContainer.new()
	bar.name = "TopBar"
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 18
	bar.offset_top = 14
	bar.offset_right = -18
	bar.offset_bottom = 136
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)
	var crest := PanelContainer.new()
	crest.custom_minimum_size = Vector2(58, 86)
	crest.add_theme_stylebox_override("panel", _box(Color("#102027"), GOLD, 1, 8, 4))
	row.add_child(crest)
	var glyph := _label("✦", 30, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crest.add_child(glyph)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 3)
	row.add_child(column)
	var title_row := HBoxContainer.new()
	column.add_child(title_row)
	var title := _label("THE HOLLOW SPIRE", 18, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	floor_label = _label("FLOOR I / III", 14, PALE, HORIZONTAL_ALIGNMENT_RIGHT)
	title_row.add_child(floor_label)
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	column.add_child(hp_row)
	var hp_caption := _label("VITALITY", 11, MUTED)
	hp_caption.custom_minimum_size.x = 62
	hp_row.add_child(hp_caption)
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size.y = 15
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_bar.show_percentage = false
	_hp_fill = _fill_style(CRIMSON, Color("#f08b7e"))
	hp_bar.add_theme_stylebox_override("background", _bar_background())
	hp_bar.add_theme_stylebox_override("fill", _hp_fill)
	hp_row.add_child(hp_bar)
	hp_value = _label("100 / 100", 12, PALE, HORIZONTAL_ALIGNMENT_RIGHT)
	hp_value.custom_minimum_size.x = 76
	hp_row.add_child(hp_value)
	var xp_row := HBoxContainer.new()
	xp_row.add_theme_constant_override("separation", 8)
	column.add_child(xp_row)
	var xp_caption := _label("SOUL", 11, MUTED)
	xp_caption.custom_minimum_size.x = 62
	xp_row.add_child(xp_caption)
	xp_bar = ProgressBar.new()
	xp_bar.custom_minimum_size.y = 8
	xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_bar.show_percentage = false
	_xp_fill = _fill_style(TEAL, Color("#b3fff5"))
	xp_bar.add_theme_stylebox_override("background", _bar_background())
	xp_bar.add_theme_stylebox_override("fill", _xp_fill)
	xp_row.add_child(xp_bar)
	xp_value = _label("0 / 10", 12, TEAL, HORIZONTAL_ALIGNMENT_RIGHT)
	xp_value.custom_minimum_size.x = 76
	xp_row.add_child(xp_value)
	upgrades_label = _label("RELICS  no boons yet", 11, MUTED)
	upgrades_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(upgrades_label)
	status = _label("SEED 1", 10, MUTED)
	column.add_child(status)
	var divider := ColorRect.new()
	divider.color = Color(0.83, 0.7, 0.44, 0.35)
	divider.custom_minimum_size.x = 1
	row.add_child(divider)
	var stats := VBoxContainer.new()
	stats.custom_minimum_size.x = 128
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 2)
	row.add_child(stats)
	threat_label = _label("7 HOSTILES", 15, CRIMSON, HORIZONTAL_ALIGNMENT_RIGHT)
	stats.add_child(threat_label)
	level_label = _label("LEVEL 1", 12, PALE, HORIZONTAL_ALIGNMENT_RIGHT)
	stats.add_child(level_label)

func _build_bottom_hint(root: Control) -> void:
	var bottom := MarginContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 150
	bottom.offset_top = -76
	bottom.offset_right = -150
	bottom.offset_bottom = -12
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 46
	panel.add_theme_stylebox_override("panel", _box(Color(0.025, 0.032, 0.045, 0.82), Color(0.83, 0.7, 0.44, 0.25), 1, 6, 10))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(panel)
	hint = _label("", 12, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(hint)

func refresh(run, enemy_count: int, exit_open: bool) -> void:
	status.text = ("TEST PROFILE  ·  " if LevelManager.test_mode else "") + "SEED %d" % run.seed_value
	floor_label.text = "FLOOR %s / III" % _roman(run.floor_number)
	level_label.text = "LEVEL %d" % run.player_level
	hp_bar.max_value = run.max_hp
	hp_bar.value = run.hp
	xp_bar.max_value = run.xp_required()
	xp_bar.value = run.xp
	hp_value.text = "%d / %d" % [run.hp, run.max_hp]
	xp_value.text = "%d / %d" % [run.xp, run.xp_required()]
	threat_label.text = "PATH OPEN" if exit_open else "%d HOSTILES" % enemy_count
	threat_label.add_theme_color_override("font_color", TEAL if exit_open else CRIMSON)
	var ratio := float(run.hp) / maxf(1.0, float(run.max_hp))
	_hp_fill.bg_color = Color("#e4635f") if ratio < 0.3 else CRIMSON
	var parts: PackedStringArray = []
	for id: String in run.upgrades:
		parts.append("%s ×%d" % [run.UPGRADES[id].title, run.upgrades[id]])
	upgrades_label.text = "RELICS  " + (", ".join(parts) if not parts.is_empty() else "no boons yet")
	if exit_open:
		hint.text = "The way onward is open — step into the teal gate.\nWASD / Arrows  ·  Auto attack  ·  Esc pause  ·  R restart"
	else:
		hint.text = "Clear the hall — purple stone sentinels wake when you draw near.\nWASD / Arrows  ·  Auto attack  ·  Esc pause  ·  R restart  ·  Seed %d" % run.seed_value

func _label(text: String, size: int, color: Color = PALE, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _panel(title: String, detail: String) -> VBoxContainer:
	close_overlay()
	overlay = Control.new()
	overlay.name = "Overlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.theme = _theme
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.005, 0.008, 0.014, 0.9)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _overlay_style())
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 540
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	column.add_child(_label("✦  ─────────────  ✦", 13, GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(_label(title, 32, GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	var body := _label(detail, 15, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(body)
	return column

func _button(column: VBoxContainer, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.set_script(load("res://scripts/ui/menu_button.gd"))
	button.text = text
	button.custom_minimum_size = Vector2(520, 52)
	button.pressed.connect(callback)
	column.add_child(button)
	return button

func show_upgrades(run, choices: Array[String]) -> void:
	var column := _panel("CHOOSE A RELIC", "Level %d  ·  The dark waits while you decide." % run.player_level)
	overlay_kind = "upgrade"
	offered = choices.duplicate()
	for id in choices:
		var button := _button(column, "%s  —  %s" % [run.UPGRADES[id].title, run.UPGRADES[id].detail], func(): upgrade_selected.emit(id))
		button.name = "Upgrade_" + id
		if id == choices[0]:
			button.grab_focus()

func show_pause() -> void:
	var column := _panel("PAUSED", "The spire holds its breath. Your run is safe here.")
	overlay_kind = "pause"
	_button(column, "Resume", func(): resume_requested.emit()).grab_focus()
	_button(column, "Restart this seed", func(): restart_requested.emit())
	_button(column, "Return to Menu", func(): menu_requested.emit())

func show_end(victory: bool, run) -> void:
	var column := _panel("THE SPIRE YIELDS" if victory else "YOUR LIGHT FADES", "Floor %d / III  ·  Level %d  ·  Seed %d" % [run.floor_number, run.player_level, run.seed_value])
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

func _roman(value: int) -> String:
	match value:
		1: return "I"
		2: return "II"
		3: return "III"
		_: return str(value)

func _build_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = _font
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", PALE)
	theme.set_stylebox("panel", "PanelContainer", _panel_style())
	theme.set_stylebox("normal", "Button", _box(Color("#101820"), Color(0.83, 0.7, 0.44, 0.45), 1, 5, 12))
	theme.set_stylebox("hover", "Button", _box(Color("#1a2b31"), GOLD, 1, 5, 12))
	theme.set_stylebox("pressed", "Button", _box(Color("#2a362f"), Color("#f0d49a"), 1, 5, 12))
	theme.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), GOLD, 2, 5, 12))
	theme.set_color("font_color", "Button", PALE)
	theme.set_color("font_hover_color", "Button", Color("#fff0cc"))
	theme.set_color("font_focus_color", "Button", Color("#fff0cc"))
	theme.set_color("font_pressed_color", "Button", Color("#fff0cc"))
	theme.set_font_size("font_size", "Button", 18)
	return theme

func _panel_style() -> StyleBoxFlat:
	return _box(PANEL, Color(0.83, 0.7, 0.44, 0.52), 1, 8, 12)

func _overlay_style() -> StyleBoxFlat:
	var style := _box(Color("#0b1118"), Color(0.86, 0.73, 0.47, 0.72), 2, 8, 18)
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 18
	return style

func _box(bg: Color, border: Color, width: int, radius: int, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = margin + 4
	style.content_margin_right = margin + 4
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style

func _bar_background() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0b1017")
	style.border_color = Color(0.74, 0.61, 0.37, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	return style

func _fill_style(color: Color, highlight: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = highlight
	style.border_width_top = 2
	style.set_corner_radius_all(3)
	return style