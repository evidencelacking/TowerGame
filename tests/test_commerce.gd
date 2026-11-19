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

	# Customer grades (#151): A 25+, B 20-24, C under 20 for fast food; boundaries pinned.
	var grade_cases := {0: 2, 19: 2, 20: 1, 24: 1, 25: 0, 30: 0, 100: 0}
	var grades_ok := true
	for customers: int in grade_cases:
		grades_ok = grades_ok and Commerce.grade_of_customers("fast_food", customers) == grade_cases[customers]
	check.call(grades_ok, "fast food grade: 19 is C, 20 and 24 are B, 25 is A")
	var g := _tower(false)
	var gshop := _shop(g)
	check.call(g.commerce.grade(g.rooms, gshop) == 1 and not g.commerce.has_settled(gshop), "a new shop is a B before its first full day")
	_run(g, 0, 1000)
	check.call(g.commerce.grade(g.rooms, gshop) == 1, "the grade does not change during the day")
	_run(g, 1000, DAY_TICKS - 1000)
	check.call(g.commerce.has_settled(gshop) and g.commerce.customers_last_day(gshop) == 0 and g.commerce.grade(g.rooms, gshop) == 2, "a settled day with no customers (day 1, unreachable shop) is a C")
	check.call(g.commerce.grade(g.rooms, g.rooms.room_ids()[0]) == -1, "an office is not graded by customers")
	var gloaded := TowerSim.new(1, 1)
	check.call(gloaded.load_state(g.save()) and gloaded.commerce.has_settled(gshop) and gloaded.commerce.grade(gloaded.rooms, gshop) == 2 and gloaded.state_hash() == g.state_hash(), "a settled zero day survives save and load")
	var RoomInfo := preload("res://scripts/view/room_info.gd")
	var info := RoomInfo.describe(full, fshop)
	var expect_bar := mini(day_customers, 30) * RoomInfo.QUALITY_MAX / 30
	check.call(RoomInfo.bar_value(info) == expect_bar and info["grade"] == full.commerce.grade(full.rooms, fshop), "the room info bar fills from last day's customers")
	check.call(RoomInfo.bar_value(RoomInfo.describe(g, gshop)) == 0 and RoomInfo.bar_color(RoomInfo.describe(g, gshop)) == RoomInfo.GRADE_COLORS[2], "an empty shop's bar is empty and red")


## First tick of the day at or after the minute of day.
static func _tick_at(t: TowerSim, minute: int) -> int:
	for k in DAY_TICKS:
		t.clock.set_to_tick(k)
		if t.clock.minute_of_day() >= minute:
			return k
	return -1


