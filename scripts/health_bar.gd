extends Node2D
class_name HealthBar

const COLOR_NORMAL: Color = Color(0.2, 0.8, 0.2, 1.0)
const COLOR_ENEMY: Color = Color(0.8, 0.0, 0.0, 1.0)
const COLOR_IMMORTAL: Color = Color(0.6, 0.0, 0.8, 1.0)

@onready var fill: ColorRect = $Fill

var max_width: float = 32.0
var _follow_target: Node2D = null
var _offset: Vector2 = Vector2(0, -16)
var _health: HealthComponent = null
var _max_hp: int = 0

func _ready() -> void:
	top_level = true

func setup(health: HealthComponent, follow_target: Node2D) -> void:
	_follow_target = follow_target
	_health = health
	_max_hp = health.max_hp
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	_update_fill(health.current_hp, health.max_hp)
	if health.immortal:
		fill.color = COLOR_IMMORTAL
	elif follow_target is Enemy:
		fill.color = COLOR_ENEMY
	else:
		fill.color = COLOR_NORMAL
	_update_visibility()

func _update_visibility() -> void:
	match _health.health_bar_visibility:
		HealthComponent.HealthBarVisibility.ALWAYS_SHOW:
			visible = true
		HealthComponent.HealthBarVisibility.ALWAYS_HIDE:
			visible = false
		HealthComponent.HealthBarVisibility.HIDE_ON_FULL_HEALTH:
			visible = _health.current_hp < _health.max_hp

func _process(_delta: float) -> void:
	if _follow_target != null:
		global_position = _follow_target.global_position + _offset

func _on_damaged(_amount: int, remaining: int) -> void:
	_update_fill(remaining, _max_hp)
	_update_visibility()

func _on_died() -> void:
	visible = false

func _update_fill(current: int, max_hp: int) -> void:
	var percent: float = float(current) / float(max_hp)
	fill.size.x = max_width * percent
