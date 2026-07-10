extends Camera2D

# --- Camera Properties ---
@export_group("Camera Properties")
@export var cam_follow_speed: float = 1.0
@export var aim_toggle_mode: bool = false

var using_controller: bool = false
var aim_active: bool = false

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion or event is InputEventJoypadButton:
		using_controller = true
	elif event is InputEventMouse or event is InputEventKey:
		using_controller = false

	if not using_controller:
		if event.is_action_pressed("aim"):
			if aim_toggle_mode:
				aim_active = !aim_active
			else:
				aim_active = true
		if event.is_action_released("aim") and not aim_toggle_mode:
			aim_active = false

func _physics_process(_delta: float) -> void:
	var player = get_parent()
	var player_pos = player.global_position
	var target = player_pos

	var peek_aim = player.current_weapon.peek_distance_aim if player.current_weapon else 0.0
	var peek_lockon = player.current_weapon.peek_distance_lockon if player.current_weapon else 0.0

	if player.lock_on_target and is_instance_valid(player.lock_on_target):
		# Lock-on peek — toward the target
		var direction = (player.lock_on_target.global_position - player_pos).normalized()
		target = player_pos + direction * peek_lockon
	elif peek_aim > 0.0:
		if using_controller:
			# Controller stick — direction + intensity, not a cursor
			# position, so this stays a fixed-magnitude peek.
			var stick = Vector2(
				Input.get_action_strength("look_right") - Input.get_action_strength("look_left"),
				Input.get_action_strength("look_down") - Input.get_action_strength("look_up")
			)
			if stick.length() > 0.05:
				target = player_pos + stick.normalized() * peek_aim
		elif aim_active:
			# Mouse — genuinely follows the cursor's actual position,
			# capped at peek_aim. Hovering near the character keeps the
			# camera near-centered; only reaching toward peek_aim's
			# distance (or beyond) pushes the camera the full amount.
			var to_mouse = get_global_mouse_position() - player_pos
			target = player_pos + to_mouse.limit_length(peek_aim)

	global_position = global_position.lerp(target, cam_follow_speed)