static func run_restaurant(check: Callable) -> void:
	var prof: Dictionary = Commerce.PROFILES["restaurant"]
	check.call(prof["grade_cap"] == 40 and Commerce.food_of("restaurant", 0) != Commerce.food_of("restaurant", 1), "restaurant: cap 40 and several kinds")
	var foods := {}
	for room in 10:
		foods[Commerce.food_of("restaurant", room)] = true
	check.call(foods.size() == 5, "a restaurant is one of 5 kinds")
	var tiers := {0: -6000, 19: -6000, 20: 4000, 24: 4000, 25: 6000, 49: 6000, 50: 10000}
	var tiers_ok := true
	for customers: int in tiers:
		tiers_ok = tiers_ok and Commerce.income_for("restaurant", customers) == tiers[customers]
	check.call(tiers_ok, "restaurant income tiers: under 20 loses $6,000, 20 earns 4,000, 25 earns 6,000, 50 earns 10,000")
	var cases := {0: 2, 17: 2, 18: 1, 25: 1, 26: 0, 40: 0}
	var ok := true
	for customers: int in cases:
		ok = ok and Commerce.grade_of_customers("restaurant", customers) == cases[customers]
	check.call(ok, "restaurant grade: 17 is C, 18 and 25 are B, 26 (over 25) is A")
	check.call(Commerce.seats_per_meal("restaurant", Commerce.DINNER_WINDOW) == 60, "diners linger an hour, so a dinner has two seatings")

	var t := TowerSim.new(42, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	t.floors.fill_span(3, 100, 163)
	t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("office"), 3, 100)
	var placed := t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("restaurant"), 3, 112)
	check.call(placed == 0, "a restaurant can be placed (refusal %d)" % placed)
	var hotel_room_placed := t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("hotel_single"), 3, 140)
	check.call(hotel_room_placed == 0, "the test hotel room places (refusal %d)" % hotel_room_placed)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 1, 100)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 2, 104)
	var diner := -1
	var hotel_room := -1
	for id in t.rooms.room_ids():
		if t.rooms.kind_of(id) == "restaurant":
			diner = id
		elif t.rooms.kind_of(id) == "hotel_single":
			hotel_room = id

	# Lunchtime workers do not eat at a restaurant: dinner only.
	_staff(t)
	_run(t, LUNCH_PERIOD_TICK, 500)
	check.call(t.commerce.customers_today(diner) == 0, "a restaurant serves nobody at lunch")

	# Hotel guests dine in the evening, and lingering limits the seats.
	var d := t
	for n in 100:
		d.people.add_guest(hotel_room, d.rng)
	var dinner_tick := _tick_at(d, Commerce.DINNER)
	_run(d, dinner_tick - 5, 60)
	var dined := d.commerce.customers_today(diner)
	check.call(dined > 0, "hotel guests dine at the restaurant in the evening (%d)" % dined)
	check.call(dined == 60, "100 guests fill the 60 dinner seats and no more (%d)" % dined)
	check.call(d.commerce.grade_input(d.rooms, diner) == 0, "the grade input is 0 before the day settles")

	# Settling: one SHOP line under the restaurant, the tier income, then a grade.
	_run(d, _tick_at(d, Commerce.SETTLE_MINUTE - 10), 40)
	var lines := _shop_lines(d)
	check.call(lines.size() == 1 and lines[0][3] == diner and lines[0][1] == Commerce.income_for("restaurant", 60), "restaurant sales reach the ledger as a shop line (%s)" % str(lines))
	check.call(d.commerce.grade(d.rooms, diner) == 0, "60 diners make the restaurant an A, from the next day")
	check.call(Finance.totals(d.ledger, 0).get(Ledger.SHOP, 0) == lines[0][1], "the finance window shows restaurant sales")
	var loaded := TowerSim.new(1, 1)
	check.call(loaded.load_state(d.save()) and loaded.state_hash() == d.state_hash(), "restaurant state survives save and load")


static func _retail_tower(linked: bool) -> TowerSim:
	var t := TowerSim.new(42, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	t.floors.fill_span(3, 100, 163)
	t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("office"), 3, 100)
	var placed := t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("retail"), 3, 112)
	assert(placed == 0, "the retail shop places, refusal %d" % placed)
	if linked:
		t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 1, 100)
		t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 2, 104)
	return t


static func _store(t: TowerSim) -> int:
	for id in t.rooms.room_ids():
		if t.rooms.kind_of(id) == "retail":
			return id
	return -1


## Gives the shop a settled last day with this many customers (the save format is the test seam).
static func _set_last_day(t: TowerSim, room: int, customers: int) -> void:
	t.commerce.load_ints([-1, 1, room, 0, customers, 0])


