# WeaponDropManager.gd
# Place as a child node in each stage scene.
# Assign a WeaponDropConfig resource in the Inspector.
extends Node
class_name WeaponDropManager

@export var config: WeaponDropConfig
@export var weapon_pickup_scene: PackedScene

# Tracks how many of each entry are currently active on the map
# Key: WeaponDropEntry, Value: int
var _active_counts: Dictionary = {}
var _drop_timer: float = 0.0
var _zones: Array = []

func _ready() -> void:
	add_to_group("weapon_drop_manager")
	# Wait for stage to finish loading
	await owner.ready
	# Collect all drop zones in the stage
	_zones = get_tree().get_nodes_in_group("drop_zone")
	if _zones.is_empty():
		push_warning("WeaponDropManager: no nodes in group 'drop_zone' found.")
	if config:
		for entry in config.entries:
			_active_counts[entry] = 0
		# Initialize altar pool counts
		for zone in _zones:
			if zone.zone_type == DropZone.ZoneType.ALTAR:
				for entry in zone.altar_weapon_pool:
					if not _active_counts.has(entry):
						_active_counts[entry] = 0
	_drop_timer = config.drop_interval if config else 0.0
	# Spawn altar weapons at stage start
	_initialize_altars()

func _initialize_altars() -> void:
	for zone in _zones:
		if zone.zone_type != DropZone.ZoneType.ALTAR:
			continue
		var markers: Array = zone.get_altar_markers()
		for i in min(markers.size(), zone.altar_weapons.size()):
			var marker: Marker2D = markers[i]
			var weapon_data: WeaponData = zone.altar_weapons[i]
			_spawn_altar_weapon(weapon_data, marker.global_position, zone, marker)

func _on_altar_weapon_removed(zone: DropZone, marker: Marker2D) -> void:
	zone.mark_unoccupied(marker)

func _spawn_altar_weapon(weapon_data: WeaponData, pos: Vector2, zone: DropZone, marker: Marker2D) -> void:
	if weapon_pickup_scene == null:
		return
	var pickup = weapon_pickup_scene.instantiate()
	pickup.weapon_data = weapon_data
	pickup.disable_despawn = true  # altar weapons never auto-despawn
	pickup.set_position(pos)
	get_parent().add_child(pickup)
	
	# Mark this marker as occupied
	zone.mark_occupied(marker)
	
	# No despawn timer for altar weapons
	pickup.picked_up.connect(_on_altar_weapon_picked_up.bind(zone, marker))
	pickup.tree_exited.connect(_on_altar_weapon_removed.bind(zone, marker))
	
func _on_altar_weapon_picked_up(zone: DropZone, marker: Marker2D) -> void:
	zone.mark_disturbed(marker)

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
	# Build list of eligible entries
	var eligible: Array = []
	for entry in config.entries:
		if entry.max_concurrent != -1 and _active_counts.get(entry, 0) >= entry.max_concurrent:
			continue
		if _get_valid_zones(entry).is_empty():
			continue
		eligible.append(entry)

	# Altar pool drops — only on available disturbed markers
	for zone in _zones:
		if zone.zone_type != DropZone.ZoneType.ALTAR:
			continue
		if not zone.has_available_disturbed_markers():
			continue
		for entry in zone.altar_weapon_pool:
			if entry.max_concurrent != -1 and _active_counts.get(entry, 0) >= entry.max_concurrent:
				continue
			if not eligible.has(entry):
				eligible.append(entry)

	if eligible.is_empty():
		return

	var entry: WeaponDropEntry = _weighted_pick(eligible)
	if entry == null:
		return

	# Check if this entry belongs to an altar pool
	for zone in _zones:
		if zone.zone_type == DropZone.ZoneType.ALTAR and zone.altar_weapon_pool.has(entry):
			var available: Array = zone.get_available_disturbed_markers()
			if available.is_empty():
				return
			var marker: Marker2D = available[randi() % available.size()]
			zone.mark_occupied(marker)
			var pickup = _spawn_weapon(entry, marker.global_position)
			if pickup:
				pickup.tree_exited.connect(_on_altar_weapon_removed.bind(zone, marker))
			return

	# Normal drop
	var valid_zones := _get_valid_zones(entry)
	var zone: DropZone = valid_zones[randi() % valid_zones.size()]
	var spawn_pos: Vector2 = zone.get_random_position()
	_spawn_weapon(entry, spawn_pos)

func _get_valid_zones(entry: WeaponDropEntry) -> Array:
	var result: Array = []
	for zone in _zones:
		if zone.zone_type == DropZone.ZoneType.ALTAR:
			continue  # altar zones handled separately
		if entry.allowed_groups.has(zone.zone_group):
			result.append(zone)
	return result

func _weighted_pick(entries: Array) -> WeaponDropEntry:
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

func _spawn_weapon(entry: WeaponDropEntry, pos: Vector2) -> Node:
	if weapon_pickup_scene == null:
		push_warning("WeaponDropManager: weapon_pickup_scene not assigned.")
		return null
	var pickup = weapon_pickup_scene.instantiate()
	pickup.weapon_data = entry.weapon_data
	pickup.set_position(pos)
	get_parent().add_child(pickup)
	
	# Increment count — weapon now exists in the world
	_active_counts[entry] += 1
	
	# Connect signals
	pickup.picked_up.connect(_on_weapon_picked_up.bind(entry))
	pickup.tree_exited.connect(_on_weapon_removed.bind(pickup, entry))
	if entry.weapon_data.despawn_timer > 0.0:
		pickup.start_despawn_timer(entry.weapon_data.despawn_timer)
	return pickup

func _on_weapon_picked_up(_entry: WeaponDropEntry) -> void:
	# Weapon is now in someone's hands — count stays the same
	# Timer is handled by the pickup node itself
	pass

func _on_weapon_removed(pickup: Node, entry: WeaponDropEntry) -> void:
	if pickup._was_picked_up:
		return
	_active_counts[entry] = max(_active_counts.get(entry, 0) - 1, 0)
	
func register_weapon_broken(weapon_data: WeaponData) -> void:
	# Call this from character.gd's break_weapon() for manager-tracked weapons
	# Find which entry this weapon belongs to
	for entry in config.entries:
		if entry.weapon_data.weapon_name == weapon_data.weapon_name:
			
			# Connect tree_exited so we can decrement when it despawns
			_active_counts[entry] = max(_active_counts.get(entry, 0) - 1, 0)
			return
			
	for zone in _zones:
		if zone.zone_type != DropZone.ZoneType.ALTAR:
			continue
		for entry in zone.altar_weapon_pool:
			if entry.weapon_data.weapon_name == weapon_data.weapon_name:
				_active_counts[entry] = max(_active_counts.get(entry, 0) - 1, 0)
				return

func register_tossed_weapon(pickup: Node) -> void:
	for entry in config.entries:
		if entry.weapon_data.weapon_name == pickup.weapon_data.weapon_name:
			pickup.tree_exited.connect(_on_tossed_weapon_removed.bind(entry))
			return
	for zone in _zones:
		if zone.zone_type != DropZone.ZoneType.ALTAR:
			continue
		for entry in zone.altar_weapon_pool:
			if entry.weapon_data.weapon_name == pickup.weapon_data.weapon_name:
				pickup.tree_exited.connect(_on_tossed_weapon_removed.bind(entry))
				return

func _on_tossed_weapon_removed(entry: WeaponDropEntry) -> void:
	_active_counts[entry] = max(_active_counts.get(entry, 0) - 1, 0)
