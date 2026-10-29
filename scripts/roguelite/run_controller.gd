extends Node
## Coordinates shared GameManager/Level nodes; run data is kept on LevelManager.
const Generator := preload("res://scripts/roguelite/dungeon_generator.gd")
const HudScript := preload("res://scripts/roguelite/hud.gd")
var manager
var run
var hud
var transitioning: bool = false

func setup(game_manager) -> void:
	manager = game_manager
	run = LevelManager.rogue_run
	hud = HudScript.new()
	hud.name = "SurvivalHUD"
	manager.add_child(hud)
	hud.upgrade_selected.connect(choose_upgrade)
	hud.resume_requested.connect(resume_run)
	hud.restart_requested.connect(restart_run)
	hud.menu_requested.connect(return_to_menu)
	manager.status_label.hide()
	build_floor()

func build_floor() -> void:
	transitioning = false
	var old: Level = manager.level
	old.stop_combat()
	manager.remove_child(old)
	old.queue_free()
	var level := Level.new()
	level.name = "Level"
	level.rogue_run = run
	manager.add_child(level)
	manager.level = level
	var data := Generator.generate(run.seed_value, run.floor_number)
	var map: Array = validated_map(data.map, run.floor_number)
	var grid := Grid.new(String(map[0]).length(), map.size(), 1.0)
	level.build(map, grid, manager.tick_manager)
	level.lost.connect(_on_death)
	level.floor_exit.connect(_on_exit)
	for child in level.get_children():
		if child.has_method("set_physics_active"):
			child.set_physics_active(true)
	manager.tick_manager.mode = TickManager.Mode.REALTIME
	manager.tick_manager.set_process(true)
	var camera: Camera3D = manager.camera
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	# Include the HUD margins and the whole map at common window aspects.
	var viewport_size: Vector2 = manager.get_viewport().get_visible_rect().size
	var aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
	camera.size = maxf(grid.height + 4.0, (grid.width + 2.0) / aspect)
	camera.position = grid.center_world() + Vector3(0, 25, 0)
	camera.look_at(grid.center_world(), Vector3(0, 0, -1))
	LevelManager.profile.best_floor = maxi(LevelManager.profile.best_floor, run.floor_number)
	LevelManager.save_settings()
	hud.refresh(run, level.enemies.size(), level.exit_active)

func _process(_delta: float) -> void:
	if manager == null or transitioning or run.ended:
		return
	hud.refresh(run, manager.level.enemies.size(), manager.level.exit_active)
	if run.pending_upgrades > 0 and hud.overlay_kind == "":
		get_tree().paused = true
		hud.show_upgrades(run, run.choices())

func choose_upgrade(id: String) -> void:
	if hud.overlay_kind != "upgrade" or not hud.offered.has(id):
		return
	if not run.apply_upgrade(id):
		return
	manager.level.floor_metrics.upgrades += 1
	manager.level.floor_metrics.upgrade_ids.append(id)
	hud.close_overlay()
	if run.pending_upgrades > 0:
		hud.show_upgrades(run, run.choices())
	else:
		get_tree().paused = false

func open_pause() -> void:
	if run.ended or transitioning or hud.overlay_kind != "":
		return
	get_tree().paused = true
	hud.show_pause()

func resume_run() -> void:
	if hud.overlay_kind != "pause":
		return
	hud.close_overlay()
	get_tree().paused = false

func restart_run() -> void:
	if GameFlow._busy:
		return
	manager.level.stop_combat()
	manager.tick_manager.set_process(false)
	get_tree().paused = false
	GameFlow.start_roguelite(run.seed_value)

func return_to_menu() -> void:
	if GameFlow._busy:
		return
	manager.level.stop_combat()
	manager.tick_manager.set_process(false)
	get_tree().paused = false
	GameFlow.goto("main_menu")

func _on_death() -> void:
	_finish(false)

func _on_exit() -> void:
	if transitioning or run.ended:
		return
	transitioning = true
	run.floor_results.append(manager.level.measurements("cleared"))
	manager.level.stop_combat()
	manager.tick_manager.set_process(false)
	# Take queued XP level-ups before changing floor; no orphaned overlay.
	if run.floor_number >= 3:
		_finish(true)
	else:
		call_deferred("_advance_floor")

func _advance_floor() -> void:
	run.floor_number += 1
	build_floor()

func _finish(victory: bool) -> void:
	if run.ended:
		return
	run.ended = true
	if not victory:
		run.floor_results.append(manager.level.measurements("death"))
	manager.level.stop_combat()
	manager.tick_manager.set_process(false)
	if victory:
		LevelManager.profile.wins += 1
	LevelManager.save_settings()
	get_tree().paused = true
	hud.refresh(run, manager.level.enemies.size(), manager.level.exit_active)
	hud.show_end(victory, run)

func describe_run() -> Dictionary:
	return {"seed": run.seed_value, "floor": run.floor_number, "hp": run.hp, "max_hp": run.max_hp, "xp": run.xp, "level": run.player_level, "pending": run.pending_upgrades, "upgrades": run.upgrades.duplicate(), "enemies": manager.level.enemies.size(), "exit_active": manager.level.exit_active, "ended": run.ended, "paused": get_tree().paused, "overlay": hud.overlay_kind, "choices": hud.offered.duplicate()}

static func validated_map(map: Array, floor_number: int) -> Array:
	# Invalid/unreachable procedural encounters are replaced before spawning actors.
	if not Generator.validate(map).get("valid", false):
		return Generator.fallback(floor_number)
	for row: String in map:
		for tile in row:
			if tile not in ["#", " ", "@", ">", "E", "T", "+"]:
				return Generator.fallback(floor_number)
	return map
