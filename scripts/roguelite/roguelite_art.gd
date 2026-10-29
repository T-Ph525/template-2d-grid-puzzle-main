extends RefCounted
class_name RogueArt

## Procedural dark-fantasy art for the roguelite only. Puzzle mode still uses Visuals.
## Floor, wall and prop decoration has no collision; the logical grid and existing
## Level collision bodies remain authoritative.

const ActorVisualScript := preload("res://scripts/roguelite/actor_visual.gd")
const ExitPortalScript := preload("res://scripts/roguelite/exit_portal.gd")
const PickupScript := preload("res://scripts/pickup.gd")
const LAYER_WORLD := 1

const INK := Color("#090b11")
const FLOOR_TOP := [Color("#252730"), Color("#1f2129"), Color("#23242d")]
const FLOOR_SIDE := [Color("#101116"), Color("#0d0e13"), Color("#111217")]
const WALL_TOP := [Color("#5c5b66"), Color("#50505b"), Color("#55545f")]
const WALL_SIDE := [Color("#202127"), Color("#1b1c22"), Color("#1e1f25")]
const GOLD := Color("#c6a15a")
const PALE_GOLD := Color("#f0d49a")
const TEAL := Color("#63e9df")
const DEEP_TEAL := Color("#174d56")
const CRIMSON := Color("#b9434f")
const VIOLET := Color("#37263f")

static var _materials: Dictionary = {}
static var _floor_meshes: Array = []
static var _wall_meshes: Array = []
static var _rubble_mesh: Mesh
static var _rune_mesh: Mesh
static var _rune_mesh_outer: Mesh

static func _hash_cell(cell: Vector2i, floor_number: int) -> int:
	return absi((cell.x * 73856093) ^ (cell.y * 19349663) ^ (floor_number * 83492791))

static func _material(key: String, color: Color, emission: Color = Color(0, 0, 0), energy: float = 0.0, unshaded: bool = false, alpha: float = 1.0, metallic: float = 0.0, roughness: float = 0.88) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.roughness = roughness
	material.metallic = metallic
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if energy > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = energy
	_materials[key] = material
	return material

static func stone() -> StandardMaterial3D:
	if not _materials.has("stone"):
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = 0.93
		material.metallic = 0.0
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials["stone"] = material
	return _materials["stone"]

static func gold() -> StandardMaterial3D:
	return _material("gold", GOLD, Color("#5e3f16"), 0.12, false, 1.0, 0.62, 0.3)

static func teal_glow() -> StandardMaterial3D:
	return _material("teal_glow", Color("#1d6870"), TEAL, 2.6, true, 1.0, 0.0, 0.32)

static func teal_soft() -> StandardMaterial3D:
	return _material("teal_soft", Color("#1a4d54"), TEAL, 1.1, true, 1.0, 0.0, 0.5)

static func cloth_dark() -> StandardMaterial3D:
	return _material("cloth_dark", Color("#17252d"), Color(0, 0, 0), 0.0, false, 1.0, 0.0, 0.96)

static func cloth_teal() -> StandardMaterial3D:
	return _material("cloth_teal", Color("#295961"), Color("#0d3036"), 0.22, false, 1.0, 0.0, 0.9)

static func leather() -> StandardMaterial3D:
	return _material("leather", Color("#4a3328"), Color(0, 0, 0), 0.0, false, 1.0, 0.0, 0.82)

static func dark_metal() -> StandardMaterial3D:
	return _material("dark_metal", Color("#303640"), Color(0, 0, 0), 0.0, false, 1.0, 0.55, 0.42)

static func shadow_flesh() -> StandardMaterial3D:
	return _material("shadow_flesh", Color("#18121f"), Color("#08060b"), 0.0, false, 1.0, 0.0, 0.98)

static func shadow_edge() -> StandardMaterial3D:
	return _material("shadow_edge", Color("#2b2037"), Color("#120b18"), 0.05, false, 1.0, 0.0, 0.94)

static func tank_stone() -> StandardMaterial3D:
	return _material("tank_stone", Color("#4b4b54"), Color(0, 0, 0), 0.0, false, 1.0, 0.0, 0.9)

static func crimson_glow() -> StandardMaterial3D:
	return _material("crimson_glow", Color("#7f2631"), Color("#ff5a68"), 1.8, true, 1.0, 0.0, 0.4)

static func ground_shadow() -> StandardMaterial3D:
	return _material("ground_shadow", Color(0.01, 0.01, 0.02, 0.42), Color(0, 0, 0), 0.0, true)

static func pale_gold_material() -> StandardMaterial3D:
	return _material("pale_gold", PALE_GOLD, Color("#6b4b1c"), 0.2, false, 1.0, 0.58, 0.34)

static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color) -> void:
	st.set_normal(normal)
	st.set_color(color)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)

