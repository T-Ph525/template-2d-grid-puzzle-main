extends Node
## Observation/input-only playtest bot. Never changes HP, damage, XP, enemies or positions.
## Launch this explicit test scene. Results distinguish normal victories, deaths and timeouts.
@export var seeds: Array[int] = [42, 101, 2026, 7, 73, 31415]
const DIRS := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const ACTIONS := ["move_up", "move_down", "move_left", "move_right"]
var game
var controller
var results: Array = []
var completed: bool = false
var seed_index: int = 0
var elapsed: float = 0.0
var floors_seen: Array = []
var upgrades_chosen: Array = []
var start_frame: int = 0
var phase: String = "starting"
var _wait: float = 0.0
@export var diagnostic_logging: bool = false
@export var hold_seed101_stall: bool = false
var diagnostic_held: bool = false
var frame_trace: Array = []
var _stalled_samples: int = 0
var diagnostics: Array = []
var _diag_delay: float = 0.0
var _last_position: Vector3 = Vector3.ZERO
var _chosen_action: int = -1
var _path_debug: Dictionary = {}
var _wall_start_ms: int = 0
var _last_attack_count: int = 0
var _last_enemy_count: int = 0
var _has_waypoint: bool = false
var _waypoint := Vector2i.ZERO
var _waypoint_floor: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	LevelManager.enable_test_mode()
	if hold_seed101_stall:
		diagnostic_logging = true
	_start()

func _start() -> void:
	_release()
	_has_waypoint = false
	LevelManager.begin_roguelite(seeds[seed_index])
	game = load("res://game.tscn").instantiate()
	game.name = "BotGame"
	add_child(game)
	controller = game.rogue_controller
	elapsed = 0.0
	floors_seen = [1]
	upgrades_chosen.clear()
	start_frame = Engine.get_physics_frames()
	phase = "playing"
	_wall_start_ms = Time.get_ticks_msec()
	_diag_delay = 0.0
	_last_position = game.level.player.global_position
	_last_attack_count = 0
	_last_enemy_count = game.level.enemies.size()

func _physics_process(delta: float) -> void:
	if completed or diagnostic_held:
		return
	if phase == "between":
		_wait -= delta
		if _wait <= 0.0:
			_start()
		return
	var run = controller.run
	if run.ended:
		_record("victory" if run.hp > 0 and run.floor_number == 3 else "death")
		return
	if not floors_seen.has(run.floor_number):
		floors_seen.append(run.floor_number)
	if controller.hud.overlay_kind == "upgrade":
		_release()
		var selected: String = controller.hud.offered[0]
		for preference in ["damage", "haste", "health", "armor", "range", "speed"]:
			if controller.hud.offered.has(preference):
				selected = preference
				break
		upgrades_chosen.append(selected)
		controller.choose_upgrade(selected)
		return
	if get_tree().paused:
		return
	elapsed += delta
	_diagnostic_sample(delta)
	if elapsed >= 240.0:
		_record("timeout")
		return
	var level: Level = game.level
	var player = level.player
	var position: Vector3 = player.global_position
	var cell := level.grid.world_to_cell(position)
	var closest: Node3D = null
	var distance := 999.0
	for enemy in level.enemies:
		var d: float = position.distance_to(enemy.global_position)
		if d < distance:
			distance = d
			closest = enemy
	var action := -1
	if closest != null and distance < 1.2 and level.has_line_of_sight(position, closest.global_position):
		_has_waypoint = false
		# Choose a collision-safe escape direction; prefer open room over a dead end.
		var best := -99999.0
		for i in 4:
			var offset: Vector3 = Vector3(DIRS[i].x, 0, DIRS[i].y) * 0.6
			var next := position + offset
			if not _body_clear(level, next) or not level.has_line_of_sight(position, next):
				continue
			var score := 0.0
			for enemy in level.enemies:
				var d: float = next.distance_to(enemy.global_position)
				score -= 3.0 / maxf(d * d, 0.02)
			var next_cell := level.grid.world_to_cell(next)
			for direction: Vector2i in DIRS:
				if level.walkable(next_cell + direction):
					score += 0.1
			if score > best:
				best = score
				action = i
	elif closest != null and distance <= controller.run.attack_range * 0.9 and level.has_line_of_sight(position, closest.global_position):
		_has_waypoint = false
		action = -1
	else:
		var destination := level.exit_cell
		if closest != null:
			destination = level.grid.world_to_cell(closest.global_position)
		# Prefer accessible XP or healing if nearby.
		var best_drop := 999.0
		for drop: Dictionary in level.drops:
			if drop.kind == "health" and run.hp >= run.max_hp:
				continue
			var d: float = position.distance_to(drop.node.global_position)
			if d < best_drop and (closest == null or d < 3.0):
				best_drop = d
				destination = level.grid.world_to_cell(drop.node.global_position)
		action = _path_action(level, cell, destination, position)
	_chosen_action = action
	if diagnostic_logging and run.seed_value == 101 and elapsed > 30.0:
		frame_trace.append({"frame": Engine.get_physics_frames(), "sim": elapsed, "player": player.global_position, "action": action, "path": _path_debug.duplicate(), "enemies": level.enemies.map(func(e): return {"name": e.name, "pos": e.global_position, "velocity": e.velocity})})
		if frame_trace.size() > 120:
			frame_trace.pop_front()
	_release()
	if action >= 0:
		Input.action_press(ACTIONS[action])

