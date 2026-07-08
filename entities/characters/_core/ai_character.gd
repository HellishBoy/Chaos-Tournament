# AICharacter.gd
# Extends Character — shared AI brain for every team (Enemy, Ally, and
# eventually Chaos). Handles decision making, target detection, dodge
# behavior, weapon/item seeking, and combat — identically for all teams.
# The only thing a subclass needs to define is WHO counts as a valid
# target and how much it prefers each one (see _is_valid_target() /
# _get_target_priority() near the bottom).
extends Character
class_name AICharacter

# ── Exports ──────────────────────────────────────────────────────

@export var can_pick_up_weapons: bool = false
@export var can_toss_weapons: bool = false
@export var can_find_weapons: bool = false
@export var can_dodge: bool = false
@export var can_double_dodge: bool = false
@export var destroy_weapon_on_death: bool = false

@export_group("Round")
@export var lives: int = 1

@export_group("Spawn")
@export var spawn_point: Marker2D

@export_group("AI")
@export var detection_range: float = 100.0
@export var idle_wander_speed: float = 0.0
# -1 = hold the current target until it dies/becomes invalid (Enemy/Ally
# default). A positive value forces a fresh _acquire_target() call after
# that many seconds, even if the current target is still alive — used
# by Chaos to cycle targets on a timer.
@export var target_hold_time: float = -1.0

@export_group("Intelligence")
# Shared baseline range used by Detection Range, Finding Weapons, and
# Health scanning below — not specific to any one subgroup.
@export var perception_range: float = 100.0

@export_subgroup("Health")
@export var is_careful: bool = false
@export var is_healthy: bool = false
@export var is_greedy: bool = false

@export_subgroup("Detection Range")
@export var is_scared: bool = false
@export var is_aggressive: bool = false

@export_subgroup("Finding Weapons")
@export var is_picky: bool = false
@export var is_desperate: bool = false

@export_subgroup("Dodging")
@export var is_swift: bool = false
@export var is_panic: bool = false
@export var dodge_interval_min: float = 1.0
@export var dodge_interval_max: float = 3.0

@export_subgroup("Evasive")
@export var is_sharp: bool = false
@export var is_alert: bool = false
@export var evasion_hit_width: float = 24.0

@export_subgroup("Combat Range")
@export var is_tactical: bool = false
@export var melee_strafe_min: float = 1.0
@export var melee_strafe_max: float = 2.5
@export var melee_stop_strafe_min: float = 0.2
@export var melee_stop_strafe_max: float = 0.5

@export_group("Attack")
@export var main_attack_cooldown: float = 0.6
@export var alt_attack_cooldown: float = 0.6
@export var can_combo: bool = false
@export var combo_switch_min: float = 1.0
@export var combo_switch_max: float = 2.5

@export_group("Appearance")
@export var sprite_feet_l: Texture2D
@export var sprite_feet_r: Texture2D
@export var sprite_hand_left: Texture2D
@export var sprite_hand_right: Texture2D
@export var sprite_head: Texture2D
@export var sprite_head_down: Texture2D

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

enum MeleeStrafeState { STRAFING, STOPPED }
var _melee_strafe_state: MeleeStrafeState = MeleeStrafeState.STRAFING
var _melee_strafe_timer: float = 0.0
var _melee_strafe_direction: float = 1.0
var _melee_strafe_angle: float = 0.0
const MELEE_STRAFE_ANGULAR_SPEED: float = 1.5  # radians/sec while circling

var _seeking_los: bool = false
var _los_seek_direction: float = 1.0

var _weapon_target: Node = null  # the pickup node being sought
var _weapon_scan_timer: float = 0.0
const WEAPON_SCAN_INTERVAL: float = 0.2  # scan for weapons every 0.2s

var _seeking_better_weapon: bool = false

var _item_target: Node = null

var _toss_cooldown_timer: float = 0.0
const TOSS_COOLDOWN: float = 0.8

var _target_hold_timer: float = 0.0

const LOW_HP_THRESHOLD: float = 0.35
const EVASION_RANGE_FACTOR: float = 0.75

const LOS_SEEK_ARC: float = PI / 2.0  # sidestep arc when tactical LOS is blocked
# PI / 3.0 = 60°
# PI / 2.0 = 90°

