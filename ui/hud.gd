# hud.gd
# Displays current weapon durability, ammo, and quantity.
# Call setup(player) once after both HUD and Player are ready.
extends CanvasLayer
class_name HUD

@export_group("Player Health Bar")
@export var player_bar_width: float = 200.0
@export var player_bar_height: float = 12.0
@export var player_bar_border_thickness: float = 1.0

@export_group("Vignette")
@export var vignette_threshold: float = 0.4  # below 40% HP vignette starts showing
@export var vignette_pulse_speed: float = 1.2

@onready var weapon_name_label: Label = $WeaponPanel/VBoxContainer/WeaponName

@onready var durability_bar: ProgressBar = $WeaponPanel/VBoxContainer/DurabilityBar
@onready var durability_label: Label = $WeaponPanel/VBoxContainer/DurabilityLabel

@onready var ammo_label: Label = $WeaponPanel/VBoxContainer/AmmoLabel
@onready var quantity_label: Label = $WeaponPanel/VBoxContainer/QuantityLabel

@onready var player_health_fill: ColorRect = $PlayerHealthBar/Fill
@onready var player_health_border: ColorRect = $PlayerHealthBar/Border
@onready var player_health_background: ColorRect = $PlayerHealthBar/Background

@onready var dodge_charges_container: HBoxContainer = $PlayerHealthBar/DodgeCharges

@onready var vignette: ColorRect = $Vignette

var _player: Player = null
var _player_max_hp: int = 0
var _health_tween: Tween = null

var _vignette_material: ShaderMaterial
var _vignette_time: float = 0.0
var _vignette_active: bool = false

func _ready() -> void:
	call_deferred("_find_player")
	_vignette_material = vignette.material as ShaderMaterial
	_vignette_material.set_shader_parameter("intensity", 1.0)
	_setup_screens()

func _process(delta: float) -> void:
	if _vignette_active:
		_vignette_time += delta * vignette_pulse_speed
		var pulse := (sin(_vignette_time * TAU) + 1.0) / 2.0
		
		# t goes from 1.0 at threshold to 0.0 at 5% HP
		var current_percent: float = float(_player.health.current_hp) / float(_player_max_hp)
		var t: float = clamp((current_percent - 0.15) / (vignette_threshold - 0.15), 0.0, 1.0)
		
		# As t goes from 1.0 to 0.0 (lower health):
		# base_intensity increases from 0.2 to 0.7
		var base_intensity: float = lerp(0.5, 0.2, t)
		# pulse_intensity increases from 0.1 to 0.3
		var pulse_intensity: float = lerp(0.15, 0.1, t)
		# shader inner edge decreases from 0.4 to 0.1 (creeps toward center)
		var inner_edge: float = lerp(0.35, 0.4, t)
		
		_vignette_material.set_shader_parameter("intensity", base_intensity + pulse * pulse_intensity)
		_vignette_material.set_shader_parameter("inner_edge", inner_edge)

func refresh_dodge(stamina: float, stamina_max: float, stamina_per_dodge: float) -> void:
	var num_circles: int = int(stamina_max / stamina_per_dodge)
	var circles := dodge_charges_container.get_children()
	
	# Rebuild if circle count changed
	if circles.size() != num_circles:
		for child in circles:
			child.queue_free()
		for i in num_circles:
			var circle := DodgeCharge.new()
			circle.custom_minimum_size = Vector2(14, 14)
			dodge_charges_container.add_child(circle)
		circles = dodge_charges_container.get_children()
	
	# Update each circle
	for i in num_circles:
		var circle := circles[i] as DodgeCharge
		var circle_min := i * stamina_per_dodge
		var circle_max := (i + 1) * stamina_per_dodge
		if stamina >= circle_max:
			# Fully filled
			circle.set_state(true)
		elif stamina <= circle_min:
			# Fully empty
			circle.set_state(false, 0.0)
		else:
			# Partially filled
			circle.set_state(false, (stamina - circle_min) / stamina_per_dodge)

func _update_vignette(current: int, max_hp: int) -> void:
	var percent: float = float(current) / float(max_hp)
	if percent <= vignette_threshold:
		_vignette_active = true
		_vignette_time = 0.0
	else:
		_vignette_active = false
		_vignette_material.set_shader_parameter("intensity", 0.0)

