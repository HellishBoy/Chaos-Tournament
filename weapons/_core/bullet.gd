extends Area2D
class_name Bullet

@export var speed: float = 300.0
@export var range_max: float = -1.0
@export var pierce: int = 0
@export var damage: int = 10

@export var knockback_tier: String = "none"
@export var flinch_tier: String = "none"

@export var dot_tag: String = ""
@export var dot_duration: float = 0.0
@export var dot_tick_interval: float = 0.0
@export var dot_damage_percent: float = 0.0
@export var dot_chance: float = 1.0

@export var root_type: String = "none"
@export var root_tag: String = ""
@export var root_duration: float = 0.0
@export var root_chance: float = 1.0

@export var disarm_tag: String = ""
@export var disarm_duration: float = 0.0
@export var disarm_chance: float = 1.0

@export var slow_tag: String = ""
@export var slow_duration: float = 0.0
@export var slow_percent: float = 0.0
@export var slow_chance: float = 1.0

var _direction: Vector2 = Vector2.RIGHT
var _distance_traveled: float = 0.0
var _hit_count: int = 0

func _ready() -> void:
	z_index = -1 # always renders behind characters
	add_to_group("projectile")
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)

func get_direction() -> Vector2:
	return _direction

func setup(dir: Vector2, bullet_speed: float, bullet_range: float, bullet_pierce: int, bullet_damage: int, bullet_knockback: String, bullet_flinch: String, bullet_dot: Dictionary = {}, bullet_root: Dictionary = {}, bullet_disarm: Dictionary = {}, bullet_slow: Dictionary = {}) -> void:
	_direction = dir.normalized()
	speed = bullet_speed
	range_max = bullet_range
	pierce = bullet_pierce
	damage = bullet_damage
	knockback_tier = bullet_knockback
	flinch_tier = bullet_flinch
	if not bullet_dot.is_empty():
		dot_tag = bullet_dot.get("tag", "")
		dot_duration = bullet_dot.get("duration", 0.0)
		dot_tick_interval = bullet_dot.get("tick_interval", 0.0)
		dot_damage_percent = bullet_dot.get("damage_percent", 0.0)
		dot_chance = bullet_dot.get("chance", 1.0)
	if not bullet_root.is_empty():
		root_type = bullet_root.get("type", "none")
		root_tag = bullet_root.get("tag", "none")
		root_duration = bullet_root.get("duration", 0.0)
		root_chance = bullet_root.get("chance", 1.0)
	if not bullet_disarm.is_empty():
		disarm_tag = bullet_disarm.get("tag", "")
		disarm_duration = bullet_disarm.get("duration", 0.0)
		disarm_chance = bullet_disarm.get("chance", 1.0)
	if not bullet_slow.is_empty():
		slow_tag = bullet_slow.get("tag", "")
		slow_duration = bullet_slow.get("duration", 0.0)
		slow_percent = bullet_slow.get("percent", 0.0)
		slow_chance = bullet_slow.get("chance", 1.0)
	rotation = _direction.angle()

func _physics_process(delta: float) -> void:
	var step := _direction * speed * delta
	position += step
	_distance_traveled += step.length()
	if range_max >= 0.0 and _distance_traveled >= range_max:
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	var parent := area.get_parent()

	CombatResolver.apply_hit(
		parent,
		damage,
		knockback_tier,
		_direction,
		flinch_tier,
		{ "tag": dot_tag, "duration": dot_duration, "tick_interval": dot_tick_interval, "damage_percent": dot_damage_percent, "chance": dot_chance },
		{ "type": root_type, "duration": root_duration, "chance": root_chance },
		{ "tag": disarm_tag, "duration": disarm_duration, "chance": disarm_chance },
		{ "tag": slow_tag, "duration": slow_duration, "percent": slow_percent, "chance": slow_chance }
	)

	_hit_count += 1
	if pierce >= 0 and _hit_count > pierce:
		queue_free()

func _on_body_entered(_body: Node) -> void:
	queue_free()
