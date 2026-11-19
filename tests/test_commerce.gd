extends RefCounted
## Fast food tests (6.6, #150): lunchtime and snack customers, none at night, an empty shop loses
## $3,000 a day, daily takings reach the ledger under their own kind and the finance window, an
## unreachable shop trades nothing, the 30 cap feeds the grade only, five kinds, save and load.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Commerce := preload("res://scripts/sim/commerce.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Ledger := preload("res://scripts/sim/ledger.gd")
const Finance := preload("res://scripts/sim/finance.gd")
const Messages := preload("res://scripts/sim/messages.gd")
const People := preload("res://scripts/sim/people.gd")

const DAY_TICKS := 2550
const LUNCH_PERIOD_TICK := 900  ## 11:00, a weekday.
const EVENING_TICK := 1800  ## 17:00.


## Lobby on floors 1-2 (columns 100-163), floor 3 above it with one office at 100 and one fast
## food shop at 112. With linked, stairs join floor 1 to floor 3. Workers move in on their own.
static func _tower(linked: bool) -> TowerSim:
	var t := TowerSim.new(42, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	t.floors.fill_span(3, 100, 163)
	t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("office"), 3, 100)
	var placed := t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("fast_food"), 3, 112)
	assert(placed == 0, "the test shop places, refusal %d" % placed)
	if linked:
		t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 1, 100)
		t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 2, 104)
	return t


static func _shop(t: TowerSim) -> int:
	for id in t.rooms.room_ids():
		if t.rooms.kind_of(id) == "fast_food":
			return id
	return -1


static func _shop_lines(t: TowerSim) -> Array:
	var found: Array = []
	for line: Array in t.ledger.lines:
		if line[2] == Ledger.SHOP:
			found.append(line)
	return found


static func _run(t: TowerSim, from_tick: int, ticks: int) -> void:
	t.clock.set_to_tick(from_tick)
	for i in ticks:
		t.step()


## Puts the office's six workers in the tower without the morning leasing.
static func _staff(t: TowerSim) -> void:
	var office: int = t.rooms.room_ids()[0]
	for n in 6:
		t.people.add_person(People.NONE, office, t.rng)


