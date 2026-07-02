# Enemy.gd
# Extends Character — handles AI decision making, target detection, and behavior.
extends Character
class_name Enemy

# ── Exports ──────────────────────────────────────────────────────

@export var can_pick_up_weapons: bool = false
@export var can_toss_weapons: bool = false
@export var can_find_weapons: bool = false
@export var can_dodge: bool = false
@export var can_double_dodge: bool = false
@export var destroy_weapon_on_death: bool = false

@export_group("Round")
@export var lives: int = 1
@export var is_main_enemy: bool = false

@export_group("Spawn")
@export var spawn_point: Marker2D

@export_group("AI")
@export var detection_range: float = 100.0
@export var idle_wander_speed: float = 0.0

@export_group("Intelligence")
@export var weapon_detection_range: float = 100.0

@export var is_careful: bool = false
@export var is_healthy: bool = false

@export var is_scared: bool = false
@export var is_aggressive: bool = false

@export var is_picky: bool = false
@export var is_desperate: bool = false

@export var is_swift: bool = false
@export var is_panic: bool = false
@export var dodge_interval_min: float = 1.0
@export var dodge_interval_max: float = 3.0

@export var is_tactical: bool = false
@export var is_strafing: bool = false
@export var tactical_strafe_min: float = 1.5
@export var tactical_strafe_max: float = 3.5

@export_group("Attack")
@export var main_attack_cooldown: float = 0.8
@export var alt_attack_cooldown: float = 0.8
@export var can_combo: bool = false
@export var combo_switch_min: float = 1.0
@export var combo_switch_max: float = 2.5

# ── Node References ──────────────────────────────────────────────

@onready var detection_area: Area2D = $DetectionArea
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D

# ── Variables ────────────────────────────────────────────────────

var _main_attack_timer: float = 0.0
var _alt_attack_timer: float = 0.0

var _combo_switch_timer: float = 0.0
var _use_alt_attack: bool = false

var _dodge_timer: float = 0.0
var _pending_dodges: int = 0

var _strafe_timer: float = 0.0
var _strafe_angle_offset: float = 0.0
var _strafe_direction: float = 1.0

var _weapon_target: Node = null  # the pickup node being sought
var _weapon_scan_timer: float = 0.0
const WEAPON_SCAN_INTERVAL: float = 0.1  # scan for weapons every 0.1s

var _seeking_better_weapon: bool = false

var _item_target: Node = null

var _toss_cooldown_timer: float = 0.0
const TOSS_COOLDOWN: float = 0.8

const LOW_HP_THRESHOLD: float = 0.35

# ── State ────────────────────────────────────────────────────────

enum FacingDirection {
	UP,
	UP_RIGHT,
	RIGHT,
	DOWN_RIGHT,
	DOWN,
	DOWN_LEFT,
	LEFT,
	UP_LEFT,
}

@export var initial_facing: FacingDirection = FacingDirection.DOWN

var target: Node2D = null
var targets_in_range: Array = []

enum AIState {
	IDLE,
	SEEK_WEAPON,
	SEEK_ITEM,
	ACTIVE,
}

var ai_state: AIState = AIState.IDLE

# ── Ready ────────────────────────────────────────────────────────

func _ready() -> void:
	super()
	detection_area.body_entered.connect(_on_target_entered)
	detection_area.body_exited.connect(_on_target_exited)
	var shape: CircleShape2D = $DetectionArea/CollisionShape2D.shape as CircleShape2D
	if shape != null:
		shape.radius = detection_range
	if can_double_dodge and not can_dodge:
		push_warning(name + ": can_double_dodge is true but can_dodge is false — can_double_dodge will have no effect.")
	if is_strafing and not is_tactical:
		push_warning(name + ": is_strafing is true but is_tactical is false — is_strafing will have no effect.")
	var dir := _facing_to_vector(initial_facing)
	last_direction = dir
	rotation = dir.angle()
	await get_tree().physics_frame
	_find_player_target()
	_reset_dodge_timer()
	_reset_strafe_timer()
	_reset_combo_switch_timer()

# ── Health Callbacks ─────────────────────────────────────────────

func _on_damaged(_amount: int, _remaining: int) -> void:
	var tween := create_tween()
	tween.tween_property($Body, "modulate", Color(8.0, 8.0, 8.0, 1.0), 0.05)
	tween.tween_property($Body, "modulate", Color.WHITE, 0.1)

