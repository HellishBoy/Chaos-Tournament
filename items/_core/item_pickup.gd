# ItemPickup.gd
# Sits on the ground and applies its effect to any character that walks over it.
extends Area2D
class_name ItemPickup

signal picked_up

@export var item_data: ItemData

var _was_picked_up: bool = false
var _despawn_tween: Tween = null

var disable_despawn: bool = false

func _ready() -> void:
	add_to_group("item_pickup")
	body_entered.connect(_on_body_entered)
	call_deferred("_apply_sprite")
	if item_data != null:
		item_data.validate_status_effect()
	if not disable_despawn and item_data != null and item_data.despawn_timer > 0.0:
		_start_despawn_timer(item_data.despawn_timer)

func _apply_sprite() -> void:
	if item_data == null:
		return
	var sprite := $Sprite2D
	if sprite and item_data.item_sprite:
		sprite.texture = item_data.item_sprite

func _on_body_entered(body: Node) -> void:
	if _was_picked_up:
		return
	if not body is Character:
		return
	_was_picked_up = true
	emit_signal("picked_up")
	_apply_effect(body)
	queue_free()

func _apply_effect(character: Character) -> void:
	match item_data.effect:
		ItemData.ItemEffect.HEAL:
			character.health.heal(item_data.effect_value)
		ItemData.ItemEffect.STATUS_EFFECT:
			character.status_effect_component.apply_effect(item_data.status_effect_name, item_data.status_effect_duration)

func _start_despawn_timer(duration: float) -> void:
	if _despawn_tween:
		_despawn_tween.kill()
	_despawn_tween = create_tween()
	_despawn_tween.tween_interval(duration)
	_despawn_tween.tween_callback(func():
		if is_instance_valid(self):
			queue_free()
	)
