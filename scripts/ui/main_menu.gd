extends Screen

## The main menu. Title, subtitle, and the top-level navigation buttons.

func _on_screen_ready() -> void:
	var col := center_column()
	col.add_child(make_title("GridKit"))
	col.add_child(make_label("SURVIVE THE DEPTHS", 22))
	col.add_child(make_label("Best floor %d / 3  •  Wins %d" % [LevelManager.profile.best_floor, LevelManager.profile.wins], 16))
	var seed_input := LineEdit.new()
	seed_input.name = "RunSeed"
	seed_input.placeholder_text = "Optional dungeon seed (number)"
	seed_input.custom_minimum_size = Vector2(360, 36)
	seed_input.max_length = 10
	col.add_child(seed_input)
	var survival := make_button("Roguelite — New Run", 360)
	survival.name = "RogueliteButton"
	survival.pressed.connect(func():
		var text := seed_input.text.strip_edges()
		GameFlow.start_roguelite(absi(text.to_int()) if text.is_valid_int() else -1))
	col.add_child(survival)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	col.add_child(spacer)

	var play := make_button("Puzzle — Original Levels", 360)
	play.pressed.connect(func(): GameFlow.play_level(0))
	col.add_child(play)

	if LevelManager.level_select_enabled:
		var level_select := make_button("Puzzle Level Select", 360)
		level_select.pressed.connect(func(): GameFlow.goto("level_select"))
		col.add_child(level_select)

	var settings := make_button("Settings")
	settings.pressed.connect(func(): GameFlow.goto("settings"))
	col.add_child(settings)

	var credits := make_button("Credits")
	credits.pressed.connect(func(): GameFlow.goto("credits"))
	col.add_child(credits)

	var quit := make_button("Quit")
	quit.pressed.connect(func(): get_tree().quit())
	col.add_child(quit)
