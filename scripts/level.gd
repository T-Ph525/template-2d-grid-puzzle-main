extends Node3D
class_name Level

## Builds the world from an ASCII map + a legend. EDITING THE MAP IS EDITING THE GAME.
## Every cell gets a ground tile (textured pixel-art); walls add a block on top; the player
## and crates are GridEntity nodes tracked in `_entities` / `_movers`.
##
## COLOR CHANNELS: doors, pressure plates, and keys each belong to a `channel` (a color).
## Channel 0 = no color (neutral). A door of channel C is OPEN while any plate of C is pressed,
## or PERMANENTLY once a key of C is collected. Colors live in Visuals.CHANNEL_COLORS.
##
## WIN: collect every star (`*`) to win. A level with no star falls back to the legacy
## sokoban rule (all channel-0 plates covered by a crate).

signal won   ## emitted once, the moment the win condition is first met
signal lost  ## emitted once when an enemy catches the player

const LEGEND := {
	"#": {type = "wall"},
	"@": {type = "player"},
	"$": {type = "box"},
	"*": {type = "star"},    # collect to win
	"T": {type = "tank"},
	">": {type = "exit"},
	"+": {type = "health"},
	"E": {type = "enemy"},   # chases the player; touching you = caught
	# channel 0 — no color:
	".": {type = "plate", channel = 0},   # also the sokoban win goal
	"K": {type = "key", channel = 0},
	"D": {type = "door", channel = 0},
	# channel 1 — blue:
	"b": {type = "plate", channel = 1},
	"B": {type = "key", channel = 1},
	"1": {type = "door", channel = 1},
	# channel 2 — green:
	"g": {type = "plate", channel = 2},
	"G": {type = "key", channel = 2},
	"2": {type = "door", channel = 2},
	# channel 3 — red:
	"r": {type = "plate", channel = 3},
	"R": {type = "key", channel = 3},
	"3": {type = "door", channel = 3},
	# anything else (space, etc.) = plain floor
}

