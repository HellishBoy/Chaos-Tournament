# Character.gd
# Base class for any entity that can hold weapons, attack, and take damage.
# Player and Enemy both extend this — do not use directly as a scene root.
extends CharacterBody2D
class_name Character

# ── Exports ──────────────────────────────────────────────────────

@export var collision_layer_index: int = 0

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

@onready var health: HealthComponent = $HealthComponent
@onready var hurtbox: Area2D = $Hurtbox
@onready var impact_component: ImpactComponent = $ImpactComponent
@onready var status_effect_component: StatusEffectComponent = $StatusEffectComponent

# ── State ────────────────────────────────────────────────────────

var last_direction: Vector2 = Vector2.UP

var is_dead: bool = false

var is_dodging: bool = false
var dodge_traveled: float = 0.0
var dodge_direction: Vector2 = Vector2.ZERO
var cooldown_timer: float = 0.0
var _stamina: float = 0.0

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

var is_throwing_grenade: bool = false
var grenade_charge_time: float = 0.0
var grenade_charge_held: bool = false
var _grenade_stance_reached: bool = false
var _grenade_thrown: bool = false
var _grenade_throw_speed: float = 0.0
var _grenade_weapon: WeaponData = null

# ── Ready ────────────────────────────────────────────────────────

func _ready() -> void:
	assert(fists != null, str(name) + ": fists WeaponData must be assigned in the Inspector.")
	assert(stats != null, str(name) + ": CharacterStats must be assigned in the Inspector.")

	stats = stats.duplicate()
	fists = fists.duplicate()
	if current_weapon:
		current_weapon = current_weapon.duplicate()

	# Apply stats to health component
	health.max_hp = stats.max_hp
	health.current_hp = stats.max_hp

	anim_upper.animation_finished.connect(_on_animation_finished)
	hurtbox.area_entered.connect(_on_hurtbox_area_entered)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	status_effect_component.effect_ticked.connect(_on_status_effect_ticked)
	status_effect_component.effect_applied.connect(_on_status_effect_applied)

	_stamina = stats.stamina_max
	set_invincible(false)

	fists.validate_impact_flags()
	fists.validate_dot_tag()
	fists.validate_linger()
	_initialize_durability(fists)
	if current_weapon:
		current_weapon.validate_impact_flags()
		current_weapon.validate_dot_tag()
		current_weapon.validate_linger()
		_initialize_durability(current_weapon)

	_update_weapon_visuals()
	call_deferred("_setup_health_bar")
	
func _on_status_effect_ticked(_effect_name: String, damage_percent: float) -> void:
	var tick_damage: int = int(round(health.max_hp * damage_percent))
	health.take_damage(tick_damage)

func _setup_health_bar() -> void:
	if health_bar_scene != null:
		var bar := health_bar_scene.instantiate() as HealthBar
		get_parent().add_child(bar)
		bar.vertical_offset = health_bar_offset
		bar.bar_width = health_bar_width
		bar.bar_height = health_bar_height
		bar.setup(health, self)

func _apply_death_state() -> void:
	is_dead = true
	
	current_weapon = null
	_update_weapon_visuals()
	status_effect_component.clear_all()

	# Stop all animation
	anim_lower.stop()
	anim_upper.stop()
	
	if collision_layer_index > 0:
		set_collision_layer_value(collision_layer_index, false)
	$Body.modulate = Color(0.3, 0.3, 0.3, 1.0)

func _apply_alive_state() -> void:
	is_dead = false
	if collision_layer_index > 0:
		set_collision_layer_value(collision_layer_index, true)
	$Body.modulate = Color.WHITE

# ── Active Weapon ────────────────────────────────────────────────

func get_active_weapon() -> WeaponData:
	return current_weapon if current_weapon else fists

# ── Durability ───────────────────────────────────────────────────
# Converts a durability tier into an actual usage count, but only if
# it hasn't been initialized yet (durability_current == -1 is the
# "uninitialized" sentinel). Called both when a weapon is picked up
# AND at spawn time, so pre-assigned weapons (set directly in the
# Inspector, never passing through try_pickup) don't end up stuck
# at -1 — which hitbox.gd reads as "never breaks."
func _initialize_durability(weapon: WeaponData) -> void:
	if weapon.durability_current == -1:
		match weapon.durability:
			"low":    weapon.durability_current = 3
			"medium": weapon.durability_current = 5
			"high":   weapon.durability_current = 8

