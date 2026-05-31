# Enemy.gd
# Extends Character — handles AI decision making, target detection, and behavior.
extends Character
class_name Enemy

# ── Exports ──────────────────────────────────────────────────────

@export var can_pick_up_weapons: bool = false
@export var can_toss_weapons: bool = false

@export_group("AI")
@export var detection_range: float = 200.0
@export var attack_range: float = 40.0
@export var idle_wander_speed: float = 0.0  # 0 = stands still when no target

# ── Node References ──────────────────────────────────────────────

@onready var detection_area: Area2D = $DetectionArea

# ── State ────────────────────────────────────────────────────────

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

# ── Health Callbacks ─────────────────────────────────────────────

func _on_damaged(_amount: int, _remaining: int) -> void:
	var tween := create_tween()
	tween.tween_property($Body, "modulate", Color.RED, 0.05)
	tween.tween_property($Body, "modulate", Color.WHITE, 0.1)

func _on_died() -> void:
	var tween := create_tween()
	tween.tween_property($Body, "modulate", Color.WHITE, 0.1)
	tween.tween_interval(0.1)
	tween.tween_callback(func(): queue_free())

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
			if not _is_attacking() and not is_tossing:
				_play_main_attack()
