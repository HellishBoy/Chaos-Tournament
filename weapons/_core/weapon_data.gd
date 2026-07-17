extends Resource
class_name WeaponData

@export_group("Identity")
@export var weapon_name: String = "Fists"
@export_enum("none", "melee", "ranged", "projectile", "grenade") var weapon_category: String = "none"
@export var power: int = 1

@export_group("Animations")
@export var idle_animation: String = ""
@export var walk_animation: String = ""
@export var main_attack_animations: Array[String] = []
@export var alt_attack_animations: Array[String] = []

@export_group("Drop")
@export var despawn_timer: float = 8.0  # -1 = never despawn

@export_group("Weapon Property")
@export_subgroup("Camera")
@export var peek_distance_aim: float = 0.0
@export var peek_distance_lockon: float = 0.0

@export_subgroup("Weight")
@export_enum("none", "light", "medium", "heavy") var weight: String = "none"

const WEIGHT_TIERS: Dictionary = {
	"none":   0.0,
	"light":  0.10,
	"medium": 0.20,
	"heavy":  0.45,
}

func get_weight_multiplier() -> float:
	var penalty: float = WEIGHT_TIERS.get(weight, 0.0)
	return 1.0 - penalty
	
@export_subgroup("Durability")
@export_enum("none", "low", "medium", "high", "infinite") var durability: String = "infinite"
@export var durability_current: int = -1  # -1 = not applicable

@export_subgroup("Recoil")
@export var can_recoil: bool = false
@export_enum("none", "low", "medium", "high") var main_recoil: String = "none"
@export_enum("none", "low", "medium", "high") var alt_recoil: String = "none"

@export_group("Combat Property")
@export_subgroup("Combat")
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

@export_subgroup("Impact")
@export var can_knockback: bool = false
@export var can_flinch: bool = false

@export_subgroup("Movement")
@export var movement_penalty: float = 0.6

@export_subgroup("Charge")
@export var main_attack_charge: bool = false
@export var alt_attack_charge: bool = false
@export var main_charge_time: float = 1.0  # seconds to reach full charge
@export var alt_charge_time: float = 1.0   # reserved for a future alt-charge attack

@export_subgroup("Toss")
@export var can_toss: bool = true

@export_subgroup("Melee")
# Reserved for melee-only fields (attack reach/arc, block/parry data,
# swing sound, etc.) — nothing here yet, since every current combat
# field (damage, knockback, flinch, combo, charge, recoil, weight,
# status effects) already applies equally to melee and ranged weapons.

@export_group("Projectile")
@export_enum("bullet", "grenade") var projectile_type: String = "bullet"
@export_subgroup("Bullet")
@export var bullet_scene: PackedScene
@export var bullet_speed: float = 300.0
@export var bullet_range: float = -1.0  # -1 = infinite
@export var bullet_pierce: int = 0      # 0 = no pierce, -1 = infinite
@export var bullet_spread: float = 0.0  # degrees

@export_subgroup("Grenade")
@export var grenade_scene: PackedScene
@export var can_impact_detonate: bool = false
@export var grenade_fuse_time: float = 2.0  # always active — the guaranteed detonation deadline
@export var grenade_blast_radius: float = 48.0
@export var grenade_throw_speed_min: float = 150.0
@export var grenade_throw_speed_max: float = 400.0
@export var can_linger: bool = false
@export var linger_duration: float = 3.0        # how long the hazard area persists after explosion
@export var linger_scan_interval: float = 0.5   # how often it re-applies DOT to anyone standing inside

@export_subgroup("Ammo")
@export_enum("Ammo", "Quantity") var amount_label: String = "Ammo"
# Shared consumable count for ranged, grenade, and projectile weapons —
# "Ammo" for guns, "Quantity" for grenades/thrown weapons (e.g. a kunai
# built on the same ranged/bullet system). amount_label only changes
# the HUD wording; the underlying gameplay logic is identical either way.
@export var amount: int = -1  # -1 = not applicable

@export_subgroup("Targeting")
@export var requires_line_of_sight: bool = false

@export_group("Status Effects")
@export_subgroup("Damage Over Time")
@export var can_apply_dot: bool = false
# Cosmetic identity only — "bleed", "poison", "burn", etc. All tags share
# the exact same tick mechanic; VFX/behavior differences are purely visual.
@export_enum("none", "bleed", "burn", "poison", "frostbite") var dot_tag: String = "none"
@export var dot_duration: float = 0.0
@export var dot_tick_interval: float = 0.5
@export var dot_damage_percent: float = 0.0 # percent of target's max HP, per tick
# 1.0 = always applies on hit, 0.3 = 30% chance per hit
@export_range(0.0, 1.0) var dot_chance: float = 1.0

