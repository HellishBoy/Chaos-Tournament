# DropZone.gd
extends Polygon2D
class_name DropZone

enum ZoneType {
	POLYGON,
	MARKERS,
	ALTAR,
}

@export var zone_group: String = ""
@export var zone_type: ZoneType = ZoneType.POLYGON

# For ALTAR type only
@export var altar_weapons: Array[WeaponData] = []
@export var altar_weapon_pool: Array[WeaponDropEntry] = []
@export var altar_items: Array[ItemData] = []
@export var altar_item_pool: Array[ItemDropEntry] = []

# Runtime tracking for altar markers
var _disturbed_markers: Array[Marker2D] = []
var _occupied_markers: Array[Marker2D] = []

func _ready() -> void:
	add_to_group("drop_zone")
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
		ZoneType.ALTAR:
			return _random_disturbed_marker_position()
	return global_position

func mark_occupied(marker: Marker2D) -> void:
	if not _occupied_markers.has(marker):
		_occupied_markers.append(marker)

func mark_unoccupied(marker: Marker2D) -> void:
	_occupied_markers.erase(marker)

func get_available_disturbed_markers() -> Array:
	var result: Array = []
	for marker in _disturbed_markers:
		if not _occupied_markers.has(marker):
			result.append(marker)
	return result

func has_available_disturbed_markers() -> bool:
	return not get_available_disturbed_markers().is_empty()

func get_altar_markers() -> Array:
	var markers: Array = []
	for child in get_children():
		if child is Marker2D:
			markers.append(child)
	return markers

func mark_disturbed(marker: Marker2D) -> void:
	if not _disturbed_markers.has(marker):
		_disturbed_markers.append(marker)

func get_disturbed_markers() -> Array:
	return _disturbed_markers

func has_disturbed_markers() -> bool:
	return has_available_disturbed_markers()

func _random_disturbed_marker_position() -> Vector2:
	var available := get_available_disturbed_markers()
	if available.is_empty():
		push_warning(name + ": no available disturbed markers.")
		return global_position
	var marker: Marker2D = available[randi() % available.size()]
	return marker.global_position
	
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
