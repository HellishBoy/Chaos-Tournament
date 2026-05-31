extends CharacterBody2D

# ── Exports ──────────────────────────────────────────────────────

@export var speed: float = 100.0
@export var current_weapon: WeaponData
@export var fists: WeaponData
@export var lock_on_toggle_mode: bool = false
@export var weapon_pickup_scene: PackedScene

@export_group("Dodge")
@export var dodge_speed: float = 250.0
@export var dodge_distance: float = 48.0
@export var dodge_cooldown: float = 0.2

@export_group("Combat")
@export var combo_window: float = 0.4

# ── Node References ──────────────────────────────────────────────

@onready var anim_upper: AnimationPlayer = $AnimationPlayerUpper
@onready var anim_lower: AnimationPlayer = $AnimationPlayerLower

# Weapon visuals
@onready var weapon_right: Sprite2D = $Body/Hands/HandRight/WeaponRight
@onready var weapon_left: Sprite2D  = $Body/Hands/HandLeft/WeaponLeft

# Muzzle points for bullet spawning
@onready var muzzle_right: Marker2D = $Body/Hands/HandRight/Muzzle_R
@onready var muzzle_left: Marker2D  = $Body/Hands/HandLeft/Muzzle_L

# Hitboxes — driven by animation tracks
@onready var hitbox_right: Area2D = $Body/Hands/HandRight/HitboxRight
@onready var hitbox_left: Area2D  = $Body/Hands/HandLeft/HitboxLeft

# Combat components
@onready var health: HealthComponent           = $HealthComponent
@onready var hurtbox: Area2D                   = $Hurtbox
@onready var knockback_component: KnockbackComponent = $KnockbackComponent

# Lock-on detection area
@onready var lock_on_area: Area2D = $Area2D

# ── State Variables ──────────────────────────────────────────────

var last_direction: Vector2 = Vector2.UP
var using_controller: bool = false

# Dodge state
var is_dodging: bool = false
var dodge_traveled: float = 0.0
var cooldown_timer: float = 0.0
var dodge_direction: Vector2 = Vector2.ZERO

# Lock-on state
var lock_on_active: bool = false
var lock_on_target: Node2D = null
var enemies_in_range: Array = []

# Action states
var is_tossing: bool = false
var is_main_attacking: bool = false
var is_alt_attacking: bool = false

# Combo tracking
var main_combo_index: int = 0
var main_combo_timer: float = 0.0
var alt_combo_index: int = 0
var alt_combo_timer: float = 0.0
var main_attack_held: bool = false
var alt_attack_held: bool = false

# Attack buffer — stores a queued attack input received during an animation
# so it fires immediately when the current animation finishes
var _buffered_attack: String = ""  # "main", "alt", or ""

# ── Ready ────────────────────────────────────────────────────────

func _ready() -> void:
	assert(fists != null, "Player: fists WeaponData must be assigned in the Inspector.")
	lock_on_area.body_entered.connect(_on_enemy_entered)
	lock_on_area.body_exited.connect(_on_enemy_exited)
	anim_upper.animation_finished.connect(_on_animation_finished)
	hurtbox.area_entered.connect(_on_hurtbox_area_entered)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	_update_weapon_visuals()

# ── Active Weapon ────────────────────────────────────────────────

# Returns current_weapon if holding one, otherwise falls back to fists
func get_active_weapon() -> WeaponData:
	return current_weapon if current_weapon else fists

# ── Pickup ───────────────────────────────────────────────────────

# Called by WeaponPickup when the player walks over it
# Blocked if already holding a weapon
func try_pickup(pickup_node: Node) -> void:
	if current_weapon != null:
		return
	var data: WeaponData = pickup_node.weapon_data
	pickup_node.queue_free()
	current_weapon = data
	_update_weapon_visuals()

# ── Toss ─────────────────────────────────────────────────────────