static func run_retail(check: Callable) -> void:
	var prof: Dictionary = Commerce.PROFILES["retail"]
	check.call(not Commerce.has_sales("retail") and Commerce.has_sales("fast_food") and Commerce.has_sales("restaurant"), "retail earns rent, not sales")
	check.call((prof["food"] as Array).size() == 11, "a retail shop is one of 11 kinds")
	var rents: Array = Catalogue.row("retail")["rent"]
	check.call(rents.size() == 4 and rents[0] < rents[1] and rents[1] < rents[2] and rents[2] < rents[3], "retail has four rent levels, lowest to highest")
	var cases := {0: 2, 14: 2, 15: 1, 20: 1, 21: 0, 30: 0}
	var ok := true
	for customers: int in cases:
		ok = ok and Commerce.grade_of_customers("retail", customers) == cases[customers]
	check.call(ok, "retail grade: 14 is C, 15 and 20 are B, 21 (over 20) is A")

	# Rent arrives at the quarter start, at the level's amount, once.
	var t := _retail_tower(true)
	var store := _store(t)
	t.clock.set_to_tick(7650 - 1)
	t.step()
	var rent_lines := 0
	var paid := 0
	for line: Array in t.ledger.lines:
		if line[2] == Ledger.INCOME and line[3] == store:
			rent_lines += 1
			paid += line[1]
	check.call(rent_lines == 1 and paid == rents[2], "a leased shop pays its default rent at the quarter start (%d)" % paid)
	check.call(t.commerce.collect_rent(t.rooms, t.rent, t.ledger, t.tick) == rents[2], "collect_rent reports the quarter's rent")

	# Shop sales never reach the ledger as a shop line for retail.
	var day := _retail_tower(true)
	_staff(day)
	_run(day, 0, DAY_TICKS)
	check.call(_shop_lines(day).is_empty() and day.commerce.has_settled(_store(day)), "retail settles a day without a sales line")
	check.call(day.commerce.customers_last_day(_store(day)) > 0, "office workers shop (customers: %d)" % day.commerce.customers_last_day(_store(day)))

	# At the rest period a shop at C leaves; B and A stay; before a settled day it is a B.
	var fresh := _retail_tower(true)
	fresh.evaluate_tenants()
	check.call(not fresh.commerce.is_vacant(_store(fresh)), "a new shop (B) stays")
	var low := _retail_tower(true)
	_set_last_day(low, _store(low), 14)
	low.evaluate_tenants()
	check.call(low.commerce.is_vacant(_store(low)), "a shop at grade C leaves at the rest period")
	var left := 0
	for i in low.messages.count():
		if low.messages.entry(i)[1] == Messages.TENANT_LEFT:
			left += 1
	check.call(left == 1, "the renter leaving is logged")
	var mid := _retail_tower(true)
	_set_last_day(mid, _store(mid), 15)
	mid.evaluate_tenants()
	check.call(not mid.commerce.is_vacant(_store(mid)), "a shop at grade B stays")

	# A vacant shop pays no rent and takes no customers, and is re-let after three evenings.
	low.clock.set_to_tick(7650 - 1)
	low.step()
	var vacant_rent := 0
	for line: Array in low.ledger.lines:
		if line[2] == Ledger.INCOME and line[3] == _store(low):
			vacant_rent += line[1]
	check.call(vacant_rent == 0, "a vacant shop pays no rent")
	low.evaluate_tenants()
	low.evaluate_tenants()
	check.call(low.commerce.is_vacant(_store(low)), "still vacant after two more evaluations")
	low.evaluate_tenants()
	check.call(not low.commerce.is_vacant(_store(low)) and not low.commerce.has_settled(_store(low)), "a new renter takes the shop after 3 evaluations, as a fresh B")

	# At the lowest rent level renters never leave.
	var cheap := _retail_tower(true)
	var cheap_id := _store(cheap)
	cheap.enqueue(TowerSim.Command.make(cheap.tick + 1, TowerSim.Command.SET_RENT, [cheap_id, 0] as Array[int]))
	cheap.step()
	_set_last_day(cheap, cheap_id, 0)
	cheap.evaluate_tenants()
	check.call(not cheap.commerce.is_vacant(cheap_id), "a C shop at the lowest rent never leaves")

	# An unreachable shop earns no customers, settles a C day and then leaves.
	var cut := _retail_tower(false)
	_staff(cut)
	_run(cut, 0, DAY_TICKS)
	cut.evaluate_tenants()
	check.call(cut.commerce.is_vacant(_store(cut)), "an unreachable shop goes C and leaves")

	# Save and load keep who is vacant.
	var loaded := TowerSim.new(1, 1)
	check.call(loaded.load_state(low.save()) and loaded.state_hash() == low.state_hash(), "retail state survives save and load")
	var vac := _retail_tower(true)
	vac.commerce.load_ints([-1, 0, 1, _store(vac), 2])
	var again := TowerSim.new(1, 1)
	check.call(again.load_state(vac.save()) and again.commerce.is_vacant(_store(vac)), "a vacant shop survives save and load")
	var bad: Dictionary = vac.save()
	bad["commerce"] = [-1, 0, 2, 5, 1]
	check.call(not TowerSim.new(1, 1).load_state(bad), "a malformed vacancy list is refused")