static func run(check: Callable) -> void:
	# Tiers, cap and kinds are data.
	var tiers := {0: -3000, 19: -3000, 20: 2000, 24: 2000, 25: 3000, 49: 3000, 50: 5000, 225: 5000}
	var tiers_ok := true
	for customers: int in tiers:
		tiers_ok = tiers_ok and Commerce.income_for("fast_food", customers) == tiers[customers]
	check.call(tiers_ok, "daily income follows the tiers: under 20 loses $3,000, 20 earns 2,000, 25 earns 3,000, 50 earns 5,000")
	check.call(Commerce.PROFILES["fast_food"]["grade_cap"] == 30, "the fast food grade cap is 30")
	var foods := {}
	for room in 10:
		foods[Commerce.food_of("fast_food", room)] = true
	check.call(foods.size() == 5, "a shop is one of 5 kinds of food")
	check.call(Commerce.seats_per_meal("fast_food", Commerce.LUNCH_WINDOW) == 48 and Commerce.seats_per_meal("fast_food", Commerce.SNACK_WINDOW) == 24, "seats per meal come from seats, window and linger time")

	# Lunch workers buy. Start at 11:00 with staff in the tower; stop before the day settles.
	var t := _tower(true)
	var shop := _shop(t)
	check.call(shop != -1 and Commerce.is_shop(t.rooms.kind_of(shop)), "the test tower has a fast food shop")
	_staff(t)
	_run(t, LUNCH_PERIOD_TICK, 500)
	var lunch_customers := t.commerce.customers_today(shop)
	check.call(lunch_customers > 0 and lunch_customers <= 6, "office workers buy at lunch (customers: %d)" % lunch_customers)
	check.call(_shop_lines(t).is_empty(), "nothing is credited until the day settles")

	# The full day settles once, as its own ledger kind, and the finance window shows it.
	var full := _tower(true)
	var fshop := _shop(full)
	_run(full, 0, DAY_TICKS)
	var lines := _shop_lines(full)
	var day_customers := full.commerce.customers_last_day(fshop)
	check.call(lines.size() == 1 and lines[0][3] == fshop, "one shop line per shop per day, referencing the room")
	check.call(day_customers > 0, "a weekday brings customers (%d)" % day_customers)
	check.call(lines[0][1] == Commerce.income_for("fast_food", day_customers), "the line is the tier income for the day's customers")
	check.call(full.commerce.customers_today(fshop) == 0, "the day's count resets after settling")
	check.call(Finance.totals(full.ledger, 0).get(Ledger.SHOP, 0) == lines[0][1], "the finance window totals shop sales")
	check.call(Finance.LABELS.has(Ledger.SHOP) and Finance.KINDS.has(Ledger.SHOP), "shop sales have their own finance row")
	check.call(full.ledger.balance == full.ledger.line_sum(), "the ledger balance equals the sum of its lines")
	var last := full.messages.entry(full.messages.count() - 1)
	check.call(last[1] == Messages.DAILY_SALES and last[2] == lines[0][1] and last[3] == 1, "the day's sales are logged")
	check.call(full.commerce.grade_input(full.rooms, fshop) == mini(day_customers, 30), "the grade input is the last day's customers, capped at 30")

	# The cap never limits customers or income: 40 customers still pay the tier income.
	check.call(Commerce.income_for("fast_food", 40) == 3000 and Commerce.income_for("fast_food", 100) == 5000, "customers above 30 still pay")

	# No customers at night, and an empty shop loses $3,000.
	var night := _tower(true)
	var nshop := _shop(night)
	_staff(night)
	_run(night, EVENING_TICK, DAY_TICKS - EVENING_TICK)
	check.call(night.commerce.customers_last_day(nshop) == 0, "no customers from 17:00 to 23:00")
	var night_lines := _shop_lines(night)
	check.call(night_lines.size() == 1 and night_lines[0][1] == -3000, "an empty shop loses $3,000 a day")

	# Unreachable: no customers and no ledger line.
	var cut := _tower(false)
	_staff(cut)
	_run(cut, LUNCH_PERIOD_TICK - 600, DAY_TICKS)
	check.call(_shop_lines(cut).is_empty() and cut.commerce.customers_last_day(_shop(cut)) == 0, "an unreachable shop earns and loses nothing")

	# A shop can go below ground; an office cannot.
	var base := _tower(true)
	base.floors.fill_span(-1, 100, 163)
	check.call(base.rooms.check_place(base.grid, base.floors, "fast_food", -1, 100)["reason"] == 0, "a fast food shop can be placed in a basement")
	check.call(base.rooms.check_place(base.grid, base.floors, "office", -1, 100)["reason"] != 0, "an office still cannot")

	# Determinism and save and load.
	var twin := _tower(true)
	_run(twin, 0, DAY_TICKS)
	check.call(twin.state_hash() == full.state_hash(), "the same seed gives the same day")
	var loaded := TowerSim.new(1, 1)
	check.call(loaded.load_state(full.save()) and loaded.state_hash() == full.state_hash(), "shop counts survive save and load")
	check.call(loaded.commerce.customers_last_day(fshop) == day_customers, "yesterday's customers are restored")
	var bad: Dictionary = full.save()
	bad["commerce"] = [0, 1, 5]
	check.call(not TowerSim.new(1, 1).load_state(bad), "a malformed commerce save is refused")
	bad["commerce"] = [-1, 1, 5, -2, 0]
	check.call(not TowerSim.new(1, 1).load_state(bad), "a negative count is refused")
	bad.erase("commerce")
	check.call(not TowerSim.new(1, 1).load_state(bad), "a save without commerce is refused")
