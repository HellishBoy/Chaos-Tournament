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

# Set this from player.gd before attacking so the hitbox
# knows how much damage to deal
var damage: int = 0

var knockback_tier: String = "none"
var knockback_facing: bool = false  # false = away from attacker, true = attacker's facing dir
var attacker: Node2D = null         # set to the player node so we know position and facing

func _ready() -> void:
	area_entered.connect(_on_area_entered)
	$CollisionShape2D.disabled = true

func _on_area_entered(area: Area2D) -> void:
	var parent := area.get_parent()
	if parent.has_node("HealthComponent"):
		var health := parent.get_node("HealthComponent") as HealthComponent
		health.take_damage(damage)

	if parent.has_node("KnockbackComponent") and attacker != null:
		var knockback := parent.get_node("KnockbackComponent") as KnockbackComponent
		var direction: Vector2
		if knockback_facing:
			# Push in attacker's facing direction (homerun hit)
			direction = Vector2.RIGHT.rotated(attacker.rotation)
		else:
			# Push away from attacker
			direction = (parent.global_position - attacker.global_position).normalized()
		knockback.apply(knockback_tier, direction)
