# realm_select.gd
# Realm selection screen.
# Shows available realms — Earth Realm unlocked, others teased as ???.
extends Control

# ── Realm Data ───────────────────────────────────────────────────

const REALMS = [
	{ "label": "Earth Realm", "scene": "res://realms/earth_realm/arena_select.tscn", "unlocked": true },
	{ "label": "???", "scene": "", "unlocked": false },
	{ "label": "???", "scene": "", "unlocked": false },
	{ "label": "???", "scene": "", "unlocked": false },
]

# ── Node References ──────────────────────────────────────────────

@onready var realm_container: VBoxContainer = $MarginContainer/RealmContainer
@onready var back_button: Button = $BackButton

# ── Ready ────────────────────────────────────────────────────────

func _ready() -> void:
	_build_realm_buttons()
	back_button.pressed.connect(_on_back_pressed)

func _build_realm_buttons() -> void:
	for data in REALMS:
		var btn := Button.new()
		btn.text = data["label"]
		btn.custom_minimum_size = Vector2(200, 50)

		if data["unlocked"]:
			btn.pressed.connect(_on_realm_pressed.bind(data["scene"]))
		else:
			btn.disabled = true
			btn.modulate = Color(0.4, 0.4, 0.4, 1.0)

		realm_container.add_child(btn)

# ── Button Callbacks ─────────────────────────────────────────────

func _on_realm_pressed(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
