extends CharacterBody2D

@onready var health: HealthComponent = $HealthComponent
@onready var sprite: Sprite2D = $Sprite2D
@onready var hurtbox: Area2D = $Hurtbox
@onready var knockback_component: KnockbackComponent = $KnockbackComponent

# Push speed in pixels/sec per tier
const KNOCKBACK_SPEED = {
	"none":   0.0,
	"low":    80.0,
	"medium": 160.0,
	"high":   200.0,
}

func _ready() -> void:
	hurtbox.area_entered.connect(_on_hurtbox_area_entered)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)

func _on_hurtbox_area_entered(_area: Area2D) -> void:
	pass

func _physics_process(_delta: float) -> void:
	if knockback_component.is_active():
		var tier := knockback_component.get_tier()
		var dir := knockback_component.get_direction()
		var push_speed: float = KNOCKBACK_SPEED.get(tier, 0.0)
		var mult := knockback_component.get_speed_multiplier()
		velocity = dir * push_speed * mult
		move_and_slide()
	else:
		velocity = Vector2.ZERO

func _on_damaged(_amount: int, _remaining: int) -> void:
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(8.0, 8.0, 8.0, 1.0), 0.05)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.1)

func _on_died() -> void:
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(8.0, 8.0, 8.0, 1.0), 0.5)
	tween.tween_interval(0.5)
	tween.tween_callback(func(): queue_free())
