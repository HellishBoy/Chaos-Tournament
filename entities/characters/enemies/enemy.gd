# Enemy.gd
# Extends AICharacter — the enemy team. Targets players first, then
# allies. (Chaos becomes priority 2 once that class exists.)
extends AICharacter
class_name Enemy

@export_group("Round")
@export var is_main_enemy: bool = false

func _is_valid_target(body: Node) -> bool:
	return body is Player or body is Ally or body is Chaos

func _get_target_priority(body: Node) -> int:
	if body is Player:
		return 0
	if body is Ally:
		return 1
	return 2  # Chaos