# Discards current weapon into the world as a pickupable scene
# Weapon flies in the direction the player is facing
func _do_toss() -> void:
	if current_weapon == null or not current_weapon.can_toss:
		return
	var data := current_weapon
	current_weapon = null
	_update_weapon_visuals()
	if weapon_pickup_scene == null:
		push_warning("Player: weapon_pickup_scene not assigned in Inspector.")
		return
	var toss_dir := Vector2.RIGHT.rotated(rotation)
	var pickup = weapon_pickup_scene.instantiate()
	pickup.weapon_data = data
	pickup._was_tossed = true
	pickup.position = global_position + toss_dir * 10.0
	get_parent().add_child(pickup)
	pickup.setup_toss(global_position, toss_dir)

# ── Weapon Visuals ───────────────────────────────────────────────

# Shows or hides hand weapon sprites based on current_weapon
# Fists = no weapon sprites shown (hands already have their own sprites)
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

# Snaps to the current weapon's idle animation with no RESET flash
# Used when animations finish naturally
func _snap_to_idle() -> void:
	anim_upper.speed_scale = 1.0
	var idle := get_active_weapon().idle_animation
	if idle != "":
		anim_upper.play(idle)
	else:
		anim_upper.stop()

# Resets all attack state and combo tracking
func _reset_attacks() -> void:
	is_main_attacking = false
	is_alt_attacking = false
	main_combo_index = 0
	main_combo_timer = 0.0
	alt_combo_index = 0
	alt_combo_timer = 0.0
	_buffered_attack = ""

# Cancels mid-animation into idle using a RESET snap to prevent frame freeze
# Only used when dodge or toss interrupts an attack
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

# ── Lock-on ──────────────────────────────────────────────────────

func _on_enemy_entered(body: Node2D) -> void:
	if not enemies_in_range.has(body):
		enemies_in_range.append(body)
	if lock_on_active:
		lock_on_target = _get_nearest_enemy()

func _on_enemy_exited(body: Node2D) -> void:
	enemies_in_range.erase(body)
	if lock_on_target == body:
		lock_on_target = _get_nearest_enemy()

# ── Health / Hurtbox ─────────────────────────────────────────────

func _on_hurtbox_area_entered(area: Area2D) -> void:
	if area.get_parent().has_node("HealthComponent"):
		var h := area.get_parent().get_node("HealthComponent") as HealthComponent
		h.take_damage(area.damage)
	if area.get_parent().has_node("KnockbackComponent"):
		var kb := area.get_parent().get_node("KnockbackComponent") as KnockbackComponent
		kb.apply(area.knockback_tier, Vector2.RIGHT.rotated(area.get_parent().rotation))

func _on_damaged(_amount: int, _remaining: int) -> void:
	var tween := create_tween()
	tween.tween_property($Body, "modulate", Color.RED, 0.05)
	tween.tween_property($Body, "modulate", Color.WHITE, 0.1)

func _on_died() -> void:
	print("Player died!")

# ── Input ────────────────────────────────────────────────────────

func _unhandled_input(_event: InputEvent) -> void:
	for action in InputMap.get_actions():
		if Input.is_action_just_pressed(action):
			print("Action pressed: ", action)

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion or event is InputEventJoypadButton:
		using_controller = true
	elif event is InputEventMouse or event is InputEventKey:
		using_controller = false

	if lock_on_toggle_mode:
		if event.is_action_pressed("lock_on"):
			lock_on_active = !lock_on_active
			lock_on_target = _get_nearest_enemy() if lock_on_active else null
	else:
		if event.is_action_pressed("lock_on"):
			lock_on_active = true
			lock_on_target = _get_nearest_enemy()
		if event.is_action_released("lock_on"):
			lock_on_active = false
			lock_on_target = null

# ── Animation Finished ───────────────────────────────────────────

func _on_animation_finished(anim_name: StringName) -> void:
	# Toss finished — resume attacking if key still held
	if anim_name == "uni_toss":
		is_tossing = false
		if main_attack_held:
			_play_main_attack()
		elif alt_attack_held:
			_play_alt_attack()
		else:
			_snap_to_idle()
		return

	# Main attack finished — check buffer, held key, or return to idle
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

	# Alt attack finished — check buffer, held key, or return to idle
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

