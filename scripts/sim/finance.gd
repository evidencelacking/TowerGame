class_name Finance
extends RefCounted
## Read-only finance report (5.10): ledger lines grouped by quarter and kind, and by ref within
## a kind. Pure functions of the ledger, so the window can never disagree with the balance. Holds
## no state and is not saved. Quarter 0 starts at tick 0 (it holds the opening line); quarter n
## starts at the tick the clock's n-th quarter_started fires.

const ClockScript := preload("res://scripts/sim/clock.gd")
const LedgerScript := preload("res://scripts/sim/ledger.gd")

## Display order of the line kinds. Covers every Ledger kind once (a test checks).
const KINDS: Array[int] = [
	LedgerScript.OPENING, LedgerScript.INCOME, LedgerScript.SALE, LedgerScript.REFUND,
	LedgerScript.CHARGE, LedgerScript.PAYOUT, LedgerScript.COST,
]
const LABELS: Dictionary = {
	LedgerScript.OPENING: "Opening funds",
	LedgerScript.INCOME: "Rent",
	LedgerScript.SALE: "Condo sales",
	LedgerScript.REFUND: "Adjustments",
	LedgerScript.CHARGE: "Construction",
	LedgerScript.PAYOUT: "Bulldoze payouts",
	LedgerScript.COST: "Running costs",
}


## Ticks in one quarter: the days of six periods.
static func ticks_per_quarter() -> int:
	var day := 0
	for period in ClockScript.PERIODS:
		day += ClockScript.period_ticks(period)
	return day * ClockScript.DAYS_PER_QUARTER


## The quarter (0 for the first) a tick falls in.
static func quarter_of(at_tick: int) -> int:
	return at_tick / ticks_per_quarter()


## "Y1 Q2" for a quarter index.
static func quarter_label(quarter: int) -> String:
	return "Y%d Q%d" % [quarter / ClockScript.QUARTERS_PER_YEAR + 1, quarter % ClockScript.QUARTERS_PER_YEAR + 1]


## Kind -> dollars for one quarter. Only kinds with lines appear.
static func totals(ledger: LedgerScript, quarter: int) -> Dictionary:
	var sums: Dictionary = {}
	for line: Array in ledger.lines:
		if quarter_of(line[0]) == quarter:
			sums[line[2]] = int(sums.get(line[2], 0)) + int(line[1])
	return sums


## Ref -> dollars for one kind in one quarter (a room id, or whatever the kind's ref means).
static func by_ref(ledger: LedgerScript, quarter: int, kind: int) -> Dictionary:
	var sums: Dictionary = {}
	for line: Array in ledger.lines:
		if line[2] == kind and quarter_of(line[0]) == quarter:
			sums[line[3]] = int(sums.get(line[3], 0)) + int(line[1])
	return sums


## Net change of the balance in one quarter.
static func net(ledger: LedgerScript, quarter: int) -> int:
	var total := 0
	for amount: int in totals(ledger, quarter).values():
		total += amount
	return total
