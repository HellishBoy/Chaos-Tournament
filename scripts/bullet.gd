extends Area2D

@export var speed: float = 300.0
@export var range_max: float = -1.0
@export var pierce: int = 0
@export var damage: int = 10
@export var knockback_tier: String = "none"

var _direction: Vector2 = Vector2.RIGHT
var _distance_traveled: float = 0.0
var _hit_count: int = 0

func _ready() -> void:
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)

func setup(dir: Vector2, bullet_speed: float, bullet_range: float, bullet_pierce: int, bullet_damage: int, bullet_knockback: String) -> void:
	_direction = dir.normalized()
	speed = bullet_speed
	range_max = bullet_range
	pierce = bullet_pierce
	damage = bullet_damage
	knockback_tier = bullet_knockback
	rotation = _direction.angle()

func _physics_process(delta: float) -> void:
	var step := _direction * speed * delta
	position += step
	_distance_traveled += step.length()
	if range_max >= 0.0 and _distance_traveled >= range_max:
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	var parent := area.get_parent()
	if parent.has_node("HealthComponent"):
		var health := parent.get_node("HealthComponent") as HealthComponent
		health.take_damage(damage)

	if parent.has_node("KnockbackComponent"):
		var knockback := parent.get_node("KnockbackComponent") as KnockbackComponent
		# Bullets always push away from direction of travel
		knockback.apply(knockback_tier, _direction)

	_hit_count += 1
	if pierce >= 0 and _hit_count > pierce:
		queue_free()

func _on_body_entered(_body: Node) -> void:
	queue_free()
