extends SceneTree
## Plays the scripted balance strategies headless and prints one line per strategy and year (#38):
##   godot --headless --path . --script res://tools/balance_run.gd -- [strategy ...] [years=10]
## Lines: `ROW|strategy|year|funds|people|stars|status`, `NOTE|strategy|text`, `DONE`. tools/balance.py runs it under a
## time limit and writes docs/balance.md. Every loop is bounded by its count.

const Play := preload("res://tools/balance_play.gd")


func _init() -> void:
	var years: int = Play.YEARS
	var names: Array[String] = []
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("years="):
			years = clampi(int(a.substr(6)), 1, Play.YEARS)
		elif Play.STRATEGIES.has(a):
			names.append(a)
	if names.is_empty():
		names = Play.STRATEGIES.duplicate()
	for strategy in names:
		var result: Dictionary = Play.play(strategy, years)
		for row: Array in result["rows"]:
			print("ROW|%s|%d|%d|%d|%d|%s" % [strategy, row[0], row[1], row[2], row[3], row[4]])
		if OS.get_cmdline_user_args().has("trace"):
			for line: String in result["trace"]:
				print("TRACE|%s|%s" % [strategy, line])
		for note: String in result["notes"]:
			print("NOTE|%s|%s" % [strategy, note])
	print("DONE")
	quit(0)
