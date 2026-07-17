# game_state.gd
# Global autoload singleton for storing game state across scenes.
# Add this to Project > Project Settings > Autoload as "GameState".
extends Node

# ── Navigation State ─────────────────────────────────────────────

# Set when player selects an arena. Used by stages and pause menu to navigate back.
var stage_select_path: String = ""

# Set when player selects a realm. Used by arena select to navigate back.
var arena_select_path: String = ""

# True once a round has ended (win or lose) — lets other UI (like the
# pause menu) know not to respond to pause/unpause input.
var game_over: bool = false
