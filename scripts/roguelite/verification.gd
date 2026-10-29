extends Node
## Repeatable in-engine integration checks. Run tests/roguelite_verification.tscn.
## It restores profile statistics/settings after checking progression.
var checks: Array = []
var failures: Array = []
var result: Dictionary = {}
var completed: bool = false
var test_game
var saved_best: int
var saved_wins: int
var saved_settings: Dictionary
var saved_visual: int
var saved_mode: String
const Generator := preload("res://scripts/roguelite/dungeon_generator.gd")
const RunState := preload("res://scripts/roguelite/run_state.gd")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func check(label: String, passed: bool, detail: Variant = null) -> void:
	var record := {"name": label, "passed": passed, "detail": detail, "frame": Engine.get_process_frames(), "physics": Engine.get_physics_frames()}
	checks.append(record)
	if not passed:
		failures.append(record)

func wait_frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _run() -> void:
	var normal_path: String = LevelManager.profile.active_path()
	var stale_profile = LevelManager.profile
	LevelManager.enable_test_mode()
	check("normal save path preserved", normal_path == "user://gridkit_profile.cfg")
	check("explicit test profile selected", LevelManager.profile.active_path() == "user://gridkit_test_profile.cfg")
	check("stale normal profile write redirected", stale_profile.active_path() == "user://gridkit_test_profile.cfg")
	var saved_to_test: bool = stale_profile.save_profile()
	check("stale reference cannot write real progress", saved_to_test and LevelManager.test_profile_status().real_unchanged)
	var profile_script = load("res://scripts/roguelite/profile.gd")
	var profile_probe = profile_script.new(true)
	profile_probe.best_floor = 2
	profile_probe.wins = 17
	profile_probe.settings = {"Master": 0.41}
	var roundtrip_saved: bool = profile_probe.save_profile()
	profile_probe.load_profile()
	check("isolated profile roundtrip", roundtrip_saved and profile_probe.best_floor == 2 and profile_probe.wins == 17 and is_equal_approx(profile_probe.settings.Master, 0.41))
	var corrupt := FileAccess.open(profile_probe.active_path(), FileAccess.WRITE)
	corrupt.store_string("broken save")
	corrupt.close()
	profile_probe.load_profile()
	check("corrupt test save defaults", profile_probe.best_floor == 0 and profile_probe.wins == 0 and profile_probe.settings.is_empty())
	LevelManager.profile.save_profile()
	saved_best = LevelManager.profile.best_floor
	saved_wins = LevelManager.profile.wins
	saved_settings = LevelManager.profile.settings.duplicate(true)
	saved_visual = LevelManager.player_visual
	saved_mode = LevelManager.game_mode
	LevelManager.player_visual = LevelManager.PLAYER_SPRITE
	var generator_failures := 0
	for seed_value in 300:
		for floor_number in range(1, 4):
			var data: Dictionary = Generator.generate(seed_value, floor_number)
			if not Generator.validate(data.map).get("valid", false) or data.map != Generator.generate(seed_value, floor_number).map:
				generator_failures += 1
	check("900 maps across 300 deterministic seeds", generator_failures == 0, generator_failures)
	for floor_number in range(1, 4):
		check("fallback floor %d" % floor_number, Generator.validate(Generator.fallback(floor_number)).get("valid", false))
	for id: String in RunState.UPGRADES:
		var state = RunState.new()
		state.pending_upgrades = 1
		var before: Array = [state.damage, state.attack_interval, state.max_hp, state.movement_speed, state.attack_range, state.damage_reduction]
		var applied: bool = state.apply_upgrade(id)
		var after: Array = [state.damage, state.attack_interval, state.max_hp, state.movement_speed, state.attack_range, state.damage_reduction]
		check("upgrade " + id, applied and before != after and state.pending_upgrades == 0)
	await _test_puzzles()
	await _test_navigation()
	await _test_survival()
	get_tree().paused = false
	if is_instance_valid(test_game):
		test_game.queue_free()
	await wait_frames(2)
	LevelManager.profile.best_floor = saved_best
	LevelManager.profile.wins = saved_wins
	LevelManager.profile.settings = saved_settings
	LevelManager.player_visual = saved_visual
	LevelManager.game_mode = saved_mode
	LevelManager.profile.save_profile()
	check("real player profile unchanged", LevelManager.test_profile_status().real_unchanged, LevelManager.test_profile_status())
	result = {"checks": checks.size(), "failures": failures, "records": checks, "profile": LevelManager.test_profile_status()}
	completed = true
	print("GRIDKIT_VERIFICATION " + JSON.stringify(result))

