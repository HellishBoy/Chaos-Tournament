# ItemDropManager.gd
extends Node
class_name ItemDropManager

@export var config: ItemDropConfig
@export var item_pickup_scene: PackedScene

var _active_counts: Dictionary = {}
var _drop_timer: float = 0.0
var _zones: Array = []

func _ready() -> void:
	add_to_group("item_drop_manager")
	await owner.ready
	_zones = get_tree().get_nodes_in_group("drop_zone")
	if _zones.is_empty():
		push_warning("ItemDropManager: no nodes in group 'drop_zone' found.")
	if config:
		for entry in config.entries:
			_active_counts[entry] = 0
			
	# Initialize altar item pool counts
	for zone in _zones:
		for entry in zone.altar_item_pool:
			if not _active_counts.has(entry):
				_active_counts[entry] = 0
	
	_drop_timer = config.drop_interval if config else 0.0
	_initialize_altars()

func _process(delta: float) -> void:
	if config == null:
		return
	_drop_timer -= delta
	if _drop_timer <= 0.0:
		_drop_timer = config.drop_interval
		_try_drop()

func _try_drop() -> void:
	var drop_count: int = randi_range(config.min_drops_per_interval, config.max_drops_per_interval)
	for i in drop_count:
		_do_single_drop()

func _do_single_drop() -> void:
	var eligible: Array = []
	for entry in config.entries:
		if entry.max_concurrent != -1 and _active_counts.get(entry, 0) >= entry.max_concurrent:
			continue
		if _get_valid_zones(entry).is_empty():
			continue
		eligible.append(entry)
		
	for zone in _zones:
		if not zone.has_available_disturbed_markers():
			continue
		for entry in zone.altar_item_pool:
			if entry.max_concurrent != -1 and _active_counts.get(entry, 0) >= entry.max_concurrent:
				continue
			if not eligible.has(entry):
				eligible.append(entry)
	
	if eligible.is_empty():
		return
		
	var entry: ItemDropEntry = _weighted_pick(eligible)
	if entry == null:
		return
		
	# Check if this entry belongs to an altar item pool
	for zone in _zones:
		var available: Array = zone.get_available_disturbed_markers()
		if zone.altar_item_pool.has(entry) and not available.is_empty():
			var marker: Marker2D = available[randi() % available.size()]
			zone.mark_occupied(marker)
			var pickup = _spawn_item(entry, marker.global_position)
			if pickup:
				pickup.tree_exited.connect(_on_altar_item_removed.bind(zone, marker))
			return
		
		
	var valid_zones := _get_valid_zones(entry)
	var zone = valid_zones[randi() % valid_zones.size()]
	var spawn_pos: Vector2 = zone.get_random_position()
	_spawn_item(entry, spawn_pos)

func _get_valid_zones(entry: ItemDropEntry) -> Array:
	var result: Array = []
	for zone in _zones:
		if entry.allowed_groups.has(zone.zone_group):
			result.append(zone)
	return result

func _initialize_altars() -> void:
	for zone in _zones:
		var markers: Array = zone.get_altar_markers()
		for i in min(markers.size(), zone.altar_items.size()):
			var marker: Marker2D = markers[i]
			var item_data: ItemData = zone.altar_items[i]
			_spawn_altar_item(item_data, marker.global_position, zone, marker)

func _spawn_altar_item(item_data: ItemData, pos: Vector2, zone: DropZone, marker: Marker2D) -> void:
	if item_pickup_scene == null:
		return
	var pickup = item_pickup_scene.instantiate()
	pickup.item_data = item_data
	pickup.disable_despawn = true
	pickup.set_position(pos)
	get_parent().add_child(pickup)
	zone.mark_occupied(marker)
	pickup.picked_up.connect(_on_altar_item_picked_up.bind(zone, marker))
	pickup.tree_exited.connect(_on_altar_item_removed.bind(zone, marker))

func _on_altar_item_picked_up(zone: DropZone, marker: Marker2D) -> void:
	zone.mark_disturbed(marker)

func _on_altar_item_removed(zone: DropZone, marker: Marker2D) -> void:
	zone.mark_unoccupied(marker)

func _weighted_pick(entries: Array) -> ItemDropEntry:
	var total_weight: float = 0.0
	for entry in entries:
		total_weight += entry.drop_weight
	var roll: float = randf() * total_weight
	var cumulative: float = 0.0
	for entry in entries:
		cumulative += entry.drop_weight
		if roll <= cumulative:
			return entry
	return entries[-1]

func _spawn_item(entry: ItemDropEntry, pos: Vector2) -> Node:
	if item_pickup_scene == null:
		push_warning("ItemDropManager: item_pickup_scene not assigned.")
		return
	var pickup = item_pickup_scene.instantiate()
	pickup.item_data = entry.item_data
	pickup.set_position(pos)
	get_parent().add_child(pickup)
	_active_counts[entry] += 1
	pickup.picked_up.connect(_on_item_picked_up.bind(entry))
	pickup.tree_exited.connect(_on_item_removed.bind(entry))
	return pickup


func _on_item_picked_up(entry: ItemDropEntry) -> void:
	_active_counts[entry] = max(_active_counts.get(entry, 0) - 1, 0)

func _on_item_removed(entry: ItemDropEntry) -> void:
	_active_counts[entry] = max(_active_counts.get(entry, 0) - 1, 0)
