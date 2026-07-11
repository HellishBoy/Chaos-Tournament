# arena_select.gd
# Arena selection screen for Earth Realm.
# Shows 10 arenas in 2 columns. Only Sandbox Arena unlocked for now.
extends Control

# ── Arena Data ───────────────────────────────────────────────────

const ARENAS = [
	{ "label": "Junkyard", "scene": "res://realms/earth_realm/1_junkyard_arena/stage_select.tscn", "stage_select": "res://realms/earth_realm/1_junkyard_arena/stage_select.tscn", "unlocked": true },
	{ "label": "City", "scene": "", "stage_select": "", "unlocked": false },
	{ "label": "Military", "scene": "", "stage_select": "", "unlocked": false },
	{ "label": "Forest", "scene": "", "stage_select": "", "unlocked": false },
	{ "label": "Sea", "scene": "", "stage_select": "", "unlocked": false },
	{ "label": "Desert", "scene": "", "stage_select": "", "unlocked": false },
	{ "label": "Arctic", "scene": "", "stage_select": "", "unlocked": false },
	{ "label": "Secret Base", "scene": "", "stage_select": "", "unlocked": false },
	{ "label": "Cave", "scene": "", "stage_select": "", "unlocked": false },
	{ "label": "Volcanic", "scene": "", "stage_select": "", "unlocked": false },
]

# ── Node References ──────────────────────────────────────────────

@onready var column_left: VBoxContainer = $MarginContainer/HBoxContainer/ColumnLeft
@onready var column_right: VBoxContainer = $MarginContainer/HBoxContainer/ColumnRight
@onready var back_button: Button = $BackButton

# ── Ready ────────────────────────────────────────────────────────

func _ready() -> void:
	_build_arena_buttons()
	back_button.pressed.connect(_on_back_pressed)

func _build_arena_buttons() -> void:
	for i in ARENAS.size():
		var data: Dictionary = ARENAS[i]
		var btn := Button.new()
		btn.text = data["label"]
		btn.custom_minimum_size = Vector2(150, 30)

		if data["unlocked"]:
			btn.pressed.connect(_on_arena_pressed.bind(data["scene"], data["stage_select"]))
		else:
			btn.disabled = true
			btn.modulate = Color(0.4, 0.4, 0.4, 1.0)

		if i < 5:
			column_left.add_child(btn)
		else:
			column_right.add_child(btn)

# ── Button Callbacks ─────────────────────────────────────────────

func _on_arena_pressed(scene_path: String, stage_select_path: String) -> void:
	GameState.stage_select_path = stage_select_path
	get_tree().change_scene_to_file(scene_path)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://realms/realm_select.tscn")
