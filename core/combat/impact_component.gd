extends Node
class_name ImpactComponent

# ── Knockback ────────────────────────────────────────────────────
# Pushes the character's position and eases its own speed back afterward.
const KNOCKBACK_TIERS: Dictionary = {
	"none":   { "speed_reduction": 0.0, "recovery_time": 0.0 },
	"low":    { "speed_reduction": 0.3, "recovery_time": 0.2 },
	"medium": { "speed_reduction": 0.6, "recovery_time": 0.5 },
	"high":   { "speed_reduction": 1.0, "recovery_time": 0.7 },
}

const KNOCKBACK_TIER_SPEEDS: Dictionary = {
	"none":   0.0,
	"low":    110.0,
	"medium": 160.0,
	"high":   200.0,
}

var _kb_tier: String = "none"
var _kb_direction: Vector2 = Vector2.ZERO
var _kb_recovery_time: float = 0.0
var _kb_timer: float = 0.0
var _kb_active: bool = false

# ── Flinch ───────────────────────────────────────────────────────
# No push — briefly reduces move speed by a tier-based percentage,
# then eases back to full speed over a fixed recovery time.
const FLINCH_TIERS: Dictionary = {
	"none":   { "reduction": 0.0 },
	"low":    { "reduction": 0.2 },
	"medium": { "reduction": 0.45 },
	"high":   { "reduction": 0.75 },
}
const FLINCH_RECOVERY_TIME: float = 0.5

var _flinch_start_multiplier: float = 1.0
var _flinch_recovery_time: float = 0.0
var _flinch_timer: float = 0.0
var _flinch_active: bool = false

signal knockback_started(tier: String, direction: Vector2)
signal knockback_ended
signal flinch_started(tier: String)
signal flinch_ended

# ── Apply ────────────────────────────────────────────────────────

func apply_knockback(tier: String, direction: Vector2) -> void:
	if tier == "none":
		return
	var data: Dictionary = KNOCKBACK_TIERS.get(tier, KNOCKBACK_TIERS["none"])
	_kb_tier = tier
	_kb_direction = direction.normalized()
	_kb_recovery_time = data["recovery_time"]
	_kb_timer = _kb_recovery_time
	_kb_active = true
	emit_signal("knockback_started", tier, direction)

func apply_flinch(tier: String, resistance: float = 0.0) -> void:
	if tier == "none":
		return
	var reduction: float = FLINCH_TIERS.get(tier, FLINCH_TIERS["none"])["reduction"]
	var effective_reduction: float = clamp(reduction * (1.0 - resistance), 0.0, 1.0)
	_flinch_start_multiplier = 1.0 - effective_reduction
	_flinch_recovery_time = FLINCH_RECOVERY_TIME
	_flinch_timer = _flinch_recovery_time
	_flinch_active = true
	emit_signal("flinch_started", tier)

# ── Process ──────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _kb_active:
		_kb_timer -= delta
		if _kb_timer <= 0.0:
			_kb_active = false
			_kb_tier = "none"
			emit_signal("knockback_ended")
	if _flinch_active:
		_flinch_timer -= delta
		if _flinch_timer <= 0.0:
			_flinch_active = false
			emit_signal("flinch_ended")

# ── Speed Multiplier ─────────────────────────────────────────────
# Combined effect on the character's own control speed.
# (The knockback PUSH itself is separate — see the queries below.)

func _get_knockback_multiplier() -> float:
	if not _kb_active:
		return 1.0
	var reduction: float = KNOCKBACK_TIERS.get(_kb_tier, KNOCKBACK_TIERS["none"])["speed_reduction"]
	var t_out: float = clamp(_kb_timer / _kb_recovery_time, 0.3, 1.0)
	return reduction * t_out

func _get_flinch_multiplier() -> float:
	if not _flinch_active:
		return 1.0
	var t: float = clamp(1.0 - (_flinch_timer / _flinch_recovery_time), 0.0, 1.0)
	return lerp(_flinch_start_multiplier, 1.0, t * t)

# ── Knockback Queries (used for the actual position push) ────────

func get_knockback_tier() -> String:
	return _kb_tier

func get_knockback_direction() -> Vector2:
	return _kb_direction

func is_knockback_active() -> bool:
	return _kb_active

func is_flinching() -> bool:
	return _flinch_active

# ── Reset (used on respawn) ───────────────────────────────────────

func reset() -> void:
	_kb_active = false
	_kb_tier = "none"
	_flinch_active = false
	
# ── Public Multiplier Getters ─────────────────────────────────────

func get_knockback_multiplier() -> float:
	return _get_knockback_multiplier()

func get_flinch_multiplier() -> float:
	return _get_flinch_multiplier()

# Used for the character's OWN movement input.
# Knockback's penalty is scaled down by knockback_resistance (0 penalty at full resistance).
# Flinch's penalty is NOT touched here — it already applied flinch_resistance at apply-time.
func get_control_speed_multiplier(knockback_resistance: float) -> float:
	var kb_mult := _get_knockback_multiplier()
	var effective_kb_mult := 1.0 - (1.0 - kb_mult) * (1.0 - knockback_resistance)
	return effective_kb_mult * _get_flinch_multiplier()
