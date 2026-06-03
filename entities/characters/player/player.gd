# Player.gd 
# Hello Claude
# Extends Character — handles input, lock-on, dodge, and camera.
extends Character
class_name Player

# ── Exports ──────────────────────────────────────────────────────

@export var lock_on_toggle_mode: bool = false

@export_group("Dodge")
@export var dodge_speed: float = 250.0
@export var dodge_distance: float = 48.0
@export var dodge_cooldown: float = 0.2

# ── Node References ──────────────────────────────────────────────

@onready var lock_on_area: Area2D = $Area2D
@onready var camera: Camera2D = $Camera2D

# ── State ────────────────────────────────────────────────────────

var using_controller: bool = false

var is_dodging: bool = false
var dodge_traveled: float = 0.0
var cooldown_timer: float = 0.0
var dodge_direction: Vector2 = Vector2.ZERO

var lock_on_active: bool = false
var lock_on_target: Node2D = null
var enemies_in_range: Array = []

# ── Ready ────────────────────────────────────────────────────────

func _ready() -> void:
	super()
	lock_on_area.body_entered.connect(_on_enemy_entered)
	lock_on_area.body_exited.connect(_on_enemy_exited)

# ── Health Callbacks ─────────────────────────────────────────────

func _on_damaged(_amount: int, _remaining: int) -> void:
	var tween := create_tween()
	tween.tween_property($Body, "modulate", Color(4.0, 0.0, 0.0, 1.0), 0.05)
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

# ── Dodge ────────────────────────────────────────────────────────

func set_invincible(state: bool) -> void:
	set_collision_mask_value(3, not state)

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

	# ── Priority 1: Dodge ────────────────────────────────────────
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
	if not is_dodging and not is_tossing:
		if Input.is_action_just_pressed("toss") and current_weapon != null:
			is_tossing = true
			_cancel_into_idle()
			anim_upper.play("uni_toss")
			_do_toss()

	# ── Priority 3: Attacks ──────────────────────────────────────
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
		_apply_movement(dodge_direction.normalized() * dodge_speed)
		if dodge_traveled >= dodge_distance:
			is_dodging = false
			set_invincible(false)
			if main_attack_held:
				_play_main_attack()
			elif alt_attack_held:
				_play_alt_attack()
			else:
				_snap_to_idle()
	else:
		var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var knock_mult := knockback_component.get_speed_multiplier()
		if _is_attacking():
			_apply_movement(direction * stats.move_speed * get_active_weapon().movement_penalty * knock_mult)
		else:
			_apply_movement(direction * stats.move_speed * knock_mult)
		if direction.length() > 0:
			last_direction = direction

	# Clean up invalid enemies
	enemies_in_range = enemies_in_range.filter(func(e): return is_instance_valid(e))
	if lock_on_target and not is_instance_valid(lock_on_target):
		lock_on_target = _get_nearest_enemy()

# ── Process (Facing / Animation) ─────────────────────────────────

func _process(_delta: float) -> void:
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
