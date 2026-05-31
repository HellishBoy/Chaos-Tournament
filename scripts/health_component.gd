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
# How long the entity is invincible after taking a hit (in seconds)
@export var invincibility_duration: float = 0.2

signal damaged(amount: int, remaining: int)
signal died
signal invincibility_started
signal invincibility_ended

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
	if current_hp <= 0:
		return  # already dead
	if _invincible:
		return  # invincible — ignore hit
	current_hp -= amount
	current_hp = max(current_hp, 0)
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

func is_dead() -> bool:
	return current_hp <= 0

func is_invincible() -> bool:
	return _invincible
