extends RefCounted
## Versioned, type-checked settings/progress. Atomic replacement preserves the previous save.
const SAVE_PATH := "user://gridkit_profile.cfg"
const TEST_SAVE_PATH := "user://gridkit_test_profile.cfg"
static var test_process: bool = false
var _test_profile: bool = false

func _init(for_testing: bool = false) -> void:
	_test_profile = for_testing

static func enable_test_process() -> void:
	# Deliberately one-way for the lifetime of the game process.
	test_process = true

func active_path() -> String:
	return TEST_SAVE_PATH if test_process or _test_profile else SAVE_PATH

var best_floor: int = 0
var wins: int = 0
var settings: Dictionary = {}

func load_profile() -> void:
	var path := active_path()
	best_floor = 0
	wins = 0
	settings = {}
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	if cfg.get_value("profile", "version", 0) != 1:
		return
	best_floor = _integer(cfg.get_value("profile", "best_floor", 0), 0, 3, 0)
	wins = _integer(cfg.get_value("profile", "wins", 0), 0, 1000000, 0)
	for key in ["cam_view", "move_mode", "player_visual"]:
		settings[key] = _integer(cfg.get_value("settings", key, 0), 0, 1, 0)
	var select: Variant = cfg.get_value("settings", "level_select_enabled", true)
	settings["level_select_enabled"] = select if select is bool else true
	for bus in ["Master", "Music", "SFX"]:
		var value: Variant = cfg.get_value("audio", bus, 1.0)
		settings[bus] = clampf(float(value), 0.0, 1.0) if (value is float or value is int) and is_finite(float(value)) else 1.0

static func _integer(value: Variant, low: int, high: int, default_value: int) -> int:
	if not (value is int or value is float) or not is_finite(float(value)):
		return default_value
	return clampi(int(value), low, high)

func save_profile() -> bool:
	var path := active_path()
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "version", 1)
	cfg.set_value("profile", "best_floor", best_floor)
	cfg.set_value("profile", "wins", wins)
	for key in ["cam_view", "move_mode", "player_visual", "level_select_enabled"]:
		if settings.has(key):
			cfg.set_value("settings", key, settings[key])
	for bus in ["Master", "Music", "SFX"]:
		cfg.set_value("audio", bus, settings.get(bus, 1.0))
	var temporary := path + ".tmp"
	if cfg.save(temporary) != OK:
		push_warning("GridKit: could not write profile")
		return false
	var error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	if error != OK:
		push_warning("GridKit: could not replace profile")
	return error == OK
