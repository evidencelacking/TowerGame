extends SceneTree
## Daily totals on the mixed tower (#459): money earned, complaints and grades, per sim day. The slow cadence must keep
## these within a stated tolerance of the per-tick behaviour; tests/test_slow_cadence.gd pins the per-tick reference
## (measured on main before the change) and checks the cadence against it.
##   godot --headless --path . --script res://tools/cadence_metrics.gd
## prints one line per day, the COLUMNS in order.

const Mixed := preload("res://tools/bench_mixed.gd")
const LedgerScript := preload("res://scripts/sim/ledger.gd")
const GradesScript := preload("res://scripts/sim/grades.gd")
const DAY_TICKS := 2550

const COLUMNS: Array[String] = ["rent", "hotel", "sale", "shop", "complaints", "grade_a", "grade_b", "grade_c", "quality"]


func _initialize() -> void:
	for row in measure(3):
		var text := ""
		for value: int in row:
			text += str(value) + " "
		print(text.strip_edges())
	quit(0)


## One row of ints (COLUMNS) per day over the mixed tower from its start. Income is what the ledger took that day;
## complaints (every reason on every graded room), grades and quality are read at the day's end.
static func measure(days: int) -> Array[Array]:
	var t := Mixed.build(42)
	var rows: Array[Array] = []
	var seen := t.ledger.lines.size()
	for _day in days:
		for _i in DAY_TICKS:
			t.step()
		var sums := {LedgerScript.INCOME: 0, LedgerScript.HOTEL: 0, LedgerScript.SALE: 0, LedgerScript.SHOP: 0}
		for n in range(seen, t.ledger.lines.size()):
			var line: Array = t.ledger.lines[n]
			if sums.has(line[2]):
				sums[line[2]] += line[1]
		seen = t.ledger.lines.size()
		var complaints := 0
		var grades := [0, 0, 0]
		var quality := 0
		for id in t.rooms.room_ids():
			var grade := t.grade(id)
			if grade == GradesScript.GRADE_NONE:
				continue
			complaints += t.complaints.reasons(id).size()
			grades[grade] += 1
			quality += t.quality(id)
		var row: Array = [sums[LedgerScript.INCOME], sums[LedgerScript.HOTEL], sums[LedgerScript.SALE], sums[LedgerScript.SHOP], complaints, grades[0], grades[1], grades[2], quality]
		rows.append(row)
	return rows
