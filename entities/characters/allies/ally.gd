# Ally.gd
# Extends AICharacter — the player's team. Targets enemies; falls back
# to chaos once that class exists. is_focus is a soft preference for
# whichever enemy is flagged is_target — if none exist, it falls
# through to the nearest regular enemy like a normal Ally would.
extends AICharacter
class_name Ally

@export_group("Focus")
@export var is_focus: bool = false

func _is_valid_target(body: Node) -> bool:
	if body is Chaos and body.is_phantom:
		return false
	return body is Enemy or body is Chaos

func _get_target_priority(body: Node) -> int:
	if is_focus and body is Enemy and body.is_target:
		return 0
	if body is Enemy:
		return 1
	return 2  # Chaos
