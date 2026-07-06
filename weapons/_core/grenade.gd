# Grenade.gd
# A thrown projectile that bounces off collisions and detonates either
# after a fixed fuse timer, or immediately on its first collision —
# whichever the weapon's grenade_detonation_mode specifies.
# On detonation, deals damage and applies the weapon's full set of hit
# effects (knockback, flinch, DOT, root, disarm, slow) to everything
# within blast radius, via the same CombatResolver melee/bullets use.
extends CharacterBody2D
class_name Grenade

@export var bounce_damping: float = 0.6

var weapon_data: WeaponData
var attacker: Node2D = null

var _fuse_timer: float = 0.0
var _can_impact_detonate: bool = false
var _has_detonated: bool = false

func setup(weapon: WeaponData, throw_attacker: Node2D, direction: Vector2, throw_speed: float) -> void:
	weapon_data = weapon
	attacker = throw_attacker
	_can_impact_detonate = weapon.can_impact_detonate
	_fuse_timer = weapon.grenade_fuse_time
	velocity = direction.normalized() * throw_speed
	rotation = direction.angle()
	if throw_attacker is CollisionObject2D:
		add_collision_exception_with(throw_attacker)

func _physics_process(delta: float) -> void:
	if _has_detonated:
		return

	_fuse_timer -= delta
	if _fuse_timer <= 0.0:
		_detonate()
		return

	var collision := move_and_collide(velocity * delta)
	if collision:
		if _can_impact_detonate:
			_detonate()
			return
		velocity = velocity.bounce(collision.get_normal()) * bounce_damping

func _detonate() -> void:
	if _has_detonated:
		return
	_has_detonated = true
	_apply_blast_damage()
	_spawn_flash_vfx()
	if weapon_data.can_linger:
		_spawn_lingering_hazard()
	queue_free()

func _spawn_lingering_hazard() -> void:
	var hazard := LingeringHazard.new()
	hazard.global_position = global_position
	get_parent().add_child(hazard)
	hazard.setup(weapon_data)

func _apply_blast_damage() -> void:
	var targets: Array = get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("enemy")
	for target in targets:
		if not is_instance_valid(target):
			continue
		if target.is_dead:
			continue
		var dist := global_position.distance_to(target.global_position)
		if dist > weapon_data.grenade_blast_radius:
			continue

		var direction: Vector2 = (target.global_position - global_position).normalized()
		if direction == Vector2.ZERO:
			direction = Vector2.RIGHT

		CombatResolver.apply_hit(
			target,
			weapon_data.damage_main,
			weapon_data.get_main_knockback_tier(),
			direction,
			weapon_data.get_main_flinch_tier(),
			weapon_data.get_dot_config(),
			weapon_data.get_root_config(),
			weapon_data.get_disarm_config(),
			weapon_data.get_slow_config()
		)

func _spawn_flash_vfx() -> void:
	var flash := ExplosionFlash.new()
	flash.global_position = global_position
	get_parent().add_child(flash)
	flash.setup(weapon_data.grenade_blast_radius)
