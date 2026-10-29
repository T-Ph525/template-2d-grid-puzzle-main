extends Node3D
class_name RogueActorVisual

## Visual-only animation state machine for the procedural player, chaser and tank.
## Gameplay damage does not wait on these states; actors call them as feedback.

@export var archetype: String = "player"

const IDLE := "idle"
const MOVE := "move"
const WINDUP := "windup"
const ATTACK := "attack"
const HIT := "hit"
const DEATH := "death"

var state: String = IDLE
var moving: bool = false
var state_clock: float = 0.0
var state_duration: float = 0.0
var _time: float = 0.0
var _parts: Dictionary = {}
var _rest: Dictionary = {}
var _mesh_materials: Array = []
var _flash_material: StandardMaterial3D
var _flash_remaining: float = 0.0

func _ready() -> void:
	_cache_parts()
	_flash_material = StandardMaterial3D.new()
	_flash_material.albedo_color = Color(0.58, 1.0, 0.9)
	_flash_material.emission_enabled = true
	_flash_material.emission = Color(0.45, 1.0, 0.88)
	_flash_material.emission_energy_multiplier = 1.15
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

func _cache_parts() -> void:
	for part_name in ["Body", "Head", "Cape", "LeftArm", "RightArm", "LeftLeg", "RightLeg", "Weapon", "Tendrils", "Eyes"]:
		var node := find_child(part_name, true, false)
		if node is Node3D:
			_parts[part_name] = node
			_rest[part_name] = node.transform
	for node in find_children("*", "MeshInstance3D", true, false):
		if node.material_override != null and node.name != "ShadowDisc":
			_mesh_materials.append({mesh = node, material = node.material_override})

func set_moving(value: bool) -> void:
	moving = value
	if state != DEATH and state != WINDUP and state != ATTACK and state != HIT:
		_set_state(MOVE if moving else IDLE)

func face_direction(direction: Vector3) -> void:
	if absf(direction.x) + absf(direction.z) < 0.001:
		return
	rotation.y = atan2(direction.x, direction.z)

func play_windup(duration: float = 0.5) -> void:
	if state == DEATH:
		return
	_set_state(WINDUP, maxf(0.08, duration))

func play_attack(duration: float = 0.26) -> void:
	if state == DEATH:
		return
	_set_state(ATTACK, maxf(0.12, duration))

func play_hit() -> void:
	if state == DEATH:
		return
	_set_state(HIT, 0.17)
	_flash_remaining = 0.07
	_apply_flash(true)

func play_death() -> void:
	_set_state(DEATH, 999.0)
	_flash_remaining = 0.0
	_apply_flash(false)

func get_state_name() -> String:
	return state

func _set_state(next_state: String, duration: float = 0.0) -> void:
	state = next_state
	state_clock = 0.0
	state_duration = duration

func _apply_flash(active: bool) -> void:
	for entry in _mesh_materials:
		var mesh: MeshInstance3D = entry.mesh
		if is_instance_valid(mesh):
			mesh.material_override = _flash_material if active else entry.material

func _process(delta: float) -> void:
	_time += delta
	if _flash_remaining > 0.0:
		_flash_remaining -= delta
		if _flash_remaining <= 0.0:
			_apply_flash(false)
	if state == DEATH:
		state_clock += delta
		_reset_pose()
		_animate_death(clampf(state_clock / 0.7, 0.0, 1.0))
		return
	state_clock += delta
	if state != IDLE and state != MOVE and state_duration > 0.0 and state_clock >= state_duration:
		_set_state(MOVE if moving else IDLE)
	_reset_pose()
	_animate_state()

func _reset_pose() -> void:
	for part_name in _rest:
		var node: Node3D = _parts.get(part_name)
		if is_instance_valid(node):
			node.transform = _rest[part_name]

func _part(part_name: String) -> Node3D:
	return _parts.get(part_name) as Node3D

func _move_part(part_name: String, offset: Vector3) -> void:
	var node := _part(part_name)
	if node != null:
		node.position += offset

func _rotate_part(part_name: String, amount: Vector3) -> void:
	var node := _part(part_name)
	if node != null:
		node.rotation += amount

func _animate_state() -> void:
	var is_tank := archetype == "tank"
	var is_chaser := archetype == "chaser"
	var body := _part("Body")
	if body == null:
		return
	body.scale = Vector3.ONE
	var breathe_speed := 1.65 if is_tank else 2.35
	var breathe := sin(_time * breathe_speed) * (0.015 if is_tank else 0.011)
	_move_part("Body", Vector3(0, breathe, 0))
	_rotate_part("Head", Vector3(sin(_time * 1.2) * 0.025, 0, 0))
	_rotate_part("Cape", Vector3(sin(_time * 1.7) * 0.025, 0, 0))
	if is_chaser:
		_move_part("Body", Vector3(0, 0.028 + sin(_time * 2.2) * 0.04, 0))
		_rotate_part("Tendrils", Vector3(0, sin(_time * 1.5) * 0.22, sin(_time * 2.1) * 0.08))
		for index in 5:
			var wisp := find_child("Wisp%d" % index, true, false) as Node3D
			if wisp != null:
				wisp.rotation.z += sin(_time * 3.0 + index) * 0.12
	match state:
		MOVE:
			_animate_move(is_tank, is_chaser)
		WINDUP:
			_animate_windup(is_tank, is_chaser)
		ATTACK:
			_animate_attack(is_tank, is_chaser)
		HIT:
			_animate_hit()
		_:
			_animate_idle(is_tank, is_chaser)

