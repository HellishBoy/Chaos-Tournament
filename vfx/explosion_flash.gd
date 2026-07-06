# ExplosionFlash.gd
# Attach to a plain Node2D. Draws an expanding, fading white circle,
# then frees itself. Purely visual — blast damage is handled separately
# by Grenade._apply_blast_damage().
extends Node2D
class_name ExplosionFlash

@export var flash_duration: float = 0.25
@export var flash_color: Color = Color.WHITE

var _max_radius: float = 48.0
var _progress: float = 0.0

func setup(radius: float) -> void:
	_max_radius = radius

func _process(delta: float) -> void:
	_progress += delta / flash_duration
	if _progress >= 1.0:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var current_radius: float = _max_radius * _progress
	var alpha: float = 1.0 - _progress
	draw_circle(Vector2.ZERO, current_radius, Color(flash_color.r, flash_color.g, flash_color.b, alpha))