const PlayerScript := preload("res://scripts/player.gd")
const BoxScript := preload("res://scripts/box.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const RogueVisuals := preload("res://scripts/roguelite/roguelite_art.gd")

var grid: Grid
var player: GridEntity

var _walls := {}        # Vector2i -> true (walls + closed doors)
var _doors := {}        # Vector2i -> Door
var _goals := []        # Array[Vector2i] (channel-0 plates double as win goals)
var _entities := {}     # Vector2i -> GridEntity (turn-based grid occupancy)
var _movers := []       # Array[GridEntity] (player + boxes; live occupancy in both modes)
var _rogue_floor_cells: Array = []
var _rogue_wall_cells: Array = []

# --- color-channel state ---
var _plates := []          # Array of { cell, channel, vis, pressed }
var _keys := {}            # Vector2i -> { channel, vis }
var _channel_doors := []   # Array of { channel, door }
var _key_collected := {}   # channel -> true (latched open forever)

# --- win state ---
var _stars := {}           # Vector2i -> star vis (uncollected)
var _star_total := 0       # stars the level started with
var _stars_collected := 0
var _won := false
var _lost := false

func build(map_lines: Array, grid_ref: Grid, tick_manager: TickManager) -> void:
	grid = grid_ref
	for y in map_lines.size():
		var line: String = map_lines[y]
		for x in line.length():
			var cell := Vector2i(x, y)
			var entry: Dictionary = LEGEND.get(line[x], {type = "floor"})
			var channel: int = entry.get("channel", 0)
			match entry.get("type", "floor"):
				"wall":
					_add_wall(cell)
				"plate":
					_add_tile(cell, Visuals.FLOOR_TEX)
					_add_plate(cell, channel)
				"key":
					_add_tile(cell, Visuals.FLOOR_TEX)
					_add_key(cell, channel)
				"star":
					_add_tile(cell, Visuals.FLOOR_TEX)
					_add_star(cell)
				"enemy", "tank":
					_add_tile(cell, Visuals.FLOOR_TEX)
					var enemy_visual: Node3D = RogueVisuals.make_enemy(entry.type == "tank") if rogue_run != null else Visuals.make_enemy()
					_spawn(EnemyScript, "enemy", cell, enemy_visual, tick_manager)
					if rogue_run != null:
						var enemy = _entities[cell]
						enemy.configure_rogue(entry.type == "tank", rogue_run.floor_number)
						enemies.append(enemy)
						floor_metrics.spawned += 1
				"exit":
					_add_tile(cell, Visuals.FLOOR_TEX)
					exit_cell = cell
					exit_visual = RogueVisuals.make_exit_portal() if rogue_run != null else Visuals.make_exit()
					exit_visual.position = grid.cell_to_world(cell) + Vector3(0, 0.025, 0)
					add_child(exit_visual)
				"health":
					_add_tile(cell, Visuals.FLOOR_TEX)
					add_drop(grid.cell_to_world(cell), "health", 25)
				"door":
					_add_door(cell, channel, map_lines)
				"player":
					_add_tile(cell, Visuals.FLOOR_TEX)
					var player_visual: Node3D = RogueVisuals.make_player() if rogue_run != null else Visuals.make_player(LevelManager.player_visual == LevelManager.PLAYER_ROBOT)
					_spawn(PlayerScript, "player", cell, player_visual, tick_manager)
				"box":
					_add_tile(cell, Visuals.FLOOR_TEX)
					_spawn_box(cell, tick_manager)
				_:
					_add_tile(cell, Visuals.FLOOR_TEX)
	if rogue_run != null:
		_finalize_roguelite_geometry()

# --- color channels (evaluated every frame; cheap for a handful of tiles) ---

func _process(_delta: float) -> void:
	if rogue_run != null:
		_rogue_process(_delta)
		return
	if grid == null:
		return
	_update_channels()

func _update_channels() -> void:
	# 1. Which cells currently have a mover (player or crate) on them?
	var occupied := {}
	for e in _movers:
		if is_instance_valid(e):
			occupied[grid.world_to_cell(e.global_position)] = true

	# 2. Player pickups: a key (latches its channel open) or a star (counts toward the win).
	if player != null and is_instance_valid(player):
		var pcell: Vector2i = grid.world_to_cell(player.global_position)
		if _keys.has(pcell):
			var info: Dictionary = _keys[pcell]
			_key_collected[info.channel] = true
			info.vis.queue_free()
			_keys.erase(pcell)
		if _stars.has(pcell):
			_stars[pcell].queue_free()
			_stars.erase(pcell)
			_stars_collected += 1

	# 3. Which channels are pressed right now? (any mover sitting on a plate of that channel)
	var pressed := {}
	for p in _plates:
		var down: bool = occupied.has(p.cell)
		if down:
			pressed[p.channel] = true
		if down != p.pressed:
			p.pressed = down
			_set_plate_texture(p)

	# 4. Open/close every door: open if its key is collected OR its channel is pressed.
	for d in _channel_doors:
		if _key_collected.get(d.channel, false) or pressed.get(d.channel, false):
			d.door.open()
		else:
			d.door.close()

	# 5. Win the moment the condition is met (frame-based, so star pickup fires instantly).
	if not _won and is_won():
		_won = true
		won.emit()

func _set_plate_texture(p: Dictionary) -> void:
	var mat: StandardMaterial3D = p.vis.material_override
	mat.albedo_texture = load(Visuals.PLATE_PRESSED_TEX if p.pressed else Visuals.PLATE_TEX)

# --- movement (the one rule every game shares) ---

## Try to move `entity` one cell in `dir`. Handles walls, bounds, and pushing.
## Returns true if the entity actually moved.
func try_move(entity: GridEntity, dir: Vector2i) -> bool:
	var target: Vector2i = entity.grid_pos + dir
	if not grid.in_bounds(target) or _walls.has(target):
		return false
	var other = _entities.get(target)   # a GridEntity (player) OR the RigidBody3D crate
	if other != null:
		if other.pushable:
			var beyond: Vector2i = target + dir
			if grid.in_bounds(beyond) and not _walls.has(beyond) and not _entities.has(beyond):
				_relocate(other, beyond)
			else:
				return false  # crate is jammed against something
		else:
			entity.on_bump(other)
			return false
	_relocate(entity, target)
	return true

func _relocate(entity, cell: Vector2i) -> void:
	_entities.erase(entity.grid_pos)
	entity.set_cell(cell)
	_entities[cell] = entity

func entity_at(cell: Vector2i) -> Node3D:
	return _entities.get(cell)

func door_at(cell: Vector2i) -> Door:
	return _doors.get(cell)

## Called by an enemy when it reaches the player. Ends the level (fires `lost` once).
func player_caught() -> void:
	if _lost:
		return
	_lost = true
	lost.emit()

# --- win condition ---
## Star levels win by collecting every star. Levels with no star fall back to the legacy
## sokoban rule (every channel-0 plate covered by a crate).
func is_won() -> bool:
	if _star_total > 0:
		return _stars_collected >= _star_total
	if _goals.is_empty():
		return false
	for g in _goals:
		var e = _entities.get(g)
		if e == null or not e.pushable:
			return false
	return true

# --- builders ---

func _add_tile(cell: Vector2i, texture_path: String) -> void:
	if rogue_run != null:
		_rogue_floor_cells.append(cell)
		return
	var t := Visuals.make_tile(texture_path)
	t.position = grid.cell_to_world(cell)
	add_child(t)

func _add_wall(cell: Vector2i) -> void:
	if rogue_run != null:
		_rogue_wall_cells.append(cell)
		_walls[cell] = true
		return
	var m: StaticBody3D = Visuals.make_wall()
	# Offset y by 0.5 so the wall cube sits ON the floor, not half-buried.
	m.position = grid.cell_to_world(cell) + Vector3(0, 0.5, 0)
	add_child(m)
	_walls[cell] = true

func _add_plate(cell: Vector2i, channel: int) -> void:
	# A pressure plate, drawn as a small overlay on the floor, tinted by its channel color.
	var vis := Visuals.make_tile(Visuals.PLATE_TEX, Vector2(0.6, 0.6), true, Visuals.channel_color(channel))
	vis.position = grid.cell_to_world(cell) + Vector3(0, 0.01, 0)
	add_child(vis)
	_plates.append({cell = cell, channel = channel, vis = vis, pressed = false})
	if channel == 0:
		_goals.append(cell)  # channel-0 plates double as the sokoban win goal

func _add_key(cell: Vector2i, channel: int) -> void:
	var vis := Visuals.make_key(Visuals.channel_color(channel))
	vis.position = grid.cell_to_world(cell) + Vector3(0, 0.5, 0)  # float above the floor tile
	add_child(vis)
	_keys[cell] = {channel = channel, vis = vis}

func _add_star(cell: Vector2i) -> void:
	var s := Visuals.make_star()
	s.position = grid.cell_to_world(cell) + Vector3(0, 0.55, 0)  # float above the floor tile
	add_child(s)
	_stars[cell] = s
	_star_total += 1

func _add_door(cell: Vector2i, channel: int, map_lines: Array) -> void:
	_add_tile(cell, Visuals.FLOOR_TEX)  # floor under the door (visible when it opens)
	var channel_tint := Visuals.channel_color(channel)
	var d: Door = RogueVisuals.make_door(channel_tint) if rogue_run != null else Visuals.make_door(channel_tint)
	# Sit the slab on the floor, dropped 0.05 so its bottom face doesn't z-fight the floor tile.
	d.position = grid.cell_to_world(cell) + Vector3(0, 0.45, 0)
	# Auto-orient: a door set into a VERTICAL wall (walls above & below) turns 90 degrees so you
	# pass through it left<->right. Otherwise it keeps the default up<->down passage.
	var vertical_wall := _is_wall_char(map_lines, cell.x, cell.y - 1) and _is_wall_char(map_lines, cell.x, cell.y + 1)
	var horizontal_wall := _is_wall_char(map_lines, cell.x - 1, cell.y) and _is_wall_char(map_lines, cell.x + 1, cell.y)
	if vertical_wall and not horizontal_wall:
		d.rotation.y = deg_to_rad(90)
	add_child(d)
	_walls[cell] = true  # blocks movement when closed
	_doors[cell] = d
	_channel_doors.append({channel = channel, door = d})
	# Door open/close keeps the wall flag in sync so turn-based movement respects it.
	d.opened.connect(func(): _walls.erase(cell))
	d.closed.connect(func(): _walls[cell] = true)

## True if map_lines has a wall ('#') at (x, y); false if out of bounds or not a wall.
func _is_wall_char(map_lines: Array, x: int, y: int) -> bool:
	if y < 0 or y >= map_lines.size():
		return false
	var line: String = map_lines[y]
	if x < 0 or x >= line.length():
		return false
	return line[x] == "#"

func _spawn(script: GDScript, kind: String, cell: Vector2i, mesh: Node3D, tick_manager: TickManager) -> void:
	var e: GridEntity = script.new()
	e.name = "Player" if kind == "player" else "Enemy%d" % _movers.size()
	e.kind = kind
	add_child(e)
	e.add_child(mesh)

	# Collision shape so the entity blocks movement in real-time mode.
	var col := CollisionShape3D.new()
	if kind == "player" or kind == "enemy":
		var cap := CapsuleShape3D.new()
		cap.radius = 0.32
		cap.height = 1.0
		col.shape = cap
		col.position.y = 0.5
		e.collision_layer = Visuals.LAYER_ENTITY
		e.collision_mask = Visuals.LAYER_WORLD | Visuals.LAYER_ENTITY
	else:
		var box := BoxShape3D.new()
		box.size = Vector3(0.9, 0.9, 0.9)   # match the visual
		col.shape = box
		col.position.y = 0.5                # center in the cube
		e.collision_layer = Visuals.LAYER_ENTITY
		e.collision_mask = Visuals.LAYER_WORLD | Visuals.LAYER_ENTITY  # collide with walls + other entities
	e.add_child(col)

	e.setup(self, cell)
	_entities[cell] = e
	_movers.append(e)
	tick_manager.tick.connect(e.on_tick)
	if kind == "player":
		player = e

## Crates are RigidBody3D (real physics in real-time; frozen + grid-controlled in turn-based).
func _spawn_box(cell: Vector2i, tick_manager: TickManager) -> void:
	var box = BoxScript.new()   # untyped: it's a RigidBody3D + the box.gd grid interface
	box.collision_layer = Visuals.LAYER_ENTITY
	box.collision_mask = Visuals.LAYER_WORLD | Visuals.LAYER_ENTITY
	box.add_child(Visuals.make_box())          # centered wood cube
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, 0.9, 0.9)
	col.shape = shape
	box.add_child(col)
	add_child(box)
	box.setup(self, cell)                       # positions it (must be in the tree first)
	_entities[cell] = box
	_movers.append(box)
	tick_manager.tick.connect(box.on_tick)

