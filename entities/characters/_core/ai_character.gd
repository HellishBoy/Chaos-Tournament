# AICharacter.gd
# Extends Character — shared AI brain for every team (Enemy, Ally, and
# Chaos). Handles decision making, target detection, dodge
# behavior, weapon/item seeking, and combat — identically for all teams.
# The only thing a subclass needs to define is WHO counts as a valid
# target and how much it prefers each one (see _is_valid_target() /
# _get_target_priority() near the bottom).
extends Character
class_name AICharacter

# ── Exports ──────────────────────────────────────────────────────

@export_group("Permission")
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
@export var eye_offset: float = 5.0

# -1 = hold the current target until it dies/becomes invalid (Enemy/Ally
# default). A positive value forces a fresh _acquire_target() call after
# that many seconds, even if the current target is still alive — used
# by Chaos to cycle targets on a timer.
@export var target_hold_time: float = -1.0

@export_group("Intelligence")
# Shared baseline range used by Detection Range, Finding Weapons, and
# Health scanning below — not specific to any one subgroup.
@export var perception_range: float = 120.0

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
@export_range(0.0, 1.0) var evasion_chance: float = 0.4

@export_subgroup("Combat Range")
@export var is_tactical: bool = false

@export_subgroup("Tracking")
@export var target_follow_speed: float = 0.15  # 0-1 per-frame lerp; 1.0 = instant snap

@export_group("Preference")
@export_enum("None", "Prefer", "Hate") var melee_preference: String = "None"
@export_enum("None", "Prefer", "Hate") var ranged_preference: String = "None"
@export_enum("None", "Prefer", "Hate") var projectile_preference: String = "None"
@export_enum("None", "Prefer", "Hate") var grenade_preference: String = "None"

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

@export_group("Debug")
@export var show_state_debug: bool = false
@export var show_los_debug: bool = false

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

var _weapon_target: Node = null  # the pickup node being sought

var _seeking_better_weapon: bool = false

var _item_target: Node = null

var _toss_cooldown_timer: float = 0.0
const TOSS_COOLDOWN: float = 0.8

var _target_hold_timer: float = 0.0

const LOW_HP_THRESHOLD: float = 0.35
const EVASION_RANGE_FACTOR: float = 0.75

const HAZARD_ESCAPE_MARGIN: float = 16.0

const PERCEPTION_SCAN_INTERVAL: float = 0.6   # replaces WEAPON_SCAN_INTERVAL — same timer now drives weapon AND item scanning
const TARGET_SCAN_INTERVAL: float = 0.3
var _target_scan_timer: float = 0.0

var _last_eye_left_origin: Vector2 = Vector2.ZERO
var _last_eye_right_origin: Vector2 = Vector2.ZERO
var _last_eye_left_end: Vector2 = Vector2.ZERO
var _last_eye_right_end: Vector2 = Vector2.ZERO
var _last_has_los: bool = false

const CROWD_PUSH_RADIUS: float = 20.0
const CROWD_PUSH_INTERVAL: float = 0.4

var _perception_scan_timer: float = 0.0
var _crowd_push_timer: float = 0.0

var _last_threat_direction: Vector2 = Vector2.ZERO

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
	_check_hated_weapon()
	_reset_dodge_timer()
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
				_perception_scan_timer = 0.0
				_seeking_better_weapon = false
				_weapon_target = null
				_use_alt_attack = false
				_reset_combo_switch_timer()
				_check_hated_weapon()
				return
	super.try_pickup(pickup_node)
	_perception_scan_timer = 0.0
	_seeking_better_weapon = false
	_weapon_target = null
	_use_alt_attack = false
	_reset_combo_switch_timer()
	_check_hated_weapon()

func _on_target_entered(body: Node2D) -> void:
	if _is_valid_target(body):
		if not targets_in_range.has(body):
			targets_in_range.append(body)

