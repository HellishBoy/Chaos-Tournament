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
@export var post_respawn_immortality: float = 0.8

@export_group("Spawn Points")
@export var player_spawn: Marker2D

@export_group("UI")
@export var win_screen: Control
@export var lose_screen: Control

# ── State ────────────────────────────────────────────────────────

var _player_lives_remaining: int = 0
var _enemy_lives: Dictionary = {}   # Enemy node -> lives remaining
var _ally_lives: Dictionary = {}    # Ally node -> lives remaining
var _chaos_lives: Dictionary = {}   # Chaos node -> lives remaining
var _main_enemies: Array = []       # Only main enemies — tracked for win condition
var _minion_enemies: Array = []     # Minions — respawn but never trigger win

var _player: Player = null

# ── Ready ────────────────────────────────────────────────────────

func _ready() -> void:
	await owner.ready

	_player = get_tree().get_first_node_in_group("player") as Player
	var all_enemies = get_tree().get_nodes_in_group("enemy")
	var all_allies = get_tree().get_nodes_in_group("ally")
	var all_chaos = get_tree().get_nodes_in_group("chaos")

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

	# Set lives per fighter from their own export (-1 = infinite)
	_player_lives_remaining = player_lives
	for enemy in all_enemies:
		_enemy_lives[enemy] = enemy.lives
	for ally in all_allies:
		if ally.spawn_point == null:
			push_warning("RoundManager: " + ally.name + " has no spawn_point assigned.")
		_ally_lives[ally] = ally.lives
	for chaos in all_chaos:
		if chaos.spawn_point == null:
			push_warning("RoundManager: " + chaos.name + " has no spawn_point assigned.")
		_chaos_lives[chaos] = chaos.lives

	# Connect death signals
	_player.health.died.connect(_on_player_died)
	for enemy in all_enemies:
		enemy.health.died.connect(_on_enemy_died.bind(enemy))
	for ally in all_allies:
		ally.health.died.connect(_on_ally_died.bind(ally))
	for chaos in all_chaos:
		chaos.health.died.connect(_on_chaos_died.bind(chaos))

	# Hide screens
	if win_screen:
		win_screen.visible = false
	if lose_screen:
		lose_screen.visible = false

# ── Lives Helper ──────────────────────────────────────────────────

# Decrements a fighter's remaining lives, respecting -1 as "infinite"
# (never runs out). Returns true if this fighter is now permanently out.
func _consume_life(lives_dict: Dictionary, fighter: Node) -> bool:
	if lives_dict[fighter] == -1:
		return false
	lives_dict[fighter] -= 1
	if lives_dict[fighter] <= 0:
		lives_dict.erase(fighter)
		return true
	return false

# ── Death Handlers ────────────────────────────────────────────────

func _on_player_died() -> void:
	_player_lives_remaining -= 1
	if _player_lives_remaining <= 0:
		_trigger_lose()
	else:
		_respawn_later(_player, player_spawn)

func _on_enemy_died(enemy: Node) -> void:
	if _consume_life(_enemy_lives, enemy):
		# Enemy is permanently out
		if enemy.is_main_enemy:
			_main_enemies.erase(enemy)
		else:
			_minion_enemies.erase(enemy)
		_check_win_condition()
	else:
		var spawn: Marker2D = enemy.spawn_point
		if spawn == null:
			push_warning("RoundManager: " + enemy.name + " has no spawn_point, can't respawn.")
			return
		_respawn_later(enemy, spawn)

func _on_ally_died(ally: Node) -> void:
	if not _consume_life(_ally_lives, ally):
		var spawn: Marker2D = ally.spawn_point
		if spawn == null:
			push_warning("RoundManager: " + ally.name + " has no spawn_point, can't respawn.")
			return
		_respawn_later(ally, spawn)
	# Permanently out — no win/lose condition tied to allies

func _on_chaos_died(chaos: Node) -> void:
	if not _consume_life(_chaos_lives, chaos):
		var spawn: Marker2D = chaos.spawn_point
		if spawn == null:
			push_warning("RoundManager: " + chaos.name + " has no spawn_point, can't respawn.")
			return
		_respawn_later(chaos, spawn)
	# Chaos never affects win/lose conditions either way

# ── Win Condition Check ───────────────────────────────────────────

func _check_win_condition() -> void:
	match win_condition:
		WinCondition.ELIMINATION:
			# Win when all main enemies are permanently out
			if _main_enemies.is_empty():
				_trigger_win()

# ── Respawn ───────────────────────────────────────────────────────

func _respawn_later(character: Node, spawn: Marker2D) -> void:
	# Stay as a visible black corpse at the death spot for a moment...
	await get_tree().create_timer(respawn_delay * 0.75).timeout
	if not is_instance_valid(character):
		return
	# ...then vanish entirely while "traveling" to the spawn point...
	character.visible = false
	await get_tree().create_timer(respawn_delay * 0.20).timeout
	if not is_instance_valid(character):
		return
	character.global_position = spawn.global_position
	# ...then a short beat before popping back into existence, fully alive.
	await get_tree().create_timer(respawn_delay * 0.05).timeout
	if not is_instance_valid(character):
		return
	_respawn(character, spawn)

func _respawn(character: Node, spawn: Marker2D) -> void:
	character.visible = true
	character.global_position = spawn.global_position

	if character is AICharacter:
		var dir: Vector2 = character._facing_to_vector(character.initial_facing)
		character.last_direction = dir
		character.rotation = dir.angle()
		character.target = null
		character.ai_state = AICharacter.AIState.IDLE

	character.health.current_hp = character.health.max_hp
	character.health._invincible = false
	character.health._invincibility_timer = 0.0
	character.health.emit_signal("damaged", 0, character.health.current_hp)

	character.velocity = Vector2.ZERO
	character.impact_component.reset()
	character.status_effect_component.clear_all()
	character._stamina = character.stats.stamina_max

	character.current_weapon = null
	character._update_weapon_visuals()
	character._cancel_into_idle()

	if character is Player:
		var hud := get_tree().get_first_node_in_group("hud") as HUD
		if hud:
			hud.refresh()
			hud.refresh_dodge(character._stamina, character.stats.stamina_max, character.stats.stamina_per_dodge)
		character.is_dodging = false
		character.is_tossing = false
		character._reset_attacks()

	# Restore alive state — re-enables collision and restores color
	character._apply_alive_state()
	if character is Player:
		character.set_invincible(false)
	character.set_physics_process(true)
	character.set_process(true)

	if character is AICharacter:
		character._acquire_target()
		
	character.health.immortal = true
	_end_immortality_later(character)

func _end_immortality_later(character: Node) -> void:
	await get_tree().create_timer(post_respawn_immortality).timeout
	if is_instance_valid(character):
		character.health.immortal = false

# ── Win / Lose ────────────────────────────────────────────────────

func _trigger_win() -> void:
	if win_screen:
		win_screen.visible = true
	get_tree().paused = true

func _trigger_lose() -> void:
	if lose_screen:
		lose_screen.visible = true
	get_tree().paused = true
