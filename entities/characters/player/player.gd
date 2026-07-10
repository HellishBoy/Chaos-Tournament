# Player.gd 
# Hello Again Claude
# Extends Character — handles input, lock-on, dodge, and camera.
extends Character
class_name Player

# ── Exports ──────────────────────────────────────────────────────

@export var lock_on_toggle_mode: bool = false
@export var lock_on_range: float = 120.0

@export_group("Debug")
@export var show_lock_on_debug: bool = false

# ── Node References ──────────────────────────────────────────────

@onready var lock_on_area: Area2D = $Area2D
@onready var lock_on_radius: CollisionShape2D = $"Area2D/LockonRange"
@onready var camera: Camera2D = $Camera2D

# ── State ────────────────────────────────────────────────────────

var using_controller: bool = false

var lock_on_active: bool = false
var lock_on_target: Node2D = null
var enemies_in_range: Array = []

var _effective_lock_on_range: float = 0.0

# ── Ready ────────────────────────────────────────────────────────

func _ready() -> void:
	super()
	lock_on_area.body_entered.connect(_on_enemy_entered)
	lock_on_area.body_exited.connect(_on_enemy_exited)
	if lock_on_radius.shape is CircleShape2D:
		lock_on_radius.shape.radius = lock_on_range
	else:
		push_warning(name + ": LockonRange's shape is not a CircleShape2D.")
		
# ── Lock-on Radius ───────────────────────────────────────────────

# Effective lock-on range = base range + the current weapon's
# peek_distance_lockon, so a weapon with more lock-on peek also lets
# you lock onto targets a bit farther away. Recomputed every physics
# frame rather than hooked to specific weapon-change call sites, since
# current_weapon changes from several places (pickup, toss, break,
# respawn) and polling here guarantees it's never stale.
func _update_lock_on_radius() -> void:
	if not (lock_on_radius.shape is CircleShape2D):
		return
	var peek_lockon: float = current_weapon.peek_distance_lockon if current_weapon else 0.0
	_effective_lock_on_range = lock_on_range + peek_lockon
	if lock_on_radius.shape.radius != _effective_lock_on_range:
		lock_on_radius.shape.radius = _effective_lock_on_range

# ── Health Callbacks ─────────────────────────────────────────────

func _on_damaged(_amount: int, _remaining: int) -> void:
	var tween := create_tween()
	tween.tween_property($Body, "modulate", Color(4.0, 0.0, 0.0, 1.0), 0.05)
	tween.tween_property($Body, "modulate", Color.WHITE, 0.1)

func _on_died() -> void:
	
	_clear_as_target_for_others()
			
	# Drop weapon
	if current_weapon != null:
		var data := current_weapon
		current_weapon = null
		call_deferred("_toss_weapon_data", data)

	# White flash then grayscale
	var tween := create_tween()
	tween.tween_property($Body, "modulate", Color(8.0, 8.0, 8.0, 1.0), 0.1)
	tween.tween_interval(0.1)
	tween.tween_callback(func():
		_apply_death_state()
		set_process(false)
	)

# ── Input ────────────────────────────────────────────────────────

#func _unhandled_input(_event: InputEvent) -> void:
	#for action in InputMap.get_actions():
		#if Input.is_action_just_pressed(action):
			#print("Action pressed: ", action)

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

	if event.is_action_pressed("change_target"):
		_cycle_lock_on_target()

# ── Lock-on ──────────────────────────────────────────────────────

func _on_enemy_entered(body: Node2D) -> void:
	if not (body is Enemy):
		return
	if not enemies_in_range.has(body):
		enemies_in_range.append(body)
	if lock_on_active:
		lock_on_target = _get_nearest_enemy()

func _on_enemy_exited(body: Node2D) -> void:
	if not (body is Enemy):
		return
	enemies_in_range.erase(body)
	if lock_on_target == body:
		lock_on_target = _get_nearest_enemy()

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
	
