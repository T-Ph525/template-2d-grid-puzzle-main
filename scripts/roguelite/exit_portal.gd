extends Node3D

## Animated exit gate. Level calls set_active() when every hostile is gone; the exit is still
## triggered by the existing cell-arrival rule, so this script is presentation only.

var active: bool = false
var _time: float = 0.0
var _veil: MeshInstance3D
var _inner: MeshInstance3D
var _gem: Node3D
var _shards: Node3D
var _light: OmniLight3D
var _veil_material: StandardMaterial3D
var _inner_material: StandardMaterial3D
var _gem_material: StandardMaterial3D

func _ready() -> void:
	_veil = get_node_or_null("Veil") as MeshInstance3D
	_inner = get_node_or_null("InnerRing") as MeshInstance3D
	_gem = get_node_or_null("Gem") as Node3D
	_shards = get_node_or_null("Shards") as Node3D
	_light = get_node_or_null("PortalLight") as OmniLight3D
	if _veil != null:
		_veil_material = _veil.material_override as StandardMaterial3D
	if _inner != null and _inner.material_override != null:
		_inner.material_override = _inner.material_override.duplicate()
		_inner_material = _inner.material_override as StandardMaterial3D
	if _gem != null and _gem is MeshInstance3D and _gem.material_override != null:
		_gem.material_override = _gem.material_override.duplicate()
		_gem_material = _gem.material_override as StandardMaterial3D
	_apply_state()

func set_active(value: bool) -> void:
	active = value
	if is_inside_tree():
		_apply_state()

func _apply_state() -> void:
	if _veil != null:
		_veil.visible = active
	if _inner != null:
		_inner.visible = active
	if _gem != null:
		_gem.visible = active
	if _veil_material != null:
		_veil_material.albedo_color = Color(0.26, 0.95, 0.88, 0.46 if active else 0.04)
		_veil_material.emission_energy_multiplier = 2.4 if active else 0.0
	if _light != null:
		_light.light_energy = 1.15 if active else 0.0
	if _inner != null:
		_inner.scale = Vector3.ONE * (1.0 if active else 0.82)
	if _inner_material != null:
		_inner_material.emission_energy_multiplier = 2.6 if active else 0.22
		_inner_material.albedo_color = Color("#3ca89f") if active else Color("#18292c")
	if _gem_material != null:
		_gem_material.emission_energy_multiplier = 2.6 if active else 0.3
	if _shards != null:
		_shards.visible = active

func _process(delta: float) -> void:
	_time += delta
	if _inner != null:
		_inner.rotation.z += delta * (0.55 if active else 0.12)
		var pulse := 1.0 + sin(_time * 2.6) * (0.04 if active else 0.015)
		_inner.scale = Vector3.ONE * pulse
	if _shards != null:
		_shards.rotation.y += delta * (1.3 if active else 0.2)
	if _gem != null:
		_gem.position.y = 1.02 + sin(_time * 1.8) * (0.05 if active else 0.015)
		_gem.rotation.y += delta * 0.9