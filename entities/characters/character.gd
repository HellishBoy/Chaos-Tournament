# Character.gd
# Base class for any entity that can hold weapons, attack, and take damage.
# Player and Enemy both extend this — do not use directly as a scene root.
extends CharacterBody2D
class_name Character

# ── Exports ──────────────────────────────────────────────────────

@export var stats: CharacterStats
@export var current_weapon: WeaponData
@export var fists: WeaponData
@export var weapon_pickup_scene: PackedScene

@export_group("Health Bar")
@export var health_bar_scene: PackedScene
@export var health_bar_width: float = 20.0
@export var health_bar_height: float = 2.0
@export var health_bar_offset: Vector2 = Vector2(0, -16)

@export_group("Combat")
@export var combo_window: float = 0.4

# ── Node References ──────────────────────────────────────────────

@onready var anim_upper: AnimationPlayer = $AnimationPlayerUpper
@onready var anim_lower: AnimationPlayer = $AnimationPlayerLower

@onready var weapon_right: Sprite2D = $Body/Hands/HandRight/WeaponRight
@onready var weapon_left: Sprite2D  = $Body/Hands/HandLeft/WeaponLeft

@onready var muzzle_right: Marker2D = $Body/Hands/HandRight/Muzzle_R
@onready var muzzle_left: Marker2D  = $Body/Hands/HandLeft/Muzzle_L

@onready var hitbox_right: Area2D = $Body/Hands/HandRight/HitboxRight
@onready var hitbox_left: Area2D  = $Body/Hands/HandLeft/HitboxLeft

@onready var health: HealthComponent             = $HealthComponent
@onready var hurtbox: Area2D                     = $Hurtbox
@onready var knockback_component: KnockbackComponent = $KnockbackComponent

# ── State ────────────────────────────────────────────────────────

var last_direction: Vector2 = Vector2.UP

var is_tossing: bool = false
var is_main_attacking: bool = false
var is_alt_attacking: bool = false

var main_combo_index: int = 0
var main_combo_timer: float = 0.0
var alt_combo_index: int = 0
var alt_combo_timer: float = 0.0
var main_attack_held: bool = false
var alt_attack_held: bool = false

var _buffered_attack: String = ""

# ── Ready ────────────────────────────────────────────────────────

func _ready() -> void:
	assert(fists != null, str(name) + ": fists WeaponData must be assigned in the Inspector.")
	assert(stats != null, str(name) + ": CharacterStats must be assigned in the Inspector.")

	# Apply stats to health component
	health.max_hp = stats.max_hp
	health.current_hp = stats.max_hp

	anim_upper.animation_finished.connect(_on_animation_finished)
	hurtbox.area_entered.connect(_on_hurtbox_area_entered)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)

	_update_weapon_visuals()
	
	call_deferred("_setup_health_bar")

func _setup_health_bar() -> void:
	if health_bar_scene != null:
		var bar := health_bar_scene.instantiate() as HealthBar
		get_parent().add_child(bar)
		bar.vertical_offset = health_bar_offset
		bar.bar_width = health_bar_width
		bar.bar_height = health_bar_height
		bar.setup(health, self)

# ── Active Weapon ────────────────────────────────────────────────

func get_active_weapon() -> WeaponData:
	return current_weapon if current_weapon else fists

# ── Pickup ───────────────────────────────────────────────────────

func try_pickup(pickup_node: Node) -> void:
	if current_weapon != null:
		return
	var data: WeaponData = pickup_node.weapon_data
	pickup_node.queue_free()
	current_weapon = data
	# Only initialize durability if not already set
	if data.durability_current == -1:
		match data.durability:
			"low":    data.durability_current = 3
			"medium": data.durability_current = 5
			"high":   data.durability_current = 8
	_update_weapon_visuals()
	var hud := get_tree().get_first_node_in_group("hud") as HUD
	if hud:
		hud.refresh()

# ── Toss ─────────────────────────────────────────────────────────

