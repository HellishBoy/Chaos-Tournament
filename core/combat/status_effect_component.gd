# StatusEffectComponent.gd
# Generic timer-based status effect tracker.
# Supports plain flag effects (e.g. "steadfast") and ticking damage-over-time
# effects (e.g. "bleed", "poison") under the same system.
# Add new buffs/debuffs by registering them in EFFECT_REGISTRY below,
# then calling apply_effect() — no other new code needed.
extends Node
class_name StatusEffectComponent

enum Category {
	BUFF,
	DEBUFF,
}

# Single source of truth for every valid effect name AND its category.
# Add new buffs/debuffs here — AI scanning, validation, and UI can all
# key off category alone without ever listing effect names individually.
const EFFECT_REGISTRY: Dictionary = {
	"steadfast": Category.BUFF,
	"bleed":     Category.DEBUFF,
	"poison":    Category.DEBUFF,
	"anchored":  Category.DEBUFF,
	"petrified":    Category.DEBUFF,
	"disarm":     Category.DEBUFF,
}

# Effect name (String) -> Dictionary {remaining, tick_interval, tick_timer, tick_damage_percent}
var _active_effects: Dictionary = {}

signal effect_applied(effect_name: String, duration: float)
signal effect_removed(effect_name: String)
signal effect_ticked(effect_name: String, damage_percent: float)

func _process(delta: float) -> void:
	if _active_effects.is_empty():
		return
	var expired: Array = []
	for effect_name in _active_effects.keys():
		var data: Dictionary = _active_effects[effect_name]
		data["remaining"] -= delta

		if data["tick_interval"] > 0.0:
			data["tick_timer"] -= delta
			if data["tick_timer"] <= 0.0:
				data["tick_timer"] += data["tick_interval"]
				emit_signal("effect_ticked", effect_name, data["tick_damage_percent"])

		if data["remaining"] <= 0.0:
			expired.append(effect_name)

	for effect_name in expired:
		_active_effects.erase(effect_name)
		emit_signal("effect_removed", effect_name)

# Applies an effect for the given duration. If already active, refreshes
# the timer (does not stack/add on top).
# tick_interval / tick_damage_percent are optional — leave at 0.0 for a
# plain flag effect like "steadfast" that has no damage-over-time component.
func apply_effect(effect_name: String, duration: float, tick_interval: float = 0.0, tick_damage_percent: float = 0.0) -> void:
	if duration <= 0.0:
		return
	if not is_known_effect(effect_name):
		push_warning("StatusEffectComponent: '" + effect_name + "' is not in EFFECT_REGISTRY — check for a typo.")
	_active_effects[effect_name] = {
		"remaining": duration,
		"tick_interval": tick_interval,
		"tick_timer": tick_interval,
		"tick_damage_percent": tick_damage_percent,
	}
	emit_signal("effect_applied", effect_name, duration)

func has_effect(effect_name: String) -> bool:
	return _active_effects.has(effect_name)

func remove_effect(effect_name: String) -> void:
	if _active_effects.has(effect_name):
		_active_effects.erase(effect_name)
		emit_signal("effect_removed", effect_name)

func get_remaining_time(effect_name: String) -> float:
	if not _active_effects.has(effect_name):
		return 0.0
	return _active_effects[effect_name]["remaining"]

func clear_all() -> void:
	_active_effects.clear()
	
# ── Static Registry Helpers ────────────────────────────────────────
# Callable without an instance: StatusEffectComponent.get_effect_category(name)

static func is_known_effect(effect_name: String) -> bool:
	return EFFECT_REGISTRY.has(effect_name)

static func get_effect_category(effect_name: String) -> int:
	return EFFECT_REGISTRY.get(effect_name, Category.DEBUFF)

static func is_buff(effect_name: String) -> bool:
	return EFFECT_REGISTRY.get(effect_name, Category.DEBUFF) == Category.BUFF
