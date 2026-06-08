# RoundManager.gd
# Handles lives, respawning, and win/lose conditions for a level.
# Place as a child node in each level scene.
# Each level exposes spawn points and lives counts — RoundManager does the rest.
extends Node
class_name RoundManager

# ── Exports ──────────────────────────────────────────────────────

@export var player_lives: int = 3
@export var enemy_lives: int = 3
@export var respawn_delay: float = 2.0

@export_group("Spawn Points")
@export var player_spawn: Marker2D
@export var enemy_spawns: Array[Marker2D] = []

@export_group("UI")
@export var win_screen: Control
@export var lose_screen: Control

# ── State ────────────────────────────────────────────────────────

var _player_lives_remaining: int = 0
var _enemy_lives: Dictionary = {}  # Enemy node -> lives remaining

var _player: Player = null
var _enemies: Array = []

# ── Ready ────────────────────────────────────────────────────────

func _ready() -> void:
	# Find player and enemies in the Contestants group
	await owner.ready

	_player = get_tree().get_first_node_in_group("player") as Player
	_enemies = get_tree().get_nodes_in_group("enemy")

	assert(_player != null, "RoundManager: No node in group 'player' found.")
	assert(player_spawn != null, "RoundManager: player_spawn Marker2D not assigned.")
	assert(not enemy_spawns.is_empty(), "RoundManager: No enemy_spawns assigned.")

	# Set lives
	_player_lives_remaining = player_lives
	for i in _enemies.size():
		_enemy_lives[_enemies[i]] = enemy_lives

	# Connect death signals
	_player.health.died.connect(_on_player_died)
	for enemy in _enemies:
		enemy.health.died.connect(_on_enemy_died.bind(enemy))

	# Hide screens
	if win_screen:
		win_screen.visible = false
	if lose_screen:
		lose_screen.visible = false

# ── Death Handlers ────────────────────────────────────────────────

func _on_player_died() -> void:
	_player_lives_remaining -= 1
	if _player_lives_remaining <= 0:
		_trigger_lose()
	else:
		_respawn_later(_player, player_spawn)

func _on_enemy_died(enemy: Node) -> void:
	_enemy_lives[enemy] -= 1
	if _enemy_lives[enemy] <= 0:
		_enemy_lives.erase(enemy)
		_enemies.erase(enemy)
		# Check if all enemies are permanently out
		if _enemies.is_empty():
			_trigger_win()
	else:
		# Find which spawn point this enemy was assigned
		var index := _get_enemy_index(enemy)
		var spawn := enemy_spawns[index % enemy_spawns.size()]
		_respawn_later(enemy, spawn)

# ── Respawn ───────────────────────────────────────────────────────

func _respawn_later(character: Node, spawn: Marker2D) -> void:
	await get_tree().create_timer(respawn_delay).timeout
	if not is_instance_valid(character):
		return
	_respawn(character, spawn)

func _respawn(character: Node, spawn: Marker2D) -> void:
	# Reset position
	character.global_position = spawn.global_position
	# Reset facing to initial direction
	if character is Enemy:
		var dir: Vector2 = character._facing_to_vector(character.initial_facing)
		character.last_direction = dir
		character.rotation = dir.angle()
		character.target = null
		character.ai_state = Enemy.AIState.IDLE

	# Reset health to full
	character.health.current_hp = character.health.max_hp
	character.health._invincible = false
	character.health._invincibility_timer = 0.0

	# Re-emit a fake "healed" signal so health bar updates
	character.health.emit_signal("damaged", 0, character.health.current_hp)

	# Reset velocity and knockback
	character.velocity = Vector2.ZERO
	character.knockback_component._active = false
	character.knockback_component._tier = "none"

	# Weapon is dropped on death by existing _on_died logic
	# so just make sure current_weapon is null and visuals are updated
	character.current_weapon = null
	character._update_weapon_visuals()

	# Snap animation back to idle
	character._cancel_into_idle()

	# Refresh HUD if player
	if character is Player:
		var hud := get_tree().get_first_node_in_group("hud") as HUD
		if hud:
			hud.refresh()

	if character is Player:
		character.is_dodging = false
		character.is_tossing = false
		character._reset_attacks()
			
	character.visible = true
	character.set_physics_process(true)
	character.set_process(true)

# ── Win / Lose ────────────────────────────────────────────────────

func _trigger_win() -> void:
	if win_screen:
		win_screen.visible = true
	get_tree().paused = true

func _trigger_lose() -> void:
	if lose_screen:
		lose_screen.visible = true
	get_tree().paused = true

# ── Helpers ───────────────────────────────────────────────────────

func _get_enemy_index(enemy: Node) -> int:
	for i in range(_enemies.size()):
		if _enemies[i] == enemy:
			return i
	return 0
