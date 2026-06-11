extends Node2D

const LEVEL_SELECT = "res://realms/earth_realm/level_select.tscn"

func _ready() -> void:
	$Hud/WinScreen/VBoxContainer/PlayAgainButton.pressed.connect(_on_play_again_pressed)
	$Hud/WinScreen/VBoxContainer/LevelSelectButton.pressed.connect(_on_level_select_pressed)
	$Hud/LoseScreen/VBoxContainer/TryAgainButton.pressed.connect(_on_try_again_pressed)
	$Hud/LoseScreen/VBoxContainer/LevelSelectButton.pressed.connect(_on_level_select_pressed)

func _on_play_again_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_try_again_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_level_select_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(LEVEL_SELECT)