# ── Pickup ───────────────────────────────────────────────────────

func try_pickup(pickup_node: Node) -> void:
	if current_weapon != null:
		return
	if is_dead:
		return
	var data: WeaponData = pickup_node.weapon_data.duplicate()
	pickup_node.queue_free()
	current_weapon = data
	current_weapon.validate_impact_flags()
	current_weapon.validate_dot_tag()
	current_weapon.validate_linger()
	_initialize_durability(data)
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
	
	# Notify drop manager about the tossed weapon
	var manager := get_tree().get_first_node_in_group("weapon_drop_manager") as WeaponDropManager
	if manager:
		manager.register_tossed_weapon(pickup)
		
	# Refresh HUD after toss
	var hud := get_tree().get_first_node_in_group("hud") as HUD
	if hud:
		hud.refresh()

func _toss_weapon_data(data: WeaponData) -> void:
	if data == null or not data.can_toss:
		return
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
	var manager := get_tree().get_first_node_in_group("weapon_drop_manager") as WeaponDropManager
	if manager:
		manager.register_tossed_weapon(pickup)
	var hud := get_tree().get_first_node_in_group("hud") as HUD
	if hud:
		hud.refresh()
		
# ── Grenade Throw ──────────────────────────────────────────────

func _start_grenade_throw() -> void:
	if get_active_weapon().weapon_category != "grenade":
		return
	if status_effect_component.has_effect("disarm"):
		return
	_cancel_into_idle()
	is_throwing_grenade = true
	_grenade_stance_reached = false
	_grenade_thrown = false
	grenade_charge_time = 0.0
	grenade_charge_held = true
	anim_upper.play("attack_hand_throw")

# Called via a Call Method track in the throw animation, at the frame
# representing the "throwing stance" pose (frame 4 in your 24-frame anim).
func _on_grenade_stance_reached() -> void:
	_grenade_stance_reached = true
	var weapon := get_active_weapon()
	if not weapon.main_attack_charge:
		# No meter on this weapon — always releases immediately at the
		# stance pose, regardless of hold duration.
		_release_grenade_throw()
		return
	if grenade_charge_held:
		anim_upper.speed_scale = 0.0  # freeze here while charging
	else:
		_release_grenade_throw()  # quick tap — throw at minimum charge

func _tick_grenade_charge(delta: float) -> void:
	if not is_throwing_grenade or not _grenade_stance_reached or _grenade_thrown:
		return
	var weapon := get_active_weapon()
	if not weapon.main_attack_charge:
		return
	if grenade_charge_held:
		grenade_charge_time = min(grenade_charge_time + delta, weapon.main_charge_time)

func _release_grenade_throw() -> void:
	if not is_throwing_grenade or _grenade_thrown:
		return
	_grenade_thrown = true
	var weapon := get_active_weapon()
	var charge_percent := 0.0
	if weapon.main_attack_charge and weapon.main_charge_time > 0.0:
		charge_percent = clamp(grenade_charge_time / weapon.main_charge_time, 0.0, 1.0)
	_grenade_throw_speed = lerp(weapon.grenade_throw_speed_min, weapon.grenade_throw_speed_max, charge_percent) if weapon.main_attack_charge else weapon.grenade_throw_speed_max
	_grenade_weapon = weapon
	anim_upper.speed_scale = 1.0
	grenade_charge_held = false

# Called via a SECOND Call Method track in the throw animation, at
# frame 12 — the point where the hand actually releases the grenade.
# Kept separate from _release_grenade_throw() so the charge DECISION
# and the visual spawn moment can land at different points in time.
func _on_grenade_release_frame() -> void:
	if _grenade_weapon == null:
		return
	_spawn_grenade(_grenade_weapon, _grenade_throw_speed)
	_grenade_weapon = null

func _spawn_grenade(weapon: WeaponData, throw_speed: float) -> void:
	if weapon.grenade_scene == null:
		push_warning(name + ": grenade_scene not assigned on weapon " + weapon.weapon_name)
		return
	var grenade := weapon.grenade_scene.instantiate()
	var direction := Vector2.RIGHT.rotated(rotation)
	grenade.global_position = global_position + direction * 18.0
	get_parent().add_child(grenade)
	grenade.setup(weapon, self, direction, throw_speed)

	if weapon.quantity > 0:
		weapon.quantity -= 1
		var hud := get_tree().get_first_node_in_group("hud") as HUD
		if hud:
			hud.refresh()
		if weapon.quantity == 0:
			break_weapon()

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
	_cancel_grenade_throw()
	anim_upper.speed_scale = 1.0
	anim_upper.stop()
	anim_upper.play("RESET")
	anim_upper.advance(0.0)
	anim_upper.stop()
	var idle := get_active_weapon().idle_animation
	if idle != "":
		anim_upper.play(idle)

