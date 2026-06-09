# Enemy.gd
# Extends Character — handles AI decision making, target detection, and behavior.
extends Character
class_name Enemy

# ── Exports ──────────────────────────────────────────────────────

@export var can_pick_up_weapons: bool = false
@export var can_toss_weapons: bool = false
@export var destroy_weapon_on_death: bool = false

@export_group("AI")
@export var detection_range: float = 200.0
@export var attack_range: float = 40.0
@export var idle_wander_speed: float = 0.0  # 0 = stands still when no target

@export_group("Attack")
@export var main_attack_cooldown: float = 1.0
@export var alt_attack_cooldown: float = 1.5

# ── Node References ──────────────────────────────────────────────

@onready var detection_area: Area2D = $DetectionArea

# ── Variables ────────────────────────────────────────────────────

var _main_attack_timer: float = 0.0
var _alt_attack_timer: float = 0.0

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
	CHASE,
	ATTACK,
}

var ai_state: AIState = AIState.IDLE

# ── Ready ────────────────────────────────────────────────────────

func _ready() -> void:
	super()
	detection_area.body_entered.connect(_on_target_entered)
	detection_area.body_exited.connect(_on_target_exited)
	# Resize detection shape to match exported value
	var shape: CircleShape2D = $DetectionArea/CollisionShape2D.shape as CircleShape2D
	if shape != null:
		shape.radius = detection_range
	var dir := _facing_to_vector(initial_facing)
	last_direction = dir
	rotation = dir.angle()
			
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
	tween.tween_callback(func(): _hide_until_respawn())
	
func _hide_until_respawn() -> void:
	visible = false
	set_physics_process(false)
	set_process(false)
	
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
	if target == null or not is_instance_valid(target):
		ai_state = AIState.IDLE
		return
	var dist := global_position.distance_to(target.global_position)
	if dist <= attack_range:
		ai_state = AIState.ATTACK
	else:
		ai_state = AIState.CHASE

# ── Physics Process ──────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	# Tick combo timers
	if main_combo_timer > 0:
		main_combo_timer -= delta
		if main_combo_timer <= 0:
			main_combo_index = 0
	if alt_combo_timer > 0:
		alt_combo_timer -= delta
		if alt_combo_timer <= 0:
			alt_combo_index = 0
			
	# Tick attack timers
	if _main_attack_timer > 0:
		_main_attack_timer -= delta
	if _alt_attack_timer > 0:
		_alt_attack_timer -= delta

	# Clean up invalid targets
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

		AIState.CHASE:
			if not _is_attacking():
				var dir := (target.global_position - global_position).normalized()
				last_direction = dir
				rotation = dir.angle()
				_apply_movement(dir * stats.move_speed)
				var walk := get_active_weapon().walk_animation
				if walk != "":
					anim_upper.play(walk)
				if velocity.length() > 0:
					anim_lower.play("feet_normal")
				else:
					anim_lower.stop()
			else:
				_apply_movement(Vector2.ZERO)

		AIState.ATTACK:
			_apply_movement(Vector2.ZERO)
			# Face the target while attacking
			if target != null:
				var dir := (target.global_position - global_position).normalized()
				last_direction = dir
				rotation = dir.angle()
			if not _is_attacking() and not is_tossing and _main_attack_timer <= 0:
				_play_main_attack()
				_main_attack_timer = main_attack_cooldown

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
