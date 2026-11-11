class_name Tower
extends RefCounted
## Placeholder for the tower simulation state. Integers only; see CLAUDE.md.

var tick: int = 0


func step() -> void:
	tick += 1
