# ItemData.gd
# Resource defining an item's properties and effect.
extends Resource
class_name ItemData

enum ItemEffect {
	HEAL,
}

@export_group("Identity")
@export var item_name: String = "Health Pack"
@export var effect: ItemEffect = ItemEffect.HEAL
@export var effect_value: int = 50

@export_group("Drop")
@export var despawn_timer: float = 10.0  # -1 = never despawn

@export_group("Sprites")
@export var item_sprite: Texture2D
