extends RefCounted

## Short-lived feedback. Puzzle keeps the original unlit rings; the roguelite uses teal
## emissive arcs, shards and readable damage numbers. All tweens pause with their parent.

const RogueVisuals := preload("res://scripts/roguelite/roguelite_art.gd")

static func _is_rogue(parent) -> bool:
	return parent != null and parent.get("rogue_run") != null

static func _effect_material(color: Color, alpha: float = 0.9) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.8
	return material

static func ring(parent: Node3D, position: Vector3, color: Color, radius: float, duration: float, expanding: bool = true) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = maxf(0.02, radius - (0.05 if _is_rogue(parent) else 0.035))
	mesh.outer_radius = radius
	mesh.rings = 16
	mesh.ring_segments = 6
	visual.mesh = mesh
	var material: StandardMaterial3D = _effect_material(color) if _is_rogue(parent) else Visuals._flat(color)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	visual.material_override = material
	visual.position = Vector3(position.x, 0.065, position.z)
	visual.name = "CombatRing"
	parent.add_child(visual)
	var tween := visual.create_tween()
	tween.set_parallel(true)
	if expanding:
		visual.scale = Vector3(0.45, 1, 0.45)
		tween.tween_property(visual, "scale", Vector3(1.4, 1, 1.4), duration)
	else:
		visual.scale = Vector3(1.1, 1, 1.1)
		tween.tween_property(visual, "scale", Vector3.ONE, duration)
	tween.tween_property(material, "albedo_color:a", 0.0 if expanding else 0.5, duration)
	tween.chain().tween_callback(visual.queue_free)
	return visual

static func number(parent: Node3D, position: Vector3, amount: int, color: Color, prefix: String = "") -> void:
	var label := Label3D.new()
	label.name = "DamageNumber"
	label.text = prefix + str(amount)
	label.font_size = 64
	label.pixel_size = 0.007
	label.outline_size = 14 if _is_rogue(parent) else 12
	label.outline_modulate = Color(0.02, 0.025, 0.04, 0.95)
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = position + Vector3(0, 0.8, 0)
	parent.add_child(label)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 0.2, 0.6)
	tween.tween_property(label, "position:z", label.position.z - 0.6, 0.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.6).set_delay(0.1)
	tween.chain().tween_callback(label.queue_free)

static func strike(parent: Node3D, from: Vector3, to: Vector3) -> void:
	if _is_rogue(parent):
		RogueVisuals.spawn_attack_arc(parent, from, to)
		ring(parent, to, Color("#68f2e7"), 0.34, 0.18)
		return
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.09, 0.04, maxf(0.1, from.distance_to(to)))
	visual.mesh = mesh
	visual.material_override = Visuals._flat(Color(1, 0.95, 0.5))
	visual.position = from.lerp(to, 0.5) + Vector3(0, 0.15, 0)
	parent.add_child(visual)
	if from.distance_to(to) > 0.01:
		visual.look_at(to + Vector3(0, 0.15, 0))
	var tween := visual.create_tween()
	tween.tween_property(visual, "scale", Vector3(0.02, 0.02, 1), 0.12)
	tween.tween_callback(visual.queue_free)

static func death(parent: Node3D, position: Vector3, tank: bool) -> void:
	if _is_rogue(parent):
		var impact := Color("#d6bf82") if tank else Color("#72ded4")
		RogueVisuals.spawn_death_burst(parent, position, tank)
		ring(parent, position, impact, 0.58 if tank else 0.42, 0.36)
		return
	var color := Color(0.8, 0.5, 1) if tank else Color(1, 0.5, 0.25)
	ring(parent, position, color, 0.55 if tank else 0.4, 0.35)
	for i in 4:
		var shard := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * 0.1
		shard.mesh = mesh
		shard.material_override = Visuals._flat(color)
		shard.position = position + Vector3(0, 0.3, 0)
		parent.add_child(shard)
		var angle := float(i) * TAU / 4.0
		var tween := shard.create_tween()
		tween.set_parallel(true)
		tween.tween_property(shard, "position", shard.position + Vector3(cos(angle), 0.3, sin(angle)) * 0.5, 0.3)
		tween.tween_property(shard, "scale", Vector3.ZERO, 0.3)
		tween.chain().tween_callback(shard.queue_free)

static func pickup(parent: Node3D, position: Vector3, kind: String) -> void:
	var color := Color("#72f3e6") if kind == "xp" else Color("#ffb95c")
	ring(parent, position, color, 0.3 if kind == "xp" else 0.4, 0.34)
	if not _is_rogue(parent):
		return
	for index in 3:
		var mote := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.025, 0.07, 0.025)
		mote.mesh = mesh
		mote.material_override = _effect_material(color)
		var angle := TAU * float(index) / 3.0
		mote.position = position + Vector3(cos(angle) * 0.12, 0.12, sin(angle) * 0.12)
		parent.add_child(mote)
		var tween := mote.create_tween()
		tween.set_parallel(true)
		tween.tween_property(mote, "position", mote.position + Vector3(0, 0.32, 0), 0.35)
		tween.tween_property(mote, "scale", Vector3.ZERO, 0.35)
		tween.chain().tween_callback(mote.queue_free)