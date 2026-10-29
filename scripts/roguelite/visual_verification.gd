extends Node

## Focused vertical-slice art verification. Controlled enemy deaths are used only to expose
## the clear-state portal and death pose; they are not normal-play victory evidence.
var records: Array = []
var failures: Array = []
var captures: Array = []
var performance: Dictionary = {}
var game
var controller
var run
var level
var player
var player_visual

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func check(label: String, passed: bool, detail: Variant = null) -> void:
	var record := {"name": label, "passed": passed, "detail": detail}
	records.append(record)
	if not passed:
		failures.append(record)

func _frames(count: int) -> void:
	for index in count:
		await get_tree().process_frame

func _physics_frames(count: int) -> void:
	for index in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "user://%s.png" % label
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	if error == OK:
		captures.append({"name": label, "path": ProjectSettings.globalize_path(path), "size": image.get_size()})
	else:
		check("capture " + label, false, error_string(error))

func _run() -> void:
	LevelManager.enable_test_mode()
	LevelManager.begin_roguelite(42)
	game = load("res://game.tscn").instantiate()
	add_child(game)
	await _frames(12)
	controller = game.rogue_controller
	run = controller.run
	level = game.level
	player = level.player
	player_visual = player.get_node_or_null("Visual")
	check("player uses 3D actor visual", player_visual != null and player_visual is Node3D and player_visual.get("archetype") == "player")
	check("visual animation API is present", player_visual != null and player_visual.has_method("set_moving") and player_visual.has_method("play_windup") and player_visual.has_method("play_attack") and player_visual.has_method("play_hit") and player_visual.has_method("play_death"))
	await _physics_frames(6)
	check("player starts idle", player_visual.get_state_name() == "idle", player_visual.get_state_name())
	var chaser = level.enemies.filter(func(enemy): return not enemy.tank).front() if level.enemies.any(func(enemy): return not enemy.tank) else null
	var tank = level.enemies.filter(func(enemy): return enemy.tank).front() if level.enemies.any(func(enemy): return enemy.tank) else null
	check("shadow chaser distinct visual", chaser != null and chaser.get_node_or_null("Visual") != null and chaser.get_node("Visual").get("archetype") == "chaser")
	check("stone tank distinct visual", tank != null and tank.get_node_or_null("Visual") != null and tank.get_node("Visual").get("archetype") == "tank")
	await _capture("roguelite_visual_idle")

	var start: Vector3 = player.global_position
	Input.action_press("move_down")
	await _physics_frames(10)
	var moving_state: String = player_visual.get_state_name()
	var moved: bool = player.global_position.distance_to(start) > 0.35
	await _capture("roguelite_visual_move")
	Input.action_release("move_down")
	check("movement state and displacement", moved and moving_state == "move", {"distance": player.global_position.distance_to(start), "state": moving_state})
	await _physics_frames(4)

	var target = level.enemies[0]
	target.set_physics_process(false)
	target.awake = true
	target.global_position = player.global_position + Vector3(0.9, 0, 0)
	target.health = 1000
	player.attack_cooldown = 0.0
	player.invulnerability = 0.0
	var target_hp: int = target.health
	player._rogue_physics(0.01)
	check("attack state starts on the damaging frame", player_visual.get_state_name() == "attack" and target.health < target_hp, {"state": player_visual.get_state_name(), "hp": target.health})
	await _capture("roguelite_visual_attack")

	target.global_position = player.global_position + Vector3(0.8, 0, 0)
	target.contact_cooldown = 0.0
	target.windup_remaining = 0.0
	player.invulnerability = 0.0
	var hp_before_windup: int = run.hp
	target._rogue_physics(0.01)
	check("enemy windup delays damage", target.windup_remaining > 0.0 and run.hp == hp_before_windup and target.get_node("Visual").get_state_name() == "windup", {"state": target.get_node("Visual").get_state_name(), "windup": target.windup_remaining})
	await _capture("roguelite_visual_windup")
	target.global_position = player.global_position + Vector3(0.8, 0, 0)
	target._rogue_physics(0.9)
	check("enemy attack state after resolved windup", run.hp < hp_before_windup and target.get_node("Visual").get_state_name() == "attack", {"hp": run.hp, "state": target.get_node("Visual").get_state_name()})
	await _capture("roguelite_visual_enemy_attack")

	player.invulnerability = 0.0
	player.take_damage(5)
	check("player hit state", player_visual.get_state_name() == "hit", player_visual.get_state_name())
	await _capture("roguelite_visual_hit")
	await _sample_performance()
	check("draw-call budget for one floor", int(performance.get("avg_draw_calls", 99999)) <= 650, performance)

	var dying = level.enemies.filter(func(enemy): return enemy != target).front() if level.enemies.size() > 1 else target
	dying.set_physics_process(false)
	dying.take_damage(99999)
	check("enemy death state", dying.get("dead") and dying.get_node("Visual").get_state_name() == "death")
	await _capture("roguelite_visual_death")

	for enemy in level.enemies.duplicate():
		if is_instance_valid(enemy):
			enemy.take_damage(99999)
	await get_tree().create_timer(0.9).timeout
	var portal = level.exit_visual
	check("exit portal opens after clear", level.exit_active and portal != null and portal.get("active") == true)
	check("decorative base has no collision", level.get_node_or_null("DioramaBase") != null and _collision_count(level.get_node("DioramaBase")) == 0)
	var wall_collision = level.get_node_or_null("WallCollision")
	var wall_shapes := _collision_count(wall_collision) if wall_collision != null else 0
	check("wall collision bodies preserved", wall_shapes == level._rogue_wall_cells.size() and wall_shapes >= 20, {"shapes": wall_shapes, "cells": level._rogue_wall_cells.size()})
	var camera: Camera3D = game.camera
	var center: Vector3 = level.grid.center_world()
	check("three-quarter orthographic camera", camera.projection == Camera3D.PROJECTION_ORTHOGONAL and camera.position.y > 10.0 and camera.position.z > center.z + 5.0, {"position": camera.position, "size": camera.size, "center": center})
	var hud = game.get_node_or_null("SurvivalHUD")
	var top_bar = hud.get_node_or_null("HudRoot/TopBar") if hud != null else null
	var view := get_viewport().get_visible_rect().size
	check("HUD anchors fit viewport", top_bar != null and top_bar.size.x <= view.x + 1.0 and top_bar.size.y < view.y * 0.3, {"hud": top_bar.size if top_bar != null else Vector2.ZERO, "viewport": view})
	await _capture("roguelite_visual_clear")
	check("real profile unchanged", LevelManager.test_profile_status().real_unchanged, LevelManager.test_profile_status())

	player.invulnerability = 0.0
	run.hp = 1
	player.take_damage(999)
	check("player death state and terminal overlay", player_visual.get_state_name() == "death" and get_tree().paused and controller.hud.overlay_kind == "end")
	await _capture("roguelite_visual_player_death")
	get_tree().paused = false
	var result := {"checks": records.size(), "failures": failures, "records": records, "captures": captures, "performance": performance, "profile": LevelManager.test_profile_status()}
	var file := FileAccess.open("user://gridkit_visual_results.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "  "))
		file.close()
	print("GRIDKIT_VISUAL_RESULTS ", ProjectSettings.globalize_path("user://gridkit_visual_results.json"))
	await _frames(2)
	get_tree().quit()

func _collision_count(node: Node) -> int:
	var count := 0
	if node is CollisionShape3D:
		count += 1
	for child in node.get_children():
		count += _collision_count(child)
	return count

func _sample_performance() -> void:
	var fps_total := 0.0
	var draws_total := 0.0
	var primitives_total := 0.0
	var samples := 30
	var frame_start := Engine.get_process_frames()
	var start_usec := Time.get_ticks_usec()
	for index in samples:
		await get_tree().process_frame
		fps_total += Performance.get_monitor(Performance.TIME_FPS)
		draws_total += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		primitives_total += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var elapsed := maxf(0.001, (Time.get_ticks_usec() - start_usec) / 1000000.0)
	var measured_fps := float(Engine.get_process_frames() - frame_start) / elapsed
	performance = {
		"monitor_fps": snappedf(fps_total / samples, 0.01),
		"measured_fps": snappedf(measured_fps, 0.01),
		"sample_seconds": snappedf(elapsed, 0.001),
		"avg_draw_calls": snappedf(draws_total / samples, 0.01),
		"avg_primitives": snappedf(primitives_total / samples, 0.01),
		"node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"static_memory_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.01),
		"context": "combat, all hostiles present",
	}