func _on_target_exited(body: Node2D) -> void:
	if _is_valid_target(body):
		targets_in_range.erase(body)

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

	if _weapon_target != null:
		if not is_instance_valid(_weapon_target) or _weapon_target._was_picked_up:
			_weapon_target = null

	if _item_target != null:
		if not is_instance_valid(_item_target) or _item_target._was_picked_up:
			_item_target = null

	# ── Perception sonar — weapon/item scanning share one interval
	# instead of running every frame. Target detection (DetectionArea
	# signals) is untouched — stays instant, not gated by this timer.
	_perception_scan_timer -= get_physics_process_delta_time()
	if _perception_scan_timer <= 0.0:
		_perception_scan_timer = PERCEPTION_SCAN_INTERVAL
		_item_target = _scan_for_beneficial_item()
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

	if _item_target != null:
		ai_state = AIState.SEEK_ITEM
		main_attack_held = false
		return

	if _weapon_target != null and (current_weapon == null or _seeking_better_weapon):
		ai_state = AIState.SEEK_WEAPON
		return

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
	var combined_mult := _apply_speed_floor(weight_mult * knock_mult * slow_mult * attack_penalty) * _get_haste_move_multiplier()
	
	if _is_petrified():
		_apply_movement(Vector2.ZERO)
		return

	if target_hold_time > 0.0 and target != null:
		_target_hold_timer -= delta
		if _target_hold_timer <= 0.0:
			target = null  # forces _update_ai_state() to reacquire this same frame

	#region Melee Combo
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
	#endregion
		
	var hp_percent := float(health.current_hp) / float(health.max_hp)
	
	#region Threat Evasion
	var evasive_active := (is_sharp and hp_percent > LOW_HP_THRESHOLD) or (is_alert and hp_percent <= LOW_HP_THRESHOLD)
	if evasive_active and can_dodge and not is_dodging and cooldown_timer <= 0 and _stamina >= stats.stamina_per_dodge:
		var threat_direction := _check_incoming_threat()
		if threat_direction != Vector2.ZERO:
			if _last_threat_direction == Vector2.ZERO and randf() <= evasion_chance:
				try_dodge(threat_direction)
			_last_threat_direction = threat_direction
		else:
			_last_threat_direction = Vector2.ZERO
	else:
		_last_threat_direction = Vector2.ZERO
	
	var should_dodge := (is_swift and hp_percent > LOW_HP_THRESHOLD) or (is_panic and hp_percent <= LOW_HP_THRESHOLD)
		
	if should_dodge and can_dodge: # and ai_state != AIState.IDLE
		_dodge_timer -= delta
		if _dodge_timer <= 0.0:
			_reset_dodge_timer()
			_pending_dodges = int(_stamina / stats.stamina_per_dodge) if can_double_dodge else 1
	#endregion

	# If scared, only allow dodging during SEEK_WEAPON or SEEK_ITEM states
	if is_scared and hp_percent <= LOW_HP_THRESHOLD and ai_state != AIState.SEEK_WEAPON and ai_state != AIState.SEEK_ITEM:
		should_dodge = false
		
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

	# Target re-evaluation is throttled — recomputing "who's best" on
	# every single Area2D enter/exit event caused visible snap-between-
	# targets jitter. This is the only place `target` gets reassigned
	# from targets_in_range now.
	_target_scan_timer -= delta
	if _target_scan_timer <= 0.0:
		_target_scan_timer = TARGET_SCAN_INTERVAL
		if not targets_in_range.is_empty():
			target = _get_nearest_target()

	_update_ai_state()

	# Cancel any in-progress attack (melee, ranged, or grenade) the
	# instant we're in a non-combat state — otherwise the AI can keep
	# swinging/throwing while walking toward a weapon or item pickup.
	if _is_attacking() and (ai_state == AIState.SEEK_WEAPON or ai_state == AIState.SEEK_ITEM or ai_state == AIState.IDLE):
		_cancel_into_idle()

	var weapon := get_active_weapon()
	var attack_dist := _get_current_attack_range()

	match ai_state:
		#region IDLE STATE
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
					rotation = lerp_angle(rotation, dir.angle(), turn_follow_speed)
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
		#endregion

		#region SEEK WEAPON STATE
		AIState.SEEK_WEAPON:
			if _weapon_target == null or not is_instance_valid(_weapon_target):
				ai_state = AIState.ACTIVE
			else:
				nav_agent.target_position = _weapon_target.global_position
				var next_pos := nav_agent.get_next_path_position()
				var dir := (next_pos - global_position).normalized()
				last_direction = dir
				rotation = lerp_angle(rotation, dir.angle(), turn_follow_speed)
				_apply_movement(dir * stats.move_speed * combined_mult)
				if not _is_attacking():
					var walk := get_active_weapon().walk_animation
					if walk != "":
						anim_upper.play(walk)
				if velocity.length() > 0:
					anim_lower.play("feet_normal")
				else:
					anim_lower.stop()

		#endregion
		
		#region SEEK ITEM STATE
		AIState.SEEK_ITEM:
			if _item_target == null or not is_instance_valid(_item_target):
				ai_state = AIState.ACTIVE
			else:
				nav_agent.target_position = _item_target.global_position
				var next_pos := nav_agent.get_next_path_position()
				var dir := (next_pos - global_position).normalized()
				last_direction = dir
				rotation = lerp_angle(rotation, dir.angle(), turn_follow_speed)
				_apply_movement(dir * stats.move_speed * combined_mult)
				_push_through_crowd(delta)
				if not _is_attacking():
					var walk := get_active_weapon().walk_animation
					if walk != "":
						anim_upper.play(walk)
				if velocity.length() > 0:
					anim_lower.play("feet_normal")
				else:
					anim_lower.stop()
					
		#endregion

		#region ACTIVE STATE
		AIState.ACTIVE:
			var dist := global_position.distance_to(target.global_position)
			var has_los := _has_line_of_sight() if weapon.requires_line_of_sight else true
			
			#region Old stuff. Not used anymore.
			# OLD tactical
			# Not used anymore
			
			#var is_melee := weapon.weapon_category == "melee"
			#if is_tactical and not is_melee and target != null and is_instance_valid(target) and has_los:
				## ── Tactical, non-melee — keep to ideal range once LOS
				## is clear: step back if too close, approach if too far.
				## No strafing or repositioning — just holds the
				## straight-line distance to the target.
				#var angle_to_target := (global_position - target.global_position).angle()
				#var ideal_pos := target.global_position + Vector2.RIGHT.rotated(angle_to_target) * (attack_dist * 0.75)
			#endregion
			
			if _wants_to_hold_range() and target != null and is_instance_valid(target) and has_los:
				# ── Hold ideal range once LOS is clear: step back if
				# too close, approach if too far. ( For Tactical AI
				# or Chaos observing regardless of weapon.)
				var angle_to_target := (global_position - target.global_position).angle()
				var hold_dist := _get_hold_range_distance(attack_dist)
				var ideal_pos := target.global_position + Vector2.RIGHT.rotated(angle_to_target) * hold_dist
				var dist_to_ideal := global_position.distance_to(ideal_pos)
				if dist_to_ideal > 1.0:
					nav_agent.target_position = ideal_pos
					var next_pos := nav_agent.get_next_path_position()
					var dir := (next_pos - global_position).normalized()
					last_direction = (target.global_position - global_position).normalized()
					rotation = lerp_angle(rotation, last_direction.angle(), target_follow_speed)
					_apply_movement(dir * stats.move_speed * combined_mult)
				else:
					var dir := (target.global_position - global_position).normalized()
					last_direction = dir
					rotation = lerp_angle(rotation, dir.angle(), target_follow_speed)
					_apply_movement(Vector2.ZERO)
			elif dist > attack_dist or (weapon.requires_line_of_sight and not has_los):
				# ── Chase — simple, direct pathfinding straight to the
				# target. (Non-tactical or no LOS yet.)
				nav_agent.target_position = target.global_position
				var next_pos := nav_agent.get_next_path_position()
				var dir := (next_pos - global_position).normalized()
				last_direction = dir
				rotation = lerp_angle(rotation, dir.angle(), target_follow_speed)
				_apply_movement(dir * stats.move_speed * combined_mult)
			else:
				# ── In range — face target and stop ──────────────────
				var dir := (target.global_position - global_position).normalized()
				last_direction = dir
				rotation = lerp_angle(rotation, dir.angle(), target_follow_speed)
				_apply_movement(Vector2.ZERO)

			if not _is_attacking() and not is_tossing:
				if velocity.length() > 0:
					var walk := weapon.walk_animation
					if walk != "":
						anim_upper.play(walk)
				else:
					_snap_to_idle()
			if velocity.length() > 0:
				anim_lower.play("feet_slow" if _is_attacking() else "feet_normal")
			else:
				anim_lower.stop()

			_handle_combat_actions(weapon, dist, has_los, delta)
		#endregion

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
	
