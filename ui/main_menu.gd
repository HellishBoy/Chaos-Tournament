# main_menu.gd
# Main menu screen.
# New Game goes to realm select. Load Game is a placeholder for now.
extends Control

# ── Node References ──────────────────────────────────────────────

@onready var new_game_button: Button = $MarginContainer/VBoxContainer/NewGameButton
@onready var load_game_button: Button = $MarginContainer/VBoxContainer/LoadGameButton
@onready var quit_button: Button = $MarginContainer/VBoxContainer/QuitButton

# ── Ready ────────────────────────────────────────────────────────

func _ready() -> void:
	new_game_button.pressed.connect(_on_new_game_pressed)
	load_game_button.pressed.connect(_on_load_game_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

# ── Button Callbacks ─────────────────────────────────────────────

func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file("res://level/arena_select.tscn")

func _on_load_game_pressed() -> void:
	# Placeholder — save system not implemented yet
	pass

func _on_quit_pressed() -> void:
	get_tree().quit()
