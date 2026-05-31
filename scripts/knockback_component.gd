extends Node
class_name KnockbackComponent

const TIERS = {
	"none":   { "speed_reduction": 0.0, "recovery_time": 0.0 },
	"low":    { "speed_reduction": 0.4, "recovery_time": 0.3 },
	"medium": { "speed_reduction": 0.7, "recovery_time": 0.5 },
	"high":   { "speed_reduction": 1.0, "recovery_time": 0.8 },
}

var _tier: String = "none"
var _direction: Vector2 = Vector2.ZERO
var _recovery_time: float = 0.0
var _timer: float = 0.0
var _active: bool = false

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
	# t goes from 1.0 to 0.0 as timer counts down
	# we want speed to start high and ease out to zero
	var t: float = clamp(_timer / _recovery_time, 0.0, 1.0)
	var reduction: float = TIERS.get(_tier, TIERS["none"])["speed_reduction"]
	return reduction * t  # starts at full push, eases to zero

func get_tier() -> String:
	return _tier

func get_direction() -> Vector2:
	return _direction

func is_active() -> bool:
	return _active