# ── Debug ──────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if show_state_debug:
		var color: Color
		match ai_state:
			AIState.IDLE:
				color = Color.WHITE
			AIState.SEEK_WEAPON, AIState.SEEK_ITEM:
				color = Color.GREEN
			AIState.ACTIVE:
				color = Color.RED
			_:
				color = Color.WHITE
		draw_arc(Vector2.ZERO, 8.0, 0, TAU, 32, color, 1.0)

	if show_los_debug and target != null and is_instance_valid(target) and get_active_weapon().requires_line_of_sight:
		var los_color := Color.RED if _last_has_los else Color.GREEN
		var local_left := to_local(_last_eye_left_origin)
		var local_right := to_local(_last_eye_right_origin)
		var local_left_end := to_local(_last_eye_left_end)
		var local_right_end := to_local(_last_eye_right_end)
		draw_line(local_left, local_left_end, los_color, 1.0)
		draw_line(local_right, local_right_end, los_color, 1.0)
	
# ── Helpers ──────────────────────────────────────────────
	
func _has_line_of_sight() -> bool:
	if target == null or not is_instance_valid(target):
		_last_has_los = false
		return false
	var to_target := target.global_position - global_position
	var dist := to_target.length()
	if dist <= 0.0:
		_last_has_los = false
		return false
	var dir := to_target / dist
	var perp := dir.rotated(PI / 2.0)

	_last_eye_left_origin = global_position - perp * eye_offset
	_last_eye_right_origin = global_position + perp * eye_offset
	_last_eye_left_end = _last_eye_left_origin + dir * dist
	_last_eye_right_end = _last_eye_right_origin + dir * dist

	var left_clear := _eye_ray_clear(_last_eye_left_origin, _last_eye_left_end)
	var right_clear := _eye_ray_clear(_last_eye_right_origin, _last_eye_right_end)
	_last_has_los = left_clear and right_clear
	return _last_has_los

