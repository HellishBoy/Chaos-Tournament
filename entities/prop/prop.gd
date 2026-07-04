# Prop.gd
# Base class for destructible world objects — trees, crates, dummies, barrels, etc.
# No weapons, no AI, no movement. Just takes damage and dies.
extends CharacterBody2D
class_name Prop

# ── Exports ──────────────────────────────────────────────────────

@export var flash_target: Node2D

@export_group("Knockback")
# 0.0 = gets pushed full amount, 1.0 = immune to knockback
@export_range(0.0, 1.0) var knockback_resistance: float = 0.0

@export_group("Health Bar")
@export var health_bar_scene: PackedScene
@export var health_bar_width: float = 20.0
@export var health_bar_height: float = 2.0
@export var health_bar_offset: Vector2 = Vector2(0, -16)

# ── Node References ──────────────────────────────────────────────

@onready var health: HealthComponent = $HealthComponent
@onready var hurtbox: Area2D = $Hurtbox
@onready var impact_component: ImpactComponent = $ImpactComponent

# ── Ready ────────────────────────────────────────────────────────

func _ready() -> void:
	hurtbox.area_entered.connect(_on_hurtbox_area_entered)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	call_deferred("_setup_health_bar")

func _setup_health_bar() -> void:
	if health_bar_scene != null:
		var bar := health_bar_scene.instantiate() as HealthBar
		get_parent().add_child(bar)
		bar.vertical_offset = health_bar_offset
		bar.bar_width = health_bar_width
		bar.bar_height = health_bar_height
		bar.setup(health, self)
		
# ── Hurtbox ──────────────────────────────────────────────────────

func _on_hurtbox_area_entered(area: Area2D) -> void:
	if not area is Hitbox:
		return
	health.take_damage(area.damage)
	if area.attacker != null and area.knockback_tier != "none":
		var direction: Vector2
		if area.knockback_facing:
			direction = Vector2.RIGHT.rotated(area.attacker.rotation)
		else:
			direction = (global_position - area.attacker.global_position).normalized()
		impact_component.apply_knockback(area.knockback_tier, direction)

# ── Physics Process ──────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if impact_component.is_knockback_active():
		var tier := impact_component.get_knockback_tier()
		var dir := impact_component.get_knockback_direction()
		var push_speed: float = ImpactComponent.KNOCKBACK_TIER_SPEEDS.get(tier, 0.0)
		var mult := impact_component.get_knockback_multiplier()
		var resistance := 1.0 - knockback_resistance
		velocity = dir * push_speed * mult * resistance
		var collision := move_and_collide(velocity * delta)
		if collision:
			velocity = velocity.bounce(collision.get_normal())
			impact_component._kb_direction = velocity.normalized()
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
