extends Node

## Puzzle-mode evidence: the original first level, original camera and materials.
func _ready() -> void:
	LevelManager.enable_test_mode()
	OS.set_environment("GRIDKIT_CAPTURE_PATH", "user://puzzle_capture.png")
	LevelManager.game_mode = "puzzle"
	LevelManager.start(0)
	GameFlow.goto("game")