func _eye_ray_clear(origin: Vector2, end: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		origin,
		end,
		1  # Layer 1 (Environment) only — every contestant is transparent
		   # except walls/obstacles. Both eyes must be clear at once.
	)
	query.exclude = [self]
	var result := space.intersect_ray(query)
	return result.is_empty()

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
	
func _get_weapon_preference(weapon_data: WeaponData) -> String:
	if weapon_data == null:
		return "None"
	match weapon_data.weapon_category:
		"melee":
			return melee_preference
		"ranged":
			return ranged_preference
		"projectile":
			return projectile_preference
		"grenade":
			return grenade_preference
	return "None"
	
# Immediately tosses the current weapon if its category is Hated —
# covers a weapon pre-assigned in the Inspector at round start, and
# any pickup that slips past the normal preference filter (e.g. an AI
# walking near a hated weapon on the ground triggers WeaponPickup's
# passive proximity pickup regardless of what it was actually seeking).
# Deferred since this can run mid-pickup, inside a physics callback.
func _check_hated_weapon() -> void:
	if current_weapon != null and _get_weapon_preference(current_weapon) == "Hate":
		call_deferred("_do_toss")
	
# I don't even know if this crowd pushing really works or not. But it doesn't break the game yet.
# So I'll just put this in here for now I guess.
func _push_through_crowd(delta: float) -> void:
	_crowd_push_timer -= delta
	if _crowd_push_timer > 0.0:
		return
	_crowd_push_timer = CROWD_PUSH_INTERVAL
	for node in get_tree().get_nodes_in_group("contestant"):
		if node == self or not is_instance_valid(node):
			continue
		if node.is_dead:
			continue
		var dist := global_position.distance_to(node.global_position)
		if dist <= CROWD_PUSH_RADIUS and node.has_node("ImpactComponent"):
			var push_dir: Vector2 = (node.global_position - global_position).normalized()
			if push_dir == Vector2.ZERO:
				push_dir = Vector2.RIGHT
			var their_impact := node.get_node("ImpactComponent") as ImpactComponent
			their_impact.apply_knockback("low", push_dir)
	#pass

