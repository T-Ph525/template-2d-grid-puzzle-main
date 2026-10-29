extends GridEntity

## An enemy that greedily steps toward the player and ends the level when it catches you.
## Works in BOTH modes like every entity: on_tick() for turn-based, _physics_process() for
## real-time (gated by _use_physics). Walls are COVER -- a blocked enemy just stays put; there
## is deliberately no pathfinding around walls, so the player uses walls to escape.

const MOVE_SPEED := 3.5     ## real-time chase speed (slower than the player's 5.0, so you can outrun it)
const TICKS_PER_MOVE := 2   ## turn-based: step once every N player ticks (higher = slower = easier)
const CATCH_RADIUS := 0.8   ## real-time catch distance (must exceed the ~0.64 capsule-contact gap)

var _tick_count := 0

func _init() -> void:
	pushable = false
	kind = "enemy"

# --- turn-based ---
func on_tick() -> void:
	if level != null and level.rogue_run != null:
		return
	if _use_physics or level.player == null:
		return
	_tick_count += 1
	if _tick_count % TICKS_PER_MOVE == 0:
		var d: Vector2i = level.player.grid_pos - grid_pos
		# Greedy: try the larger axis first, then the other. Blocked both ways -> stay put.
		for step in _step_order(d):
			if step != Vector2i.ZERO and level.try_move(self, step):
				break
	_check_caught()

func _step_order(d: Vector2i) -> Array:
	var horiz := Vector2i(signi(d.x), 0)
	var vert := Vector2i(0, signi(d.y))
	return [horiz, vert] if abs(d.x) >= abs(d.y) else [vert, horiz]

# --- real-time ---
func _physics_process(_delta: float) -> void:
	if level != null and level.rogue_run != null:
		_rogue_physics(_delta)
		return
	if not _use_physics:
		return
	if level.player != null:
		var to_player: Vector3 = level.player.global_position - global_position
		to_player.y = 0.0
		velocity = to_player.normalized() * MOVE_SPEED
	move_and_slide()
	_check_caught()

func _check_caught() -> void:
	if level.player == null:
		return
	if _use_physics:
		var a: Vector3 = global_position;  a.y = 0.0
		var b: Vector3 = level.player.global_position;  b.y = 0.0
		if a.distance_to(b) < CATCH_RADIUS:
			level.player_caught()
	else:
		var d: Vector2i = level.player.grid_pos - grid_pos
		if abs(d.x) + abs(d.y) <= 1:  # reached an adjacent cell -> grabs you
			level.player_caught()

var health: int = 40
var contact_damage: int = 12
var chase_speed: float = 2.15
var xp_reward: int = 5
var dead: bool = false
var contact_cooldown: float = 0.0
var hit_flash: float = 0.0
var tank: bool = false
var windup_remaining: float = 0.0
var telegraph: MeshInstance3D
var telegraphs_started: int = 0
var attacks_resolved: int = 0
var _has_nav_waypoint: bool = false
var _nav_waypoint: Vector3 = Vector3.ZERO
var _nav_stall_seconds: float = 0.0
var awake: bool = true
var _actor_visual: Node3D

func configure_rogue(is_tank: bool, floor_number: int) -> void:
	tank = is_tank
	awake = not tank
	_actor_visual = get_node_or_null("Visual") as Node3D
	health = (85 if tank else 36) + floor_number * 6
	contact_damage = 22 if tank else 12
	chase_speed = 1.35 if tank else 2.15
	xp_reward = 7 if tank else 4
	collision_layer = 4
	collision_mask = Visuals.LAYER_WORLD
	set_physics_active(true)

func _rogue_physics(delta: float) -> void:
	if dead or not level.combat_active or level.rogue_run.ended or level.player == null:
		velocity = Vector3.ZERO
		return
	if not awake:
		var distance_cost: int = level._distance_field.get(level.grid.world_to_cell(global_position), 99999)
		if distance_cost <= 5:
			awaken()
		else:
			velocity = Vector3.ZERO
			return
	contact_cooldown = maxf(0.0, contact_cooldown - delta)
	hit_flash = maxf(0.0, hit_flash - delta)
	if _actor_visual == null:
		_actor_visual = get_node_or_null("Visual") as Node3D
	if windup_remaining > 0.0:
		velocity = Vector3.ZERO
		if _actor_visual != null and _actor_visual.has_method("set_moving"):
			_actor_visual.set_moving(false)
		windup_remaining = maxf(0.0, windup_remaining - delta)
		if windup_remaining == 0.0:
			var target_position: Vector3 = level.player.global_position
			attacks_resolved += 1
			if global_position.distance_to(target_position) <= 0.95 and level.has_line_of_sight(global_position, target_position):
				level.player.take_damage(contact_damage)
			contact_cooldown = 0.9
			if _actor_visual != null and _actor_visual.has_method("play_attack"):
				_actor_visual.play_attack(0.28 if tank else 0.2)
			cancel_attack()
		return
	grid_pos = level.grid.world_to_cell(global_position)
	if not _has_nav_waypoint or global_position.distance_to(_nav_waypoint) <= 0.08 or not level.walkable(level.grid.world_to_cell(_nav_waypoint)) or _nav_stall_seconds > 0.5:
		_nav_waypoint = level.chase_target(global_position)
		_has_nav_waypoint = true
		_nav_stall_seconds = 0.0
	var offset := _nav_waypoint - global_position
	offset.y = 0.0
	velocity = offset.normalized() * chase_speed if offset.length() > 0.08 else Vector3.ZERO
	velocity = level.steer_around_peers(self, velocity)
	if _actor_visual != null:
		if _actor_visual.has_method("set_moving"):
			_actor_visual.set_moving(velocity.length_squared() > 0.01)
		if _actor_visual.has_method("face_direction") and velocity.length_squared() > 0.01:
			_actor_visual.face_direction(velocity)
	var before_move := global_position
	move_and_slide()
	_nav_stall_seconds = _nav_stall_seconds + delta if before_move.distance_to(global_position) < 0.001 else 0.0
	var target: Vector3 = level.player.global_position
	if contact_cooldown <= 0.0 and global_position.distance_to(target) <= 0.85 and level.has_line_of_sight(global_position, target):
		windup_remaining = 0.7 if tank else 0.45
		telegraphs_started += 1
		telegraph = level.attack_telegraph(global_position, windup_remaining)
		velocity = Vector3.ZERO
		if _actor_visual != null and _actor_visual.has_method("play_windup"):
			_actor_visual.play_windup(windup_remaining)

func take_damage(amount: int) -> void:
	if dead or level == null or level.rogue_run == null or not level.combat_active:
		return
	var applied := mini(health, maxi(0, amount))
	if applied == 0:
		return
	if not awake:
		awaken()
	health -= applied
	level.damage_feedback(global_position, applied, false)
	hit_flash = 0.12
	if _actor_visual != null and _actor_visual.has_method("play_hit"):
		_actor_visual.play_hit()
	if health <= 0:
		dead = true
		cancel_attack()
		if _actor_visual != null and _actor_visual.has_method("play_death"):
			_actor_visual.play_death()
		collision_layer = 0
		collision_mask = 0
		level.enemy_defeated(self, xp_reward)
		get_tree().create_timer(0.55).timeout.connect(queue_free)

func cancel_attack() -> void:
	windup_remaining = 0.0
	if is_instance_valid(telegraph):
		telegraph.queue_free()
	telegraph = null

func awaken() -> void:
	if awake:
		return
	awake = true
	level.guard_awakened(global_position)
