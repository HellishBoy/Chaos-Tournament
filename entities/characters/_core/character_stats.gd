# CharacterStats.gd
# Assign one of these as a resource in the Inspector on any Character.
# Holds all tunable per-character values so nothing is hardcoded in scripts.
extends Resource
class_name CharacterStats

@export_group("Movement")
@export var move_speed: float = 120.0

# The lowest total speed multiplier a character can be reduced to,
# regardless of how many slowing effects (weight, knockback, flinch,
# attack penalty) stack together. 0.0 = can be fully stopped, 1.0 = 
# immune to all slowing (rarely what you want).
@export_range(0.0, 1.0) var min_speed_multiplier: float = 0.15

@export_group("Combat")
@export var damage_multiplier: float = 1.0
@export var attack_speed_multiplier: float = 1.0

@export_group("Health")
@export var max_hp: int = 300

@export_group("Defense")

# flat % damage reduction, applies to every damage source uniformly. 1.0 = immune to all damage.
@export_range(0.0, 1.0) var divine_aegis: float = 0.0

# 0.0 = gets pushed full amount, 1.0 = immune to knockback
@export_range(0.0, 1.0) var knockback_resistance: float = 0.0

# 0.0 = takes full flinch effect, 1.0 = immune to flinch
@export_range(0.0, 1.0) var flinch_resistance: float = 0.0

# Reduces root DURATION, not intensity (root is binary — you're either
# stopped or you're not). 1.0 = root effects have zero duration on this character.
@export_range(0.0, 1.0) var root_resistance: float = 0.0

@export_group("Dodge")
@export var stamina_max: float = 10.0
@export var stamina_regen: float = 3.0
@export var stamina_per_dodge: float = 5.0
@export var dodge_speed: float = 250.0
@export var dodge_distance: float = 48.0
@export var dodge_cooldown: float = 0.1

@export_group("Passive Skills")
@export var passive_skills: Array[PassiveSkillData] = []

const MAX_PASSIVE_SLOTS: int = 4

func validate_passive_skills() -> void:
	if passive_skills.size() > MAX_PASSIVE_SLOTS:
		push_warning("CharacterStats: passive_skills has " + str(passive_skills.size()) + " entries — only " + str(MAX_PASSIVE_SLOTS) + " slots are intended. Extra entries will still be applied.")
	for skill in passive_skills:
		if skill != null:
			skill.validate_effect_type()
