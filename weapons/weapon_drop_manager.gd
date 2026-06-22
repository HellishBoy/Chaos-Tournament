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
	_zones = get_tree().get_nodes_in_group("weapon_drop_zone")
	if _zones.is_empty():
		push_warning("WeaponDropManager: no nodes in group 'weapon_drop_zone' found.")
	# Initialize active counts
	if config:
		for entry in config.entries:
			_active_counts[entry] = 0
	_drop_timer = config.drop_interval if config else 0.0

func _process(delta: float) -> void:
	if config == null:
		return
	_drop_timer -= delta
	if _drop_timer <= 0.0:
		_drop_timer = config.drop_interval
		_try_drop()

func _try_drop() -> void:
	# Build list of eligible entries
	var eligible: Array = []
	for entry in config.entries:
		# Check max concurrent
		if entry.max_concurrent != -1 and _active_counts.get(entry, 0) >= entry.max_concurrent:
			continue
		# Check if any valid zone exists for this entry
		if _get_valid_zones(entry).is_empty():
			continue
		eligible.append(entry)
	if eligible.is_empty():
		return
	# Weighted random pick
	var entry: WeaponDropEntry = _weighted_pick(eligible)
	if entry == null:
		return
	# Pick a zone and position
	var valid_zones := _get_valid_zones(entry)
	var zone: WeaponDropZone = valid_zones[randi() % valid_zones.size()]
	var spawn_pos: Vector2 = zone.get_random_position()
	_spawn_weapon(entry, spawn_pos)

func _get_valid_zones(entry: WeaponDropEntry) -> Array:
	var result: Array = []
	for zone in _zones:
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

func _spawn_weapon(entry: WeaponDropEntry, pos: Vector2) -> void:
	if weapon_pickup_scene == null:
		push_warning("WeaponDropManager: weapon_pickup_scene not assigned.")
		return
	var pickup = weapon_pickup_scene.instantiate()
	pickup.weapon_data = entry.weapon_data
	pickup.set_position(pos)
	get_parent().add_child(pickup)
	# Increment count — weapon now exists in the world
	_active_counts[entry] += 1
	# Connect signals
	pickup.picked_up.connect(_on_weapon_picked_up.bind(entry))
	pickup.tree_exited.connect(_on_weapon_removed.bind(pickup, entry))

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

func register_tossed_weapon(pickup: Node) -> void:
	for entry in config.entries:
		if entry.weapon_data.weapon_name == pickup.weapon_data.weapon_name:
			pickup.tree_exited.connect(_on_tossed_weapon_removed.bind(entry))
			return

func _on_tossed_weapon_removed(entry: WeaponDropEntry) -> void:
	_active_counts[entry] = max(_active_counts.get(entry, 0) - 1, 0)