func _test_puzzles() -> void:
	var tick := TickManager.new()
	tick.set_process(false)
	add_child(tick)
	for index in 5:
		var level := Level.new()
		add_child(level)
		var map: Array = LevelManager.LEVELS[index].map
		level.build(map, Grid.new(String(map[0]).length(), map.size()), tick)
		check("legacy map builds %d" % index, level.player != null and level.rogue_run == null and not level.is_won())
		if index == 0:
			level.try_move(level.player, Vector2i.RIGHT)
			level.try_move(level.player, Vector2i.RIGHT)
			level.player.position = level.grid.cell_to_world(level.player.grid_pos)
			level._update_channels()
			check("legacy star win", level.is_won())
		if index == 1:
			level.player.position = level.grid.cell_to_world(Vector2i(5, 1))
			level._update_channels()
			check("legacy key opens door", not level._walls.has(Vector2i(2, 3)))
		if index == 2:
			var box = level.entity_at(Vector2i(2, 2))
			check("legacy crate push", level.try_move(level.player, Vector2i.DOWN) and level.try_move(level.player, Vector2i.RIGHT) and box.grid_pos == Vector2i(3, 2))
			level._relocate(box, Vector2i(5, 2))
			box.global_position = level.grid.cell_to_world(Vector2i(5, 2)) + Vector3(0, 0.45, 0)
			level._update_channels()
			check("legacy blue plate", not level._walls.has(Vector2i(8, 3)))
		if index == 3:
			check("legacy door orientation", is_equal_approx(level.door_at(Vector2i(4, 2)).rotation.y, PI / 2.0))
		if index == 4:
			var enemy = level.entity_at(Vector2i(6, 4))
			level._relocate(level.player, Vector2i(5, 4))
			enemy._check_caught()
			check("legacy enemy catch", level._lost)
		level.stop_combat()
		level.queue_free()
		await wait_frames(2)
	tick.queue_free()

func _test_navigation() -> void:
	var tick := TickManager.new()
	tick.set_process(false)
	add_child(tick)
	var level := Level.new()
	level.rogue_run = RunState.new()
	add_child(level)
	var map := ["#########", "#@ # E >#", "#  D    #", "#  #    #", "#       #", "#########"]
	level.build(map, Grid.new(9, 6), tick)
	level._rebuild_navigation()
	check("LOS blocks wall", not level.has_line_of_sight(Vector3(2, 0, 1), Vector3(4, 0, 1)))
	check("LOS blocks closed door", not level.has_line_of_sight(Vector3(2, 0, 2), Vector3(4, 0, 2)))
	check("BFS reaches enemy around barrier", level._distance_field.has(Vector2i(5, 1)), level._distance_field.get(Vector2i(5, 1)))
	level.door_at(Vector2i(3, 2)).open()
	check("LOS permits opened door", level.has_line_of_sight(Vector3(2, 0, 2), Vector3(4, 0, 2)))
	var player = level.player
	player.set_physics_active(true)
	var enemy = level.enemies[0]
	player.global_position = Vector3(2.45, 0, 1)
	enemy.global_position = Vector3(3.55, 0, 1)
	# The wall between these two blocks even extended attack range.
	level.rogue_run.attack_range = 3.5
	var enemy_hp: int = enemy.health
	player._rogue_physics(0.1)
	check("automatic melee respects wall", enemy.health == enemy_hp)
	player.global_position = Vector3(1, 0, 1)
	player.set_physics_process(false)
	enemy.global_position = Vector3(5, 0, 1)
	level._rebuild_navigation()
	var nav_before: Vector3 = enemy.global_position
	await wait_frames(330)
	check("enemy navigates around wall and closed door", enemy.global_position.distance_to(player.global_position) < 1.5, {"from": nav_before, "to": enemy.global_position})
	level.stop_combat()
	level.queue_free()
	tick.queue_free()
	await wait_frames(2)

