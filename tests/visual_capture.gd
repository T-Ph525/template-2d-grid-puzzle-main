extends Node

## Reproducible visual evidence for the roguelite vertical slice.
## Run this scene explicitly, then inspect docs/screenshots/roguelite_capture.png.
const OUTPUT_PATH := "user://roguelite_capture.png"

func _ready() -> void:
	LevelManager.enable_test_mode()
	OS.set_environment("GRIDKIT_CAPTURE_PATH", OUTPUT_PATH)
	GameFlow.start_roguelite(42)