func _on_died() -> void:
	call_deferred("_drop_weapon")
	var tween := create_tween()
	tween.tween_property($Body, "modulate", Color(8.0, 8.0, 8.0, 1.0), 0.1)
	tween.tween_interval(0.1)
	tween.tween_callback(func(): 
		_apply_death_state()
		set_physics_process(false)
		set_process(false)
	)

func _drop_weapon() -> void:
	if current_weapon == null:
		return
	if destroy_weapon_on_death:
		current_weapon = null
		return
	if weapon_pickup_scene == null:
		push_warning(name + ": weapon_pickup_scene not assigned, can't drop weapon.")
		return
	var data := current_weapon
	current_weapon = null
	_update_weapon_visuals()
	var pickup = weapon_pickup_scene.instantiate()
	pickup.weapon_data = data
	pickup._was_tossed = true
	pickup.position = global_position
	get_parent().add_child(pickup)
	pickup.setup_toss(global_position, Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized())

# ── Detection ────────────────────────────────────────────────────

func _find_player_target() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player and is_instance_valid(player) and not player.is_dead:
		target = player
		ai_state = AIState.ACTIVE
	else:
		target = null
		ai_state = AIState.IDLE

func try_pickup(pickup_node: Node) -> void:
	if current_weapon != null:
		var hp_percent := float(health.current_hp) / float(health.max_hp)
		var picky_active := is_picky and hp_percent > LOW_HP_THRESHOLD
		var desperate_active := is_desperate and hp_percent <= LOW_HP_THRESHOLD
		if picky_active or desperate_active:
			var incoming_power: int = pickup_node.weapon_data.power if pickup_node.weapon_data else 0
			if incoming_power > current_weapon.power:
				# Toss current weapon and pick up the better one
				_do_toss()
				# Wait one frame for toss to clear current_weapon
				await get_tree().physics_frame
				if is_instance_valid(pickup_node) and not pickup_node._was_picked_up:
					super.try_pickup(pickup_node)
				_weapon_scan_timer = 0.0
				_seeking_better_weapon = false
				_weapon_target = null
				_use_alt_attack = false
				_reset_combo_switch_timer()
				return
	super.try_pickup(pickup_node)
	_weapon_scan_timer = 0.0
	_seeking_better_weapon = false
	_weapon_target = null
	_use_alt_attack = false
	_reset_combo_switch_timer()

func _on_target_entered(body: Node2D) -> void:
	if body is Player:
		if not targets_in_range.has(body):
			targets_in_range.append(body)
		target = _get_nearest_target()

func _on_target_exited(body: Node2D) -> void:
	if body is Player:
		targets_in_range.erase(body)
		target = _get_nearest_target()