# Sets hitbox damage and knockback info then plays the next main attack animation
func _play_main_attack() -> void:
	var anims := get_active_weapon().main_attack_animations
	if anims.is_empty():
		return
	main_combo_index = main_combo_index % anims.size()
	is_main_attacking = true
	is_alt_attacking = false
	main_combo_timer = 0.0
	anim_upper.speed_scale = get_active_weapon().main_attack_speed
	# Set hitbox stats before animation plays so they're ready at the hit frame
	hitbox_right.damage           = get_active_weapon().damage_main
	hitbox_left.damage            = get_active_weapon().damage_main
	hitbox_right.knockback_tier   = get_active_weapon().main_knockback
	hitbox_right.knockback_facing = get_active_weapon().knockback_main_facing
	hitbox_right.attacker         = self
	hitbox_left.knockback_tier    = get_active_weapon().main_knockback
	hitbox_left.knockback_facing  = get_active_weapon().knockback_main_facing
	hitbox_left.attacker          = self
	anim_upper.play(anims[main_combo_index])
	main_combo_index += 1

# Sets hitbox damage and knockback info then plays the next alt attack animation
func _play_alt_attack() -> void:
	var anims := get_active_weapon().alt_attack_animations
	if anims.is_empty():
		return
	alt_combo_index = alt_combo_index % anims.size()
	is_alt_attacking = true
	is_main_attacking = false
	alt_combo_timer = 0.0
	anim_upper.speed_scale = get_active_weapon().alt_attack_speed
	# Set hitbox stats before animation plays so they're ready at the hit frame
	hitbox_right.damage           = get_active_weapon().damage_alt
	hitbox_left.damage            = get_active_weapon().damage_alt
	hitbox_right.knockback_tier   = get_active_weapon().alt_knockback
	hitbox_right.knockback_facing = get_active_weapon().knockback_alt_facing
	hitbox_right.attacker         = self
	hitbox_left.knockback_tier    = get_active_weapon().alt_knockback
	hitbox_left.knockback_facing  = get_active_weapon().knockback_alt_facing
	hitbox_left.attacker          = self
	anim_upper.play(anims[alt_combo_index])
	alt_combo_index += 1

# ── State Helpers ────────────────────────────────────────────────

func _is_attacking() -> bool:
	return is_main_attacking or is_alt_attacking

# ── Physics Process ──────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	# Tick timers
	if cooldown_timer > 0:
		cooldown_timer -= delta
	if main_combo_timer > 0:
		main_combo_timer -= delta
		if main_combo_timer <= 0:
			main_combo_index = 0
	if alt_combo_timer > 0:
		alt_combo_timer -= delta
		if alt_combo_timer <= 0:
			alt_combo_index = 0

	# Track held attack keys each frame for chaining and post-dodge resuming
	main_attack_held = Input.is_action_pressed("attack_main")
	alt_attack_held  = Input.is_action_pressed("attack_alt")

	# ── Priority 1: Dodge ────────────────────────────────────────
	# Highest priority — cancels all attacks and toss
	if Input.is_action_just_pressed("dodge") and not is_dodging and cooldown_timer <= 0:
		var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		dodge_direction = input_dir if input_dir.length() > 0 else last_direction
		is_dodging = true
		dodge_traveled = 0.0
		cooldown_timer = dodge_cooldown
		set_invincible(true)
		is_tossing = false
		_cancel_into_idle()
		anim_upper.play("uni_dodge")
		anim_lower.stop()

	# ── Priority 2: Toss ─────────────────────────────────────────
	# Cancels attacks — only works when holding a weapon
	if not is_dodging and not is_tossing:
		if Input.is_action_just_pressed("toss") and current_weapon != null:
			is_tossing = true
			_cancel_into_idle()
			anim_upper.play("uni_toss")
			_do_toss()

	# ── Priority 3: Attacks ──────────────────────────────────────
	# Main and alt have equal priority — neither cancels the other
	# Pressing the other attack while one is active buffers it instead
	if not is_dodging and not is_tossing:
		if Input.is_action_just_pressed("attack_main"):
			if not is_alt_attacking and not is_main_attacking:
				_play_main_attack()
			elif is_alt_attacking:
				_buffered_attack = "main"

		if Input.is_action_just_pressed("attack_alt"):
			if get_active_weapon().alt_attack_animations.size() > 0:
				if not is_main_attacking and not is_alt_attacking:
					_play_alt_attack()
				elif is_main_attacking:
					_buffered_attack = "alt"

	# ── Movement ─────────────────────────────────────────────────
	if is_dodging:
		var step := dodge_direction.normalized() * dodge_speed * delta
		dodge_traveled += step.length()
		velocity = dodge_direction.normalized() * dodge_speed
		if dodge_traveled >= dodge_distance:
			is_dodging = false
			set_invincible(false)
			# Resume attacking if key still held after dodge
			if main_attack_held:
				_play_main_attack()
			elif alt_attack_held:
				_play_alt_attack()
			else:
				_snap_to_idle()
	else:
		var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		# Knockback multiplier reduces speed while active, recovers smoothly
		var knock_mult := knockback_component.get_speed_multiplier()
		if _is_attacking():
			velocity = direction * speed * get_active_weapon().movement_penalty * knock_mult
		else:
			velocity = direction * speed * knock_mult
		if direction.length() > 0:
			last_direction = direction

	move_and_slide()

	# Clean up invalid enemies from tracking arrays
	enemies_in_range = enemies_in_range.filter(func(e): return is_instance_valid(e))
	if lock_on_target and not is_instance_valid(lock_on_target):
		lock_on_target = _get_nearest_enemy()

