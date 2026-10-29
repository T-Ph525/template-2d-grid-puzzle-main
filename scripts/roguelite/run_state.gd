extends RefCounted
## A run's data survives floor swaps; Puzzle preferences are never changed.
const UPGRADES := {
	"damage": {"title": "Sharpen", "detail": "+6 attack damage"},
	"haste": {"title": "Quick hands", "detail": "10% faster attacks"},
	"health": {"title": "Vitality", "detail": "+25 max HP and heal 25"},
	"speed": {"title": "Fleet feet", "detail": "+0.35 movement speed"},
	"range": {"title": "Long reach", "detail": "+0.2 attack range"},
	"armor": {"title": "Iron skin", "detail": "+2 damage reduction"},
}
var seed_value: int = 1
var floor_number: int = 1
var hp: int = 100
var max_hp: int = 100
var damage: int = 22
var attack_interval: float = 0.65
var movement_speed: float = 4.0
var attack_range: float = 1.5
var damage_reduction: int = 0
var xp: int = 0
var player_level: int = 1
var pending_upgrades: int = 0
var upgrades: Dictionary = {}
var ended: bool = false
var rng := RandomNumberGenerator.new()

func initialize(value: int) -> void:
	seed_value = value
	rng.seed = value

func xp_required() -> int:
	return 10 + (player_level - 1) * 5

func add_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_required():
		xp -= xp_required()
		player_level += 1
		pending_upgrades += 1

func choices() -> Array[String]:
	var pool: Array = UPGRADES.keys()
	var result: Array[String] = []
	for i in 3:
		var index := rng.randi_range(0, pool.size() - 1)
		result.append(pool[index])
		pool.remove_at(index)
	return result

func apply_upgrade(id: String) -> bool:
	if pending_upgrades <= 0 or not UPGRADES.has(id):
		return false
	pending_upgrades -= 1
	upgrades[id] = int(upgrades.get(id, 0)) + 1
	match id:
		"damage": damage += 6
		"haste": attack_interval = maxf(0.18, attack_interval * 0.9)
		"health":
			max_hp += 25
			hp = mini(max_hp, hp + 25)
		"speed": movement_speed = minf(7.0, movement_speed + 0.35)
		"range": attack_range = minf(3.5, attack_range + 0.2)
		"armor": damage_reduction += 2
	return true

# Runtime-only measurements, never serialized into the player profile.
var floor_results: Array = []
