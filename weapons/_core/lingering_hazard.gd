# LingeringHazard.gd
# Spawned by a Grenade on detonation when the weapon has can_linger
# enabled. Draws a low-alpha circle (borrowing grenade_blast_radius for
# size) and periodically re-applies the weapon's own DOT config to
# anyone standing inside, refreshing their DOT timer each scan — so
# staying in the hazard keeps you ticking, and it fades out over the
# DOT's own duration once you step out.
extends Node2D
class_name LingeringHazard

var weapon_data: WeaponData
var _radius: float = 48.0
var _duration_timer: float = 0.0
var _scan_timer: float = 0.0

func _ready() -> void:
	add_to_group("lingering_hazard")

func get_radius() -> float:
	return _radius

func setup(weapon: WeaponData) -> void:
	weapon_data = weapon
	_radius = weapon.grenade_blast_radius
	_duration_timer = weapon.linger_duration
	_scan_timer = 0.0
	queue_redraw()

func _process(delta: float) -> void:
	_duration_timer -= delta
	if _duration_timer <= 0.0:
		queue_free()
		return

	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = weapon_data.linger_scan_interval
		_apply_dot_to_targets()

func _apply_dot_to_targets() -> void:
	var dot_config := weapon_data.get_dot_config()
	if dot_config.get("tag", "") == "":
		return
	var targets: Array = get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("enemy")
	for target in targets:
		if not is_instance_valid(target):
			continue
		if target.is_dead:
			continue
		var dist := global_position.distance_to(target.global_position)
		if dist > _radius:
			continue
		if not target.has_node("StatusEffectComponent"):
			continue
		var status := target.get_node("StatusEffectComponent") as StatusEffectComponent
		status.apply_effect(dot_config["tag"], dot_config["duration"], dot_config["tick_interval"], dot_config["damage_percent"])

func _draw() -> void:
	draw_circle(Vector2.ZERO, _radius, Color(1.0, 1.0, 1.0, 0.15))
