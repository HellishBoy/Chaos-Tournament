# DodgeCharge.gd
# A single dodge charge circle — filled, empty, or partially filled.
extends Control
class_name DodgeCharge

const COLOR_FULL: Color = Color(0.2, 0.8, 1.0, 1.0)
const COLOR_EMPTY: Color = Color(0.15, 0.15, 0.15, 1.0)
const COLOR_RECOVERING: Color = Color(0.2, 0.8, 1.0, 0.5)
const COLOR_BORDER: Color = Color(0.0, 0.0, 0.0, 1.0)

var fill_percent: float = 1.0  # 0.0 = empty, 1.0 = full
var is_full: bool = true

func _draw() -> void:
	var center := size / 2.0
	var radius: float = min(size.x, size.y) / 2.0
	# Border
	draw_circle(center, radius, COLOR_BORDER)
	# Background
	draw_circle(center, radius - 1.5, COLOR_EMPTY)
	# Fill — only draw if recovering or full
	if is_full:
		draw_circle(center, radius - 1.5, COLOR_FULL)
	elif fill_percent > 0.0:
		# Partial fill using an arc
		draw_arc(center, radius - 3.5, -PI / 2.0, -PI / 2.0 + TAU * fill_percent, 32, COLOR_RECOVERING, 3.5)

func set_state(full: bool, percent: float = 1.0) -> void:
	is_full = full
	fill_percent = percent
	queue_redraw()
