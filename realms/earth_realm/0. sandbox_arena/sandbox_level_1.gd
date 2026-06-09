extends Node2D

func _ready() -> void:
	$Hud/WinScreen/VBoxContainer/Button.pressed.connect(_on_continue_pressed)
	$Hud/LoseScreen/VBoxContainer/Button.pressed.connect(_on_try_again_pressed)

func _on_continue_pressed() -> void:
	get_tree().paused = false
	# For now just reload the scene — level select comes later
	get_tree().reload_current_scene()

func _on_try_again_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