func _do_toss() -> void:
	if current_weapon == null or not current_weapon.can_toss:
		return
	var data := current_weapon
	current_weapon = null
	_update_weapon_visuals()
	if weapon_pickup_scene == null:
		push_warning(name + ": weapon_pickup_scene not assigned in Inspector.")
		return
	var toss_dir := Vector2.RIGHT.rotated(rotation)
	var pickup = weapon_pickup_scene.instantiate()
	pickup.weapon_data = data
	pickup._was_tossed = true
	pickup.position = global_position + toss_dir * 10.0
	get_parent().add_child(pickup)
	pickup.setup_toss(global_position, toss_dir)
		# Refresh HUD after toss
	var hud := get_tree().get_first_node_in_group("hud") as HUD
	if hud:
		hud.refresh()

# ── Weapon Visuals ───────────────────────────────────────────────

func _update_weapon_visuals() -> void:
	if current_weapon == null:
		weapon_right.texture = null
		weapon_left.texture  = null
		weapon_right.visible = false
		weapon_left.visible  = false
	else:
		weapon_right.texture = current_weapon.weapon_sprite_right
		weapon_left.texture  = current_weapon.weapon_sprite_left
		weapon_right.visible = current_weapon.weapon_sprite_right != null
		weapon_left.visible  = current_weapon.weapon_sprite_left  != null

# ── Animation Helpers ────────────────────────────────────────────

func _snap_to_idle() -> void:
	anim_upper.speed_scale = 1.0
	var idle := get_active_weapon().idle_animation
	if idle != "":
		anim_upper.play(idle)
	else:
		anim_upper.stop()

func _reset_attacks() -> void:
	is_main_attacking = false
	is_alt_attacking = false
	main_combo_index = 0
	main_combo_timer = 0.0
	alt_combo_index = 0
	alt_combo_timer = 0.0
	_buffered_attack = ""

func _cancel_into_idle() -> void:
	_reset_attacks()
	anim_upper.speed_scale = 1.0
	anim_upper.stop()
	anim_upper.play("RESET")
	anim_upper.advance(0.0)
	anim_upper.stop()
	var idle := get_active_weapon().idle_animation
	if idle != "":
		anim_upper.play(idle)

# ── Hurtbox — receives incoming damage ───────────────────────────

# Fixed version: applies damage and knockback to SELF, not the attacker
func _on_hurtbox_area_entered(area: Area2D) -> void:
	if not area is Hitbox:
		return
	health.take_damage(area.damage)
	if area.attacker != null:
		var direction: Vector2
		if area.knockback_facing:
			direction = Vector2.RIGHT.rotated(area.attacker.rotation)
		else:
			direction = (global_position - area.attacker.global_position).normalized()
		knockback_component.apply(area.knockback_tier, direction)

# ── Health Callbacks — override in subclass for visual feedback ──

func _on_damaged(_amount: int, _remaining: int) -> void:
	pass

func _on_died() -> void:
	pass

# ── Animation Finished ───────────────────────────────────────────

func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == "uni_toss":
		is_tossing = false
		if main_attack_held:
			_play_main_attack()
		elif alt_attack_held:
			_play_alt_attack()
		else:
			_snap_to_idle()
		return

	if is_main_attacking:
		is_main_attacking = false
		if _buffered_attack == "alt" and get_active_weapon().alt_attack_animations.size() > 0:
			_buffered_attack = ""
			_play_alt_attack()
		elif main_attack_held and get_active_weapon().main_attack_animations.size() > 0:
			_play_main_attack()
		else:
			main_combo_timer = combo_window
			_snap_to_idle()
		return

	if is_alt_attacking:
		is_alt_attacking = false
		if _buffered_attack == "main" and get_active_weapon().main_attack_animations.size() > 0:
			_buffered_attack = ""
			_play_main_attack()
		elif alt_attack_held and get_active_weapon().alt_attack_animations.size() > 0:
			_play_alt_attack()
		else:
			alt_combo_timer = combo_window
			_snap_to_idle()

# ── Attack Helpers ───────────────────────────────────────────────

