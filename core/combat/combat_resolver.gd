# CombatResolver.gd
# Shared logic for applying the effects of a single hit — damage,
# knockback, flinch, DOT, root, disarm, slow — to a target.
# Used by Hitbox (melee), Bullet (ranged), and Grenade (explosion), so
# all three hit types stay in sync: add or change an effect here once,
# everywhere that can deal a hit gets it automatically.
extends RefCounted
class_name CombatResolver

static func apply_hit(
	target: Node,
	damage: int,
	knockback_tier: String,
	knockback_direction: Vector2,
	flinch_tier: String,
	dot_config: Dictionary,
	root_config: Dictionary,
	disarm_config: Dictionary,
	slow_config: Dictionary
) -> void:
	if target.has_node("HealthComponent"):
		var health := target.get_node("HealthComponent") as HealthComponent
		health.take_damage(damage)

	var status: StatusEffectComponent = target.get_node("StatusEffectComponent") if target.has_node("StatusEffectComponent") else null
	var is_steadfast: bool = status != null and status.has_effect("steadfast")

	if target.has_node("ImpactComponent") and not is_steadfast:
		var impact := target.get_node("ImpactComponent") as ImpactComponent
		if knockback_tier != "none":
			impact.apply_knockback(knockback_tier, knockback_direction)
		elif flinch_tier != "none":
			var resistance: float = target.stats.flinch_resistance if target is Character else 0.0
			impact.apply_flinch(flinch_tier, resistance)

	if status == null:
		return

	if dot_config.get("tag", "") != "" and randf() <= dot_config.get("chance", 1.0):
		status.apply_effect(dot_config["tag"], dot_config["duration"], dot_config.get("tick_interval", 0.0), dot_config.get("damage_percent", 0.0))

	if root_config.get("type", "none") != "none" and randf() <= root_config.get("chance", 1.0):
		var root_resist: float = target.stats.root_resistance if target is Character else 0.0
		var effective_duration: float = root_config["duration"] * (1.0 - root_resist)
		status.apply_effect(root_config["type"], effective_duration)

	if disarm_config.get("tag", "") != "" and randf() <= disarm_config.get("chance", 1.0):
		status.apply_effect(disarm_config["tag"], disarm_config["duration"])

	if slow_config.get("tag", "") != "" and randf() <= slow_config.get("chance", 1.0):
		status.apply_effect(slow_config["tag"], slow_config["duration"], 0.0, 0.0, slow_config.get("percent", 0.0))
