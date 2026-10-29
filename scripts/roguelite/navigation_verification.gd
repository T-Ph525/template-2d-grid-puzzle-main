extends Node
const RunState := preload("res://scripts/roguelite/run_state.gd")
var completed: bool = false
var checks: Array = []
var result: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	LevelManager.enable_test_mode()
	call_deferred("_run")

func check(label: String, passed: bool, detail: Variant = null) -> void:
	checks.append({"name": label, "passed": passed, "detail": detail, "physics": Engine.get_physics_frames()})

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func make_level(map: Array) -> Level:
	var tick := TickManager.new()
	tick.set_process(false)
	add_child(tick)
	var level := Level.new()
	level.rogue_run = RunState.new()
	add_child(level)
	level.build(map, Grid.new(String(map[0]).length(), map.size()), tick)
	level.player.set_physics_active(true)
	level.player.set_physics_process(false)
	level.player.invulnerability = 999.0
	level._rebuild_navigation()
	return level

func _run() -> void:
	var bot = load("res://scripts/roguelite/playtest_bot.gd").new()
	bot.controller = {"run": {"floor_number": 2}}
	var level := Level.new()
	level.grid = Grid.new(9, 8)
	var position := Vector3(1.066667, 0, 3.466666)
	var actions: Array = []
	for i in 30:
		var destination := Vector2i(4, 4 if i % 2 == 0 else 3)
		var action: int = bot._path_action(level, level.grid.world_to_cell(position), destination, position)
		actions.append(action)
		if action >= 0:
			var direction: Vector2i = bot.DIRS[action]
			position += Vector3(direction.x, 0, direction.y) * (4.0 / 60.0)
	check("seed101 moving-target waypoint regression", position.x > 1.5 and actions[0] == actions[1], {"end": position, "actions": actions})
	bot.free()
	level.free()
	var open_map := ["#########", "#       #", "#       #", "#@  E  >#", "#       #", "#       #", "#########"]
	level = make_level(open_map)
	var enemy = level.enemies[0]
	enemy.global_position = Vector3(4, 0, 3.533717)
	var before: Vector3 = enemy.global_position
	for i in 120:
		level.player.global_position = Vector3(1.066667, 0, 3.466666 if i % 2 == 0 else 3.533333)
		level._rebuild_navigation()
		await frames(1)
	check("enemy approaches target jittering across row boundary", enemy.global_position.x < 3.0, {"from": before, "to": enemy.global_position})
	level.stop_combat()
	level.queue_free()
	await frames(2)
	var corridor := ["###########", "#@        #", "######### #", "#         #", "# #########", "# E E E  >#", "###########"]
	level = make_level(corridor)
	var initial: Array = level.enemies.map(func(e): return e.global_position)
	await frames(1100)
	var distances: Array = level.enemies.map(func(e): return e.global_position.distance_to(level.player.global_position))
	check("three enemies traverse winding one-cell corridor", distances.all(func(d): return d < 1.6), {"initial": initial, "distances": distances})
	level.stop_combat()
	level.queue_free()
	await frames(2)
	var blocked := ["#########", "#@ D E >#", "#########"]
	level = make_level(blocked)
	enemy = level.enemies[0]
	var blocked_position: Vector3 = enemy.global_position
	await frames(120)
	check("unreachable enemy waits without crossing closed door", not level._distance_field.has(Vector2i(5, 1)) and enemy.global_position.distance_to(blocked_position) < 0.1)
	level._key_collected[0] = true
	level._update_channels()
	await frames(240)
	check("enemy replans when door makes target reachable", enemy.global_position.distance_to(level.player.global_position) < 1.5, enemy.global_position)
	level.stop_combat()
	level.queue_free()
	await frames(2)
	var controller_script = load("res://scripts/roguelite/run_controller.gd")
	var disconnected := ["#######", "#@#E >#", "#######"]
	var safe_map: Array = controller_script.validated_map(disconnected, 1)
	check("disconnected procedural encounter replaced before spawning", load("res://scripts/roguelite/dungeon_generator.gd").validate(safe_map).get("valid", false) and safe_map != disconnected)
	var sealed := ["#########", "#@ D E >#", "#########"]
	check("unresolved procedural gate cannot softlock run", controller_script.validated_map(sealed, 1) != sealed)
	level = make_level(open_map)
	enemy = level.enemies[0]
	await frames(5)
	level._add_wall(Vector2i(3, 3))
	level._rebuild_navigation()
	await frames(300)
	check("enemy replans around newly added obstacle", enemy.global_position.distance_to(level.player.global_position) < 1.5, enemy.global_position)
	level.stop_combat()
	level.queue_free()
	await frames(2)
	var crowd := ["#########", "#       #", "#       #", "#@  EE >#", "#       #", "#       #", "#########"]
	level = make_level(crowd)
	level.enemies[0].global_position = Vector3(4, 0, 3)
	level.enemies[1].global_position = Vector3(4.02, 0, 3.05)
	await frames(45)
	check("open-room peer steering separates enemies", level.enemies[0].global_position.distance_to(level.enemies[1].global_position) > 0.06)
	await frames(180)
	check("peer steering preserves pursuit progress", level.enemies.all(func(e): return e.global_position.distance_to(level.player.global_position) < 1.5))
	level.stop_combat()
	level.queue_free()
	await frames(2)
	var guards := ["#############", "#           #", "#           #", "#@        T>#", "#           #", "#############"]
	level = make_level(guards)
	enemy = level.enemies[0]
	var guard_position: Vector3 = enemy.global_position
	await frames(30)
	check("distant sentry holds its room", not enemy.awake and enemy.global_position.distance_to(guard_position) < 0.01)
	level.player.global_position = Vector3(6, 0, 3)
	level._rebuild_navigation()
	await frames(20)
	check("nearby sentry activates once", enemy.awake and level.floor_metrics.guard_activations == 1)
	level.stop_combat()
	level.queue_free()
	await frames(2)
	result = {"checks": checks.size(), "failures": checks.filter(func(c): return not c.passed), "records": checks, "profile": LevelManager.test_profile_status()}
	completed = true
	print("GRIDKIT_NAV_RESULTS " + JSON.stringify(result))
