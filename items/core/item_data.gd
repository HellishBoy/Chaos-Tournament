# ItemData.gd
# Resource defining an item's properties and effect.
extends Resource
class_name ItemData

enum ItemEffect {
	HEAL,
	STATUS_EFFECT,
}

@export_group("Identity")
@export var item_name: String = "Health Pack"
@export var effect: ItemEffect = ItemEffect.HEAL
@export var effect_value: int = 50

@export_group("Status Effect")
# Only used when effect == STATUS_EFFECT.
# status_effect_name must match the exact string checked via has_effect()
# elsewhere in code (e.g. "steadfast").
@export var status_effect_name: String = ""
@export var status_effect_duration: float = 5.0

@export_group("Drop")
@export var despawn_timer: float = 10.0  # -1 = never despawn

@export_group("Sprites")
@export var item_sprite: Texture2D

func validate_status_effect() -> void:
	if effect == ItemEffect.STATUS_EFFECT and not StatusEffectComponent.KNOWN_EFFECTS.has(status_effect_name):
		push_warning(item_name + ": status_effect_name '" + status_effect_name + "' does not match any entry in StatusEffectComponent.KNOWN_EFFECTS.")