# Shared build/nav extension for procedural survival maps.
signal floor_exit
const Feedback := preload("res://scripts/roguelite/combat_feedback.gd")
var feedback_counts: Dictionary = {"damage": 0, "strike": 0, "death": 0, "telegraph": 0, "unlock": 0, "heal": 0}
var floor_metrics: Dictionary = {"sim_seconds": 0.0, "encounter_seconds": 0.0, "movement_seconds": 0.0, "navigation_seconds": 0.0, "combat_movement_seconds": 0.0, "blocked_seconds": 0.0, "distance": 0.0, "kills": 0, "damage_received": 0, "xp_gained": 0, "healing": 0, "upgrades": 0, "upgrade_ids": [], "clear_at": -1.0, "spawned": 0, "guard_activations": 0}
var _wall_started_ms: int = Time.get_ticks_msec()
var rogue_run = null
var combat_active: bool = true
var enemies: Array = []
var drops: Array = []
var exit_cell := Vector2i(-1, -1)
var exit_visual: Node3D
var exit_active: bool = false
var _distance_field: Dictionary = {}
var _nav_delay: float = 0.0
var _nav_player_cell := Vector2i(-999, -999)
const NAV_DIRS := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

func walkable(cell: Vector2i) -> bool:
	return grid != null and grid.in_bounds(cell) and not _walls.has(cell)

