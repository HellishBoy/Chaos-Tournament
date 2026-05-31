extends CharacterBody2D
@export var weapon_data: WeaponData
@export var toss_initial_speed: float = 220.0
@export var toss_bounce_damping: float = 0.45

# ── How long after toss before weapon stops and becomes pickable ──
@export var toss_duration: float = 0.8
@onready var sprite: Sprite2D = $Sprite2D

var _in_flight: bool = false
var _resting: bool = false
var _pickup_enabled: bool = false
var _was_tossed: bool = false
var _toss_timer: float = 0.0
var _has_bounced: bool = false

func _ready() -> void:
	call_deferred("_apply_sprite")
	if not _was_tossed:
		_resting = true
		_pickup_enabled = true

func _apply_sprite() -> void:
	if weapon_data == null:
		return
	if weapon_data.weapon_sprite_ground:
		sprite.texture = weapon_data.weapon_sprite_ground
	elif weapon_data.weapon_sprite_right:
		sprite.texture = weapon_data.weapon_sprite_right
	elif weapon_data.weapon_sprite_left:
		sprite.texture = weapon_data.weapon_sprite_left

func setup_toss(origin: Vector2, direction: Vector2) -> void:
	global_position = origin + direction.normalized() * 10.0
	velocity = direction.normalized() * toss_initial_speed
	_in_flight = true
	_has_bounced = false
	_resting = false
	_pickup_enabled = false
	_toss_timer = toss_duration
	sprite.modulate.a = 0.4
	_apply_sprite()

func _physics_process(delta: float) -> void:
	if _resting:
		if _pickup_enabled:
			_check_player_overlap()
		return
	if not _in_flight:
		return
	# Count down — when timer hits zero, stop and allow pickup
	_toss_timer -= delta
	if _toss_timer <= 0.0:
		_come_to_rest()
		return
	# Decelerate quadratically over the toss duration
	var t: float = _toss_timer / toss_duration  # 1.0 at start, 0.0 at end
	var target_speed: float = toss_initial_speed * t * t
	if _has_bounced:
		target_speed *= toss_bounce_damping
	velocity = velocity.normalized() * target_speed
	var collision := move_and_collide(velocity * delta)
	if collision:
		velocity = velocity.bounce(collision.get_normal())
		_has_bounced = true

func _come_to_rest() -> void:
	_in_flight = false
	_resting = true
	_pickup_enabled = true
	velocity = Vector2.ZERO
	sprite.modulate.a = 1.0

func _check_player_overlap() -> void:
	var space := get_world_2d().direct_space_state
	var shape: Shape2D = $CollisionShape2D.shape
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = $CollisionShape2D.global_transform
	query.collision_mask = 1 << 1
	var results := space.intersect_shape(query)
	for result in results:
		var body: Object = result["collider"]
		if body.has_method("try_pickup"):
			body.try_pickup(self)
			return
