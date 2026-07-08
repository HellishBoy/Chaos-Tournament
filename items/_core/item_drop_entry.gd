# ItemDropEntry.gd
extends Resource
class_name ItemDropEntry

@export_group("Item")
@export var item_data: ItemData

@export_group("Drop")
@export var drop_weight: float = 1.0
@export var allowed_groups: Array[String] = []

@export_group("Limits")
@export var max_concurrent: int = 3
