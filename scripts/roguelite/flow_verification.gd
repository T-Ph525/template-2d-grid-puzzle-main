extends Node
## Tests normal GameFlow transitions without debugger suspension.
var result: Dictionary = {}
var completed: bool = false
var records: Array = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	LevelManager.enable_test_mode()
	call_deferred("_run")

func _check(label: String, passed: bool, detail: Variant = null) -> void:
	records.append({"name": label, "passed": passed, "detail": detail, "frame": Engine.get_process_frames()})

func _settle() -> bool:
	for i in 180:
		await get_tree().process_frame
		if not GameFlow._busy:
			return true
	return false

func _run() -> void:
	# Keep this test observer alive while GameFlow replaces current_scene.
	get_tree().current_scene = null
	GameFlow.start_roguelite(42)
	var settled: bool = await _settle()
	_check("start flow settled", settled)
	var game = get_tree().current_scene
	if game == null or not game.has_node("Roguelite"):
		_finish()
		return
	var controller = game.rogue_controller
	var before: Dictionary = controller.describe_run()
	_check("new test run", before.seed == 42 and before.floor == 1 and before.hp == 100)
	var hit: bool = game.level.player.take_damage(12)
	_check("restart fixture damaged", hit and controller.run.hp == 88)
	controller.restart_run()
	settled = await _settle()
	game = get_tree().current_scene
	controller = game.rogue_controller
	var after: Dictionary = controller.describe_run()
	_check("restart same seed resets run", settled and after.seed == 42 and after.hp == 100 and after.floor == 1 and after.level == 1 and after.upgrades.is_empty(), after)
	controller.open_pause()
	_check("normal pause overlay", get_tree().paused and controller.hud.overlay_kind == "pause")
	controller.resume_run()
	_check("normal resume", not get_tree().paused)
	controller.open_pause()
	controller.return_to_menu()
	settled = await _settle()
	_check("paused return to menu", settled and get_tree().current_scene.name == "MainMenu" and not get_tree().paused)
	_check("flow tests preserve real profile", LevelManager.test_profile_status().real_unchanged)
	_finish()

func _finish() -> void:
	var failures: Array = []
	for record: Dictionary in records:
		if not record.passed:
			failures.append(record)
	result = {"records": records, "checks": records.size(), "failures": failures, "profile": LevelManager.test_profile_status()}
	completed = true
	print("GRIDKIT_FLOW_RESULTS " + JSON.stringify(result))