## A low-poly stone block whose top is chamfered inward. Vertex colour supplies the face
## separation, so every tile and wall can share one material.
static func _beveled_mesh(hx: float, hz: float, bottom_y: float, top_y: float, bevel: float, top_color: Color, side_color: Color, rim_color: Color = Color(0, 0, 0, 0), rim_width: float = 0.026) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shoulder_y := maxf(bottom_y + 0.002, top_y - bevel)
	var tx := maxf(0.01, hx - bevel)
	var tz := maxf(0.01, hz - bevel)
	var top := [Vector3(-tx, top_y, -tz), Vector3(tx, top_y, -tz), Vector3(tx, top_y, tz), Vector3(-tx, top_y, tz)]
	var shoulder := [Vector3(-hx, shoulder_y, -hz), Vector3(hx, shoulder_y, -hz), Vector3(hx, shoulder_y, hz), Vector3(-hx, shoulder_y, hz)]
	var bottom := [Vector3(-hx, bottom_y, -hz), Vector3(hx, bottom_y, -hz), Vector3(hx, bottom_y, hz), Vector3(-hx, bottom_y, hz)]
	var chamfer := top_color.lerp(side_color, 0.34)
	if rim_color.a > 0.0:
		var ix := maxf(0.002, tx - rim_width)
		var iz := maxf(0.002, tz - rim_width)
		var inner := [Vector3(-ix, top_y, -iz), Vector3(ix, top_y, -iz), Vector3(ix, top_y, iz), Vector3(-ix, top_y, iz)]
		_add_quad(st, top[0], top[1], inner[1], inner[0], Vector3.UP, rim_color)
		_add_quad(st, top[1], top[2], inner[2], inner[1], Vector3.UP, rim_color)
		_add_quad(st, top[2], top[3], inner[3], inner[2], Vector3.UP, rim_color)
		_add_quad(st, top[3], top[0], inner[0], inner[3], Vector3.UP, rim_color)
		_add_quad(st, inner[0], inner[1], inner[2], inner[3], Vector3.UP, top_color)
	else:
		_add_quad(st, top[0], top[1], top[2], top[3], Vector3.UP, top_color)
	_add_quad(st, top[3], top[2], shoulder[2], shoulder[3], Vector3(0, bevel, bevel).normalized(), chamfer)
	_add_quad(st, top[1], top[0], shoulder[0], shoulder[1], Vector3(0, bevel, -bevel).normalized(), chamfer)
	_add_quad(st, top[2], top[1], shoulder[1], shoulder[2], Vector3(bevel, bevel, 0).normalized(), chamfer)
	_add_quad(st, top[0], top[3], shoulder[3], shoulder[0], Vector3(-bevel, bevel, 0).normalized(), chamfer)
	_add_quad(st, shoulder[3], shoulder[2], bottom[2], bottom[3], Vector3.BACK, side_color)
	_add_quad(st, shoulder[1], shoulder[0], bottom[0], bottom[1], Vector3.FORWARD, side_color)
	_add_quad(st, shoulder[2], shoulder[1], bottom[1], bottom[2], Vector3.RIGHT, side_color)
	_add_quad(st, shoulder[0], shoulder[3], bottom[3], bottom[0], Vector3.LEFT, side_color)
	_add_quad(st, bottom[0], bottom[1], bottom[2], bottom[3], Vector3.DOWN, side_color.darkened(0.2))
	return st.commit()

static func _ensure_shared_meshes() -> void:
	if not _floor_meshes.is_empty():
		return
	for index in 3:
		_floor_meshes.append(_beveled_mesh(0.463, 0.463, -0.075, 0.0, 0.018, FLOOR_TOP[index], FLOOR_SIDE[index]))
		_wall_meshes.append(_beveled_mesh(0.487, 0.487, -0.5, 0.6, 0.06, WALL_TOP[index], WALL_SIDE[index], Color("#9b7d4c"), 0.02))
	_rune_mesh = TorusMesh.new()
	_rune_mesh.inner_radius = 0.145
	_rune_mesh.outer_radius = 0.165
	_rune_mesh.rings = 12
	_rune_mesh.ring_segments = 4
	_rune_mesh_outer = TorusMesh.new()
	_rune_mesh_outer.inner_radius = 0.205
	_rune_mesh_outer.outer_radius = 0.218
	_rune_mesh_outer.rings = 12
	_rune_mesh_outer.ring_segments = 4
	_rubble_mesh = SphereMesh.new()
	_rubble_mesh.radius = 0.09
	_rubble_mesh.height = 0.1
	_rubble_mesh.radial_segments = 5
	_rubble_mesh.rings = 3

static func _mesh_node(mesh: Mesh, material: Material, position: Vector3 = Vector3.ZERO, rotation: Vector3 = Vector3.ZERO, shadows: bool = true) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	instance.rotation = rotation
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance

static func _pivot(parent: Node3D, node_name: String, position: Vector3 = Vector3.ZERO) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = position
	parent.add_child(node)
	return node
static func _multimesh_instance(mesh: Mesh, transforms: Array, material: Material, shadows: bool) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in transforms.size():
		multimesh.set_instance_transform(index, transforms[index])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance

static func _cell_transforms(cells: Array, y: float) -> Array:
	var transforms: Array = []
	for cell: Vector2i in cells:
		transforms.append(Transform3D(Basis.IDENTITY, Vector3(cell.x, y, cell.y)))
	return transforms

static func make_wall_collision_body(cells: Array) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "WallCollision"
	body.collision_layer = LAYER_WORLD
	for cell: Vector2i in cells:
		var collider := CollisionShape3D.new()
		collider.shape = BoxShape3D.new()
		collider.position = Vector3(cell.x, 0.5, cell.y)
		body.add_child(collider)
	return body

static func _disable_actor_shadows(root: Node3D) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
static func make_floor_layer(cells: Array, floor_number: int) -> Node3D:
	_ensure_shared_meshes()
	var root := Node3D.new()
	root.name = "FloorLayer"
	var groups: Array = [[], [], []]
	var runes: Array = []
	var rocks: Array = []
	var chips: Array = []
	for cell: Vector2i in cells:
		var cell_hash := _hash_cell(cell, floor_number)
		groups[cell_hash % 3].append(cell)
		if cell_hash % 17 == 0:
			runes.append(cell)
		if cell_hash % 29 == 0:
			rocks.append(Transform3D(Basis.from_euler(Vector3(0.2, cell_hash % 7, 0.1)).scaled(Vector3(0.9, 0.55, 0.75)), Vector3(cell.x + 0.28, 0.055, cell.y - 0.25)))
		if cell_hash % 37 == 0:
			chips.append(Transform3D(Basis.from_euler(Vector3(0.7, 0.3, 0.4)).scaled(Vector3(0.55, 0.3, 0.5)), Vector3(cell.x - 0.3, 0.04, cell.y + 0.23)))
	for index in 3:
		if not groups[index].is_empty():
			root.add_child(_multimesh_instance(_floor_meshes[index], _cell_transforms(groups[index], 0.0), stone(), false))
	if not runes.is_empty():
		root.add_child(_multimesh_instance(_rune_mesh, _cell_transforms(runes, 0.008), teal_glow(), false))
		root.add_child(_multimesh_instance(_rune_mesh_outer, _cell_transforms(runes, 0.007), teal_soft(), false))
	if not rocks.is_empty():
		root.add_child(_multimesh_instance(_rubble_mesh, rocks, stone(), false))
	if not chips.is_empty():
		root.add_child(_multimesh_instance(_rubble_mesh, chips, stone(), false))
	return root

