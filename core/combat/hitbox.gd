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
var dot_chance: float = 1.0

var root_type: String = "none"
var root_tag: String = "none"
var root_duration: float = 0.0
var root_chance: float = 1.0

var disarm_tag: String = ""
var disarm_duration: float = 0.0
var disarm_chance: float = 1.0

var slow_tag: String = ""
var slow_duration: float = 0.0
var slow_percent: float = 0.0
var slow_chance: float = 1.0

func _ready() -> void:
	area_entered.connect(_on_area_entered)
	$CollisionShape2D.disabled = true

func _on_area_entered(area: Area2D) -> void:
	var parent := area.get_parent()

	var knockback_direction := Vector2.ZERO
	if attacker != null:
		if knockback_facing:
			knockback_direction = Vector2.RIGHT.rotated(attacker.rotation)
		else:
			knockback_direction = (parent.global_position - attacker.global_position).normalized()

	CombatResolver.apply_hit(
		parent,
		damage,
		knockback_tier,
		knockback_direction,
		flinch_tier,
		{ "tag": dot_tag, "duration": dot_duration, "tick_interval": dot_tick_interval, "damage_percent": dot_damage_percent, "chance": dot_chance },
		{ "type": root_type, "duration": root_duration, "chance": root_chance },
		{ "tag": disarm_tag, "duration": disarm_duration, "chance": disarm_chance },
		{ "tag": slow_tag, "duration": slow_duration, "percent": slow_percent, "chance": slow_chance }
	)

	if attacker != null and attacker is Character:
		var weapon: WeaponData = attacker.get_active_weapon()
		if weapon.durability_current > 0:
			weapon.durability_current -= 1
			var hud := get_tree().get_first_node_in_group("hud") as HUD
			if hud:
				hud.refresh()
			if weapon.durability_current == 0:
				attacker.call_deferred("break_weapon")
