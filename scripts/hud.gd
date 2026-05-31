# hud.gd
# Displays current weapon durability, ammo, and quantity.
# Call setup(player) once after both HUD and Player are ready.
extends CanvasLayer
class_name HUD

@onready var weapon_name_label: Label = $WeaponPanel/VBoxContainer/WeaponName
@onready var durability_bar: ProgressBar = $WeaponPanel/VBoxContainer/DurabilityBar
@onready var ammo_label: Label = $WeaponPanel/VBoxContainer/AmmoLabel
@onready var quantity_label: Label = $WeaponPanel/VBoxContainer/QuantityLabel

var _player: Player = null

func _ready() -> void:
	call_deferred("_find_player")

func _find_player() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	print("HUD found player: ", player)
	if player:
		setup(player)

func setup(player: Player) -> void:
	_player = player
	refresh()

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
	else:
		durability_bar.visible = true
		durability_bar.max_value = _get_durability_max(weapon.durability)
		durability_bar.value = weapon.durability_current

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