static func make_wall_collider() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Wall"
	body.collision_layer = LAYER_WORLD
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = BoxShape3D.new()
	body.add_child(collision)
	return body

static func make_wall_layer(cells: Array, floor_number: int) -> Node3D:
	_ensure_shared_meshes()
	var root := Node3D.new()
	root.name = "WallLayer"
	var groups: Array = [[], [], []]
	for cell: Vector2i in cells:
		var cell_hash := _hash_cell(cell, floor_number)
		groups[cell_hash % 3].append(cell)
		if cell_hash % 23 == 3:
			root.add_child(_make_brazier_prop(cell))
	for index in 3:
		if not groups[index].is_empty():
			root.add_child(_multimesh_instance(_wall_meshes[index], _cell_transforms(groups[index], 0.5), stone(), true))
	return root

static func _make_brazier_prop(cell: Vector2i) -> Node3D:
	var root := Node3D.new()
	root.name = "Brazier"
	root.position = Vector3(cell.x, 0.5, cell.y)
	_add_brazier(root)
	return root
static func make_floor_tile(cell: Vector2i, floor_number: int) -> Node3D:
	_ensure_shared_meshes()
	var root := Node3D.new()
	root.name = "FloorTile"
	var cell_hash := _hash_cell(cell, floor_number)
	var variant := cell_hash % 3
	root.add_child(_mesh_node(_floor_meshes[variant], stone(), Vector3.ZERO, Vector3.ZERO, false))
	if cell_hash % 17 == 0:
		root.add_child(_mesh_node(_rune_mesh, teal_glow(), Vector3(0, 0.008, 0), Vector3.ZERO, false))
		root.add_child(_mesh_node(_rune_mesh_outer, teal_soft(), Vector3(0, 0.007, 0), Vector3.ZERO, false))
	if cell_hash % 29 == 0:
		var rock := _mesh_node(_rubble_mesh, stone(), Vector3(0.28, 0.055, -0.25), Vector3(0.2, cell_hash % 7, 0.1), false)
		rock.scale = Vector3(0.9, 0.55, 0.75)
		root.add_child(rock)
	if cell_hash % 37 == 0:
		var chip := _mesh_node(_rubble_mesh, stone(), Vector3(-0.3, 0.04, 0.23), Vector3(0.7, 0.3, 0.4), false)
		chip.scale = Vector3(0.55, 0.3, 0.5)
		root.add_child(chip)
	return root

static func make_wall(cell: Vector2i, floor_number: int) -> StaticBody3D:
	_ensure_shared_meshes()
	var body := StaticBody3D.new()
	body.name = "Wall"
	body.collision_layer = LAYER_WORLD
	var variant := _hash_cell(cell, floor_number) % 3
	body.add_child(_mesh_node(_wall_meshes[variant], stone()))
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	body.add_child(collision)
	if _hash_cell(cell, floor_number) % 23 == 3:
		_add_brazier(body)
	return body

static func _add_brazier(body: Node3D) -> void:
	var bowl := CylinderMesh.new()
	bowl.top_radius = 0.13
	bowl.bottom_radius = 0.08
	bowl.height = 0.09
	bowl.radial_segments = 8
	body.add_child(_mesh_node(bowl, gold(), Vector3(0, 0.66, 0), Vector3.ZERO, true))
	var stem := CylinderMesh.new()
	stem.top_radius = 0.035
	stem.bottom_radius = 0.055
	stem.height = 0.12
	stem.radial_segments = 6
	body.add_child(_mesh_node(stem, dark_metal(), Vector3(0, 0.58, 0), Vector3.ZERO, true))
	var flame := CylinderMesh.new()
	flame.top_radius = 0.005
	flame.bottom_radius = 0.075
	flame.height = 0.18
	flame.radial_segments = 6
	var glow := _material("flame", Color("#ffcf74"), Color("#ffb24e"), 3.0, true)
	body.add_child(_mesh_node(flame, glow, Vector3(0, 0.79, 0), Vector3(0, 0.3, 0), false))
	var light := OmniLight3D.new()
	light.name = "WarmBrazier"
	light.position = Vector3(0, 0.88, 0)
	light.light_color = Color("#ffc474")
	light.light_energy = 0.9
	light.omni_range = 3.2
	light.shadow_enabled = false
	body.add_child(light)

static func make_diorama_base(grid: Grid) -> Node3D:
	var root := Node3D.new()
	root.name = "DioramaBase"
	var half_width := grid.width * 0.5 + 0.52
	var half_depth := grid.height * 0.5 + 0.52
	var mesh := _beveled_mesh(half_width, half_depth, -0.34, 0.0, 0.09, Color("#20232b"), Color("#101219"), GOLD, 0.032)
	root.add_child(_mesh_node(mesh, stone(), Vector3.ZERO, Vector3.ZERO, false))
	root.position = Vector3((grid.width - 1) * 0.5, -0.076, (grid.height - 1) * 0.5)
	return root