func _get_nearest_target() -> Node2D:
	if targets_in_range.is_empty():
		return null
	var nearest: Node2D = null
	var nearest_dist: float = INF
	for t in targets_in_range:
		if not is_instance_valid(t):
			continue
		var dist := global_position.distance_to(t.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = t
	return nearest

# ── AI State Machine ─────────────────────────────────────────────

func _update_ai_state() -> void:
	if _seeking_better_weapon and current_weapon != null and _weapon_target != null:
		if not is_instance_valid(_weapon_target) or _weapon_target._was_picked_up:
			_seeking_better_weapon = false
			_weapon_target = null
	
	# Invalidate weapon target if it's gone or picked up
	if _weapon_target != null:
		if not is_instance_valid(_weapon_target) or _weapon_target._was_picked_up:
			_weapon_target = null
			
	# Invalidate item target if it's gone or picked up		
	if _item_target != null:
		if not is_instance_valid(_item_target) or _item_target._was_picked_up:
			_item_target = null
			
	# Scan for heal item — highest priority when scared and low HP
	_item_target = _scan_for_heal_item()
	if _item_target != null:
		ai_state = AIState.SEEK_ITEM
		main_attack_held = false
		return

	# Scan for weapons on interval
	_weapon_scan_timer -= get_physics_process_delta_time()
	if _weapon_scan_timer <= 0.0:
		_weapon_scan_timer = WEAPON_SCAN_INTERVAL
		if can_find_weapons:
			if current_weapon == null:
				_weapon_target = _scan_for_weapon()
				_seeking_better_weapon = false
			elif _toss_cooldown_timer <= 0.0:
				var better := _scan_for_better_weapon()
				if better != null:
					_weapon_target = better
					_seeking_better_weapon = true
					_toss_cooldown_timer = TOSS_COOLDOWN
					call_deferred("_toss_backward_and_seek")

	# Weapon seeking takes priority — check this before target validation
	if _weapon_target != null and (current_weapon == null or _seeking_better_weapon):
		ai_state = AIState.SEEK_WEAPON
		return

	# No target — try to find player
	if target == null or not is_instance_valid(target) or target.is_dead:
		_find_player_target()
		if target == null:
			ai_state = AIState.IDLE
			main_attack_held = false
			return

	ai_state = AIState.ACTIVE


# ── Physics Process ──────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	
	if main_combo_timer > 0:
		main_combo_timer -= delta
		if main_combo_timer <= 0:
			main_combo_index = 0
	if alt_combo_timer > 0:
		alt_combo_timer -= delta
		if alt_combo_timer <= 0:
			alt_combo_index = 0

	if _main_attack_timer > 0:
		_main_attack_timer -= delta
	if _alt_attack_timer > 0:
		_alt_attack_timer -= delta
	if _toss_cooldown_timer > 0:
		_toss_cooldown_timer -= delta
	if cooldown_timer > 0:
		cooldown_timer -= delta
		
	_tick_stamina(delta)
	
	if can_combo and get_active_weapon().has_combo:
		_combo_switch_timer -= delta
		if _combo_switch_timer <= 0.0:
			_reset_combo_switch_timer()
			_use_alt_attack = not _use_alt_attack
		
	var hp_percent := float(health.current_hp) / float(health.max_hp)
	var should_dodge := (is_swift and hp_percent > LOW_HP_THRESHOLD) or (is_panic and hp_percent <= LOW_HP_THRESHOLD)
	
	# If scared, only allow dodging during SEEK_WEAPON or SEEK_ITEM states
	if is_scared and hp_percent <= LOW_HP_THRESHOLD and ai_state != AIState.SEEK_WEAPON and ai_state != AIState.SEEK_ITEM:
		should_dodge = false
	
	if should_dodge and can_dodge and ai_state != AIState.IDLE:
		_dodge_timer -= delta
		if _dodge_timer <= 0.0:
			_reset_dodge_timer()
			_pending_dodges = int(_stamina / stats.stamina_per_dodge) if can_double_dodge else 1

	# Fire pending dodges when not already dodging
	if _pending_dodges > 0 and not is_dodging and cooldown_timer <= 0:
		_pending_dodges -= 1
		try_dodge(last_direction)
			
	# Tick dodge for all states
	if is_dodging:
		_tick_dodge(delta)
		return

	targets_in_range = targets_in_range.filter(func(t): return is_instance_valid(t))
	if target and not is_instance_valid(target):
		target = _get_nearest_target()
	
	_update_ai_state()

	match ai_state:
		AIState.IDLE:
			_apply_movement(Vector2.ZERO)
			if not _is_attacking():
				_snap_to_idle()
				anim_lower.stop()

		AIState.SEEK_WEAPON:
			if _weapon_target == null or not is_instance_valid(_weapon_target):
				ai_state = AIState.ACTIVE
			else:
				nav_agent.target_position = _weapon_target.global_position
				var next_pos := nav_agent.get_next_path_position()
				var dir := (next_pos - global_position).normalized()
				last_direction = dir
				rotation = dir.angle()
				_apply_movement(dir * stats.move_speed)
				if not _is_attacking():
					var walk := get_active_weapon().walk_animation
					if walk != "":
						anim_upper.play(walk)
				if velocity.length() > 0:
					anim_lower.play("feet_normal")
				else:
					anim_lower.stop()

		AIState.SEEK_ITEM:
			if _item_target == null or not is_instance_valid(_item_target):
				ai_state = AIState.ACTIVE
			else:
				nav_agent.target_position = _item_target.global_position
				var next_pos := nav_agent.get_next_path_position()
				var dir := (next_pos - global_position).normalized()
				last_direction = dir
				rotation = dir.angle()
				_apply_movement(dir * stats.move_speed)
				if not _is_attacking():
					var walk := get_active_weapon().walk_animation
					if walk != "":
						anim_upper.play(walk)
				if velocity.length() > 0:
					anim_lower.play("feet_normal")
				else:
					anim_lower.stop()

		AIState.ACTIVE:
			var weapon := get_active_weapon()
			var attack_dist := _get_current_attack_range()
			var dist := global_position.distance_to(target.global_position)
			var has_los := _has_line_of_sight() if weapon.requires_line_of_sight else true

			if is_tactical and target != null and is_instance_valid(target) and has_los:
				# ── Tactical — orbit at ideal range ──────────────────
				if is_strafing:
					_strafe_timer -= get_physics_process_delta_time()
					if _strafe_timer <= 0.0:
						_reset_strafe_timer()
				else:
					_strafe_angle_offset = 0.0

				var angle_to_target := (global_position - target.global_position).angle()
				var strafe_angle := angle_to_target + _strafe_angle_offset * _strafe_direction
				var ideal_pos := target.global_position + Vector2.RIGHT.rotated(strafe_angle) * (attack_dist * 0.95)
				var dist_to_ideal := global_position.distance_to(ideal_pos)
				if dist_to_ideal > 1.0:
					nav_agent.target_position = ideal_pos
					var next_pos := nav_agent.get_next_path_position()
					var dir := (next_pos - global_position).normalized()
					last_direction = (target.global_position - global_position).normalized()
					rotation = last_direction.angle()
					_apply_movement(dir * stats.move_speed)
				else:
					var dir := (target.global_position - global_position).normalized()
					last_direction = dir
					rotation = dir.angle()
					_apply_movement(Vector2.ZERO)
			elif dist > attack_dist or (weapon.requires_line_of_sight and not has_los):
				# ── Standard chase ────────────────────────────────────
				nav_agent.target_position = target.global_position
				var next_pos := nav_agent.get_next_path_position()
				var dir := (next_pos - global_position).normalized()
				last_direction = dir
				rotation = dir.angle()
				_apply_movement(dir * stats.move_speed)
			else:
				# ── In range — face target and stop ──────────────────
				var dir := (target.global_position - global_position).normalized()
				last_direction = dir
				rotation = dir.angle()
				_apply_movement(Vector2.ZERO)

			if not _is_attacking() and not is_tossing:
				var walk := get_active_weapon().walk_animation
				if walk != "":
					anim_upper.play(walk)
			if velocity.length() > 0:
				anim_lower.play("feet_slow" if _is_attacking() else "feet_normal")
			else:
				anim_lower.stop()

			# ── Hands — attack if in range ────────────────────────
			if dist <= attack_dist and has_los and not is_tossing:
				if _main_attack_timer <= 0:
					if target != null and not target.is_dead:
						if _use_alt_attack and get_active_weapon().alt_attack_animations.size() > 0:
							if weapon.ai_alt_attack_mode == "HOLD":
								alt_attack_held = true
								main_attack_held = false
								if not _is_attacking():
									_play_alt_attack()
							else:
								alt_attack_held = false
								main_attack_held = false
								if not _is_attacking():
									_play_alt_attack()
									_main_attack_timer = alt_attack_cooldown
						else:
							if weapon.ai_main_attack_mode == "HOLD":
								main_attack_held = true
								alt_attack_held = false
								if not _is_attacking():
									_play_main_attack()
							else:
								main_attack_held = false
								alt_attack_held = false
								if not _is_attacking():
									_play_main_attack()
									_main_attack_timer = main_attack_cooldown
			else:
				main_attack_held = false
				alt_attack_held = false

# ── Facing on start ──────────────────────────────────────────────

func _facing_to_vector(facing: FacingDirection) -> Vector2:
	match facing:
		FacingDirection.UP:         return Vector2(0, -1)
		FacingDirection.UP_RIGHT:   return Vector2(1, -1).normalized()
		FacingDirection.RIGHT:      return Vector2(1, 0)
		FacingDirection.DOWN_RIGHT: return Vector2(1, 1).normalized()
		FacingDirection.DOWN:       return Vector2(0, 1)
		FacingDirection.DOWN_LEFT:  return Vector2(-1, 1).normalized()
		FacingDirection.LEFT:       return Vector2(-1, 0)
		FacingDirection.UP_LEFT:    return Vector2(-1, -1).normalized()
	return Vector2(0, 1)
	
# ── Helpers ──────────────────────────────────────────────
	
func _has_line_of_sight() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		global_position,
		target.global_position,
		collision_mask
	)
	query.exclude = [self]
	var result := space.intersect_ray(query)
	if result.is_empty():
		return true
	return result["collider"] == target
	