func has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var count := maxi(1, ceili(from.distance_to(to) * 12.0))
	var previous: Vector2i = grid.world_to_cell(from)
	if not walkable(previous):
		return false
	for i in range(1, count + 1):
		var cell: Vector2i = grid.world_to_cell(from.lerp(to, float(i) / count))
		if not walkable(cell):
			return false
		if cell.x != previous.x and cell.y != previous.y:
			if not walkable(Vector2i(cell.x, previous.y)) or not walkable(Vector2i(previous.x, cell.y)):
				return false
		previous = cell
	return true

func _rebuild_navigation() -> void:
	_distance_field.clear()
	if player == null:
		return
	var start: Vector2i = grid.world_to_cell(player.global_position)
	_nav_player_cell = start
	var queue: Array[Vector2i] = [start]
	_distance_field[start] = 0
	var cursor := 0
	while cursor < queue.size():
		var cell := queue[cursor]
		cursor += 1
		for direction: Vector2i in NAV_DIRS:
			var next := cell + direction
			if walkable(next) and not _distance_field.has(next):
				_distance_field[next] = int(_distance_field[cell]) + 1
				queue.append(next)

func chase_target(world_position: Vector3) -> Vector3:
	var cell := grid.world_to_cell(world_position)
	if not _distance_field.has(cell):
		return world_position
	if cell == _nav_player_cell:
		return player.global_position
	var best := cell
	var distance: int = _distance_field[cell]
	var world_distance := grid.cell_to_world(cell).distance_squared_to(player.global_position)
	for direction: Vector2i in NAV_DIRS:
		var next := cell + direction
		var next_cost: int = _distance_field.get(next, 99999)
		var next_world_distance := grid.cell_to_world(next).distance_squared_to(player.global_position)
		if walkable(next) and (next_cost < distance or (next_cost == distance and next_cost < int(_distance_field[cell]) and next_world_distance < world_distance)):
			best = next
			distance = next_cost
			world_distance = next_world_distance
	# Align to corridor center before changing axis, preventing corner snags.
	var center := grid.cell_to_world(cell)
	var next_center := grid.cell_to_world(best)
	if best.x != cell.x and absf(world_position.z - center.z) > 0.08:
		return Vector3(world_position.x, 0, center.z)
	if best.y != cell.y and absf(world_position.x - center.x) > 0.08:
		return Vector3(center.x, 0, world_position.z)
	return next_center

