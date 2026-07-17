# pause_menu.gd
# Simple pause menu. ESC to toggle pause.
# Resume, Stage Select, Main Menu, Quit.
extends Control

const ARENA_SELECT = "res://level/arena_select.tscn"
const MAIN_MENU = "res://ui/main_menu.tscn"

@onready var resume_button: Button = $PanelContainer/VBoxContainer/ResumeButton
@onready var stage_select_button: Button = $PanelContainer/VBoxContainer/StageSelectButton
@onready var main_menu_button: Button = $PanelContainer/VBoxContainer/MainMenuButton
@onready var quit_button: Button = $PanelContainer/VBoxContainer/QuitButton

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	resume_button.pressed.connect(_on_resume_pressed)
	stage_select_button.pressed.connect(_on_stage_select_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

func _unhandled_input(event: InputEvent) -> void:
	if GameState.game_over:
		return
	if event.is_action_pressed("ui_cancel"):
		if get_tree().paused:
			_on_resume_pressed()
		else:
			_pause()
func _pause() -> void:
	visible = true
	get_tree().paused = true

func _on_resume_pressed() -> void:
	visible = false
	get_tree().paused = false

func _on_stage_select_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(ARENA_SELECT)

func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU)

func _on_quit_pressed() -> void:
	get_tree().quit()
