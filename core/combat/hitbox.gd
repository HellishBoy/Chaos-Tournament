## Hitbox.gd
## Attach to the Hitbox Area2D on the player.
##
## Scene structure:
##   Hitbox (Area2D)           ← Layer: 7 (Hitbox), Mask: 6 (Hurtbox)
##   └── CollisionShape2D      ← disabled by default
##
## The animation drives everything:
##   - Position, rotation, scale of this node
##   - The CollisionShape2D's "disabled" property (on/off per frame)

extends Area2D
class_name Hitbox

# Set this from player.gd before attacking so the hitbox knows how much damage to deal
var damage: int = 0

var knockback_tier: String = "none"
var flinch_tier: String = "none"
var knockback_facing: bool = false  # false = away from attacker, true = attacker's facing dir
var attacker: Node2D = null         # set to the player node so we know position and facing

var dot_tag: String = ""
var dot_duration: float = 0.0
var dot_tick_interval: float = 0.0
var dot_damage_percent: float = 0.0

var root_type: String = "none"
var root_duration: float = 0.0

func _ready() -> void:
	area_entered.connect(_on_area_entered)
	$CollisionShape2D.disabled = true

func _on_area_entered(area: Area2D) -> void:
	var parent := area.get_parent()
	if parent.has_node("HealthComponent"):
		var health := parent.get_node("HealthComponent") as HealthComponent
		health.take_damage(damage)

	var status: StatusEffectComponent = parent.get_node("StatusEffectComponent") if parent.has_node("StatusEffectComponent") else null
	var is_steadfast: bool = status != null and status.has_effect("steadfast")

	if parent.has_node("ImpactComponent") and attacker != null and not is_steadfast:
		var impact := parent.get_node("ImpactComponent") as ImpactComponent
		if knockback_tier != "none":
			var direction: Vector2
			if knockback_facing:
				direction = Vector2.RIGHT.rotated(attacker.rotation)
			else:
				direction = (parent.global_position - attacker.global_position).normalized()
			impact.apply_knockback(knockback_tier, direction)
		elif flinch_tier != "none":
			var resistance: float = parent.stats.flinch_resistance if parent is Character else 0.0
			impact.apply_flinch(flinch_tier, resistance)

	if dot_tag != "" and status != null:
		status.apply_effect(dot_tag, dot_duration, dot_tick_interval, dot_damage_percent)
		
	if root_type != "none" and status != null:
		var root_resist: float = parent.stats.root_resistance if parent is Character else 0.0
		var effective_duration: float = root_duration * (1.0 - root_resist)
		status.apply_effect(root_type, effective_duration)

	if attacker != null and attacker is Character:
		var weapon: WeaponData = attacker.get_active_weapon()
		if weapon.durability_current > 0:
			weapon.durability_current -= 1
			var hud := get_tree().get_first_node_in_group("hud") as HUD
			if hud:
				hud.refresh()
			if weapon.durability_current == 0:
				attacker.call_deferred("break_weapon")