func _rogue_process(delta: float) -> void:
	if not combat_active or rogue_run.ended or player == null:
		return
	floor_metrics.sim_seconds += delta
	if not enemies.is_empty():
		floor_metrics.encounter_seconds += delta
	_update_channels()
	_nav_delay -= delta
	var current_cell := grid.world_to_cell(player.global_position)
	if _nav_delay <= 0.0 or current_cell != _nav_player_cell:
		_nav_delay = 0.2
		_rebuild_navigation()
	for i in range(drops.size() - 1, -1, -1):
		var drop: Dictionary = drops[i]
		var node: Node3D = drop.node
		var distance: float = node.global_position.distance_to(player.global_position)
		var radius := 1.0 if drop.kind == "xp" else 0.65
		if distance <= radius and has_line_of_sight(node.global_position, player.global_position):
			if drop.kind == "xp":
				floor_metrics.xp_gained += int(drop.amount)
				rogue_run.add_xp(drop.amount)
				Feedback.pickup(self, node.global_position, "xp")
			else:
				if rogue_run.hp >= rogue_run.max_hp:
					continue
				var healed: int = mini(rogue_run.max_hp - rogue_run.hp, int(drop.amount))
				rogue_run.hp += healed
				floor_metrics.healing += healed
				feedback_counts.heal += 1
				Feedback.pickup(self, node.global_position, "health")
				Feedback.number(self, player.global_position, healed, Color(0.5, 1, 0.6), "+")
			node.queue_free()
			drops.remove_at(i)
	var was_active := exit_active
	exit_active = enemies.is_empty()
	if exit_active and not was_active:
		floor_metrics.clear_at = floor_metrics.sim_seconds
		feedback_counts.unlock += 1
		Feedback.ring(self, grid.cell_to_world(exit_cell), Color(0.4, 1, 0.65), 0.8, 0.9)
	if exit_visual != null and exit_active != was_active:
		if exit_visual.has_method("set_active"):
			exit_visual.set_active(exit_active)
		else:
			exit_visual.material_override = Visuals._flat(Color(0.4, 1.0, 0.65) if exit_active else Color(0.25, 0.3, 0.28))
	if exit_active and current_cell == exit_cell:
		combat_active = false
		floor_exit.emit()

func enemy_defeated(enemy: Node3D, reward: int) -> void:
	floor_metrics.kills += 1
	feedback_counts.death += 1
	Feedback.death(self, enemy.global_position, enemy.tank)
	enemies.erase(enemy)
	_movers.erase(enemy)
	_entities.erase(enemy.grid_pos)
	add_drop(enemy.global_position, "xp", reward)
	if rogue_run.rng.randf() < 0.2:
		add_drop(enemy.global_position, "health", 15)

func add_drop(world_position: Vector3, kind: String, amount: int) -> void:
	var visual: Node3D = RogueVisuals.make_drop(kind) if rogue_run != null else Visuals.make_drop(kind)
	visual.position = Vector3(world_position.x, 0.2, world_position.z)
	add_child(visual)
	drops.append({"node": visual, "kind": kind, "amount": amount})

