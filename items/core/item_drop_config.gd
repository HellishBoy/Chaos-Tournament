# ItemDropConfig.gd
extends Resource
class_name ItemDropConfig

@export_group("Timing")
@export var drop_interval: float = 5.0

@export_group("Drop Amount")
@export var min_drops_per_interval: int = 1
@export var max_drops_per_interval: int = 1

@export_group("Item Pool")
@export var entries: Array[ItemDropEntry] = []
