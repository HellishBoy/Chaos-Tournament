# WeaponDropConfig.gd
# Stage-level configuration for the weapon drop system.
# Create one .tres per stage and assign it to WeaponDropManager.
extends Resource
class_name WeaponDropConfig

@export_group("Timing")
@export var drop_interval: float = 3.0

@export_group("Weapon Pool")
@export var entries: Array[WeaponDropEntry] = []
