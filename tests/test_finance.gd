extends RefCounted
## Finance window tests (5.10): ledger lines group by quarter and kind, the window totals equal
## the ledger sums for a scripted quarter, condo sales stay apart from rent, and opening the
## window never changes the sim.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Ledger := preload("res://scripts/sim/ledger.gd")
const Finance := preload("res://scripts/sim/finance.gd")
const Hud := preload("res://scripts/view/hud.gd")
const TestRunningCosts := preload("res://tests/test_running_costs.gd")
const TestPersonWindow := preload("res://tests/test_person_window.gd")
const RunningCosts := preload("res://scripts/sim/running_costs.gd")

const QUARTER_TICKS := 7650


## Sum of ledger lines of one kind in one quarter, worked out here from the raw lines.
static func _sum(t: TowerSim, kind: int, quarter: int) -> int:
	var total := 0
	for line: Array in t.ledger.lines:
		if line[2] == kind and line[0] / QUARTER_TICKS == quarter:
			total += line[1]
	return total


static func run(check: Callable) -> void:
	# Quarters and labels.
	check.call(Finance.ticks_per_quarter() == QUARTER_TICKS, "a quarter is three days of 2,550 ticks")
	check.call(Finance.quarter_of(0) == 0 and Finance.quarter_of(QUARTER_TICKS - 1) == 0, "ticks up to the quarter start are quarter 0")
	check.call(Finance.quarter_of(QUARTER_TICKS) == 1 and Finance.quarter_of(5 * QUARTER_TICKS) == 5, "the quarter start tick opens the next quarter")
	check.call(Finance.quarter_label(0) == "Y1 Q1" and Finance.quarter_label(4) == "Y2 Q1" and Finance.quarter_label(7) == "Y2 Q4", "quarter labels count years and quarters")
	var kinds: Dictionary = {}
	for kind in Finance.KINDS:
		kinds[kind] = true
	var all_labelled := true
	for kind in [Ledger.OPENING, Ledger.CHARGE, Ledger.REFUND, Ledger.PAYOUT, Ledger.INCOME, Ledger.COST, Ledger.SALE, Ledger.SHOP]:
		all_labelled = all_labelled and kinds.has(kind) and Finance.LABELS.has(kind)
	check.call(all_labelled and Finance.KINDS.size() == 8, "every ledger kind is listed once and labelled")

	# A scripted quarter: build in quarter 0, then the quarter start credits rent and charges costs.
	var t := TestRunningCosts._tower()
	t.tick = QUARTER_TICKS - 1  # the clock was set to the same point, so tick and clock agree
	t.step()
	check.call(t.clock.quarter_started and Finance.quarter_of(t.tick) == 1, "the scripted tick starts quarter 1")
	var costs := RunningCosts.quarterly_total(t.rooms, t.floors)
	var q0 := Finance.totals(t.ledger, 0)
	var q1 := Finance.totals(t.ledger, 1)
	check.call(q1.get(Ledger.INCOME, 0) == 20000 and q1.get(Ledger.COST, 0) == -costs, "quarter 1 shows rent $20,000 and running costs")
	check.call(q1.size() == 2, "quarter 1 has only rent and running costs")
	check.call(q0.has(Ledger.OPENING) and q0.has(Ledger.CHARGE) and not q0.has(Ledger.COST), "quarter 0 shows the opening funds and construction, no running costs")
	var grouped_ok := true
	for quarter in 2:
		for kind in Finance.KINDS:
			grouped_ok = grouped_ok and int(Finance.totals(t.ledger, quarter).get(kind, 0)) == _sum(t, kind, quarter)
	check.call(grouped_ok, "every kind's total equals the sum of its ledger lines in that quarter")
	check.call(Finance.net(t.ledger, 0) + Finance.net(t.ledger, 1) == t.ledger.balance, "the quarters' nets add up to the balance")
	check.call(Finance.net(t.ledger, 1) == 20000 - costs, "quarter 1's net is rent minus running costs")
	var rent_refs := Finance.by_ref(t.ledger, 1, Ledger.INCOME)
	var ref_total := 0
	for amount: int in rent_refs.values():
		ref_total += amount
	check.call(rent_refs.size() == 2 and ref_total == 20000, "rent groups by room: two offices, $20,000 together")
	check.call(Finance.by_ref(t.ledger, 1, Ledger.SALE).is_empty(), "no sales in quarter 1")

	# The window shows those same numbers and leaves the sim alone.
	var window := FinanceWindow.new()
	window.bind(t)
	var hash_before := t.state_hash()
	check.call(not window.is_open() and not window.panel.visible, "window: starts closed")
	window.toggle()
	check.call(window.is_open() and window.panel.visible and window.panel.title_text() == "Finances", "window: toggle opens it")
	var body := window.panel.body_text()
	check.call("Y1 Q2 (this quarter)" in body and "Y1 Q1" in body, "window: shows the current and the past quarter")
	check.call("  Rent: %s" % Hud.format_money(_sum(t, Ledger.INCOME, 1)) in body, "window: rent equals the ledger sum")
	check.call("  Running costs: %s" % Hud.format_money(_sum(t, Ledger.COST, 1)) in body, "window: running costs equal the ledger sum")
	check.call("  Construction: %s" % Hud.format_money(_sum(t, Ledger.CHARGE, 0)) in body, "window: construction equals the ledger sum")
	check.call("  Net: %s" % Hud.format_money(20000 - costs) in body, "window: the quarter's net is shown")
	check.call("Balance: %s" % Hud.format_money(t.ledger.balance) in body, "window: the balance matches the ledger")
	check.call(t.state_hash() == hash_before, "window: opening it leaves the sim hash unchanged")
	window.toggle()
	check.call(not window.is_open() and not window.panel.visible, "window: toggle closes it")

	# Only the last four quarters are listed.
	var long := TowerSim.new()
	long.tick = 9 * QUARTER_TICKS
	var lines := FinanceWindow.lines_for(long)
	var headers := 0
	for line in lines:
		if line.begins_with("Y"):
			headers += 1
	check.call(headers == FinanceWindow.QUARTERS_SHOWN, "window: lists the current and three past quarters")

	# Condo sales are their own kind, apart from rent.
	var sold := TestPersonWindow._fixture()
	var sale_quarter := Finance.quarter_of(sold.tick)
	var sales := Finance.totals(sold.ledger, sale_quarter)
	check.call(int(sales.get(Ledger.SALE, 0)) > 0 and not sales.has(Ledger.INCOME), "a condo sale is Condo sales, not rent")
	check.call(int(sales.get(Ledger.SALE, 0)) == _sum(sold, Ledger.SALE, sale_quarter), "condo sales equal the ledger sum")
	var sold_window := FinanceWindow.new()
	sold_window.bind(sold)
	sold_window.open()
	check.call("Condo sales: " in sold_window.panel.body_text(), "window: lists condo sales")
	window.free()
	sold_window.free()