const HAZARD_ESCAPE_MARGIN: float = 16.0

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
	_apply_appearance()

	detection_area.body_entered.connect(_on_target_entered)
	detection_area.body_exited.connect(_on_target_exited)
	var shape: CircleShape2D = $DetectionArea/CollisionShape2D.shape as CircleShape2D
	
	if shape != null:
		shape.radius = detection_range
	if can_double_dodge and not can_dodge:
		push_warning(name + ": can_double_dodge is true but can_dodge is false — can_double_dodge will have no effect.")

		
	var dir := _facing_to_vector(initial_facing)
	last_direction = dir
	rotation = dir.angle()
	await get_tree().physics_frame
	
	_acquire_target()
	_reset_dodge_timer()
	_reset_melee_strafe_timer()
	_reset_combo_switch_timer()

# ── Health Callbacks ─────────────────────────────────────────────

func _on_damaged(_amount: int, _remaining: int) -> void:
	var tween := create_tween()
	tween.tween_property($Body, "modulate", Color(8.0, 8.0, 8.0, 1.0), 0.05)
	tween.tween_property($Body, "modulate", Color.WHITE, 0.1)

func _on_died() -> void:
	call_deferred("_drop_weapon")
	_clear_as_target_for_others()
	var tween := create_tween()
	tween.tween_property($Body, "modulate", Color(8.0, 8.0, 8.0, 1.0), 0.1)
	tween.tween_interval(0.1)
	tween.tween_callback(func(): 
		_apply_death_state()
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

# Full-map fallback scan — used at spawn and any time the current
# target is lost (died, despawned, invalid). Groups every valid
# candidate by priority tier and picks the nearest one in the best
# tier, via the same _pick_best_target() the in-range detector uses.
func _acquire_target() -> void:
	var candidates: Array = []
	for node in get_tree().get_nodes_in_group("contestant"):
		if node == self or not is_instance_valid(node):
			continue
		if node.is_dead:
			continue
		if _is_valid_target(node):
			candidates.append(node)
	target = _pick_best_target(candidates)
	ai_state = AIState.ACTIVE if target != null else AIState.IDLE
	if target != null:
		_target_hold_timer = target_hold_time

func _find_hazard_to_escape() -> Node:
	var best: Node = null
	var best_dist: float = INF
	for hazard in get_tree().get_nodes_in_group("lingering_hazard"):
		if not is_instance_valid(hazard):
			continue
		var dist := global_position.distance_to(hazard.global_position)
		if dist <= hazard.get_radius() + HAZARD_ESCAPE_MARGIN and dist < best_dist:
			best_dist = dist
			best = hazard
	return best

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
	if _is_valid_target(body):
		if not targets_in_range.has(body):
			targets_in_range.append(body)
		target = _get_nearest_target()

func _on_target_exited(body: Node2D) -> void:
	if _is_valid_target(body):
		targets_in_range.erase(body)
		target = _get_nearest_target()

func _get_nearest_target() -> Node2D:
	return _pick_best_target(targets_in_range)

# Shared by both the in-range detector and the full-map fallback scan.
# Picks the nearest candidate within the lowest (best) priority tier
# present — so a preferred target (e.g. is_focus's main enemy) always
# wins if one's around, and it's a plain nearest-pick otherwise.
func _pick_best_target(candidates: Array) -> Node2D:
	var best: Node2D = null
	var best_priority: int = 999999
	var best_dist: float = INF
	for c in candidates:
		if not is_instance_valid(c):
			continue
		var priority := _get_target_priority(c)
		var dist := global_position.distance_to(c.global_position)
		if priority < best_priority or (priority == best_priority and dist < best_dist):
			best_priority = priority
			best_dist = dist
			best = c
	return best

# ── Target Rules — override in subclasses ────────────────────────
# This is the ONLY thing that differs between Enemy, Ally, and Chaos.

# Is this body a legal target at all for my team?
func _is_valid_target(_body: Node) -> bool:
	return false

# Lower number = higher priority. Ties broken by nearest distance.
func _get_target_priority(_body: Node) -> int:
	return 0

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
	_item_target = _scan_for_beneficial_item()
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

	# No target — try to acquire one
	if target == null or not is_instance_valid(target) or target.is_dead:
		_acquire_target()
		if target == null:
			ai_state = AIState.IDLE
			main_attack_held = false
			return

	ai_state = AIState.ACTIVE

# ── Physics Process ──────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	# Stamina regen — keeps ticking even while dead, so dodge charges
	# refill during the respawn wait instead of freezing at death.
	_tick_stamina(delta)
	if is_dead:
		return
	
	var knock_mult := impact_component.get_control_speed_multiplier(stats.knockback_resistance)
	var weight_mult := get_active_weapon().get_weight_multiplier()
	var slow_mult := _get_slow_multiplier()
	var attack_penalty: float = get_active_weapon().movement_penalty if _is_attacking() else 1.0
	var combined_mult := _apply_speed_floor(weight_mult * knock_mult * slow_mult * attack_penalty)
	
	if _is_petrified():
		_apply_movement(Vector2.ZERO)
		return

	if target_hold_time > 0.0 and target != null:
		_target_hold_timer -= delta
		if _target_hold_timer <= 0.0:
			target = null  # forces _update_ai_state() to reacquire this same frame

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
		
	if can_combo and get_active_weapon().has_combo:
		_combo_switch_timer -= delta
		if _combo_switch_timer <= 0.0:
			_reset_combo_switch_timer()
			_use_alt_attack = not _use_alt_attack
		
	var hp_percent := float(health.current_hp) / float(health.max_hp)
	
	var evasive_active := (is_sharp and hp_percent > LOW_HP_THRESHOLD) or (is_alert and hp_percent <= LOW_HP_THRESHOLD)
	if evasive_active and can_dodge and not is_dodging and cooldown_timer <= 0 and _stamina >= stats.stamina_per_dodge and ai_state != AIState.IDLE:
		var threat_direction := _check_incoming_threat()
		if threat_direction != Vector2.ZERO:
			try_dodge(threat_direction)
	
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

	# Safety net: if a throw was in progress and the target died or vanished
	# before the throw naturally resolved (e.g. the grenade that killed them
	# was the last action, flipping ai_state to IDLE before anything else
	# could clean up), cancel it instead of leaving the animation stuck.
	if is_throwing_grenade and (target == null or not is_instance_valid(target) or target.is_dead):
		_cancel_into_idle()
		
	_update_ai_state()

	match ai_state:
		AIState.IDLE:
			if is_careful or is_healthy:
				var hazard := _find_hazard_to_escape()
				if hazard != null:
					var away_dir: Vector2 = (global_position - hazard.global_position).normalized()
					if away_dir == Vector2.ZERO:
						away_dir = Vector2.RIGHT  # standing exactly on the center — pick any direction out
					var escape_target: Vector2 = hazard.global_position + away_dir * (hazard.get_radius() + HAZARD_ESCAPE_MARGIN)
					nav_agent.target_position = escape_target
					var next_pos := nav_agent.get_next_path_position()
					var dir := (next_pos - global_position).normalized()
					last_direction = dir
					rotation = dir.angle()
					_apply_movement(dir * stats.move_speed * combined_mult)
					if not _is_attacking():
						var walk := get_active_weapon().walk_animation
						if walk != "":
							anim_upper.play(walk)
					if velocity.length() > 0:
						anim_lower.play("feet_normal")
					else:
						anim_lower.stop()
					return
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
				_apply_movement(dir * stats.move_speed * combined_mult)
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
				_apply_movement(dir * stats.move_speed * combined_mult)
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
			var is_melee := weapon.weapon_category == "melee"

			if is_tactical and is_melee and target != null and is_instance_valid(target):
				# ── Tactical melee — cyclic strafe/stop, no LOS concern ──
				_seeking_los = false
				_tick_melee_strafe(delta)
				if _melee_strafe_state == MeleeStrafeState.STRAFING:
					var angle_to_target := (global_position - target.global_position).angle()
					var strafe_pos := target.global_position + Vector2.RIGHT.rotated(angle_to_target + _melee_strafe_angle) * (attack_dist * 0.95)
					nav_agent.target_position = strafe_pos
					var next_pos := nav_agent.get_next_path_position()
					var dir := (next_pos - global_position).normalized()
					last_direction = (target.global_position - global_position).normalized()
					rotation = last_direction.angle()
					_apply_movement(dir * stats.move_speed * combined_mult)
				else:
					var dir := (target.global_position - global_position).normalized()
					last_direction = dir
					rotation = dir.angle()
					_apply_movement(Vector2.ZERO)
			elif is_tactical and not is_melee and target != null and is_instance_valid(target) and has_los:
				# ── Tactical, non-melee, LOS clear — settle at ideal
				# range and stop strafing entirely; strafing only ever
				# exists to find LOS, not to wobble while attacking.
				_seeking_los = false
				var angle_to_target := (global_position - target.global_position).angle()
				var ideal_pos := target.global_position + Vector2.RIGHT.rotated(angle_to_target) * (attack_dist * 0.95)
				var dist_to_ideal := global_position.distance_to(ideal_pos)
				if dist_to_ideal > 1.0:
					nav_agent.target_position = ideal_pos
					var next_pos := nav_agent.get_next_path_position()
					var dir := (next_pos - global_position).normalized()
					last_direction = (target.global_position - global_position).normalized()
					rotation = last_direction.angle()
					_apply_movement(dir * stats.move_speed * combined_mult)
				else:
					var dir := (target.global_position - global_position).normalized()
					last_direction = dir
					rotation = dir.angle()
					_apply_movement(Vector2.ZERO)
			elif is_tactical and not is_melee and target != null and is_instance_valid(target) and weapon.requires_line_of_sight and not has_los:
				# ── Tactical, non-melee, LOS blocked — decide a side
				# (away from the obstruction) and strafe toward it.
				# Stops the instant LOS is regained (handled by the
				# branch above taking over next frame).
				if not _seeking_los:
					_seeking_los = true
					_los_seek_direction = _decide_los_strafe_direction()
				var angle_to_target := (global_position - target.global_position).angle()
				var seek_angle := angle_to_target + LOS_SEEK_ARC * _los_seek_direction
				var seek_pos := target.global_position + Vector2.RIGHT.rotated(seek_angle) * (attack_dist * 0.95)
				nav_agent.target_position = seek_pos
				var next_pos := nav_agent.get_next_path_position()
				var dir := (next_pos - global_position).normalized()
				last_direction = (target.global_position - global_position).normalized()
				rotation = last_direction.angle()
				_apply_movement(dir * stats.move_speed * combined_mult)
			elif dist > attack_dist or (weapon.requires_line_of_sight and not has_los):
				# ── Standard chase ────────────────────────────────────
				_seeking_los = false
				nav_agent.target_position = target.global_position
				var next_pos := nav_agent.get_next_path_position()
				var dir := (next_pos - global_position).normalized()
				last_direction = dir
				rotation = dir.angle()
				_apply_movement(dir * stats.move_speed * combined_mult)
			else:
				_seeking_los = false
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
				if weapon.weapon_category == "grenade":
					_handle_grenade_attack(weapon, delta)
				elif _main_attack_timer <= 0:
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
				if weapon.weapon_category == "grenade" and is_throwing_grenade:
					_cancel_into_idle()

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
	
func _get_effective_perception_range() -> float:
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
	return perception_range

func _scan_for_weapon() -> Node:
	if not can_find_weapons or current_weapon != null:
		return null
	var effective_range := _get_effective_perception_range()
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
	var effective_range := _get_effective_perception_range()
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

func _scan_for_beneficial_item() -> Node:
	var hp_percent := float(health.current_hp) / float(health.max_hp)
	var wants_heal := (is_careful and hp_percent <= LOW_HP_THRESHOLD) or (is_healthy and hp_percent < 1.0)
	var wants_buff := is_greedy

	if not wants_heal and not wants_buff:
		return null

	var effective_range := _get_effective_perception_range()
	var best: Node = null
	var best_dist: float = INF

	for pickup in get_tree().get_nodes_in_group("item_pickup"):
		if not is_instance_valid(pickup):
			continue
		if pickup._was_picked_up:
			continue
		if pickup.item_data == null:
			continue

		var qualifies := false
		if wants_heal and pickup.item_data.effect == ItemData.ItemEffect.HEAL:
			qualifies = true
		elif wants_buff and pickup.item_data.effect == ItemData.ItemEffect.STATUS_EFFECT:
			var is_buff_effect := StatusEffectComponent.is_buff(pickup.item_data.status_effect_name)
			var already_has_it := status_effect_component.has_effect(pickup.item_data.status_effect_name)
			if is_buff_effect and not already_has_it:
				qualifies = true

		if not qualifies:
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

# ── Evasive Dodge ──────────────────────────────────────────────
# Reactive, threat-based dodging — distinct from is_swift/is_panic's
# periodic timer. Checked first every frame; if it fires, is_dodging
# becomes true immediately, which naturally skips the periodic dodge
# check below for that frame (no extra flag needed).
func _check_incoming_threat() -> Vector2:
	# Priority 1: opponent is mid-swing with a melee weapon, in range.
	if target != null and is_instance_valid(target) and not target.is_dead:
		var target_weapon: WeaponData = target.get_active_weapon()
		if target_weapon.weapon_category == "melee" and (target.is_main_attacking or target.is_alt_attacking):
			var melee_dist := global_position.distance_to(target.global_position)
			if melee_dist <= target_weapon.ai_main_attack_range:
				return Vector2.LEFT.rotated(rotation)  # straight back — always facing target

	# Priority 2: any live projectile on a collision course.
	var evasion_range: float = detection_range * EVASION_RANGE_FACTOR
	for projectile in get_tree().get_nodes_in_group("projectile"):
		if not is_instance_valid(projectile):
			continue
		if projectile is Grenade and not projectile.can_impact_detonate:
			continue  # a pure-timer grenade isn't an immediate threat

		var proj_pos: Vector2 = projectile.global_position
		var proj_dir: Vector2 = projectile.get_direction() if projectile is Bullet else projectile.velocity.normalized()
		if proj_dir == Vector2.ZERO:
			continue

		var to_self := global_position - proj_pos
		var t := to_self.dot(proj_dir)
		if t <= 0.0 or t > evasion_range:
			continue  # already past us, or still too far out to react to

		var closest_point := proj_pos + proj_dir * t
		var perp_dist := global_position.distance_to(closest_point)
		if perp_dist <= evasion_hit_width:
			var side := 1.0 if randf() < 0.5 else -1.0
			return proj_dir.rotated(PI / 2.0 * side)

	return Vector2.ZERO

func _reset_dodge_timer() -> void:
	_dodge_timer = randf_range(dodge_interval_min, dodge_interval_max)
	
func _reset_melee_strafe_timer() -> void:
	_melee_strafe_state = MeleeStrafeState.STRAFING
	_melee_strafe_direction = 1.0 if randf() > 0.5 else -1.0
	_melee_strafe_angle = 0.0
	_melee_strafe_timer = randf_range(melee_strafe_min, melee_strafe_max)

func _tick_melee_strafe(delta: float) -> void:
	if _melee_strafe_state == MeleeStrafeState.STRAFING:
		_melee_strafe_angle += delta * MELEE_STRAFE_ANGULAR_SPEED * _melee_strafe_direction
	_melee_strafe_timer -= delta
	if _melee_strafe_timer > 0.0:
		return
	match _melee_strafe_state:
		MeleeStrafeState.STRAFING:
			_melee_strafe_state = MeleeStrafeState.STOPPED
			_melee_strafe_timer = randf_range(melee_stop_strafe_min, melee_stop_strafe_max)
		MeleeStrafeState.STOPPED:
			_melee_strafe_state = MeleeStrafeState.STRAFING
			_melee_strafe_direction = 1.0 if randf() > 0.5 else -1.0
			_melee_strafe_angle = 0.0
			_melee_strafe_timer = randf_range(melee_strafe_min, melee_strafe_max)

# Casts a ray toward the target to find what's blocking line of sight,
# then strafes toward the side AWAY from that obstruction — a decided
# choice based on real geometry, not a coin flip. If this consistently
# strafes INTO the blocker instead of away from it in practice, flip
# the two return values below.
func _decide_los_strafe_direction() -> float:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, target.global_position, collision_mask)
	query.exclude = [self]
	var result := space.intersect_ray(query)
	if result.is_empty():
		return 1.0 if randf() > 0.5 else -1.0
	var to_target: Vector2 = (target.global_position - global_position).normalized()
	var to_obstruction: Vector2 = (result["position"] - global_position).normalized()
	var cross := to_target.cross(to_obstruction)
	return -1.0 if cross > 0.0 else 1.0

