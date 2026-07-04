# WeaponDropEntry.gd
# Per-weapon configuration for the drop system.
# Add these as entries in a WeaponDropConfig resource.
extends Resource
class_name WeaponDropEntry

@export_group("Weapon")
@export var weapon_data: WeaponData

@export_group("Drop")
@export var drop_weight: float = 1.0
@export var allowed_groups: Array[String] = []

@export_group("Limits")
# -1 = no limit
@export var max_concurrent: int = 3
