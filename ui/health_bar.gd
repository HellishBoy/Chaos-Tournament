extends Node2D
class_name HealthBar

const COLOR_NORMAL: Color = Color(0.2, 0.8, 0.2, 1.0)
const COLOR_ENEMY: Color = Color(0.8, 0.0, 0.0, 1.0)
const COLOR_IMMORTAL: Color = Color(0.6, 0.0, 0.8, 1.0)

@export var bar_width: float = 32.0
@export var bar_height: float = 4.0
@export var border_thickness: float = 1.0

@onready var border: ColorRect = $Border
@onready var background: ColorRect = $Background
@onready var fill: ColorRect = $Fill

@export var vertical_offset: Vector2 = Vector2(0, -16)

var max_width: float = 0.0
var _follow_target: Node2D = null
var _health: HealthComponent = null
var _max_hp: int = 0

func _ready() -> void:
	top_level = true
	# Border — slightly larger than background
	border.size = Vector2(bar_width + border_thickness * 2, bar_height + border_thickness * 2)
	border.position = Vector2(-bar_width / 2.0 - border_thickness, -border_thickness)
	border.color = Color(0.0, 0.0, 0.0, 1.0)
	# Background
	background.size = Vector2(bar_width, bar_height)
	background.position = Vector2(-bar_width / 2.0, 0.0)
	# Fill
	fill.size = Vector2(bar_width, bar_height)
	fill.position = Vector2(-bar_width / 2.0, 0.0)
	max_width = bar_width

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
		var parent_scale := _follow_target.scale
		global_position = _follow_target.global_position + vertical_offset
		_apply_scale(parent_scale)

func _apply_scale(parent_scale: Vector2) -> void:
	var scaled_width: float = bar_width * parent_scale.x
	var scaled_height: float = bar_height * parent_scale.y
	# Border stays at fixed thickness
	border.size = Vector2(scaled_width + border_thickness * 2, scaled_height + border_thickness * 2)
	border.position = Vector2(-scaled_width / 2.0 - border_thickness, -border_thickness)
	# Background scales
	background.size = Vector2(scaled_width, scaled_height)
	background.position = Vector2(-scaled_width / 2.0, 0.0)
	# Fill scales but respects current HP percentage
	var percent: float = fill.size.x / max_width if max_width > 0 else 1.0
	fill.size = Vector2(scaled_width * percent, scaled_height)
	fill.position = Vector2(-scaled_width / 2.0, 0.0)
	max_width = scaled_width

func _on_damaged(_amount: int, remaining: int) -> void:
	_update_fill(remaining, _max_hp)
	_update_visibility()
	_flash()

func _on_died() -> void:
	visible = false
	
func _flash() -> void:
	var tween := create_tween()
	tween.tween_property(fill, "modulate", Color(2.0, 2.0, 2.0, 1.0), 0.05)
	tween.tween_property(fill, "modulate", Color.WHITE, 0.15)\
		.set_ease(Tween.EASE_OUT)\
		.set_trans(Tween.TRANS_QUINT)

func _update_fill(current: int, max_hp: int) -> void:
	var percent: float = float(current) / float(max_hp)
	fill.size.x = max_width * percent
