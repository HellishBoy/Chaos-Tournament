# Prop.gd
# Base class for destructible world objects — trees, crates, dummies, barrels, etc.
# No weapons, no AI, no movement. Just takes damage and dies.
extends CharacterBody2D
class_name Prop

# ── Exports ──────────────────────────────────────────────────────

@export var health_bar_scene: PackedScene
@export var knockback_immune: bool = false
@export var flash_target: Node2D

# ── Node References ──────────────────────────────────────────────

@onready var health: HealthComponent = $HealthComponent
@onready var hurtbox: Area2D = $Hurtbox
@onready var knockback_component: KnockbackComponent = $KnockbackComponent

# ── Ready ────────────────────────────────────────────────────────

func _ready() -> void:
	hurtbox.area_entered.connect(_on_hurtbox_area_entered)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	if health_bar_scene != null:
		var bar := health_bar_scene.instantiate() as HealthBar
		add_child(bar)
		bar.setup(health, self)

# ── Hurtbox ──────────────────────────────────────────────────────

func _on_hurtbox_area_entered(area: Area2D) -> void:
	if not area is Hitbox:
		return
	health.take_damage(area.damage)
	if area.attacker != null and not knockback_immune:
		var direction: Vector2
		if area.knockback_facing:
			direction = Vector2.RIGHT.rotated(area.attacker.rotation)
		else:
			direction = (global_position - area.attacker.global_position).normalized()
		knockback_component.apply(area.knockback_tier, direction)

# ── Physics Process ──────────────────────────────────────────────

func _physics_process(_delta: float) -> void:
	if knockback_component.is_active() and not knockback_immune:
		var tier := knockback_component.get_tier()
		var dir := knockback_component.get_direction()
		var push_speed: float = KnockbackComponent.TIER_SPEEDS.get(tier, 0.0)
		var mult := knockback_component.get_speed_multiplier()
		velocity = dir * push_speed * mult
		move_and_slide()
	else:
		velocity = Vector2.ZERO

# ── Hit Flash ────────────────────────────────────────────────────

func _on_damaged(_amount: int, _remaining: int) -> void:
	var target := flash_target if flash_target != null else self
	var tween := create_tween()
	tween.tween_property(target, "modulate", Color(8.0, 8.0, 8.0, 1.0), 0.05)
	tween.tween_property(target, "modulate", Color.WHITE, 0.1)

# ── Death ────────────────────────────────────────────────────────

func _on_died() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.1)
	tween.tween_interval(0.1)
	tween.tween_callback(func(): queue_free())