# ── Process (Facing / Animation) ─────────────────────────────────

func _process(_delta: float) -> void:
	var cam = $Camera2D

	# ── Facing direction ─────────────────────────────────────────
	# Lock-on overrides all other facing modes
	if lock_on_target:
		look_at(lock_on_target.global_position)
	elif using_controller:
		var stick := Vector2(
			Input.get_action_strength("look_right") - Input.get_action_strength("look_left"),
			Input.get_action_strength("look_down") - Input.get_action_strength("look_up")
		)
		if stick.length() > 0.05:
			rotation = stick.angle()
			last_direction = stick
		else:
			rotation = last_direction.angle()
	else:
		if cam.aim_active:
			look_at(get_global_mouse_position())
		else:
			rotation = last_direction.angle()

	# Body rotates independently during dodge so sprite faces dodge direction
	$Body.rotation = dodge_direction.angle() - rotation if is_dodging else 0.0

	# ── Upper body animation ──────────────────────────────────────
	# Only plays walk/idle when no priority action is active
	if not is_dodging and not is_tossing and not _is_attacking():
		if velocity.length() > 0:
			var walk := get_active_weapon().walk_animation
			if walk != "":
				anim_upper.play(walk)
		else:
			_snap_to_idle()

	# ── Feet animation ────────────────────────────────────────────
	if not is_dodging:
		if velocity.length() > 0:
			anim_lower.play("feet_slow" if _is_attacking() else "feet_normal")
		else:
			anim_lower.stop()

# ── Utilities ────────────────────────────────────────────────────

# Toggles player collision mask to ignore enemy layer during dodge i-frames
func set_invincible(state: bool) -> void:
	set_collision_mask_value(3, not state)

func _get_nearest_enemy() -> Node2D:
	if enemies_in_range.is_empty():
		return null
	var nearest: Node2D = null
	var nearest_dist: float = INF
	for enemy in enemies_in_range:
		if not is_instance_valid(enemy):
			continue
		var dist := global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy
	return nearest

# ── Bullets ──────────────────────────────────────────────────────

# Called by animation method track at the fire frame
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
	bullet.position = muzzle.global_position  # set before add_child to prevent origin flash
	get_parent().add_child(bullet)
	bullet.setup(
		Vector2.RIGHT.rotated(rotation),
		weapon.bullet_speed,
		weapon.bullet_range,
		weapon.bullet_pierce,
		weapon.damage_main,
		weapon.main_knockback
	)
