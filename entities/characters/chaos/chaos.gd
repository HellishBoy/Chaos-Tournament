# Chaos.gd
# Extends AICharacter — the wildcard team. Targets anyone (Player, Ally,
# or Enemy) and cycles on a timer rather than fighting to the death with
# one target. Tracked by RoundManager like any other fighter, but never
# affects win/lose conditions.
extends AICharacter
class_name Chaos

const TARGET_CLASSES: Array[String] = ["player", "ally", "enemy"]
const FAIRNESS_WINDOW: int = 4

var _recent_target_classes: Array[String] = []

# ── Target Rules ─────────────────────────────────────────────────
# Chaos bypasses the shared nearest/priority system entirely — no
# tiers, no distance weighting, just a fair dice roll on a timer.

func _is_valid_target(body: Node) -> bool:
	return body is Player or body is Ally or body is Enemy

# Ignore proximity-driven target switching completely — Chaos's target
# only ever changes via the roll timer in _acquire_target().
func _on_target_entered(_body: Node2D) -> void:
	pass

func _on_target_exited(_body: Node2D) -> void:
	pass

func _acquire_target() -> void:
	var chosen_class := _roll_target_class()
	var candidates := _get_living_members_of_class(chosen_class)

	# That class currently has nobody alive — fall back to whichever
	# other class does, rather than leaving Chaos with no target.
	if candidates.is_empty():
		for fallback_class in TARGET_CLASSES:
			if fallback_class == chosen_class:
				continue
			candidates = _get_living_members_of_class(fallback_class)
			if not candidates.is_empty():
				chosen_class = fallback_class
				break

	if candidates.is_empty():
		target = null
		ai_state = AIState.IDLE
		return

	target = candidates[randi() % candidates.size()]
	ai_state = AIState.ACTIVE
	_target_hold_timer = target_hold_time
	_record_target_class(chosen_class)

func _get_living_members_of_class(class_label: String) -> Array:
	var result: Array = []
	for node in get_tree().get_nodes_in_group("contestant"):
		if node == self or not is_instance_valid(node):
			continue
		if node.is_dead:
			continue
		if _get_class_label(node) == class_label:
			result.append(node)
	return result

func _get_class_label(body: Node) -> String:
	if body is Player:
		return "player"
	if body is Ally:
		return "ally"
	if body is Enemy:
		return "enemy"
	return ""

# True random, with two fairness rules layered on top:
#   1. Can't repeat the same class immediately (no back-to-back rolls)
#   2. If a class hasn't appeared at all across the last 4 rolls, the
#      next roll is forced to that class — otherwise Chaos could keep
#      alternating between just two classes forever and starve the third
func _roll_target_class() -> String:
	if _recent_target_classes.size() >= FAIRNESS_WINDOW:
		for class_label in TARGET_CLASSES:
			if not _recent_target_classes.has(class_label):
				return class_label

	var last_class: String = _recent_target_classes.back() if not _recent_target_classes.is_empty() else ""
	var pool: Array[String] = []
	for class_label in TARGET_CLASSES:
		if class_label != last_class:
			pool.append(class_label)

	return pool[randi() % pool.size()]

func _record_target_class(class_label: String) -> void:
	_recent_target_classes.append(class_label)
	if _recent_target_classes.size() > FAIRNESS_WINDOW:
		_recent_target_classes.pop_front()