static func configure_environment(world_environment: WorldEnvironment) -> void:
	if world_environment == null:
		return
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#070a11")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#2b4359")
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0
	environment.fog_enabled = true
	environment.fog_light_color = Color("#122b35")
	environment.fog_light_energy = 0.35
	environment.fog_density = 0.008
	environment.fog_sky_affect = 0.15
	environment.glow_enabled = true
	environment.glow_intensity = 0.62
	environment.glow_strength = 1.1
	environment.glow_bloom = 0.06
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.06
	environment.adjustment_saturation = 1.08
	world_environment.environment = environment

static func decorate_level(level: Level, world_environment: WorldEnvironment) -> void:
	level.add_child(make_diorama_base(level.grid))
	configure_environment(world_environment)
	if level.get_node_or_null("RogueSun") == null:
		var sun := DirectionalLight3D.new()
		sun.name = "RogueSun"
		sun.light_color = Color("#f6c77d")
		sun.light_energy = 0.82
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 42.0
		sun.rotation_degrees = Vector3(-58, -31, 0)
		level.add_child(sun)
	if level.get_node_or_null("RogueFill") == null:
		var fill := DirectionalLight3D.new()
		fill.name = "RogueFill"
		fill.light_color = Color("#5aa5ba")
		fill.light_energy = 0.36
		fill.shadow_enabled = false
		fill.rotation_degrees = Vector3(-34, 142, 0)
		level.add_child(fill)
