extends RefCounted
## Rent and running cost tests (5.4): rent on the first weekday of each quarter only, running costs
## once a quarter from catalogue upkeep (elevators per shaft, stairs free), exact balance over a
## quarter and a year, nothing for vacant offices, bulldozing stops a cost.

const TowerSim := preload("res://scripts/sim/tower.gd")
const RunningCosts := preload("res://scripts/sim/running_costs.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Ledger := preload("res://scripts/sim/ledger.gd")
const Messages := preload("res://scripts/sim/messages.gd")
const TestRent := preload("res://tests/test_rent.gd")
const TestTenancy := preload("res://tests/test_tenancy.gd")

const QUARTER_TICKS := 7650  ## 3 days of 2,550 ticks.
const SHAFT_X := 126  ## Over the second office; a link sits in front of the room behind it.


## Sum of ledger line amounts of one kind at or after from_tick.
static func _sum(t: TowerSim, kind: int, from_tick: int) -> int:
	var total := 0
	for line: Array in t.ledger.lines:
		if line[2] == kind and line[0] >= from_tick:
			total += line[1]
	return total


## Ticks of ledger lines of one kind at or after from_tick, as a set (tick -> true).
static func _ticks(t: TowerSim, kind: int, from_tick: int) -> Dictionary:
	var found := {}
	for line: Array in t.ledger.lines:
		if line[2] == kind and line[0] >= from_tick:
			found[line[0]] = true
	return found


## Two leased offices (see TestRent), plus one local shaft on floors 1 to 3 (its machine room is on 4), one tick before a quarter starts.
static func _tower() -> TowerSim:
	var t := TestRent._two_offices()
	var placed := t.rooms.place_shaft(t.grid, t.floors, t.ledger, t.tick, Catalogue.IDS.find("local_shaft"), 1, 3, SHAFT_X)
	assert(placed == 0, "the test shaft places")
	t.clock.set_to_tick(QUARTER_TICKS - 1)
	return t


static func run(check: Callable) -> void:
	# Costs are catalogue data: elevators about $10,000 (reference), stairs free, the guesses flagged.
	check.call(RunningCosts.upkeep_of("local_shaft") == 10000, "a local elevator costs $10,000 a quarter")
	check.call(RunningCosts.upkeep_of("stairs") == 0 and RunningCosts.upkeep_of("office") == 0, "stairs and offices cost nothing to run")
	check.call(Catalogue.UPKEEP_UNVERIFIED.size() > 0 and not Catalogue.UPKEEP_UNVERIFIED.has("local_shaft"), "unverified upkeep is flagged, the elevator figure is not")
	var flagged_ok := true
	for kind in Catalogue.IDS:
		if RunningCosts.upkeep_of(kind) > 0 and kind != "local_shaft" and not Catalogue.UPKEEP_UNVERIFIED.has(kind):
			flagged_ok = false
	check.call(flagged_ok, "every upkeep other than the elevator is listed as unverified")

	# The first quarter: two default offices pay $20,000; the lobby and the shaft cost.
	var t := _tower()
	var lobby_cost := RunningCosts.upkeep_of("lobby")
	var expected_costs := lobby_cost + 10000
	check.call(RunningCosts.quarterly_total(t.rooms, t.floors) == expected_costs, "the quarterly total is lobby plus elevator (stairs free)")
	var opening := t.ledger.balance
	var start := t.tick
	TestRent.settle_quarter(t)
	check.call(t.clock.quarter_started, "the test stepped onto a quarter start")
	check.call(_sum(t, Ledger.INCOME, start + 1) == 20000, "rent of $20,000 is credited over the quarter's three days")
	check.call(_sum(t, Ledger.COST, start + 1) == -expected_costs, "running costs of $%d are charged at the quarter start" % expected_costs)
	check.call(t.ledger.balance == opening + 20000 - expected_costs, "balance is opening plus rent minus costs, exactly")
	var settled := t.messages.entry(t.messages.count() - 1)
	check.call(settled[1] == Messages.QUARTER_SETTLED and settled[2] == 20000 and settled[3] == expected_costs, "the quarter close is logged with rent and costs")
	check.call(t.ledger.balance == t.ledger.line_sum(), "the ledger balance equals the sum of its lines")

	# Then a full year: four more quarter starts, and nothing on any other tick.
	var year_start := t.tick
	for k in 4 * QUARTER_TICKS:
		t.step()
	var income_ticks := _ticks(t, Ledger.INCOME, year_start + 1)
	var cost_ticks := _ticks(t, Ledger.COST, year_start + 1)
	var on_quarter_starts := true
	var rent_on_day_starts := true
	for tick_key: int in income_ticks.keys():
		if (tick_key - year_start) % (QUARTER_TICKS / 3) != 0:
			rent_on_day_starts = false
	check.call(rent_on_day_starts, "rent lands only on day starts")
	for tick_key: int in cost_ticks.keys():
		if (tick_key - year_start) % QUARTER_TICKS != 0:
			on_quarter_starts = false
	check.call(on_quarter_starts, "running costs land only on quarter starts")
	check.call(income_ticks.size() == 12 and cost_ticks.size() == 4, "a full year pays rent 12 days and settles costs four times")
	check.call(_sum(t, Ledger.INCOME, year_start + 1) == 4 * 20000, "a year of rent is four quarters of $20,000")
	check.call(_sum(t, Ledger.COST, year_start + 1) == -4 * expected_costs, "a year of running costs is four quarters")
	check.call(t.ledger.balance == opening + 5 * (20000 - expected_costs) and t.ledger.balance == t.ledger.line_sum(), "over a year the balance equals income minus costs")

	# A vacant office pays no rent, but the tower still pays running costs.
	var vacant := TestTenancy._tower()  # an office no one can reach, so it stays vacant
	var vacant_start := vacant.tick
	TestRent.settle_quarter(vacant)
	check.call(_sum(vacant, Ledger.INCOME, vacant_start + 1) == 0, "a vacant office pays no rent")
	check.call(_sum(vacant, Ledger.COST, vacant_start + 1) == -lobby_cost, "a vacant tower still pays for its lobby")

	# Costs are never refused: the balance may go below zero.
	var broke := TowerSim.new(1, 100000000)
	broke.floors.build_lobby(broke.ledger, 0, 1, 100, 131, 1)
	broke.ledger.payout(0, broke.ledger.balance - 1000, 0)
	var before := broke.ledger.balance
	broke.clock.set_to_tick(QUARTER_TICKS - 1)
	broke.step()
	check.call(before == 1000 and broke.ledger.balance == before - lobby_cost and broke.ledger.balance < 0, "running costs may leave the balance negative")

	# Removing a shaft stops its cost; the total follows from placed rooms, so saves need nothing.
	var gone := _tower()
	var rooms_before := gone.rooms.room_count()
	check.call(gone.rooms.shaft_count() == 1, "the test tower has one shaft")
	gone.enqueue(TowerSim.Command.make(gone.tick + 1, TowerSim.Command.BULLDOZE, [3, SHAFT_X] as Array[int]))
	gone.step()
	check.call(gone.rooms.shaft_count() == 0 and gone.rooms.room_count() == rooms_before - 1, "bulldozing picks the shaft, not the office behind it")
	check.call(RunningCosts.quarterly_total(gone.rooms, gone.floors) == lobby_cost, "a bulldozed shaft costs nothing")
	var copy := TowerSim.new(7, 100000000)
	check.call(copy.load_state(t.save()) and copy.state_hash() == t.state_hash(), "a save round trip keeps the state with running costs charged")