func _setup_hitboxes_main() -> void:
	var weapon := get_active_weapon()
	hitbox_right.damage           = weapon.damage_main
	hitbox_left.damage            = weapon.damage_main
	hitbox_right.knockback_tier   = weapon.main_knockback
	hitbox_left.knockback_tier    = weapon.main_knockback
	hitbox_right.knockback_facing = weapon.knockback_main_facing
	hitbox_left.knockback_facing  = weapon.knockback_main_facing
	hitbox_right.attacker         = self
	hitbox_left.attacker          = self

func _setup_hitboxes_alt() -> void:
	var weapon := get_active_weapon()
	hitbox_right.damage           = weapon.damage_alt
	hitbox_left.damage            = weapon.damage_alt
	hitbox_right.knockback_tier   = weapon.alt_knockback
	hitbox_left.knockback_tier    = weapon.alt_knockback
	hitbox_right.knockback_facing = weapon.knockback_alt_facing
	hitbox_left.knockback_facing  = weapon.knockback_alt_facing
	hitbox_right.attacker         = self
	hitbox_left.attacker          = self

func _play_main_attack() -> void:
	var anims := get_active_weapon().main_attack_animations
	if anims.is_empty():
		return
	main_combo_index = main_combo_index % anims.size()
	is_main_attacking = true
	is_alt_attacking = false
	main_combo_timer = 0.0
	anim_upper.speed_scale = get_active_weapon().main_attack_speed
	_setup_hitboxes_main()
	anim_upper.play(anims[main_combo_index])
	main_combo_index += 1

func _play_alt_attack() -> void:
	var anims := get_active_weapon().alt_attack_animations
	if anims.is_empty():
		return
	alt_combo_index = alt_combo_index % anims.size()
	is_alt_attacking = true
	is_main_attacking = false
	alt_combo_timer = 0.0
	anim_upper.speed_scale = get_active_weapon().alt_attack_speed
	_setup_hitboxes_alt()
	anim_upper.play(anims[alt_combo_index])
	alt_combo_index += 1

# ── State Helpers ────────────────────────────────────────────────

func _is_attacking() -> bool:
	return is_main_attacking or is_alt_attacking

# ── Movement (shared base) ───────────────────────────────────────

# Applies velocity with knockback factored in and calls move_and_slide.
# Pass in the desired movement vector (already scaled by speed/penalty).
func _apply_movement(desired_velocity: Vector2) -> void:
	if knockback_component.is_active() and not stats.knockback_immune:
		var tier := knockback_component.get_tier()
		var dir := knockback_component.get_direction()
		var push_speed: float = KnockbackComponent.TIER_SPEEDS.get(tier, 0.0)
		var mult := knockback_component.get_speed_multiplier()
		var resistance := 1.0 - stats.knockback_resistance
		velocity = desired_velocity + dir * push_speed * mult * resistance
	else:
		velocity = desired_velocity
	move_and_slide()

# ── Bullets ──────────────────────────────────────────────────────

func spawn_bullet_right() -> void:
	spawn_bullet(muzzle_right)

func spawn_bullet_left() -> void:
	spawn_bullet(muzzle_left)

func spawn_bullet(muzzle: Marker2D) -> void:
	var weapon := get_active_weapon()
	if weapon.bullet_scene == null:
		push_warning("spawn_bullet: no bullet_scene assigned on %s" % weapon.weapon_name)
		return
	var bullet = weapon.bullet_scene.instantiate()
	bullet.position = muzzle.global_position
	get_parent().add_child(bullet)
	bullet.setup(
		Vector2.RIGHT.rotated(rotation),
		weapon.bullet_speed,
		weapon.bullet_range,
		weapon.bullet_pierce,
		weapon.damage_main,
		weapon.main_knockback
	)
	
	# Decrement ammo
	if weapon.ammo > 0:
		weapon.ammo -= 1
		var hud := get_tree().get_first_node_in_group("hud") as HUD
		if hud:
			hud.refresh()
		if weapon.ammo == 0:
			break_weapon()

# ── Weapon break ──────────────────────────────────────────────────────

func break_weapon() -> void:
	current_weapon = null
	_update_weapon_visuals()
	_cancel_into_idle()
	var hud := get_tree().get_first_node_in_group("hud") as HUD
	if hud:
		hud.refresh()
