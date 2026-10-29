extends Node
## Run this scene explicitly for safe manual/runtime-tool playtests.
func _ready() -> void:
	LevelManager.enable_test_mode()
	# Keep the launch seed deterministic, without changing normal menu behavior.
	GameFlow.start_roguelite(42)
