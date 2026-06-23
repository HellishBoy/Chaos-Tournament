# RoundManager.gd
# Handles lives, respawning, and win/lose conditions for a level.
# Place as a child node in each level scene.
extends Node
class_name RoundManager

# ── Win Conditions ────────────────────────────────────────────────

enum WinCondition {
	ELIMINATION,    # Deplete all Main enemy lives
	# SURVIVAL,     # Hold out until timer runs out
	# CAPTURE_FLAG, # Capture and hold a point
}

# ── Exports ──────────────────────────────────────────────────────

@export var win_condition: WinCondition = WinCondition.ELIMINATION
@export var player_lives: int = 3
@export var respawn_delay: float = 2.0

@export_group("Spawn Points")
@export var player_spawn: Marker2D

@export_group("UI")
@export var win_screen: Control
@export var lose_screen: Control

# ── State ────────────────────────────────────────────────────────

var _player_lives_remaining: int = 0
var _enemy_lives: Dictionary = {}   # Enemy node -> lives remaining
var _main_enemies: Array = []       # Only main enemies — tracked for win condition
var _minion_enemies: Array = []     # Minions — respawn but never trigger win

var _player: Player = null

# ── Ready ────────────────────────────────────────────────────────

func _ready() -> void:
	await owner.ready

	_player = get_tree().get_first_node_in_group("player") as Player
	var all_enemies = get_tree().get_nodes_in_group("enemy")

	assert(_player != null, "RoundManager: No node in group 'player' found.")
	assert(player_spawn != null, "RoundManager: player_spawn Marker2D not assigned.")

	# Sort enemies into main and minion
	for enemy in all_enemies:
		if enemy.spawn_point == null:
			push_warning("RoundManager: " + enemy.name + " has no spawn_point assigned.")
		if enemy.is_main_enemy:
			_main_enemies.append(enemy)
		else:
			_minion_enemies.append(enemy)

	# Set lives per enemy from their own export
	_player_lives_remaining = player_lives
	for enemy in all_enemies:
		_enemy_lives[enemy] = enemy.lives

	# Connect death signals
	_player.health.died.connect(_on_player_died)
	for enemy in all_enemies:
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
		# Enemy is permanently out
		_enemy_lives.erase(enemy)
		if enemy.is_main_enemy:
			_main_enemies.erase(enemy)
		else:
			_minion_enemies.erase(enemy)
		_check_win_condition()
	else:
		# Enemy still has lives — respawn
		var spawn: Marker2D = enemy.spawn_point
		if spawn == null:
			push_warning("RoundManager: " + enemy.name + " has no spawn_point, can't respawn.")
			return
		_respawn_later(enemy, spawn)

# ── Win Condition Check ───────────────────────────────────────────

func _check_win_condition() -> void:
	match win_condition:
		WinCondition.ELIMINATION:
			# Win when all main enemies are permanently out
			if _main_enemies.is_empty():
				_trigger_win()
		# WinCondition.SURVIVAL:
		#     pass  # Handled by a timer elsewhere
		# WinCondition.CAPTURE_FLAG:
		#     pass  # Handled by flag node elsewhere

# ── Respawn ───────────────────────────────────────────────────────

func _respawn_later(character: Node, spawn: Marker2D) -> void:
	await get_tree().create_timer(respawn_delay).timeout
	if not is_instance_valid(character):
		return
	_respawn(character, spawn)

func _respawn(character: Node, spawn: Marker2D) -> void:
	character.global_position = spawn.global_position

	if character is Enemy:
		var dir: Vector2 = character._facing_to_vector(character.initial_facing)
		character.last_direction = dir
		character.rotation = dir.angle()
		character.target = null
		character.ai_state = Enemy.AIState.IDLE

	character.health.current_hp = character.health.max_hp
	character.health._invincible = false
	character.health._invincibility_timer = 0.0
	character.health.emit_signal("damaged", 0, character.health.current_hp)

	character.velocity = Vector2.ZERO
	character.knockback_component._active = false
	character.knockback_component._tier = "none"

	character.current_weapon = null
	character._update_weapon_visuals()
	character._cancel_into_idle()

	if character is Player:
		var hud := get_tree().get_first_node_in_group("hud") as HUD
		if hud:
			hud.refresh()
		character.is_dodging = false
		character.is_tossing = false
		character._reset_attacks()

	# Restore alive state — re-enables collision and restores color
	character._apply_alive_state()
	character.set_physics_process(true)
	character.set_process(true)

	if character is Enemy:
		character._find_player_target()

# ── Win / Lose ────────────────────────────────────────────────────

func _trigger_win() -> void:
	if win_screen:
		win_screen.visible = true
	get_tree().paused = true

func _trigger_lose() -> void:
	if lose_screen:
		lose_screen.visible = true
	get_tree().paused = true