func _get_effective_weapon_range() -> float:
	if is_aggressive and target != null:
		var target_hp_percent := float(target.health.current_hp) / float(target.health.max_hp)
		if target_hp_percent <= 0.1:
			return 30.0
	if is_scared:
		var hp_percent := float(health.current_hp) / float(health.max_hp)
		if hp_percent <= 0.2:
			return 225.0
		elif hp_percent <= LOW_HP_THRESHOLD:
			return 175.0
	return weapon_detection_range

func _scan_for_weapon() -> Node:
	if not can_find_weapons or current_weapon != null:
		return null
	var effective_range := _get_effective_weapon_range()
	var hp_percent := float(health.current_hp) / float(health.max_hp)
	var use_picky := is_picky and hp_percent > LOW_HP_THRESHOLD
	var use_desperate := is_desperate and hp_percent <= LOW_HP_THRESHOLD

	var best: Node = null
	var best_power: int = -1
	var best_dist: float = INF

	for pickup in get_tree().get_nodes_in_group("weapon_pickup"):
		if not is_instance_valid(pickup):
			continue
		if pickup._was_picked_up:
			continue
		if not pickup._pickup_enabled:
			continue
		var dist := global_position.distance_to(pickup.global_position)
		if dist > effective_range:
			continue
		if use_picky or use_desperate:
			var power: int = pickup.weapon_data.power if pickup.weapon_data else 0
			if power > best_power:
				best_power = power
				best_dist = dist
				best = pickup
		else:
			if dist < best_dist:
				best_dist = dist
				best = pickup
	return best
	