func _test_survival() -> void:
	LevelManager.begin_roguelite(42)
	test_game = load("res://game.tscn").instantiate()
	test_game.name = "SurvivalGame"
	add_child(test_game)
	var controller = test_game.rogue_controller
	var run = controller.run
	var level: Level = test_game.level
	var player = level.player
	# Stop enemy AI while testing isolated input and damage.
	for enemy in level.enemies:
		enemy.set_physics_process(false)
	var position_before: Vector3 = player.global_position
	var before_frame := Engine.get_physics_frames()
	Input.action_press("move_down")
	await wait_frames(15)
	Input.action_release("move_down")
	check("real-time input moves player", player.global_position.z > position_before.z + 0.5, {"from": position_before, "to": player.global_position, "before_physics": before_frame})
	check("sprite default", player.find_child("*", false, false) != null and not player.has_node("Robot"))
	run.hp = 100
	player.invulnerability = 0.0
	var feedback_before: int = level.feedback_counts.damage
	var first: bool = player.take_damage(12)
	var second: bool = player.take_damage(12)
	check("100 HP and invulnerability", first and not second and run.hp == 88, run.hp)
	check("telemetry counts accepted damage only", level.floor_metrics.damage_received == 12)
	check("damage numbers fire only for accepted damage", level.feedback_counts.damage == feedback_before + 1)
	await wait_frames(55)
	var third: bool = player.take_damage(12)
	check("invulnerability expires", third and run.hp == 76, run.hp)
	var hp_before_pickup: int = run.hp
	level.add_drop(player.global_position, "health", 25)
	await wait_frames(2)
	check("health pickup heals", run.hp > hp_before_pickup and run.hp <= run.max_hp)
	check("telemetry counts actual pickup healing", level.floor_metrics.healing == run.hp - hp_before_pickup)
	run.add_xp(10)
	await wait_frames(2)
	check("level-up pauses with three distinct offers", get_tree().paused and controller.hud.offered.size() == 3 and run.player_level == 2)
	var position_paused: Vector3 = player.global_position
	var attacks_paused: int = player.attacks_made
	Input.action_press("move_right")
	await wait_frames(15)
	Input.action_release("move_right")
	check("upgrade pause stops actors", player.global_position == position_paused and player.attacks_made == attacks_paused, {"from": position_paused, "to": player.global_position, "attacks_before": attacks_paused, "attacks_after": player.attacks_made})
	var choice: String = controller.hud.offered[0]
	controller.choose_upgrade(choice)
	check("upgrade resumes gameplay", not get_tree().paused and run.upgrades.get(choice, 0) == 1)
	check("telemetry records chosen upgrade", level.floor_metrics.upgrades == 1 and level.floor_metrics.upgrade_ids.has(choice))
	controller.open_pause()
	await wait_frames(2)
	check("pause menu", get_tree().paused and controller.hud.overlay_kind == "pause")
	controller.resume_run()
	check("resume menu", not get_tree().paused)
	# Telegraph resolves after the wind-up and rechecks distance/line of sight.
	var telegraph_enemy = level.enemies[0]
	var original_enemy_position: Vector3 = telegraph_enemy.global_position
	telegraph_enemy.global_position = player.global_position + Vector3(0.7, 0, 0)
	telegraph_enemy.contact_cooldown = 0.0
	var hp_before_telegraph: int = run.hp
	telegraph_enemy._rogue_physics(0.01)
	check("windup precedes damage", telegraph_enemy.windup_remaining > 0.0 and run.hp == hp_before_telegraph and is_instance_valid(telegraph_enemy.telegraph))
	telegraph_enemy.global_position = original_enemy_position
	telegraph_enemy._rogue_physics(0.8)
	check("dodged telegraph does not damage player", run.hp == hp_before_telegraph and telegraph_enemy.windup_remaining == 0.0)
	telegraph_enemy.global_position = player.global_position + Vector3(0.7, 0, 0)
	telegraph_enemy.contact_cooldown = 0.0
	player.invulnerability = 0.0
	telegraph_enemy._rogue_physics(0.01)
	telegraph_enemy._rogue_physics(0.8)
	check("landed telegraph deals actual contact damage", run.hp < hp_before_telegraph)
	telegraph_enemy.global_position = original_enemy_position
	# Actual timed automatic attack -> enemy death -> XP pickup.
	run.damage = 1000
	run.attack_range = 1.5
	var target = level.enemies[0]
	target.global_position = player.global_position + Vector3(0.7, 0, 0)
	target.health = 1
	var enemy_count_before := level.enemies.size()
	var attacks_before: int = player.attacks_made
	await wait_frames(50)
	if controller.hud.overlay_kind == "upgrade":
		controller.choose_upgrade(controller.hud.offered[0])
	check("automatic attack kills and drops XP", level.enemies.size() < enemy_count_before and player.attacks_made > attacks_before and (run.xp > 0 or run.pending_upgrades > 0 or run.player_level > 2))
	check("strike and death feedback follow real hits", level.feedback_counts.strike > 0 and level.feedback_counts.death > 0)
	# Exercise real death signal and terminal stop.
	run.hp = 1
	player.invulnerability = 0.0
	player.take_damage(100)
	await wait_frames(2)
	check("death stops run", run.ended and get_tree().paused and controller.hud.overlay_kind == "end" and not level.combat_active)
	get_tree().paused = false
	test_game.queue_free()
	await wait_frames(2)
	# Exercise all three real exit signals with controlled floor clears.
	LevelManager.begin_roguelite(101)
	test_game = load("res://game.tscn").instantiate()
	add_child(test_game)
	controller = test_game.rogue_controller
	run = controller.run
	for floor_number in range(1, 4):
		level = test_game.level
		check("floor reached %d" % floor_number, run.floor_number == floor_number)
		for enemy in level.enemies.duplicate():
			enemy.take_damage(99999)
		await wait_frames(2)
		check("exit activates after clear %d" % floor_number, level.exit_active and level.enemies.is_empty())
		check("exit unlock feedback fires once %d" % floor_number, level.feedback_counts.unlock == 1)
		level.player.global_position = level.grid.cell_to_world(level.exit_cell)
		await wait_frames(3)
		# Queued levels are resolved before the next floor can run.
		while controller.hud.overlay_kind == "upgrade":
			controller.choose_upgrade(controller.hud.offered[0])
	check("floor three victory", run.ended and get_tree().paused and controller.hud.overlay_kind == "end" and LevelManager.profile.wins == saved_wins + 1)
	check("per-floor measurements finalized once", run.floor_results.size() == 3 and run.floor_results.all(func(m): return m.outcome == "cleared" and m.kills == m.spawned))
