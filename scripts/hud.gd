# hud.gd
# Displays current weapon durability, ammo, and quantity.
# Call setup(player) once after both HUD and Player are ready.
extends CanvasLayer
class_name HUD

const PLAYER_BAR_WIDTH: float = 200.0

@onready var weapon_name_label: Label = $WeaponPanel/VBoxContainer/WeaponName
@onready var durability_bar: ProgressBar = $WeaponPanel/VBoxContainer/DurabilityBar
@onready var ammo_label: Label = $WeaponPanel/VBoxContainer/AmmoLabel
@onready var quantity_label: Label = $WeaponPanel/VBoxContainer/QuantityLabel
@onready var durability_label: Label = $WeaponPanel/VBoxContainer/DurabilityLabel
@onready var player_health_fill: ColorRect = $PlayerHealthBar/Fill

var _player: Player = null
var _player_max_hp: int = 0

func _ready() -> void:
	call_deferred("_find_player")

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
	refresh()

func _on_player_damaged(amount: int, remaining: int) -> void:
	_update_player_health(remaining, _player_max_hp)
	
func _on_player_died() -> void:
	player_health_fill.size.x = 0.0

func _update_player_health(current: int, max_hp: int) -> void:
	var percent: float = float(current) / float(max_hp)
	player_health_fill.size.x = PLAYER_BAR_WIDTH * percent

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
