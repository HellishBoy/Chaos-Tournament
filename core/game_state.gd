# game_state.gd
# Global autoload singleton for storing game state across scenes.
# Add this to Project > Project Settings > Autoload as "GameState".
extends Node

# ── Navigation State ─────────────────────────────────────────────

# Set when player selects an arena. Used by stages and pause menu to navigate back.
var stage_select_path: String = ""

# Set when player selects a realm. Used by arena select to navigate back.
var arena_select_path: String = ""