static func _actor_root(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Visual"
	root.set_script(ActorVisualScript)
	root.set("archetype", kind)
	root.scale = Vector3.ONE * (1.15 if kind == "tank" else (1.08 if kind == "chaser" else 1.12))
	var disc := MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 0.34
	disc_mesh.bottom_radius = 0.34
	disc_mesh.height = 0.006
	disc_mesh.radial_segments = 12
	disc.name = "ShadowDisc"
	disc.mesh = disc_mesh
	disc.material_override = ground_shadow()
	disc.position.y = 0.004
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(disc)
	return root

static func make_player() -> Node3D:
	var root := _actor_root("player")
	var body := _pivot(root, "Body")
	var cape_pivot := _pivot(body, "Cape", Vector3(0, 0.42, -0.14))
	var cape := BoxMesh.new()
	cape.size = Vector3(0.34, 0.56, 0.035)
	cape_pivot.add_child(_mesh_node(cape, cloth_dark(), Vector3(0, 0.0, 0), Vector3(0.08, 0, 0)))
	var skirt := CylinderMesh.new()
	skirt.top_radius = 0.19
	skirt.bottom_radius = 0.31
	skirt.height = 0.42
	skirt.radial_segments = 8
	body.add_child(_mesh_node(skirt, cloth_teal(), Vector3(0, 0.32, 0), Vector3.ZERO, true))
	var torso := CylinderMesh.new()
	torso.top_radius = 0.17
	torso.bottom_radius = 0.21
	torso.height = 0.38
	torso.radial_segments = 6
	body.add_child(_mesh_node(torso, leather(), Vector3(0, 0.55, 0), Vector3.ZERO, true))
	var chest := _beveled_mesh(0.16, 0.12, -0.14, 0.14, 0.025, Color("#40515b"), Color("#26353d"), Color("#a58b5a"), 0.016)
	body.add_child(_mesh_node(chest, stone(), Vector3(0, 0.58, 0.07), Vector3.ZERO, true))
	var clasp := TorusMesh.new()
	clasp.inner_radius = 0.19
	clasp.outer_radius = 0.215
	clasp.rings = 10
	clasp.ring_segments = 4
	body.add_child(_mesh_node(clasp, gold(), Vector3(0, 0.71, 0), Vector3.ZERO, true))
	var hem := TorusMesh.new()
	hem.inner_radius = 0.275
	hem.outer_radius = 0.3
	hem.rings = 12
	hem.ring_segments = 4
	body.add_child(_mesh_node(hem, teal_soft(), Vector3(0, 0.12, 0), Vector3.ZERO, false))
	for side in [-1.0, 1.0]:
		var shoulder := _beveled_mesh(0.09, 0.105, -0.06, 0.06, 0.022, Color("#3d4e57"), Color("#25343b"), Color("#b99a63"), 0.014)
		body.add_child(_mesh_node(shoulder, stone(), Vector3(side * 0.225, 0.7, 0), Vector3(0, 0, side * 0.18), true))
	_add_player_head(body)
	_add_player_arms(body)
	_add_player_legs(body)
	_disable_actor_shadows(root)
	var aura := OmniLight3D.new()
	aura.name = "SoulAura"
	aura.position = Vector3(0, 0.62, 0)
	aura.light_color = TEAL
	aura.light_energy = 0.2
	aura.omni_range = 2.1
	aura.shadow_enabled = false
	root.add_child(aura)
	return root

static func _add_player_head(body: Node3D) -> void:
	var head := _pivot(body, "Head", Vector3(0, 0.8, 0))
	var hood := CylinderMesh.new()
	hood.top_radius = 0.018
	hood.bottom_radius = 0.23
	hood.height = 0.38
	hood.radial_segments = 8
	head.add_child(_mesh_node(hood, cloth_teal(), Vector3(0, 0.11, -0.015), Vector3.ZERO, true))
	var brim := TorusMesh.new()
	brim.inner_radius = 0.19
	brim.outer_radius = 0.245
	brim.rings = 12
	brim.ring_segments = 4
	head.add_child(_mesh_node(brim, gold(), Vector3(0, -0.04, -0.01), Vector3.ZERO, true))
	var face := SphereMesh.new()
	face.radius = 0.115
	face.height = 0.19
	face.radial_segments = 8
	face.rings = 4
	var face_instance := _mesh_node(face, _material("void_face", Color("#030408"), Color(0, 0, 0), 0.0, true), Vector3(0, 0.04, 0.145), Vector3.ZERO, false)
	face_instance.scale = Vector3(0.82, 1.0, 0.52)
	head.add_child(face_instance)
	var eye_mesh := BoxMesh.new()
	eye_mesh.size = Vector3(0.033, 0.013, 0.012)
	for side in [-1.0, 1.0]:
		var eye := _mesh_node(eye_mesh, teal_glow(), Vector3(side * 0.043, 0.065, 0.2), Vector3(0, 0, side * 0.12), false)
		eye.name = "Eyes" if side > 0 else "EyeLeft"
		head.add_child(eye)

static func _add_player_arms(body: Node3D) -> void:
	for side in [-1.0, 1.0]:
		var arm := _pivot(body, "LeftArm" if side < 0 else "RightArm", Vector3(side * 0.235, 0.69, 0))
		var sleeve := CylinderMesh.new()
		sleeve.top_radius = 0.07
		sleeve.bottom_radius = 0.058
		sleeve.height = 0.3
		sleeve.radial_segments = 6
		arm.add_child(_mesh_node(sleeve, cloth_teal(), Vector3(0, -0.15, 0), Vector3.ZERO, true))
		var bracer := BoxMesh.new()
		bracer.size = Vector3(0.1, 0.07, 0.1)
		arm.add_child(_mesh_node(bracer, gold(), Vector3(0, -0.27, 0), Vector3.ZERO, true))
		var hand := SphereMesh.new()
		hand.radius = 0.055
		hand.height = 0.1
		hand.radial_segments = 6
		hand.rings = 3
		arm.add_child(_mesh_node(hand, leather(), Vector3(0, -0.34, 0), Vector3.ZERO, true))
		if side > 0:
			_add_player_weapon(arm)

static func _add_player_weapon(arm: Node3D) -> void:
	var weapon := _pivot(arm, "Weapon", Vector3(0, -0.34, 0.02))
	weapon.rotation = Vector3(0.95, 0, -0.28)
	var grip := CylinderMesh.new()
	grip.top_radius = 0.022
	grip.bottom_radius = 0.025
	grip.height = 0.15
	grip.radial_segments = 6
	weapon.add_child(_mesh_node(grip, leather(), Vector3(0, 0.05, 0), Vector3.ZERO, true))
	var guard := BoxMesh.new()
	guard.size = Vector3(0.2, 0.035, 0.045)
	weapon.add_child(_mesh_node(guard, gold(), Vector3(0, 0.13, 0), Vector3.ZERO, true))
	var blade_mesh := _beveled_mesh(0.035, 0.012, 0.0, 0.46, 0.008, Color("#9aa8ae"), Color("#4b5c64"), PALE_GOLD, 0.006)
	weapon.add_child(_mesh_node(blade_mesh, stone(), Vector3(0, 0.16, 0), Vector3.ZERO, true))
	var rune := BoxMesh.new()
	rune.size = Vector3(0.014, 0.16, 0.005)
	weapon.add_child(_mesh_node(rune, teal_glow(), Vector3(0, 0.39, 0.014), Vector3.ZERO, false))

static func _add_player_legs(body: Node3D) -> void:
	for side in [-1.0, 1.0]:
		var leg := _pivot(body, "LeftLeg" if side < 0 else "RightLeg", Vector3(side * 0.095, 0.3, 0))
		var trouser := CylinderMesh.new()
		trouser.top_radius = 0.065
		trouser.bottom_radius = 0.055
		trouser.height = 0.25
		trouser.radial_segments = 6
		leg.add_child(_mesh_node(trouser, leather(), Vector3(0, -0.105, 0), Vector3.ZERO, true))
		var boot := _beveled_mesh(0.062, 0.095, -0.06, 0.06, 0.018, Color("#3b3f43"), Color("#202328"), GOLD, 0.008)
		leg.add_child(_mesh_node(boot, stone(), Vector3(0, -0.24, 0.025), Vector3.ZERO, true))
static func make_enemy(tank: bool) -> Node3D:
	return make_tank() if tank else make_chaser()

static func make_chaser() -> Node3D:
	var root := _actor_root("chaser")
	var body := _pivot(root, "Body", Vector3(0, 0.08, 0))
	var skirt := CylinderMesh.new()
	skirt.top_radius = 0.09
	skirt.bottom_radius = 0.29
	skirt.height = 0.62
	skirt.radial_segments = 7
	body.add_child(_mesh_node(skirt, shadow_flesh(), Vector3(0, 0.36, 0), Vector3.ZERO, true))
	var torso := SphereMesh.new()
	torso.radius = 0.2
	torso.height = 0.35
	torso.radial_segments = 7
	torso.rings = 4
	var torso_instance := _mesh_node(torso, shadow_edge(), Vector3(0, 0.68, 0), Vector3.ZERO, true)
	torso_instance.scale = Vector3(0.9, 1.1, 0.75)
	body.add_child(torso_instance)
	var head := _pivot(body, "Head", Vector3(0, 0.82, 0))
	var hood := SphereMesh.new()
	hood.radius = 0.19
	hood.height = 0.34
	hood.radial_segments = 7
	hood.rings = 4
	head.add_child(_mesh_node(hood, shadow_flesh(), Vector3.ZERO, Vector3.ZERO, true))
	var face := SphereMesh.new()
	face.radius = 0.095
	face.height = 0.17
	face.radial_segments = 6
	face.rings = 3
	head.add_child(_mesh_node(face, _material("void_face", Color("#030408"), Color(0, 0, 0), 0.0, true), Vector3(0, 0, 0.14), Vector3.ZERO, false))
	for side in [-1.0, 1.0]:
		var eye_mesh := BoxMesh.new()
		eye_mesh.size = Vector3(0.035, 0.016, 0.012)
		var eye := _mesh_node(eye_mesh, teal_glow(), Vector3(side * 0.042, 0.035, 0.195), Vector3(0, 0, side * 0.18), false)
		eye.name = "Eyes" if side > 0 else "EyeLeft"
		head.add_child(eye)
	for side in [-1.0, 1.0]:
		var arm := _pivot(body, "LeftArm" if side < 0 else "RightArm", Vector3(side * 0.18, 0.63, 0))
		var limb := CylinderMesh.new()
		limb.top_radius = 0.06
		limb.bottom_radius = 0.025
		limb.height = 0.3
		limb.radial_segments = 5
		arm.add_child(_mesh_node(limb, shadow_edge(), Vector3(0, -0.14, 0), Vector3(0, 0, side * 0.18), true))
		for claw in 3:
			var claw_mesh := CylinderMesh.new()
			claw_mesh.top_radius = 0.003
			claw_mesh.bottom_radius = 0.018
			claw_mesh.height = 0.11
			claw_mesh.radial_segments = 4
			arm.add_child(_mesh_node(claw_mesh, teal_soft(), Vector3((claw - 1) * 0.035, -0.32, 0.02), Vector3(0.25, 0, (claw - 1) * 0.3), false))
	var tendrils := _pivot(body, "Tendrils", Vector3(0, 0.12, 0))
	for index in 5:
		var angle := TAU * float(index) / 5.0
		var wisp := CylinderMesh.new()
		wisp.top_radius = 0.008
		wisp.bottom_radius = 0.06
		wisp.height = 0.32
		wisp.radial_segments = 4
		var piece := _mesh_node(wisp, shadow_flesh(), Vector3(cos(angle) * 0.14, -0.11, sin(angle) * 0.14), Vector3(0.18, -angle, 0.12), false)
		piece.name = "Wisp%d" % index
		tendrils.add_child(piece)
	_disable_actor_shadows(root)
	var rim := TorusMesh.new()
	rim.inner_radius = 0.19
	rim.outer_radius = 0.205
	rim.rings = 10
	rim.ring_segments = 4
	body.add_child(_mesh_node(rim, teal_soft(), Vector3(0, 0.27, 0), Vector3.ZERO, false))
	var chest_sigil := BoxMesh.new()
	chest_sigil.size = Vector3(0.065, 0.2, 0.012)
	body.add_child(_mesh_node(chest_sigil, teal_glow(), Vector3(0, 0.58, 0.155), Vector3(0, 0, 0.28), false))
	var back_sigil := BoxMesh.new()
	back_sigil.size = Vector3(0.05, 0.18, 0.012)
	body.add_child(_mesh_node(back_sigil, teal_soft(), Vector3(0, 0.58, -0.14), Vector3(0, 0, -0.32), false))
	var crown := TorusMesh.new()
	crown.inner_radius = 0.14
	crown.outer_radius = 0.158
	crown.rings = 12
	crown.ring_segments = 4
	head.add_child(_mesh_node(crown, teal_soft(), Vector3(0, 0.04, 0), Vector3.ZERO, false))
	var soul_flame := CylinderMesh.new()
	soul_flame.top_radius = 0.002
	soul_flame.bottom_radius = 0.045
	soul_flame.height = 0.2
	soul_flame.radial_segments = 5
	head.add_child(_mesh_node(soul_flame, _material("soul_flame", Color("#1b6a68"), TEAL, 1.5, true), Vector3(0, 0.32, 0), Vector3.ZERO, false))
	for side in [-1.0, 1.0]:
		var horn := CylinderMesh.new()
		horn.top_radius = 0.0
		horn.bottom_radius = 0.045
		horn.height = 0.18
		horn.radial_segments = 4
		head.add_child(_mesh_node(horn, shadow_edge(), Vector3(side * 0.15, 0.1, 0), Vector3(0, 0, side * -0.5), true))
	return root

static func make_tank() -> Node3D:
	var root := _actor_root("tank")
	var body := _pivot(root, "Body")
	var torso := _beveled_mesh(0.32, 0.24, -0.28, 0.3, 0.06, Color("#6a6870"), Color("#3b3b44"), Color("#987b4e"), 0.025)
	body.add_child(_mesh_node(torso, stone(), Vector3(0, 0.66, 0), Vector3.ZERO, true))
	var pelvis := _beveled_mesh(0.26, 0.19, -0.12, 0.12, 0.045, Color("#55545d"), Color("#30313a"), Color("#8d7248"), 0.018)
	body.add_child(_mesh_node(pelvis, stone(), Vector3(0, 0.34, 0), Vector3.ZERO, true))
	for side in [-1.0, 1.0]:
		var shoulder := _beveled_mesh(0.14, 0.16, -0.13, 0.13, 0.042, Color("#77727a"), Color("#45444e"), Color("#a88956"), 0.018)
		body.add_child(_mesh_node(shoulder, stone(), Vector3(side * 0.39, 0.78, 0), Vector3(0, 0, side * 0.12), true))
		var arm := _pivot(body, "LeftArm" if side < 0 else "RightArm", Vector3(side * 0.4, 0.74, 0))
		var upper := _beveled_mesh(0.105, 0.105, -0.28, 0.05, 0.035, Color("#5d5c64"), Color("#353640"), Color("#8d7048"), 0.012)
		arm.add_child(_mesh_node(upper, stone(), Vector3(0, -0.16, 0), Vector3.ZERO, true))
		var fist := _beveled_mesh(0.13, 0.13, -0.13, 0.13, 0.04, Color("#6d6a71"), Color("#3d3d47"), Color("#aa8b57"), 0.016)
		arm.add_child(_mesh_node(fist, stone(), Vector3(0, -0.36, 0.02), Vector3.ZERO, true))
		var leg := _pivot(body, "LeftLeg" if side < 0 else "RightLeg", Vector3(side * 0.16, 0.31, 0))
		var shin := _beveled_mesh(0.1, 0.11, -0.18, 0.08, 0.03, Color("#4e4d56"), Color("#2c2d36"), Color("#7b6546"), 0.012)
		leg.add_child(_mesh_node(shin, stone(), Vector3(0, -0.16, 0), Vector3.ZERO, true))
		var foot := _beveled_mesh(0.13, 0.18, -0.075, 0.075, 0.026, Color("#626069"), Color("#34353e"), Color("#8c7149"), 0.012)
		leg.add_child(_mesh_node(foot, stone(), Vector3(0, -0.27, 0.04), Vector3.ZERO, true))
	_add_tank_head(body)
	var chest_rune := BoxMesh.new()
	chest_rune.size = Vector3(0.16, 0.19, 0.012)
	body.add_child(_mesh_node(chest_rune, teal_glow(), Vector3(0, 0.67, 0.247), Vector3.ZERO, false))
	var chest_core := TorusMesh.new()
	chest_core.inner_radius = 0.09
	chest_core.outer_radius = 0.105
	chest_core.rings = 12
	chest_core.ring_segments = 4
	body.add_child(_mesh_node(chest_core, gold(), Vector3(0, 0.67, 0.258), Vector3(PI * 0.5, 0, 0), false))
	_disable_actor_shadows(root)
	return root

static func _add_tank_head(body: Node3D) -> void:
	var head := _pivot(body, "Head", Vector3(0, 0.99, 0))
	var helm := _beveled_mesh(0.16, 0.14, -0.12, 0.12, 0.04, Color("#77747c"), Color("#44444d"), Color("#b0925b"), 0.018)
	head.add_child(_mesh_node(helm, stone(), Vector3.ZERO, Vector3.ZERO, true))
	var visor := BoxMesh.new()
	visor.size = Vector3(0.20, 0.042, 0.02)
	head.add_child(_mesh_node(visor, teal_glow(), Vector3(0, -0.015, 0.137), Vector3.ZERO, false))
	var crown := BoxMesh.new()
	crown.size = Vector3(0.045, 0.12, 0.08)
	for side in [-1.0, 1.0]:
		head.add_child(_mesh_node(crown, gold(), Vector3(side * 0.105, 0.12, 0), Vector3(0, 0, side * -0.2), true))
static func make_drop(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Loot"
	root.set_script(PickupScript)
	var glow := CylinderMesh.new()
	glow.top_radius = 0.19
	glow.bottom_radius = 0.19
	glow.height = 0.005
	glow.radial_segments = 12
	root.add_child(_mesh_node(glow, teal_soft() if kind == "xp" else crimson_glow(), Vector3(0, -0.18, 0), Vector3.ZERO, false))
	if kind == "xp":
		var shard := SphereMesh.new()
		shard.radius = 0.12
		shard.height = 0.3
		shard.radial_segments = 5
		shard.rings = 3
		var core := _mesh_node(shard, _material("xp_glow", Color("#1b9d97"), TEAL, 1.15, true), Vector3(0, 0.03, 0), Vector3.ZERO, false)
		core.scale = Vector3(0.8, 1.15, 0.8)
		root.add_child(core)
		var ring := TorusMesh.new()
		ring.inner_radius = 0.14
		ring.outer_radius = 0.155
		ring.rings = 12
		ring.ring_segments = 4
		root.add_child(_mesh_node(ring, gold(), Vector3(0, 0.03, 0), Vector3(PI * 0.5, 0, 0), false))
	else:
		var vial := CylinderMesh.new()
		vial.top_radius = 0.065
		vial.bottom_radius = 0.085
		vial.height = 0.2
		vial.radial_segments = 6
		root.add_child(_mesh_node(vial, crimson_glow(), Vector3(0, 0.01, 0), Vector3.ZERO, false))
		var neck := CylinderMesh.new()
		neck.top_radius = 0.04
		neck.bottom_radius = 0.045
		neck.height = 0.08
		neck.radial_segments = 6
		root.add_child(_mesh_node(neck, gold(), Vector3(0, 0.14, 0), Vector3.ZERO, false))
		var cross_h := BoxMesh.new()
		cross_h.size = Vector3(0.16, 0.035, 0.02)
		root.add_child(_mesh_node(cross_h, pale_gold_material(), Vector3(0, 0.05, 0.08), Vector3.ZERO, false))
		var cross_v := BoxMesh.new()
		cross_v.size = Vector3(0.035, 0.13, 0.02)
		root.add_child(_mesh_node(cross_v, pale_gold_material(), Vector3(0, 0.05, 0.08), Vector3.ZERO, false))
	return root

static func make_exit_portal() -> Node3D:
	var root := Node3D.new()
	root.name = "ExitPortal"
	root.set_script(ExitPortalScript)
	var base := TorusMesh.new()
	base.inner_radius = 0.31
	base.outer_radius = 0.39
	base.rings = 16
	base.ring_segments = 5
	root.add_child(_mesh_node(base, gold(), Vector3(0, 0.025, 0), Vector3.ZERO, false))
	var floor_rune := TorusMesh.new()
	floor_rune.inner_radius = 0.24
	floor_rune.outer_radius = 0.255
	floor_rune.rings = 16
	floor_rune.ring_segments = 4
	root.add_child(_mesh_node(floor_rune, teal_soft(), Vector3(0, 0.032, 0), Vector3.ZERO, false))
	var arch := TorusMesh.new()
	arch.inner_radius = 0.31
	arch.outer_radius = 0.39
	arch.rings = 16
	arch.ring_segments = 6
	var arch_node := _mesh_node(arch, gold(), Vector3(0, 0.61, 0), Vector3(PI * 0.5, 0, 0), true)
	arch_node.name = "Arch"
	root.add_child(arch_node)
	var veil := QuadMesh.new()
	veil.size = Vector2(0.57, 0.76)
	var veil_material := _material("portal_veil", Color(0.1, 0.55, 0.55, 0.22), TEAL, 1.2, true)
	var veil_node := _mesh_node(veil, veil_material, Vector3(0, 0.59, 0.01), Vector3.ZERO, false)
	veil_node.name = "Veil"
	root.add_child(veil_node)
	var inner := TorusMesh.new()
	inner.inner_radius = 0.255
	inner.outer_radius = 0.28
	inner.rings = 16
	inner.ring_segments = 4
	var inner_node := _mesh_node(inner, teal_glow(), Vector3(0, 0.6, 0.012), Vector3(PI * 0.5, 0, 0), false)
	inner_node.name = "InnerRing"
	root.add_child(inner_node)
	var gem := SphereMesh.new()
	gem.radius = 0.065
	gem.height = 0.13
	gem.radial_segments = 6
	gem.rings = 3
	var gem_node := _mesh_node(gem, teal_glow(), Vector3(0, 1.02, 0), Vector3.ZERO, false)
	gem_node.name = "Gem"
	root.add_child(gem_node)
	var shards := Node3D.new()
	shards.name = "Shards"
	root.add_child(shards)
	var shard_mesh := BoxMesh.new()
	shard_mesh.size = Vector3(0.04, 0.11, 0.025)
	for index in 6:
		var angle := TAU * float(index) / 6.0
		var shard := _mesh_node(shard_mesh, teal_glow(), Vector3(cos(angle) * 0.42, 0.6 + sin(angle * 2.0) * 0.16, sin(angle) * 0.12), Vector3(0, -angle, 0.3), false)
		shards.add_child(shard)
	var light := OmniLight3D.new()
	light.name = "PortalLight"
	light.position = Vector3(0, 0.7, 0)
	light.light_color = TEAL
	light.light_energy = 0.0
	light.omni_range = 2.8
	light.shadow_enabled = false
	root.add_child(light)
	return root

static func make_door(tint: Color = Color.WHITE) -> Door:
	var DoorScript := preload("res://scripts/door.gd")
	var door: Door = DoorScript.new()
	door.name = "Door"
	door.add_child(_door_half(-0.25, "LeftHalf", tint))
	door.add_child(_door_half(0.25, "RightHalf", tint))
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = LAYER_WORLD
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = BoxShape3D.new()
	body.add_child(collision)
	door.add_child(body)
	return door

static func _door_half(x_pos: float, node_name: String, tint: Color) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = Vector3(x_pos, 0, 0)
	var slab := _beveled_mesh(0.225, 0.08, -0.45, 0.45, 0.035, Color("#4a444d"), Color("#27242c"), tint, 0.012)
	node.add_child(_mesh_node(slab, stone(), Vector3.ZERO, Vector3.ZERO, true))
	var inlay := BoxMesh.new()
	inlay.size = Vector3(0.07, 0.56, 0.015)
	node.add_child(_mesh_node(inlay, _material("door_inlay", tint.darkened(0.35), tint, 0.8, false), Vector3(0, 0, 0.087), Vector3.ZERO, false))
	return node

static func spawn_attack_arc(parent: Node3D, from: Vector3, to: Vector3) -> void:
	var direction := to - from
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		return
	var root := Node3D.new()
	root.name = "AttackArc"
	root.position = from + Vector3(0, 0.5, 0)
	root.rotation.y = atan2(direction.x, direction.z)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 9
	for index in segments:
		var a0 := -1.05 + 2.1 * float(index) / segments
		var a1 := -1.05 + 2.1 * float(index + 1) / segments
		var r0 := 0.42
		var r1 := 0.68
		var p0 := Vector3(sin(a0) * r0, 0, cos(a0) * r0)
		var p1 := Vector3(sin(a1) * r0, 0, cos(a1) * r0)
		var p2 := Vector3(sin(a1) * r1, 0, cos(a1) * r1)
		var p3 := Vector3(sin(a0) * r1, 0, cos(a0) * r1)
		_add_quad(st, p0, p1, p2, p3, Vector3.UP, TEAL)
	var mesh := st.commit()
	var material := _material("attack_arc", Color(0.25, 1.0, 0.94, 0.9), TEAL, 2.4, true)
	var instance := _mesh_node(mesh, material, Vector3.ZERO, Vector3.ZERO, false)
	root.add_child(instance)
	parent.add_child(root)
	var tween := root.create_tween()
	tween.set_parallel(true)
	root.scale = Vector3(0.72, 1, 0.72)
	tween.tween_property(root, "scale", Vector3(1.15, 1, 1.15), 0.18)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.2)
	tween.chain().tween_callback(root.queue_free)

static func spawn_death_burst(parent: Node3D, position: Vector3, tank: bool) -> void:
	var color := Color("#9fe6d8") if tank else Color("#72ded4")
	for index in 7:
		var shard := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.055, 0.14, 0.04) if tank else Vector3(0.035, 0.11, 0.025)
		shard.mesh = mesh
		shard.material_override = _material("death_shard", color, color, 2.0, true)
		shard.position = position + Vector3(0, 0.28, 0)
		shard.rotation = Vector3(randf() * 0.5, randf() * TAU, randf() * 0.5)
		parent.add_child(shard)
		var angle := TAU * float(index) / 7.0
		var tween := shard.create_tween()
		tween.set_parallel(true)
		tween.tween_property(shard, "position", shard.position + Vector3(cos(angle), 0.45 + randf() * 0.35, sin(angle)) * 0.62, 0.48)
		tween.tween_property(shard, "rotation", shard.rotation + Vector3(1.8, 1.2, -1.5), 0.48)
		tween.tween_property(shard, "scale", Vector3.ZERO, 0.48)
		tween.chain().tween_callback(shard.queue_free)