extends RefCounted
## The balance runs (#38, tools/balance_play.gd): the same seed gives the same report twice, and a run that
## goes broke or stalls is reported, not a crash. Uses 1-year runs; the 10-year runs are `python tools/balance.py`.

const Play := preload("res://tools/balance_play.gd")


static func run(check: Callable) -> void:
	var first: Dictionary = Play.play("mixed", 1)
	var second: Dictionary = Play.play("mixed", 1)
	check.call(first["rows"].size() == 1, "balance: a 1-year run reports one row")
	check.call(first["rows"] == second["rows"] and first["hash"] == second["hash"], "balance: the same seed gives an identical report twice")
	var row: Array = first["rows"][0]
	check.call(int(row[0]) == 1 and int(row[2]) > 0 and int(row[3]) >= 1, "balance: the row holds year, funds, people and stars")
	var other: Dictionary = Play.play("mixed", 1, 7)
	check.call(other["rows"].size() == 1, "balance: another seed also reports")

	# Only the lobby can be afforded: running costs take the funds below zero, so the run ends bankrupt (a stalled run also passes).
	var poor: Dictionary = Play.play("offices", 3, Play.SEED, 665000)
	var rows: Array = poor["rows"]
	check.call(rows.size() >= 1 and rows.size() <= 3, "balance: a broke run still reports its years")
	var status: String = rows[rows.size() - 1][4]
	check.call(status == "bankrupt" or status == "stalled", "balance: a broke run is reported as bankrupt or stalled, not ok (%s)" % status)
	if status == "bankrupt":
		check.call(int(rows[rows.size() - 1][1]) < 0, "balance: a bankrupt run's last row shows funds below zero")