func _cancel_grenade_throw() -> void:
	is_throwing_grenade = false
	_grenade_stance_reached = false
	_grenade_thrown = false
	grenade_charge_held = false
	grenade_charge_time = 0.0
	_grenade_weapon = null

# ── Hurtbox — receives incoming damage ───────────────────────────

# Fixed version: applies damage and knockback to SELF, not the attacker
func _on_hurtbox_area_entered(area: Area2D) -> void:
	if not area is Hitbox:
		return
	health.take_damage(area.damage)
	if area.attacker != null and not status_effect_component.has_effect("steadfast"):
		if area.knockback_tier != "none":
			var direction: Vector2
			if area.knockback_facing:
				direction = Vector2.RIGHT.rotated(area.attacker.rotation)
			else:
				direction = (global_position - area.attacker.global_position).normalized()
			impact_component.apply_knockback(area.knockback_tier, direction)
		elif area.flinch_tier != "none":
			impact_component.apply_flinch(area.flinch_tier, stats.flinch_resistance)

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

	if anim_name == "attack_hand_throw":
		_cancel_grenade_throw()
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
	hitbox_right.knockback_tier   = weapon.get_main_knockback_tier()
	hitbox_left.knockback_tier    = weapon.get_main_knockback_tier()
	hitbox_right.flinch_tier      = weapon.get_main_flinch_tier()
	hitbox_left.flinch_tier       = weapon.get_main_flinch_tier()
	hitbox_right.knockback_facing = weapon.knockback_main_facing
	hitbox_left.knockback_facing  = weapon.knockback_main_facing
	_apply_dot_config(weapon)
	_apply_root_config(weapon)
	_apply_disarm_config(weapon)
	_apply_slow_config(weapon)
	hitbox_right.attacker         = self
	hitbox_left.attacker          = self

func _setup_hitboxes_alt() -> void:
	var weapon := get_active_weapon()
	hitbox_right.damage           = weapon.damage_alt
	hitbox_left.damage            = weapon.damage_alt
	hitbox_right.knockback_tier   = weapon.get_alt_knockback_tier()
	hitbox_left.knockback_tier    = weapon.get_alt_knockback_tier()
	hitbox_right.flinch_tier      = weapon.get_alt_flinch_tier()
	hitbox_left.flinch_tier       = weapon.get_alt_flinch_tier()
	hitbox_right.knockback_facing = weapon.knockback_alt_facing
	hitbox_left.knockback_facing  = weapon.knockback_alt_facing
	_apply_dot_config(weapon)
	_apply_root_config(weapon)
	_apply_disarm_config(weapon)
	_apply_slow_config(weapon)
	hitbox_right.attacker         = self
	hitbox_left.attacker          = self
	
func _apply_dot_config(weapon: WeaponData) -> void:
	var dot_config := weapon.get_dot_config()
	hitbox_right.dot_tag             = dot_config["tag"]
	hitbox_right.dot_duration        = dot_config["duration"]
	hitbox_right.dot_tick_interval   = dot_config["tick_interval"]
	hitbox_right.dot_damage_percent  = dot_config["damage_percent"]
	hitbox_right.dot_chance          = dot_config["chance"]
	hitbox_left.dot_tag              = dot_config["tag"]
	hitbox_left.dot_duration         = dot_config["duration"]
	hitbox_left.dot_tick_interval    = dot_config["tick_interval"]
	hitbox_left.dot_damage_percent   = dot_config["damage_percent"]
	hitbox_left.dot_chance           = dot_config["chance"]

func _apply_root_config(weapon: WeaponData) -> void:
	var root_config := weapon.get_root_config()
	hitbox_right.root_type     = root_config["type"]
	hitbox_right.root_tag      = root_config["tag"]
	hitbox_right.root_duration = root_config["duration"]
	hitbox_right.root_chance   = root_config["chance"]
	hitbox_left.root_type       = root_config["type"]
	hitbox_left.root_tag        = root_config["tag"]
	hitbox_left.root_duration   = root_config["duration"]
	hitbox_left.root_chance     = root_config["chance"]

