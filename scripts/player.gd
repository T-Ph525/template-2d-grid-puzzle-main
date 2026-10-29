extends GridEntity

## The player. In turn-based mode on_tick() reads input and asks the Level for one grid move.
## In real-time mode _physics_process() reads input every frame and calls move_and_slide()
## for free movement with real collision against walls. When the player walks into a
## pushable box, velocity transfers to the box so it slides away.
##
## Input actions (move_up/down/left/right, action) come from the keyboard OR an Arduino --
## this script doesn't know or care which. See scripts/input_router.gd.

const MOVE_SPEED: float = 5.0
const PUSH_IMPULSE: float = 0.6   ## per-frame shove into a crate; capped at MOVE_SPEED so it can't run away

func _physics_process(_delta: float) -> void:
	if level != null and level.rogue_run != null:
		_rogue_physics(_delta)
		return
	if not _use_physics:
		return
	var dir := _read_dir_free()
	velocity = Vector3(dir.x, 0.0, dir.y) * MOVE_SPEED
	move_and_slide()

	# Push any pushable box we collided with.
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var other := col.get_collider()
		if other is RigidBody3D and other.pushable:
			var push_dir := -col.get_normal()
			push_dir.y = 0.0
			push_dir = push_dir.normalized()
			# Push at the CONTACT POINT so an off-center hit also spins the crate. Cap its speed
			# near ours so repeated per-frame impulses don't accelerate it forever.
			if other.linear_velocity.dot(push_dir) < MOVE_SPEED:
				other.apply_impulse(push_dir * PUSH_IMPULSE, col.get_position() - other.global_position)

func on_tick() -> void:
	if _use_physics:
		return
	var dir := _read_dir_grid()
	if dir != Vector2i.ZERO:
		level.try_move(self, dir)

## Grid movement: single-axis priority, no diagonals.
func _read_dir_grid() -> Vector2i:
	if Input.is_action_pressed("move_up"):
		return Vector2i(0, -1)
	if Input.is_action_pressed("move_down"):
		return Vector2i(0, 1)
	if Input.is_action_pressed("move_left"):
		return Vector2i(-1, 0)
	if Input.is_action_pressed("move_right"):
		return Vector2i(1, 0)
	return Vector2i.ZERO

## Free movement: normalized vector, diagonals allowed.
func _read_dir_free() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		dir.y -= 1.0
	if Input.is_action_pressed("move_down"):
		dir.y += 1.0
	if Input.is_action_pressed("move_left"):
		dir.x -= 1.0
	if Input.is_action_pressed("move_right"):
		dir.x += 1.0
	return dir.normalized()

# Roguelite combat is opt-in; Puzzle keeps the original movement/tick implementation.
var invulnerability: float = 0.0
var attack_cooldown: float = 0.0
var attacks_made: int = 0
var hits_taken: int = 0
var _actor_visual: Node3D

func _rogue_physics(delta: float) -> void:
	var run = level.rogue_run
	if run.ended or not level.combat_active:
		velocity = Vector3.ZERO
		return
	invulnerability = maxf(0.0, invulnerability - delta)
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	# Four directions; no diagonal speed or corner-cutting.
	var direction := _read_dir_grid()
	if _actor_visual == null:
		_actor_visual = get_node_or_null("Visual") as Node3D
	if _actor_visual != null:
		if _actor_visual.has_method("set_moving"):
			_actor_visual.set_moving(direction != Vector2i.ZERO)
		if direction != Vector2i.ZERO and _actor_visual.has_method("face_direction"):
			_actor_visual.face_direction(Vector3(direction.x, 0, direction.y))
	velocity = Vector3(direction.x, 0, direction.y) * run.movement_speed
	var before_move := global_position
	var commanded_velocity := velocity
	move_and_slide()
	level.record_motion(before_move, global_position, commanded_velocity, delta)
	grid_pos = level.grid.world_to_cell(global_position)
	for child in get_children():
		if child is AnimatedSprite3D:
			child.modulate = (Color(3, 3, 3) if invulnerability > 0.7 else Color(1, 0.35, 0.35)) if invulnerability > 0.55 else Color.WHITE
	if attack_cooldown > 0.0:
		return
	var target: Node3D = null
	var nearest: float = run.attack_range
	for enemy in level.enemies:
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		var distance: float = global_position.distance_to(enemy.global_position)
		if distance <= nearest and level.has_line_of_sight(global_position, enemy.global_position):
			target = enemy
			nearest = distance
	if target != null:
		attack_cooldown = run.attack_interval
		attacks_made += 1
		if _actor_visual != null:
			if _actor_visual.has_method("face_direction"):
				_actor_visual.face_direction(target.global_position - global_position)
			if _actor_visual.has_method("play_attack"):
				_actor_visual.play_attack(0.26)
		level.show_strike(global_position, target.global_position)
		target.take_damage(run.damage)

func take_damage(amount: int) -> bool:
	if level == null or level.rogue_run == null or not level.combat_active:
		return false
	var run = level.rogue_run
	if run.ended or invulnerability > 0.0:
		return false
	var applied := mini(int(run.hp), maxi(1, amount - int(run.damage_reduction)))
	run.hp = maxi(0, run.hp - applied)
	level.floor_metrics.damage_received += applied
	level.damage_feedback(global_position, applied, true)
	if _actor_visual != null and _actor_visual.has_method("play_hit"):
		_actor_visual.play_hit()
	invulnerability = 0.8
	hits_taken += 1
	if run.hp == 0:
		if _actor_visual != null and _actor_visual.has_method("play_death"):
			_actor_visual.play_death()
		level.player_caught()
	return true