func _scan_for_better_weapon() -> Node:
	if not is_picky and not is_desperate:
		return null
	if current_weapon == null:
		return null
	var hp_percent := float(health.current_hp) / float(health.max_hp)
	# picky only works above threshold, desperate only below
	if is_picky and not is_desperate and hp_percent <= LOW_HP_THRESHOLD:
		return null
	if is_desperate and not is_picky and hp_percent > LOW_HP_THRESHOLD:
		return null
	var effective_range := _get_effective_weapon_range()
	var best: Node = null
	var best_power: int = current_weapon.power # only beat what we have
	for pickup in get_tree().get_nodes_in_group("weapon_pickup"):
		if not is_instance_valid(pickup):
			continue
		if pickup._was_picked_up:
			continue
		if not pickup._pickup_enabled:
			continue
		var dist := global_position.distance_to(pickup.global_position)
		if dist > effective_range:
			continue
		var power: int = pickup.weapon_data.power if pickup.weapon_data else 0
		if power > best_power:
			best_power = power
			best = pickup
	return best

func _scan_for_heal_item() -> Node:
	if not is_careful and not is_healthy:
		return null
	var hp_percent := float(health.current_hp) / float(health.max_hp)
	if is_careful and hp_percent > LOW_HP_THRESHOLD:
		return null
	if is_healthy and hp_percent >= 1.0:
		return null
	var effective_range := _get_effective_weapon_range()
	var best: Node = null
	var best_dist: float = INF
	for pickup in get_tree().get_nodes_in_group("item_pickup"):
		if not is_instance_valid(pickup):
			continue
		if pickup._was_picked_up:
			continue
		if pickup.item_data == null or pickup.item_data.effect != ItemData.ItemEffect.HEAL:
			continue
		var dist := global_position.distance_to(pickup.global_position)
		if dist <= effective_range and dist < best_dist:
			best_dist = dist
			best = pickup
	return best

func _toss_backward_and_seek() -> void:
	# Rotate 180 to toss behind
	var original_rotation := rotation
	rotation = original_rotation + PI
	_do_toss()
	# Rotate back to original facing after toss
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(self) and not is_dead:
		rotation = original_rotation

func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == "uni_toss":
		is_tossing = false
		_snap_to_idle()
		return
	super._on_animation_finished(anim_name)
	
func _reset_dodge_timer() -> void:
	_dodge_timer = randf_range(dodge_interval_min, dodge_interval_max)
	
func _reset_strafe_timer() -> void:
	_strafe_timer = randf_range(tactical_strafe_min, tactical_strafe_max)
	_strafe_direction = 1.0 if randf() > 0.5 else -1.0
	_strafe_angle_offset = randf_range(-0.3, 0.3)

func _get_current_attack_range() -> float:
	var weapon := get_active_weapon()
	if is_alt_attacking or _use_alt_attack:
		return weapon.ai_alt_attack_range
	return weapon.ai_main_attack_range

func _reset_combo_switch_timer() -> void:
	_combo_switch_timer = randf_range(combo_switch_min, combo_switch_max)
	
func break_weapon() -> void:
	super.break_weapon()
	_use_alt_attack = false
	alt_attack_held = false
	main_attack_held = false
	is_alt_attacking = false
	is_main_attacking = false
	_reset_combo_switch_timer()
	_cancel_into_idle()