func _body_clear(level: Level, position: Vector3) -> bool:
	for offset in [Vector3.ZERO, Vector3(0.34, 0, 0), Vector3(-0.34, 0, 0), Vector3(0, 0, 0.34), Vector3(0, 0, -0.34)]:
		if not level.walkable(level.grid.world_to_cell(position + offset)):
			return false
	return true

func _path_action(level: Level, start: Vector2i, goal: Vector2i, position: Vector3) -> int:
	_path_debug = {"start": start, "goal": goal}
	if _has_waypoint and _waypoint_floor == controller.run.floor_number and level.walkable(_waypoint):
		var waypoint_world := level.grid.cell_to_world(_waypoint)
		if position.distance_to(waypoint_world) > 0.09:
			_path_debug["committed"] = _waypoint
			return _axis(waypoint_world - position)
	_has_waypoint = false
	if start == goal:
		var goal_center := level.grid.cell_to_world(goal)
		return _axis(goal_center - position) if position.distance_to(goal_center) > 0.12 else -1
	var queue: Array[Vector2i] = [start]
	var parent: Dictionary = {start: start}
	var cursor := 0
	while cursor < queue.size() and not parent.has(goal):
		var cell := queue[cursor]
		cursor += 1
		for direction: Vector2i in DIRS:
			var next := cell + direction
			if level.walkable(next) and not parent.has(next):
				parent[next] = cell
				queue.append(next)
	if not parent.has(goal):
		return -1
	var next_step := goal
	while parent[next_step] != start:
		next_step = parent[next_step]
	var center := level.grid.cell_to_world(start)
	_path_debug["next"] = next_step
	_path_debug["center"] = center
	# Complete a cell-center waypoint before replanning a moving target.
	# Rounding into an adjacent cell is not the same as reaching its center.
	var cross_offset: float = absf(position.z - center.z) if next_step.x != start.x else absf(position.x - center.x)
	_waypoint = start if cross_offset > 0.09 else next_step
	_waypoint_floor = controller.run.floor_number
	_has_waypoint = true
	_path_debug["committed"] = _waypoint
	return _axis(level.grid.cell_to_world(_waypoint) - position)

func _axis(offset: Vector3) -> int:
	if absf(offset.x) > absf(offset.z):
		return 3 if offset.x > 0.0 else 2
	return 1 if offset.z > 0.0 else 0

func _release() -> void:
	for action in ACTIONS:
		Input.action_release(action)