func show_strike(from: Vector3, to: Vector3) -> void:
	feedback_counts.strike += 1
	Feedback.strike(self, from, to)
	Feedback.ring(self, to, Color(1, 0.95, 0.5), 0.3, 0.15)

func damage_feedback(world_position: Vector3, amount: int, player_hit: bool) -> void:
	feedback_counts.damage += 1
	Feedback.number(self, world_position, amount, Color(1, 0.35, 0.35) if player_hit else Color(1, 0.95, 0.7))
	if player_hit:
		Feedback.ring(self, world_position, Color(1, 0.25, 0.25), 0.45, 0.2)

func attack_telegraph(world_position: Vector3, duration: float) -> MeshInstance3D:
	feedback_counts.telegraph += 1
	return Feedback.ring(self, world_position, Color(1, 0.6, 0.15), 0.95, duration, false)

func stop_combat() -> void:
	combat_active = false
	process_mode = Node.PROCESS_MODE_DISABLED
	for mover in _movers:
		if is_instance_valid(mover):
			if mover.has_method("cancel_attack"):
				mover.cancel_attack()
			if mover is CharacterBody3D:
				mover.velocity = Vector3.ZERO
			mover.process_mode = Node.PROCESS_MODE_DISABLED

func record_motion(before: Vector3, after: Vector3, commanded_velocity: Vector3, delta: float) -> void:
	var travelled := before.distance_to(after)
	floor_metrics.distance += travelled
	if travelled > 0.001:
		floor_metrics.movement_seconds += delta
		var in_combat := enemies.any(func(e): return e.global_position.distance_to(after) <= float(rogue_run.attack_range) + 0.4 and has_line_of_sight(e.global_position, after))
		if in_combat:
			floor_metrics.combat_movement_seconds += delta
		else:
			floor_metrics.navigation_seconds += delta
	elif commanded_velocity.length_squared() > 0.01:
		floor_metrics.blocked_seconds += delta

func measurements(outcome: String = "active") -> Dictionary:
	var data := floor_metrics.duplicate(true)
	data["floor"] = rogue_run.floor_number
	data["outcome"] = outcome
	data["wall_seconds"] = (Time.get_ticks_msec() - _wall_started_ms) / 1000.0
	data["enemies_left"] = enemies.size()
	data["exit_travel_seconds"] = maxf(0.0, float(data.sim_seconds) - float(data.clear_at)) if float(data.clear_at) >= 0.0 else 0.0
	data["unreachable_enemies"] = enemies.filter(func(e): return not _distance_field.has(grid.world_to_cell(e.global_position))).size()
	return data

func guard_awakened(world_position: Vector3) -> void:
	floor_metrics.guard_activations += 1
	Feedback.ring(self, world_position, Color(0.8, 0.55, 1), 0.55, 0.4)

func steer_around_peers(actor: Node3D, desired: Vector3) -> Vector3:
	if desired.length_squared() < 0.01:
		return desired
	var cell := grid.world_to_cell(actor.global_position)
	var openings := 0
	for direction: Vector2i in NAV_DIRS:
		if walkable(cell + direction):
			openings += 1
	# Do not push enemies sideways into narrow-corridor walls.
	if openings < 3:
		return desired
	var forward := desired.normalized()
	var avoidance := Vector3.ZERO
	for other in enemies:
		if other == actor or not is_instance_valid(other):
			continue
		var offset: Vector3 = actor.global_position - other.global_position
		var distance := offset.length()
		if distance < 0.6:
			if distance < 0.01:
				offset = Vector3(-forward.z, 0, forward.x) * (1.0 if String(actor.name) < String(other.name) else -1.0)
			avoidance += offset.normalized() * (0.6 - distance)
	avoidance -= forward * avoidance.dot(forward)
	return (forward + avoidance.limit_length(0.12)).normalized() * desired.length()
func decorate_roguelite(world_environment: WorldEnvironment) -> void:
	if rogue_run == null:
		return
	RogueVisuals.decorate_level(self, world_environment)
func _finalize_roguelite_geometry() -> void:
	if _rogue_floor_cells.is_empty():
		return
	add_child(RogueVisuals.make_floor_layer(_rogue_floor_cells, rogue_run.floor_number))
	add_child(RogueVisuals.make_wall_layer(_rogue_wall_cells, rogue_run.floor_number))
	add_child(RogueVisuals.make_wall_collision_body(_rogue_wall_cells))