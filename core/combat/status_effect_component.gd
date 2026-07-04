# StatusEffectComponent.gd
# Generic timer-based status effect tracker.
# Supports plain flag effects (e.g. "steadfast") and ticking damage-over-time
# effects (e.g. "bleed", "poison") under the same system.
# Add new buffs/debuffs by calling apply_effect() — no new code needed here.
extends Node
class_name StatusEffectComponent

# Source of truth for valid effect names — add new buffs/debuffs here
# so anything applying an effect by name can be validated against typos.
const KNOWN_EFFECTS: Array[String] = [
	"steadfast",
	"bleed",
	"poison",
]

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
	if not KNOWN_EFFECTS.has(effect_name):
		push_warning("StatusEffectComponent: '" + effect_name + "' is not in KNOWN_EFFECTS — check for a typo.")
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