func _record(outcome: String) -> void:
	_release()
	var run = controller.run
	results.append({"seed": seeds[seed_index], "outcome": outcome, "seconds": snappedf(elapsed, 0.01), "floors": floors_seen.duplicate(), "floor": run.floor_number, "hp": run.hp, "level": run.player_level, "enemies_left": game.level.enemies.size(), "upgrades": run.upgrades.duplicate(), "start_physics": start_frame, "end_physics": Engine.get_physics_frames(), "floor_metrics": run.floor_results.duplicate(true) + ([game.level.measurements("timeout")] if outcome == "timeout" else []), "real_elapsed_seconds": snappedf((Time.get_ticks_msec() - _wall_start_ms) / 1000.0, 0.001), "method": "normal stats, observation + Input actions, automatic combat, no controlled clears"})
	game.level.stop_combat()
	game.queue_free()
	get_tree().paused = false
	seed_index += 1
	if seed_index >= seeds.size():
		completed = true
		phase = "finished"
		print("GRIDKIT_BOT_RESULTS " + JSON.stringify({"runs": results, "profile": LevelManager.test_profile_status()}))
	else:
		phase = "between"
		_wait = 0.1

func status() -> Dictionary:
	return {"completed": completed, "phase": phase, "seed": seeds[mini(seed_index, seeds.size() - 1)], "elapsed": elapsed, "results": results, "run": controller.describe_run() if phase == "playing" else {}, "profile": LevelManager.test_profile_status()}

func _diagnostic_sample(delta: float) -> void:
	if not diagnostic_logging:
		return
	_diag_delay -= delta
	if _diag_delay > 0.0:
		return
	_diag_delay = 1.0
	var level: Level = game.level
	var player = level.player
	var positions: Array = []
	for enemy in level.enemies:
		var goal: Vector3 = level.chase_target(enemy.global_position)
		positions.append({"name": enemy.name, "pos": enemy.global_position, "cell": level.grid.world_to_cell(enemy.global_position), "goal": goal, "velocity": enemy.velocity, "hp": enemy.health, "windup": enemy.windup_remaining, "cost": level._distance_field.get(level.grid.world_to_cell(enemy.global_position), -1), "los": level.has_line_of_sight(enemy.global_position, player.global_position), "slides": enemy.get_slide_collision_count()})
	var sample := {"seed": controller.run.seed_value, "sim_seconds": snappedf(elapsed, 0.01), "wall_seconds": (Time.get_ticks_msec() - _wall_start_ms) / 1000.0, "floor": controller.run.floor_number, "player": player.global_position, "player_cell": level.grid.world_to_cell(player.global_position), "player_velocity": player.velocity, "player_slides": player.get_slide_collision_count(), "moved_since_sample": player.global_position.distance_to(_last_position), "action": _chosen_action, "path": _path_debug.duplicate(), "hp": controller.run.hp, "xp": controller.run.xp, "level": controller.run.player_level, "attacks": player.attacks_made, "hits": player.hits_taken, "enemy_count": level.enemies.size(), "exit_active": level.exit_active, "feedback": level.feedback_counts.duplicate(), "enemies": positions}
	if diagnostics.size() < 800:
		diagnostics.append(sample)
	if controller.run.seed_value == 101 and elapsed > 35.0 and int(elapsed) % 20 == 0:
		print("SEED101_TRACE " + JSON.stringify(sample))
	if controller.run.seed_value == 101 and elapsed > 45.0 and sample.moved_since_sample < 0.02 and sample.attacks == _last_attack_count and sample.enemy_count == _last_enemy_count:
		_stalled_samples += 1
	else:
		_stalled_samples = 0
	_last_attack_count = sample.attacks
	_last_enemy_count = sample.enemy_count
	_last_position = player.global_position
	if hold_seed101_stall and _stalled_samples >= 5:
		diagnostic_held = true
		_release()
		get_tree().paused = true
		var f := FileAccess.open("res://tests/seed101-stall-trace.json", FileAccess.WRITE)
		f.store_string(JSON.stringify({"status": status(), "samples": diagnostics.filter(func(s): return s.seed == 101).slice(-8), "frames": frame_trace}, "\t"))
		f.close()
		print("SEED101_STALL_CAPTURED")

func diagnostic_tail(count: int = 3) -> Array:
	return diagnostics.slice(maxi(0, diagnostics.size() - count))