func _cycle_lock_on_target() -> void:
	if not lock_on_active or enemies_in_range.is_empty():
		return
	var sorted := enemies_in_range.duplicate()
	sorted.sort_custom(func(a, b): return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position))
	var current_index := sorted.find(lock_on_target)
	var next_index := (current_index + 1) % sorted.size()
	lock_on_target = sorted[next_index]
	
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

	# Track held attack keys
	main_attack_held = Input.is_action_pressed("attack_main")
	alt_attack_held  = Input.is_action_pressed("attack_alt")
	
	# ── Stamina regen ────────────────────────────────────────────
	_tick_stamina(delta)
	var hud := get_tree().get_first_node_in_group("hud") as HUD
	if hud:
		hud.refresh_dodge(_stamina, stats.stamina_max, stats.stamina_per_dodge)
		
	_update_lock_on_radius()
		
	if is_dead:
		return
		
	if _is_petrified():
		_apply_movement(Vector2.ZERO)
		return

	# ── Priority 1: Dodge ────────────────────────────────────────
	if Input.is_action_just_pressed("dodge") and not is_dodging:
		var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		try_dodge(input_dir)
		if is_dodging:
			var hud2 := get_tree().get_first_node_in_group("hud") as HUD
			if hud2:
				hud2.refresh_dodge(_stamina, stats.stamina_max, stats.stamina_per_dodge)

	# ── Priority 2: Toss ─────────────────────────────────────────
	if not is_dodging and not is_tossing:
		if Input.is_action_just_pressed("toss") and current_weapon != null:
			is_tossing = true
			_cancel_into_idle()
			anim_upper.play("uni_toss")
			_do_toss()

	# ── Priority 3: Attacks ──────────────────────────────────────
	if not is_dodging and not is_tossing:
		if get_active_weapon().weapon_category == "grenade":
			if Input.is_action_just_pressed("attack_main") and not is_throwing_grenade:
				_start_grenade_throw()
			if Input.is_action_pressed("attack_main"):
				_tick_grenade_charge(delta)
			if Input.is_action_just_released("attack_main") and is_throwing_grenade:
				grenade_charge_held = false
				if _grenade_stance_reached:
					_release_grenade_throw()
		else:
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
		_tick_dodge(delta)
	else:
		var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var knock_mult := impact_component.get_control_speed_multiplier(stats.knockback_resistance)
		var weight_mult := get_active_weapon().get_weight_multiplier()
		var slow_mult := _get_slow_multiplier()
		if _is_attacking():
			var combined := _apply_speed_floor(get_active_weapon().movement_penalty * weight_mult * knock_mult * slow_mult)
			_apply_movement(direction * stats.move_speed * combined)
		else:
			var combined := _apply_speed_floor(weight_mult * knock_mult * slow_mult)
			_apply_movement(direction * stats.move_speed * combined)
		if direction.length() > 0:
			last_direction = direction

	# Clean up invalid enemies
	enemies_in_range = enemies_in_range.filter(func(e): return is_instance_valid(e))
	if lock_on_target and not is_instance_valid(lock_on_target):
		lock_on_target = _get_nearest_enemy()

# ── Process (Facing / Animation) ─────────────────────────────────

func _process(_delta: float) -> void:
	queue_redraw()
	check_if_cornered()
	if _is_petrified():
		return

	# ── Facing ───────────────────────────────────────────────────
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
		if camera.aim_active:
			look_at(get_global_mouse_position())
		else:
			rotation = last_direction.angle()

	# Body rotates independently during dodge
	$Body.rotation = dodge_direction.angle() - rotation if is_dodging else 0.0

	# ── Upper body animation ──────────────────────────────────────
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
			
# ── Misc. ────────────────────────────────────────────

func _draw() -> void:
	if show_lock_on_debug:
		var show_circle := lock_on_active if lock_on_toggle_mode else Input.is_action_pressed("lock_on")
		if show_circle:
			draw_arc(Vector2.ZERO, _effective_lock_on_range, 0, TAU, 64, Color.WHITE, 1.0)
	if is_throwing_grenade and _grenade_stance_reached and not _grenade_thrown:
		var weapon := get_active_weapon()
		var percent := 1.0
		if weapon.main_attack_charge and weapon.main_charge_time > 0.0:
			percent = clamp(grenade_charge_time / weapon.main_charge_time, 0.0, 1.0)
		var length := 48.0 * percent
		draw_line(Vector2.ZERO, Vector2.RIGHT * length, Color.WHITE, 2.0)
		
func check_if_cornered() -> bool:
	var wall_count = 0
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)
		# A dot product near zero helps detect perpendicular (corner) surfaces
		if abs(collision.get_normal().dot(Vector2.UP)) < 0.5:
			wall_count += 1
	
	# If they are colliding with more than one wall boundary, it's a corner
	return wall_count >= 2
