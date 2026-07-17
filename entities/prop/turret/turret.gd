# Turret.gd
# Extends Prop — stationary, can't move, but detects and fires at any
# contestant that enters range. Ignores Chaos entirely for now.
extends Prop
class_name Turret

enum FacingDirection {
	UP, UP_RIGHT, RIGHT, DOWN_RIGHT, DOWN, DOWN_LEFT, LEFT, UP_LEFT,
}

@export_group("Weapon")
# Reused wholesale from your weapon system — bullet_scene/grenade_scene,
# damage, knockback/flinch tiers, DOT/root/disarm/slow, main_attack_speed,
# and main_attack_animations[0] as the fire animation all come from here.
@export var weapon_data: WeaponData

@export_group("Attack")
@export var attack_cooldown: float = 1.0
@export var lock_on_time: float = 1.0

@export_group("Detection")
@export var detection_range: float = 150.0

@export_group("Facing")
@export var initial_facing: FacingDirection = FacingDirection.DOWN
@export var turn_follow_speed: float = 0.2

# ── Node References ──────────────────────────────────────────────

@onready var detection_area: Area2D = $DetectionArea
@onready var muzzle: Marker2D = $Muzzle1
@onready var anim_player: AnimationPlayer = $AnimationPlayer

# ── State ────────────────────────────────────────────────────────

var target: Node2D = null
var targets_in_range: Array = []

var _attack_timer: float = 0.0
var _lock_on_timer: float = 0.0
var _previous_target: Node2D = null

var _initial_direction: Vector2 = Vector2.DOWN
var _is_dead: bool = false


func _ready() -> void:
	super()
	_initial_direction = _facing_to_vector(initial_facing)
	rotation = _initial_direction.angle()

	detection_area.body_entered.connect(_on_body_entered)
	detection_area.body_exited.connect(_on_body_exited)
	var shape: CircleShape2D = $DetectionArea/CollisionShape2D.shape as CircleShape2D
	if shape != null:
		shape.radius = detection_range

func _on_died() -> void:
	_is_dead = true
	super._on_died()

# ── Physics Process ──────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	targets_in_range = targets_in_range.filter(func(t): return is_instance_valid(t) and not t.is_dead)

	# Drop the current target if it died, left range, or lost LOS —
	# any of these forces a fresh scan for someone else visible.
	if target != null and (not is_instance_valid(target) or target.is_dead or not _has_line_of_sight_to(target)):
		target = null
	if target == null and not targets_in_range.is_empty():
		target = _get_nearest_target()

	# New target acquired (including re-acquiring after losing one) —
	# reset the lock-on delay so it always has to re-aim before firing.
	if target != _previous_target:
		_lock_on_timer = lock_on_time
		_previous_target = target

	if _attack_timer > 0.0:
		_attack_timer -= delta
	if _lock_on_timer > 0.0:
		_lock_on_timer -= delta

	if target != null:
		var dir := (target.global_position - global_position).normalized()
		rotation = lerp_angle(rotation, dir.angle(), turn_follow_speed)
		if _attack_timer <= 0.0 and _lock_on_timer <= 0.0:
			_attack_timer = attack_cooldown
			_try_fire()
	else:
		rotation = lerp_angle(rotation, _initial_direction.angle(), turn_follow_speed)

# ── Detection ────────────────────────────────────────────────────

func _is_valid_target(body: Node) -> bool:
	if body is Chaos:
		return false
	return body is Player or body is Enemy or body is Ally

func _on_body_entered(body: Node2D) -> void:
	if _is_valid_target(body) and not targets_in_range.has(body):
		targets_in_range.append(body)

func _on_body_exited(body: Node2D) -> void:
	targets_in_range.erase(body)
	if target == body:
		target = null

func _get_nearest_target() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist: float = INF
	for t in targets_in_range:
		if not _has_line_of_sight_to(t):
			continue
		var dist := global_position.distance_to(t.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = t
	return nearest

func _has_line_of_sight_to(body: Node2D) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		global_position,
		body.global_position,
		1  # Layer 1 (Environment) only
	)
	query.exclude = [self]
	var result := space.intersect_ray(query)
	return result.is_empty()

# ── Firing ───────────────────────────────────────────────────────

func _try_fire() -> void:
	if weapon_data == null or target == null:
		return
	if anim_player and not weapon_data.main_attack_animations.is_empty():
		anim_player.speed_scale = weapon_data.main_attack_speed
		anim_player.play(weapon_data.main_attack_animations[0])
	else:
		# No animation assigned — fire immediately, same as before.
		_fire_projectile()

# Call this from a Call Method track in the fire animation, at the
# frame where the shot should actually leave the muzzle.
func _on_fire_frame() -> void:
	_fire_projectile()

func _fire_projectile() -> void:
	if weapon_data.projectile_type == "grenade":
		_fire_grenade()
	else:
		_fire_bullet()

func _fire_bullet() -> void:
	if weapon_data.bullet_scene == null:
		push_warning(name + ": bullet_scene not assigned on turret's weapon_data.")
		return
	var bullet = weapon_data.bullet_scene.instantiate()
	bullet.position = muzzle.global_position
	get_parent().add_child(bullet)
	var spread_rad := deg_to_rad(randf_range(-weapon_data.bullet_spread, weapon_data.bullet_spread))
	var direction := Vector2.RIGHT.rotated(rotation + spread_rad)
	bullet.setup(
		direction,
		weapon_data.bullet_speed,
		weapon_data.bullet_range,
		weapon_data.bullet_pierce,
		weapon_data.damage_main,
		weapon_data.get_main_knockback_tier(),
		weapon_data.get_main_flinch_tier(),
		weapon_data.get_dot_config(),
		weapon_data.get_root_config(),
		weapon_data.get_disarm_config(),
		weapon_data.get_slow_config()
	)

func _fire_grenade() -> void:
	if weapon_data.grenade_scene == null:
		push_warning(name + ": grenade_scene not assigned on turret's weapon_data.")
		return
	var grenade := weapon_data.grenade_scene.instantiate()
	grenade.global_position = muzzle.global_position
	get_parent().add_child(grenade)
	var direction := Vector2.RIGHT.rotated(rotation)
	grenade.setup(weapon_data, self, direction, weapon_data.grenade_throw_speed_max)

# ── Facing ───────────────────────────────────────────────────────

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
