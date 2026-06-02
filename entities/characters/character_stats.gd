# CharacterStats.gd
# Assign one of these as a resource in the Inspector on any Character.
# Holds all tunable per-character values so nothing is hardcoded in scripts.
extends Resource
class_name CharacterStats

@export_group("Movement")
@export var move_speed: float = 100.0

@export_group("Combat")
@export var damage_multiplier: float = 1.0
@export var defense: int = 0

@export_group("Health")
@export var max_hp: int = 100

@export_group("Knockback")
# 0.0 = gets pushed full amount, 1.0 = immune to knockback
@export_range(0.0, 1.0) var knockback_resistance: float = 0.0
@export var knockback_immune: bool = false
