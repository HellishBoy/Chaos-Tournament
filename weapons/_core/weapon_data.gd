extends Resource
class_name WeaponData

@export_group("Identity")
@export var weapon_name: String = "Fists"
@export_enum("none", "melee_1h", "melee_2h", "melee_dual",
			 "ranged_1h", "ranged_2h", "ranged_dual",
			 "projectile", "grenade") var weapon_category: String = "none"
@export var power: int = 1

@export_group("Animations")
@export var idle_animation: String = ""
@export var walk_animation: String = ""
@export var main_attack_animations: Array[String] = []
@export var alt_attack_animations: Array[String] = []

@export_group("Drop")
@export var despawn_timer: float = 8.0  # -1 = never despawn

@export_group("Camera")
@export var peek_distance_aim: float = 0.0
@export var peek_distance_lockon: float = 0.0

@export_group("Movement")
@export var movement_penalty: float = 0.6

@export_group("Weight")
@export_enum("none", "low", "medium", "high") var weight: String = "none"

const WEIGHT_TIERS: Dictionary = {
	"none":   0.0,
	"low":    0.10,
	"medium": 0.30,
	"high":   0.55,
}

func get_weight_multiplier() -> float:
	var penalty: float = WEIGHT_TIERS.get(weight, 0.0)
	return 1.0 - penalty

@export_group("Combat")
@export var main_attack_speed: float = 1.0
@export var alt_attack_speed: float = 1.0
@export var damage_main: int = 10
@export var damage_alt: int = 5
@export_enum("none", "low", "medium", "high") var main_knockback: String = "none"
@export_enum("none", "low", "medium", "high") var alt_knockback: String = "none"
@export_enum("none", "low", "medium", "high") var main_flinch: String = "none"
@export_enum("none", "low", "medium", "high") var alt_flinch: String = "none"
@export var has_combo: bool = false

# false = push away from attacker, true = push in attacker's facing direction
@export var knockback_main_facing: bool = false
@export var knockback_alt_facing: bool = false

@export_group("Recoil")
@export var can_recoil: bool = false
@export_enum("none", "low", "medium", "high") var main_recoil: String = "none"
@export_enum("none", "low", "medium", "high") var alt_recoil: String = "none"

@export_group("Impact")
@export var can_knockback: bool = false
@export var can_flinch: bool = false

@export_group("Durability")
@export_enum("none", "low", "medium", "high", "infinite") var durability: String = "infinite"
@export var durability_current: int = -1  # -1 = not applicable

@export_group("Ammo")
@export var ammo: int = -1      # -1 = not applicable
@export var quantity: int = -1  # -1 = not applicable

@export_group("Toss")
@export var can_toss: bool = true

@export_group("Charge")
@export var main_attack_charge: bool = false
@export var alt_attack_charge: bool = false

@export_group("Bullet | Projectile")
@export var bullet_scene: PackedScene
@export var bullet_speed: float = 300.0
@export var bullet_range: float = -1.0  # -1 = infinite
@export var bullet_pierce: int = 0      # 0 = no pierce, -1 = infinite
@export var bullet_spread: float = 0.0  # degrees

@export_group("Damage Over Time")
@export var can_apply_dot: bool = false
# Cosmetic identity only — "bleed", "poison", "burn", etc. All tags share
# the exact same tick mechanic; VFX/behavior differences are purely visual.
@export var main_dot_tag: String = ""
@export var main_dot_duration: float = 0.0
@export var main_dot_tick_interval: float = 1.0
@export var main_dot_damage_percent: float = 0.0 # percent of target's max HP, per tick
@export var alt_dot_tag: String = ""
@export var alt_dot_duration: float = 0.0
@export var alt_dot_tick_interval: float = 1.0
@export var alt_dot_damage_percent: float = 0.0 # percent of target's max HP, per tick

@export_group("Root")
@export var can_root: bool = false
@export_enum("none", "anchored", "petrified") var main_root_type: String = "none"
@export var main_root_duration: float = 0.0
@export_enum("none", "anchored", "petrified") var alt_root_type: String = "none"
@export var alt_root_duration: float = 0.0

@export_group("Sprites")
@export var weapon_sprite_ground: Texture2D
@export var weapon_sprite_left: Texture2D
@export var weapon_sprite_right: Texture2D

@export_group("AI")
@export_enum("TAP", "HOLD") var ai_main_attack_mode: String = "TAP"
@export var ai_main_attack_range: float = 24.0

@export_enum("TAP", "HOLD") var ai_alt_attack_mode: String = "TAP"
@export var ai_alt_attack_range: float = 24.0

@export var requires_line_of_sight: bool = false

# ── Impact Tier Getters ──────────────────────────────────────────
# Gate the raw tier behind the safety flag, so a weapon can't
# accidentally apply an effect nobody toggled on.

func get_main_knockback_tier() -> String:
	return main_knockback if can_knockback else "none"

func get_alt_knockback_tier() -> String:
	return alt_knockback if can_knockback else "none"

func get_main_flinch_tier() -> String:
	return main_flinch if can_flinch else "none"

func get_alt_flinch_tier() -> String:
	return alt_flinch if can_flinch else "none"
	
func get_main_recoil_tier() -> String:
	return main_recoil if can_recoil else "none"

func get_alt_recoil_tier() -> String:
	return alt_recoil if can_recoil else "none"
	
func get_main_root_type() -> String:
	return main_root_type if can_root else "none"

func get_alt_root_type() -> String:
	return alt_root_type if can_root else "none"

func validate_impact_flags() -> void:
	if can_knockback and can_flinch:
		push_warning(weapon_name + ": can_knockback and can_flinch cannot both be true — a weapon must use only one impact effect.")

# ── Damage Over Time ──────────────────────────────────────────

func get_main_dot_config() -> Dictionary:
	if not can_apply_dot:
		return { "tag": "", "duration": 0.0, "tick_interval": 0.0, "damage_percent": 0.0 }
	return {
		"tag": main_dot_tag,
		"duration": main_dot_duration,
		"tick_interval": main_dot_tick_interval,
		"damage_percent": main_dot_damage_percent,
	}

func get_alt_dot_config() -> Dictionary:
	if not can_apply_dot:
		return { "tag": "", "duration": 0.0, "tick_interval": 0.0, "damage_percent": 0.0 }
	return {
		"tag": alt_dot_tag,
		"duration": alt_dot_duration,
		"tick_interval": alt_dot_tick_interval,
		"damage_percent": alt_dot_damage_percent,
	}

func validate_dot_tag() -> void:
	if not can_apply_dot:
		return
	if main_dot_tag != "" and not StatusEffectComponent.is_known_effect(main_dot_tag):
		push_warning(weapon_name + ": main_dot_tag '" + main_dot_tag + "' does not match any entry in StatusEffectComponent.EFFECT_REGISTRY.")
	if alt_dot_tag != "" and not StatusEffectComponent.is_known_effect(alt_dot_tag):
		push_warning(weapon_name + ": alt_dot_tag '" + alt_dot_tag + "' does not match any entry in StatusEffectComponent.EFFECT_REGISTRY.")