func _scan_for_weapon() -> Node:
	if not can_find_weapons or current_weapon != null:
		return null
	var effective_range := _get_effective_perception_range()
	var hp_percent := float(health.current_hp) / float(health.max_hp)
	var use_picky := is_picky and hp_percent > LOW_HP_THRESHOLD
	var use_desperate := is_desperate and hp_percent <= LOW_HP_THRESHOLD

	var preferred_candidates: Array = []
	var normal_candidates: Array = []

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
		var preference := _get_weapon_preference(pickup.weapon_data)
		if preference == "Hate":
			continue
		if preference == "Prefer":
			preferred_candidates.append(pickup)
		else:
			normal_candidates.append(pickup)

	# A preferred category always wins over everything else, regardless
	# of power — picky/desperate only decide WHICH preferred one to
	# take if there's more than one in range.
	if not preferred_candidates.is_empty():
		return _pick_weapon_pickup(preferred_candidates, use_picky or use_desperate)

	return _pick_weapon_pickup(normal_candidates, use_picky or use_desperate)

# Shared by weapon scans: nearest by default, or highest-power if
# by_power is true (picky/desperate active).
func _pick_weapon_pickup(candidates: Array, by_power: bool) -> Node:
	var best: Node = null
	var best_power: int = -1
	var best_dist: float = INF
	for pickup in candidates:
		var dist := global_position.distance_to(pickup.global_position)
		if by_power:
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
	if is_picky and not is_desperate and hp_percent <= LOW_HP_THRESHOLD:
		return null
	if is_desperate and not is_picky and hp_percent > LOW_HP_THRESHOLD:
		return null
	var effective_range := _get_effective_perception_range()
	var current_is_preferred := _get_weapon_preference(current_weapon) == "Prefer"

	var preferred_candidates: Array = []
	var normal_candidates: Array = []

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
		var preference := _get_weapon_preference(pickup.weapon_data)
		if preference == "Hate":
			continue
		if preference == "Prefer":
			preferred_candidates.append(pickup)
		else:
			normal_candidates.append(pickup)

	if current_is_preferred:
		# Already holding a preferred weapon — only a BETTER preferred
		# one counts as an upgrade. Never swap out of the preferred
		# category into something non-preferred, no matter its power.
		return _pick_better_by_power(preferred_candidates, current_weapon.power)

	if not preferred_candidates.is_empty():
		# Not currently preferred — any preferred weapon on the ground
		# is an automatic upgrade, power notwithstanding. If more than
		# one is in range, take the strongest.
		return _pick_better_by_power(preferred_candidates, -1)

	# No preferred weapons around — ordinary highest-power-beats-
	# current comparison among everything else non-hated.
	return _pick_better_by_power(normal_candidates, current_weapon.power)

func _pick_better_by_power(candidates: Array, minimum_power: int) -> Node:
	var best: Node = null
	var best_power: int = minimum_power
	for pickup in candidates:
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
	
func _handle_combat_actions(weapon: WeaponData, dist: float, has_los: bool, delta: float) -> void:
	var attack_dist := _get_current_attack_range()
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

# Override to control who uses "hold ideal range" positioning instead
# of plain chase-and-stop. Defaults to is_tactical; Chaos overrides
# this for "observe from a distance" behavior when can_attack is
# false, independent of is_tactical entirely.
func _wants_to_hold_range() -> bool:
	return is_tactical

# The distance to hold once hold-range positioning is active. Defaults
# to just inside attack range; Chaos overrides with its own randomly-
# rolled observe range.
func _get_hold_range_distance(attack_dist: float) -> float:
	return attack_dist * 0.95

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
				var away_from_attacker: Vector2 = (global_position - target.global_position).normalized()
				if away_from_attacker == Vector2.ZERO:
					away_from_attacker = Vector2.LEFT.rotated(rotation)  # exact overlap — fall back to facing-based
				return away_from_attacker

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
		$Body/FeetLeft.texture = sprite_feet_l
	if sprite_feet_r:
		$Body/FeetRight.texture = sprite_feet_r
	if sprite_hand_left:
		$Body/Hands/HandLeft.texture = sprite_hand_left
	if sprite_hand_right:
		$Body/Hands/HandRight.texture = sprite_hand_right
	if sprite_head:
		$Body/Head.texture = sprite_head
	if sprite_head_down:
		$Body/HeadDown.texture = sprite_head_down
