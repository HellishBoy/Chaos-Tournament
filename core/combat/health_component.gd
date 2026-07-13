## HealthComponent.gd
## Attach as a child Node to any entity that can take damage.
## Works for both player and enemies.
##
## Node name must be "HealthComponent" so other scripts can find it with:
##   $HealthComponent

extends Node
class_name HealthComponent

@export var max_hp: int = 100
@export var current_hp: int = 100
@export var immortal: bool = false
# How long the entity is invincible after taking a hit (in seconds)
@export var invincibility_duration: float = 0.0

enum HealthBarVisibility {
	ALWAYS_SHOW,
	ALWAYS_HIDE,
	HIDE_ON_FULL_HEALTH,
}

@export var health_bar_visibility: HealthBarVisibility = HealthBarVisibility.ALWAYS_SHOW

signal damaged(amount: int, remaining: int)
signal died
signal invincibility_started
signal invincibility_ended

signal healed(amount: int, current: int)

var _invincible: bool = false
var _invincibility_timer: float = 0.0

func _ready() -> void:
	current_hp = max_hp

func _process(delta: float) -> void:
	if _invincible:
		_invincibility_timer -= delta
		if _invincibility_timer <= 0.0:
			_invincible = false
			emit_signal("invincibility_ended")

func take_damage(amount: int) -> void:
	if immortal:
		return
	if current_hp <= 0:
		return  # already dead
	if _invincible:
		return  # invincible — ignore hit
	var reduced_amount := amount
	var owner_node := get_parent()
	if owner_node is Character and owner_node.stats != null:
		reduced_amount = roundi(amount * (1.0 - owner_node.stats.divine_aegis))
	current_hp -= reduced_amount
	emit_signal("damaged", amount, current_hp)
	if current_hp <= 0:
		emit_signal("died")
	else:
		# Only start i-frames if still alive
		_invincible = true
		_invincibility_timer = invincibility_duration
		emit_signal("invincibility_started")

func heal(amount: int) -> void:
	current_hp = min(current_hp + amount, max_hp)
	emit_signal("healed", amount, current_hp)

func is_dead() -> bool:
	return current_hp <= 0

func is_invincible() -> bool:
	return _invincible
