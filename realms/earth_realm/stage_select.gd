# stage_select.gd
# Level selection screen for Sandbox Arena.
# Shows 10 stages in 2 columns. Level 1 unlocked, rest greyed out for now.
extends Control

# ── Level Data ───────────────────────────────────────────────────

const STAGES = [
	{ "label": "Stage 1", "scene": "res://realms/earth_realm/0_sandbox_arena/sandbox_stage1.tscn", "unlocked": true },
	{ "label": "Stage 2", "scene": "", "unlocked": false },
	{ "label": "Stage 3", "scene": "", "unlocked": false },
	{ "label": "Stage 4", "scene": "", "unlocked": false },
	{ "label": "Stage 5", "scene": "", "unlocked": false },
	{ "label": "Stage 6", "scene": "", "unlocked": false },
	{ "label": "Stage 7", "scene": "", "unlocked": false }
]

# ── Node References ──────────────────────────────────────────────

@onready var column_left: VBoxContainer = $MarginContainer/HBoxContainer/ColumnLeft
@onready var column_right: VBoxContainer = $MarginContainer/HBoxContainer/ColumnRight
@onready var back_button: Button = $BackButton

# ── Ready ────────────────────────────────────────────────────────

func _ready() -> void:
	_build_level_buttons()
	back_button.pressed.connect(_on_back_pressed)

func _build_level_buttons() -> void:
	for i in STAGES.size():
		var data: Dictionary = STAGES[i]
		var btn := Button.new()
		btn.text = data["label"]
		btn.custom_minimum_size = Vector2(160, 40)

		if data["unlocked"]:
			btn.pressed.connect(_on_level_pressed.bind(data["scene"]))
		else:
			btn.disabled = true
			btn.modulate = Color(0.4, 0.4, 0.4, 1.0)

		# First 5 go in left column, next 5 in right column
		if i < 5:
			column_left.add_child(btn)
		else:
			column_right.add_child(btn)

# ── Button Callbacks ─────────────────────────────────────────────

func _on_level_pressed(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)

func _on_back_pressed() -> void:
	# Placeholder — will go to realm select later
	pass
