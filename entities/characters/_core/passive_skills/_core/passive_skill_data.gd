# PassiveSkillData.gd
# A passive skill slotted into CharacterStats.passive_skills.
# One effect per resource — set effect_type, then fill in only the
# fields relevant to that type. Read-only at runtime (no mutation),
# so it does NOT need to be duplicated like WeaponData.
extends Resource
class_name PassiveSkillData

@export_group("Identity")
@export var skill_name: String = "Passive Skill"
@export var description: String = ""
@export var icon: Texture2D

@export_group("Effect")
@export_enum("none", "durability_save", "ammo_save", "no_movement_penalty", "tier_reduction", "dot_reduction") var effect_type: String = "none"

@export_subgroup("Durability or Ammo Save")
# Used by: durability_save, ammo_save
# Chance the consume (durability tick / ammo tick) is skipped entirely.
@export_range(0.0, 1.0) var chance: float = 1.0

@export_subgroup("No Movement Penalty")
# Used by: no_movement_penalty
@export_enum("any", "melee", "ranged", "projectile", "grenade") var weapon_category_filter: String = "any"

@export_subgroup("Tier Reduction")
# Used by: tier_reduction — steps recoil and/or weight down one tier,
# clamped at "none". Applies regardless of weapon category.
@export var reduce_recoil: bool = true
@export var reduce_weight: bool = true

@export_subgroup("DoT Reduction")
# Used by: dot_reduction
@export_enum("bleed", "burn", "poison", "frostbite") var dot_tag_filter: String = "burn"
# Percent reduction applied to incoming damage of this DoT tag (0.3 = 30% less damage per tick)
@export_range(0.0, 1.0) var dot_reduction_percent: float = 0.0

func validate_effect_type() -> void:
	if effect_type == "none":
		push_warning(skill_name + ": effect_type is 'none' — this passive skill will do nothing.")