func _apply_disarm_config(weapon: WeaponData) -> void:
	var disarm_config := weapon.get_disarm_config()
	hitbox_right.disarm_tag      = disarm_config["tag"]
	hitbox_right.disarm_duration = disarm_config["duration"]
	hitbox_right.disarm_chance   = disarm_config["chance"]
	hitbox_left.disarm_tag       = disarm_config["tag"]
	hitbox_left.disarm_duration  = disarm_config["duration"]
	hitbox_left.disarm_chance    = disarm_config["chance"]

func _apply_slow_config(weapon: WeaponData) -> void:
	var slow_config := weapon.get_slow_config()
	hitbox_right.slow_tag      = slow_config["tag"]
	hitbox_right.slow_duration = slow_config["duration"]
	hitbox_right.slow_percent  = slow_config["percent"]
	hitbox_right.slow_chance   = slow_config["chance"]
	hitbox_left.slow_tag       = slow_config["tag"]
	hitbox_left.slow_duration  = slow_config["duration"]
	hitbox_left.slow_percent   = slow_config["percent"]
	hitbox_left.slow_chance    = slow_config["chance"]

func _play_main_attack() -> void:
	var anims := get_active_weapon().main_attack_animations
	if anims.is_empty():
		return
	if status_effect_component.has_effect("disarm"):
		return
	main_combo_index = main_combo_index % anims.size()
	is_main_attacking = true
	is_alt_attacking = false
	main_combo_timer = 0.0
	anim_upper.speed_scale = get_active_weapon().main_attack_speed * stats.attack_speed_multiplier
	_setup_hitboxes_main()
	_apply_recoil(get_active_weapon().get_main_recoil_tier())
	anim_upper.play(anims[main_combo_index])
	main_combo_index += 1

func _play_alt_attack() -> void:
	var anims := get_active_weapon().alt_attack_animations
	if anims.is_empty():
		return
	if status_effect_component.has_effect("disarm"):
		return
	alt_combo_index = alt_combo_index % anims.size()
	is_alt_attacking = true
	is_main_attacking = false
	alt_combo_timer = 0.0
	anim_upper.speed_scale = get_active_weapon().alt_attack_speed * stats.attack_speed_multiplier
	_setup_hitboxes_alt()
	_apply_recoil(get_active_weapon().get_alt_recoil_tier())
	anim_upper.play(anims[alt_combo_index])
	alt_combo_index += 1
	
func _apply_recoil(tier: String) -> void:
	if tier == "none":
		return
	if status_effect_component.has_effect("steadfast"):
		return
	var direction := Vector2.LEFT.rotated(rotation)  # opposite of facing
	impact_component.apply_knockback(tier, direction)

# ── State Helpers ────────────────────────────────────────────────

func _is_attacking() -> bool:
	return is_main_attacking or is_alt_attacking or is_throwing_grenade

# ── Movement (shared base) ───────────────────────────────────────

func _apply_movement(desired_velocity: Vector2) -> void:
	if status_effect_component.has_effect("anchored"):
		# Fully locked — no self movement, immune to knockback push too.
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if status_effect_component.has_effect("petrified"):
		# No self movement, but still an inert object — knockback can push it.
		desired_velocity = Vector2.ZERO
	
	if impact_component.is_knockback_active():
		var tier := impact_component.get_knockback_tier()
		var dir := impact_component.get_knockback_direction()
		var push_speed: float = ImpactComponent.KNOCKBACK_TIER_SPEEDS.get(tier, 0.0)
		var mult := impact_component.get_knockback_multiplier()
		var resistance := 1.0 - stats.knockback_resistance
		velocity = desired_velocity + dir * push_speed * mult * resistance
	else:
		velocity = desired_velocity
	move_and_slide()

func set_invincible(state: bool) -> void:
	set_collision_mask_value(2, not state)
	set_collision_mask_value(3, not state)
	set_collision_mask_value(4, not state)
	set_collision_mask_value(5, not state)
	set_collision_mask_value(6, not state)
	hurtbox.set_deferred("monitorable", not state)
	# Tell all other characters to drop this character's layer from their mask
	var all_characters := get_tree().get_nodes_in_group("player") + \
		get_tree().get_nodes_in_group("enemy")
	for character in all_characters:
		if character == self:
			continue
		character.set_collision_mask_value(collision_layer_index, not state)

