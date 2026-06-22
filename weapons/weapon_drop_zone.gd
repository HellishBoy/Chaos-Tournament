# WeaponDropZone.gd
extends Polygon2D
class_name WeaponDropZone

enum ZoneType {
	POLYGON,
	MARKERS,
}

@export var zone_group: String = ""
@export var zone_type: ZoneType = ZoneType.POLYGON

func _ready() -> void:
	add_to_group("weapon_drop_zone")
	# Make it semi-transparent so you can see it in game if needed
	modulate = Color(1.0, 1.0, 0.0, 0.3)
	# Hide in game, only useful in editor
	visible = false

func get_random_position() -> Vector2:
	match zone_type:
		ZoneType.POLYGON:
			return _random_point_in_polygon()
		ZoneType.MARKERS:
			return _random_marker_position()
	return global_position

func _random_point_in_polygon() -> Vector2:
	var poly := polygon
	if poly.size() < 3:
		push_warning(name + ": polygon has fewer than 3 points.")
		return global_position
	var min_x: float = poly[0].x
	var max_x: float = poly[0].x
	var min_y: float = poly[0].y
	var max_y: float = poly[0].y
	for point in poly:
		min_x = min(min_x, point.x)
		max_x = max(max_x, point.x)
		min_y = min(min_y, point.y)
		max_y = max(max_y, point.y)
	var attempts: int = 0
	while attempts < 100:
		var candidate := Vector2(
			randf_range(min_x, max_x),
			randf_range(min_y, max_y)
		)
		if Geometry2D.is_point_in_polygon(candidate, poly):
			return global_position + candidate
		attempts += 1
	push_warning(name + ": failed to find point in polygon after 100 attempts.")
	return global_position

func _random_marker_position() -> Vector2:
	var markers: Array = []
	for child in get_children():
		if child is Marker2D:
			markers.append(child)
	if markers.is_empty():
		push_warning(name + ": no Marker2D children found.")
		return global_position
	var marker: Marker2D = markers[randi() % markers.size()]
	return marker.global_position
