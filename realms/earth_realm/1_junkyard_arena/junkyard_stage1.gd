extends Node2D

const STAGE_SELECT = "res://realms/earth_realm/1_junkyard_arena/stage_select.tscn"

func _ready() -> void:
	$Hud/WinScreen/VBoxContainer/PlayAgainButton.pressed.connect(_on_play_again_pressed)
	$Hud/WinScreen/VBoxContainer/StageSelectButton.pressed.connect(_on_stage_select_pressed)
	$Hud/LoseScreen/VBoxContainer/TryAgainButton.pressed.connect(_on_try_again_pressed)
	$Hud/LoseScreen/VBoxContainer/StageSelectButton.pressed.connect(_on_stage_select_pressed)

func _on_play_again_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_try_again_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_stage_select_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(GameState.stage_select_path)