func _animate_idle(is_tank: bool, is_chaser: bool) -> void:
	var sway := sin(_time * 1.7) * (0.018 if is_tank else 0.03)
	_rotate_part("LeftArm", Vector3(sway, 0, 0))
	_rotate_part("RightArm", Vector3(-sway, 0, 0))
	_rotate_part("Head", Vector3(0, sin(_time * 0.8) * 0.06, 0))
	if is_chaser:
		_rotate_part("LeftArm", Vector3(-0.18, 0, 0.45))
		_rotate_part("RightArm", Vector3(-0.18, 0, -0.45))

func _animate_move(is_tank: bool, is_chaser: bool) -> void:
	var phase := _time * (7.0 if is_tank else 10.0)
	var stride := 0.26 if is_tank else 0.48
	_rotate_part("Body", Vector3(0.06 if not is_chaser else 0.12, 0, sin(phase * 0.5) * 0.025))
	_rotate_part("LeftLeg", Vector3(sin(phase) * stride, 0, 0))
	_rotate_part("RightLeg", Vector3(-sin(phase) * stride, 0, 0))
	_rotate_part("LeftArm", Vector3(-sin(phase) * stride * 0.72, 0, 0))
	_rotate_part("RightArm", Vector3(sin(phase) * stride * 0.72, 0, 0))
	_rotate_part("Cape", Vector3(-0.12 - absf(sin(phase)) * 0.1, 0, sin(_time * 2.0) * 0.04))
	if is_chaser:
		_move_part("Body", Vector3(0, absf(sin(phase)) * 0.03, 0))
		_rotate_part("LeftArm", Vector3(-0.3, 0, 0.52))
		_rotate_part("RightArm", Vector3(-0.3, 0, -0.52))

func _animate_windup(is_tank: bool, is_chaser: bool) -> void:
	var progress := clampf(state_clock / maxf(0.08, state_duration), 0.0, 1.0)
	var pull := ease(progress, 0.35)
	_rotate_part("Body", Vector3(-0.12 * pull, 0, 0))
	if is_tank:
		_rotate_part("RightArm", Vector3(-1.15 * pull, 0, 0.2 * pull))
		_rotate_part("LeftArm", Vector3(-0.4 * pull, 0, -0.15 * pull))
	else:
		_rotate_part("RightArm", Vector3(-1.35 * pull, 0, -0.2 * pull))
		_rotate_part("Head", Vector3(-0.12 * pull, 0, 0))
	if is_chaser:
		_rotate_part("LeftArm", Vector3(-1.0 * pull, 0, 0.5))
		_rotate_part("RightArm", Vector3(-1.0 * pull, 0, -0.5))
	var eyes := _part("Eyes")
	if eyes != null:
		eyes.scale = Vector3.ONE * (1.0 + pull * 0.45)

func _animate_attack(is_tank: bool, is_chaser: bool) -> void:
	var progress := clampf(state_clock / maxf(0.12, state_duration), 0.0, 1.0)
	var swing := sin(progress * PI)
	_rotate_part("Body", Vector3(0.18 * swing, 0, 0))
	_rotate_part("Body", Vector3(0, -0.28 + progress * 0.58, 0))
	_rotate_part("RightArm", Vector3(-1.2 + progress * 2.1, 0, -0.45 * swing))
	_rotate_part("LeftArm", Vector3(0.25 * swing, 0, 0.25 * swing))
	_rotate_part("Weapon", Vector3(0, 0, -0.8 + progress * 1.7))
	if is_tank:
		_rotate_part("Body", Vector3(0.1 * swing, 0, 0))
		_rotate_part("RightArm", Vector3(-0.7 + progress * 1.4, 0, -0.2 * swing))
	if is_chaser:
		_rotate_part("LeftArm", Vector3(-1.1 + progress * 1.9, 0, 0.8 * swing))
		_rotate_part("RightArm", Vector3(-1.1 + progress * 1.9, 0, -0.8 * swing))

func _animate_hit() -> void:
	var shake := sin(state_clock * 85.0) * 0.08
	_rotate_part("Body", Vector3(0.18, 0, shake))
	_move_part("Body", Vector3(-shake * 0.12, 0, 0))
	_rotate_part("Head", Vector3(-0.14, 0, shake * 0.5))

func _animate_death(progress: float) -> void:
	var body := _part("Body")
	if body == null:
		return
	if archetype == "chaser":
		body.position.y += progress * 0.2
		body.scale = Vector3.ONE * (1.0 - progress * 0.82)
		body.rotation.y += progress * 1.6
	else:
		body.position.y -= progress * 0.28
		body.rotation.z += progress * 1.25
		body.scale = Vector3(1.0 - progress * 0.18, 1.0 - progress * 0.3, 1.0 - progress * 0.18)