func try_dodge(direction: Vector2) -> void:
	if is_dodging or cooldown_timer > 0 or _stamina < stats.stamina_per_dodge:
		return
	if status_effect_component.has_effect("anchored") or status_effect_component.has_effect("petrified"):
		return
	dodge_direction = direction if direction.length() > 0 else last_direction
	is_dodging = true
	dodge_traveled = 0.0
	cooldown_timer = stats.dodge_cooldown
	_stamina -= stats.stamina_per_dodge
	set_invincible(true)
	is_tossing = false
	_cancel_into_idle()
	anim_upper.play("uni_dodge")
	anim_lower.stop()

func _tick_dodge(delta: float) -> void:
	if is_dodging:
		var step := dodge_direction.normalized() * stats.dodge_speed * delta
		dodge_traveled += step.length()
		_apply_movement(dodge_direction.normalized() * stats.dodge_speed)
		if dodge_traveled >= stats.dodge_distance:
			is_dodging = false
			set_invincible(false)
			if get_active_weapon().weapon_category == "grenade":
				if main_attack_held:
					_start_grenade_throw()
				else:
					_snap_to_idle()
			elif main_attack_held:
				_play_main_attack()
			elif alt_attack_held:
				_play_alt_attack()
			else:
				_snap_to_idle()

func _tick_stamina(delta: float) -> void:
	if _stamina < stats.stamina_max:
		_stamina = min(_stamina + stats.stamina_regen * delta, stats.stamina_max)
		
# Clamps a combined speed multiplier so it never drops below this
# character's floor, no matter how many slowing effects are stacked.
func _apply_speed_floor(multiplier: float) -> float:
	return max(multiplier, stats.min_speed_multiplier)
	
func _get_slow_multiplier() -> float:
	if status_effect_component.has_effect("slow"):
		return 1.0 - status_effect_component.get_magnitude("slow")
	return 1.0

func _is_petrified() -> bool:
	return status_effect_component.has_effect("petrified")

func _on_status_effect_applied(effect_name: String, _duration: float) -> void:
	if effect_name != "petrified":
		return
	call_deferred("_snap_to_idle_for_petrify")
	
func _snap_to_idle_for_petrify() -> void:
	if is_dodging:
		is_dodging = false
		set_invincible(false)
	is_tossing = false
	_cancel_into_idle()
	anim_lower.stop()

# ── Bullets ──────────────────────────────────────────────────────

func spawn_bullet_right() -> void:
	spawn_bullet(muzzle_right)

func spawn_bullet_left() -> void:
	spawn_bullet(muzzle_left)

func spawn_bullet(muzzle: Marker2D) -> void:
	var weapon := get_active_weapon()
	if weapon == fists:
		return
	if weapon.bullet_scene == null:
		push_warning("spawn_bullet: no bullet_scene assigned on %s" % weapon.weapon_name)
		return
	var bullet = weapon.bullet_scene.instantiate()
	bullet.position = muzzle.global_position
	get_parent().add_child(bullet)
	var spread_rad := deg_to_rad(randf_range(-weapon.bullet_spread, weapon.bullet_spread))
	var direction := Vector2.RIGHT.rotated(rotation + spread_rad)
	bullet.setup(
		direction,
		weapon.bullet_speed,
		weapon.bullet_range,
		weapon.bullet_pierce,
		weapon.damage_main,
		weapon.get_main_knockback_tier(),
		weapon.get_main_flinch_tier(),
		weapon.get_dot_config(),
		weapon.get_root_config(),
		weapon.get_disarm_config(),
		weapon.get_slow_config()
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
	var broken_data := current_weapon
	current_weapon = null
	_update_weapon_visuals()
	_cancel_into_idle()
	
	# Resume attacking with fists if the key/AI intent is still active —
	# otherwise the swing silently drops until the button is released and re-pressed.
	if main_attack_held and get_active_weapon().main_attack_animations.size() > 0:
		_play_main_attack()
	elif alt_attack_held and get_active_weapon().alt_attack_animations.size() > 0:
		_play_alt_attack()
		
	var hud := get_tree().get_first_node_in_group("hud") as HUD
	if hud:
		hud.refresh()
	# Notify drop manager that this weapon is gone
	var manager := get_tree().get_first_node_in_group("weapon_drop_manager") as WeaponDropManager
	if manager:
		manager.register_weapon_broken(broken_data)