func _find_player() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	print("HUD found player: ", player)
	if player:
		setup(player)

func setup(player: Player) -> void:
	_player = player
	_player_max_hp = player.health.max_hp
	player.health.damaged.connect(_on_player_damaged)
	player.health.died.connect(_on_player_died)
	_update_player_health(player.health.current_hp, player.health.max_hp)
	_setup_player_health_bar()
	refresh()
	_update_vignette(player.health.current_hp, player.health.max_hp)
	refresh_dodge(player._stamina, player.stats.stamina_max, player.stats.stamina_per_dodge)
	
func _setup_player_health_bar() -> void:
	# Border
	player_health_border.size = Vector2(player_bar_width + player_bar_border_thickness * 2, player_bar_height + player_bar_border_thickness * 2)
	player_health_border.position = Vector2(-player_bar_border_thickness, -player_bar_border_thickness)
	player_health_border.color = Color(0.0, 0.0, 0.0, 1.0)
	# Background
	player_health_background.size = Vector2(player_bar_width, player_bar_height)
	player_health_background.position = Vector2(0.0, 0.0)
	# Fill
	player_health_fill.size = Vector2(player_bar_width, player_bar_height)
	player_health_fill.position = Vector2(0.0, 0.0)

func _on_player_damaged(_amount: int, remaining: int) -> void:
	_update_player_health(remaining, _player_max_hp)
	_flash_health_bar()
	_update_vignette(remaining, _player_max_hp)
	
func _on_player_died() -> void:
	player_health_fill.size.x = 0.0
	
func _flash_health_bar() -> void:
	var tween := create_tween()
	tween.tween_property(player_health_fill, "modulate", Color(2.0, 2.0, 2.0, 1.0), 0.05)
	tween.tween_property(player_health_fill, "modulate", Color.WHITE, 0.15)\
		.set_ease(Tween.EASE_OUT)\
		.set_trans(Tween.TRANS_QUINT)

func _update_player_health(current: int, max_hp: int) -> void:
	var percent: float = float(current) / float(max_hp)
	var target_width: float = player_bar_width * percent
	if _health_tween:
		_health_tween.kill()
	_health_tween = create_tween()
	_health_tween.tween_property(player_health_fill, "size:x", target_width, 0.15)\
		.set_ease(Tween.EASE_OUT)\
		.set_trans(Tween.TRANS_QUINT)

func refresh() -> void:
	if _player == null:
		return
	var weapon := _player.get_active_weapon()
	print("weapon: ", weapon.weapon_name)
	print("durability: ", weapon.durability)
	print("durability_current: ", weapon.durability_current)

	# Weapon name
	weapon_name_label.text = weapon.weapon_name

	# Durability
	if weapon.durability == "none" or weapon.durability == "infinite" or weapon.durability_current == -1:
		durability_bar.visible = false
		durability_label.visible = false
	else:
		var max_dur: int = _get_durability_max(weapon.durability)
		weapon.durability_current = min(weapon.durability_current, max_dur)
		durability_bar.visible = true
		durability_label.visible = true
		durability_bar.max_value = max_dur
		durability_bar.value = weapon.durability_current
		durability_bar.show_percentage = false
		durability_label.text = "%d / %d" % [weapon.durability_current, max_dur]

	# Ammo
	if weapon.ammo == -1:
		ammo_label.visible = false
	else:
		ammo_label.visible = true
		ammo_label.text = "Ammo: %d" % weapon.ammo

	# Quantity
	if weapon.quantity == -1:
		quantity_label.visible = false
	else:
		quantity_label.visible = true
		quantity_label.text = "x%d" % weapon.quantity

func _get_durability_max(tier: String) -> int:
	match tier:
		"low":    return 3
		"medium": return 5
		"high":   return 8
	return 1
	
func _setup_screens() -> void:
	$WinScreen/VBoxContainer/PlayAgainButton.pressed.connect(_on_play_again_pressed)
	$WinScreen/VBoxContainer/StageSelectButton.pressed.connect(_on_stage_select_pressed)
	$LoseScreen/VBoxContainer/TryAgainButton.pressed.connect(_on_try_again_pressed)
	$LoseScreen/VBoxContainer/StageSelectButton.pressed.connect(_on_stage_select_pressed)

func _on_play_again_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_try_again_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_stage_select_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(GameState.stage_select_path)