func _get_current_attack_range() -> float:
	var weapon := get_active_weapon()
	if is_alt_attacking or _use_alt_attack:
		return weapon.ai_alt_attack_range
	return weapon.ai_main_attack_range

func _reset_combo_switch_timer() -> void:
	_combo_switch_timer = randf_range(combo_switch_min, combo_switch_max)
	
# ── Grenade AI ───────────────────────────────────────────────────
# AI always fully charges (if the weapon supports it) and throws the
# instant they're in range — no nuanced charge control, matching the
# "grab and go" chaos philosophy rather than tactical AI.
func _handle_grenade_attack(weapon: WeaponData, delta: float) -> void:
	if not is_throwing_grenade:
		if _main_attack_timer <= 0 and target != null and not target.is_dead:
			_main_attack_timer = main_attack_cooldown
			_start_grenade_throw()
		return
	if _grenade_stance_reached and not _grenade_thrown:
		_tick_grenade_charge(delta)
		if not weapon.main_attack_charge or grenade_charge_time >= weapon.main_charge_time:
			_release_grenade_throw()
			
# ── Appearance ───────────────────────────────────────────────────
	
func _apply_appearance() -> void:
	if sprite_feet_l:
		$Body/FeetL.texture = sprite_feet_l
	if sprite_feet_r:
		$Body/FeetR.texture = sprite_feet_r
	if sprite_hand_left:
		$Body/Hands/HandLeft.texture = sprite_hand_left
	if sprite_hand_right:
		$Body/Hands/HandRight.texture = sprite_hand_right
	if sprite_head:
		$Body/Head.texture = sprite_head
	if sprite_head_down:
		$Body/HeadDown.texture = sprite_head_down
