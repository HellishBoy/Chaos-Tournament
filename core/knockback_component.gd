extends Node
class_name KnockbackComponent

const TIERS = {
	"none":   { "speed_reduction": 0.0, "recovery_time": 0.0 },
	"low":    { "speed_reduction": 0.3, "recovery_time": 0.2 },
	"medium": { "speed_reduction": 0.6, "recovery_time": 0.5 },
	"high":   { "speed_reduction": 1.0, "recovery_time": 0.7 },
}

const TIER_SPEEDS: Dictionary = {
	"none":   0.0,
	"low":    110.0,
	"medium": 160.0,
	"high":   200.0,
}

var _tier: String = "none"
var _direction: Vector2 = Vector2.ZERO
var _recovery_time: float = 0.0
var _timer: float = 0.0
var _active: bool = false
var immune: bool = false

signal knockback_started(tier: String, direction: Vector2)
signal knockback_ended

func apply(tier: String, direction: Vector2) -> void:
	if tier == "none":
		return
	var data: Dictionary = TIERS.get(tier, TIERS["none"])
	_tier = tier
	_direction = direction.normalized()
	_recovery_time = data["recovery_time"]
	_timer = _recovery_time
	_active = true
	emit_signal("knockback_started", tier, direction)

func _process(delta: float) -> void:
	if not _active:
		return
	_timer -= delta
	if _timer <= 0.0:
		_active = false
		_tier = "none"
		emit_signal("knockback_ended")

func get_speed_multiplier() -> float:
	if not _active:
		return 1.0
	var t: float = clamp(1.0 - (_timer / _recovery_time), 0.3, 1.0)
	var reduction: float = TIERS.get(_tier, TIERS["none"])["speed_reduction"]
	if immune:
		# Ease in — starts slow, gradually restores
		return t * t
	else:
		# Ease out — starts at full push, gradually reduces
		var t_out: float = clamp(_timer / _recovery_time, 0.3, 1.0)
		return reduction * t_out
		
func get_tier() -> String:
	return _tier

func get_direction() -> Vector2:
	return _direction

func is_active() -> bool:
	return _active