@export_subgroup("Root")
@export var can_root: bool = false
@export_enum("none", "anchored", "petrified") var root_type: String = "none"
@export_enum("none", "ensnared", "zapped") var root_tag: String = "none"
@export var root_duration: float = 0.0
# 1.0 = always applies on hit, 0.3 = 30% chance per hit
@export_range(0.0, 1.0) var root_chance: float = 1.0

@export_subgroup("Disarm")
@export var can_disarm: bool = false
# Reserved for future disarm variants — only "disarm" exists for now.
@export_enum("disarm") var disarm_tag: String = "disarm"
@export var disarm_duration: float = 0.0
# 1.0 = always applies on hit, 0.3 = 30% chance per hit
@export_range(0.0, 1.0) var disarm_chance: float = 1.0

@export_subgroup("Slow")
@export var can_slow: bool = false
# Reserved for future slow variants — only "slow" exists for now.
@export_enum("slow") var slow_tag: String = "slow"
@export var slow_duration: float = 0.0
# Fixed movement speed reduction while active (0.3 = 30% slower)
@export_range(0.0, 1.0) var slow_percent: float = 0.0
# 1.0 = always applies on hit, 0.3 = 30% chance per hit
@export_range(0.0, 1.0) var slow_chance: float = 1.0

@export_group("Sprites")
@export var weapon_sprite_ground: Texture2D
@export var weapon_sprite_left: Texture2D
@export var weapon_sprite_right: Texture2D

@export_group("AI")
@export_enum("TAP", "HOLD") var ai_main_attack_mode: String = "TAP"
@export var ai_main_attack_range: float = 24.0

@export_enum("TAP", "HOLD") var ai_alt_attack_mode: String = "TAP"
@export var ai_alt_attack_range: float = 24.0

const WEIGHT_TIER_ORDER: Array[String] = ["none", "light", "medium", "heavy"]
const IMPACT_TIER_ORDER: Array[String] = ["none", "low", "medium", "high"]

static func step_down_weight_tier(tier: String) -> String:
	var idx := WEIGHT_TIER_ORDER.find(tier)
	if idx <= 0:
		return tier
	return WEIGHT_TIER_ORDER[idx - 1]

static func step_down_impact_tier(tier: String) -> String:
	var idx := IMPACT_TIER_ORDER.find(tier)
	if idx <= 0:
		return tier
	return IMPACT_TIER_ORDER[idx - 1]

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
	
func get_root_config() -> Dictionary:
	if not can_root:
		return { "type": "none", "tag": "none", "duration": 0.0, "chance": 0.0 }
	return { "type": root_type, "tag": root_tag, "duration": root_duration, "chance": root_chance }
	
func get_disarm_config() -> Dictionary:
	if not can_disarm:
		return { "tag": "", "duration": 0.0, "chance": 0.0 }
	return { "tag": disarm_tag, "duration": disarm_duration, "chance": disarm_chance }

func get_slow_config() -> Dictionary:
	if not can_slow:
		return { "tag": "", "duration": 0.0, "percent": 0.0, "chance": 0.0 }
	return { "tag": slow_tag, "duration": slow_duration, "percent": slow_percent, "chance": slow_chance }

func validate_impact_flags() -> void:
	if can_knockback and can_flinch:
		push_warning(weapon_name + ": can_knockback and can_flinch cannot both be true — a weapon must use only one impact effect.")

# ── Damage Over Time ──────────────────────────────────────────

func get_dot_config() -> Dictionary:
	if not can_apply_dot or dot_tag == "none":
		return { "tag": "", "duration": 0.0, "tick_interval": 0.0, "damage_percent": 0.0, "chance": 0.0 }
	return {
		"tag": dot_tag,
		"duration": dot_duration,
		"tick_interval": dot_tick_interval,
		"damage_percent": dot_damage_percent,
		"chance": dot_chance,
	}

func validate_dot_tag() -> void:
	if can_apply_dot and dot_tag != "none" and not StatusEffectComponent.is_known_effect(dot_tag):
		push_warning(weapon_name + ": dot_tag '" + dot_tag + "' does not match any entry in StatusEffectComponent.EFFECT_REGISTRY.")
		
func validate_linger() -> void:
	if can_linger and not can_apply_dot:
		push_warning(weapon_name + ": can_linger is true but can_apply_dot is false — the lingering hazard has no DOT effect to apply.")
