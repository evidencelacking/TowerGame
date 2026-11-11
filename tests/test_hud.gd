extends RefCounted
## HUD formatting tests (the static helper only; no scene needed).

const Hud := preload("res://scripts/view/hud.gd")


static func run(check: Callable) -> void:
	check.call(Hud.format_money(0) == "$0", "zero dollars shows as $0")
	check.call(Hud.format_money(2000000) == "$2,000,000", "the starting funds show with separators")
	check.call(Hud.format_money(-500) == "-$500", "a negative balance shows a leading minus")
	check.call(Hud.format_money(1000) == "$1,000", "exactly four digits get one separator")
