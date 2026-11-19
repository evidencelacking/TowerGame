class_name Commerce
extends RefCounted
## Customer trade (6.6): shops that sell to the people in the tower at meal times and settle their
## takings once a day. Built for fast food (#150); a restaurant (#152) or retail (#153) adds a
## profile to PROFILES and reuses all of it.
##
## Demand is abstract: at each meal minute every person inside the tower may become a customer
## (a seeded draw), picks a reachable shop at random, and is served if the shop still has a seat
## for the meal (seats x window / linger). Nobody is clamped to the grade cap.
## Once a day, at SETTLE_MINUTE, each reachable shop's customer count maps to a daily income
## (a negative one is a loss, kept on purpose: an empty shop costs money) credited to the ledger
## as its own SHOP kind. An unreachable shop trades nothing and settles at zero.
##
## Customer grades (#151): a shop is graded A, B or C by its customers in the last settled day, so
## the grade changes at the day's settlement (the next day). Before its first settled day a shop is
## a B, like a new office. The grade cap (30 for fast food) is the grade bar's full scale.
## All numbers here are UNVERIFIED tunables except where marked (docs/gameplay-reference.md).
##
## Saved: the last minute seen, and per shop the customers today and yesterday (-1: no settled day yet).

const Clock := preload("res://scripts/sim/clock.gd")
const FloorsScript := preload("res://scripts/sim/floors.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const GridScript := preload("res://scripts/sim/grid.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")
const TenancyScript := preload("res://scripts/sim/tenancy.gd")
const LedgerScript := preload("res://scripts/sim/ledger.gd")
const MessagesScript := preload("res://scripts/sim/messages.gd")
const HotelScript := preload("res://scripts/sim/hotel.gd")
const RentScript := preload("res://scripts/sim/rent.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const GradesScript := preload("res://scripts/sim/grades.gd")

## Meal times (minute of day), windows (minutes a meal lasts) and the percent of people inside
## the tower who buy. All tunable.
const SNACK_MORNING := 630  ## 10:30, the office break.
const LUNCH := 720  ## 12:00.
const SNACK_AFTERNOON := 900  ## 15:00.
const SNACK_WINDOW := 15
const LUNCH_WINDOW := 60
const SNACK_PERCENT := 20
const LUNCH_PERCENT := 60

## Restaurants (#152) serve dinner only: two seatings in the window, and every hotel guest in the
## tower dines (GUEST_PERCENT). Unverified tunables.
const DINNER := 1140  ## 19:00.
const DINNER_WINDOW := 120
const DINNER_PERCENT := 30
const GUEST_PERCENT := 100

## The meals: [minute of day, window, percent of people inside who buy, shop kind that serves it],
## in the order they are checked each minute (fast food's order is part of the determinism pin).
const MEALS: Array = [
	[SNACK_MORNING, SNACK_WINDOW, SNACK_PERCENT, "fast_food"],
	[LUNCH, LUNCH_WINDOW, LUNCH_PERCENT, "fast_food"],
	[SNACK_AFTERNOON, SNACK_WINDOW, SNACK_PERCENT, "fast_food"],
	[DINNER, DINNER_WINDOW, DINNER_PERCENT, "restaurant"],
	[SHOP_LUNCH, SHOP_LUNCH_WINDOW, SHOP_LUNCH_PERCENT, "retail"],
	[SHOP_EVENING, SHOP_EVENING_WINDOW, SHOP_EVENING_PERCENT, "retail"],
]

## Retail (#153): shoppers come at lunch and after work (percent of people inside who shop).
const SHOP_LUNCH := 750  ## 12:30.
const SHOP_LUNCH_WINDOW := 60
const SHOP_LUNCH_PERCENT := 25
const SHOP_EVENING := 1050  ## 17:30.
const SHOP_EVENING_WINDOW := 120
const SHOP_EVENING_PERCENT := 25
## Days a shop stays vacant after its renter leaves before a new renter takes it (if reachable).
const RELET_DAYS := 3

const SETTLE_MINUTE := 1380  ## 23:00: the day's takings are credited.

## Per shop kind. seats and linger_minutes are tunable guesses; tiers are [customers from, daily
## income] in ascending order and are the review's tuning start (unverified); grade_cap is the
## issue's "cap 30" (the grade bar's full scale, owner ruling on #150); grade_a and grade_b are the
## fewest customers in a day for an A and a B (#151; fast food's are unverified, owner ruling);
## food is the five kinds of shop.
const PROFILES: Dictionary = {
	"fast_food": {
		"seats": 24, "linger_minutes": 30, "grade_cap": 30, "grade_a": 25, "grade_b": 20,
		"tiers": [[0, -3000], [20, 2000], [25, 3000], [50, 5000]],
		"food": ["Burgers", "Pizza", "Noodles", "Sandwiches", "Ice cream"],
	},
	# Restaurant (#152): cap 40 is a grade input only (owner ruling). Seats and linger are guesses.
	"restaurant": {
		"seats": 30, "linger_minutes": 60, "grade_cap": 40, "grade_a": 26, "grade_b": 18,
		"tiers": [[0, -6000], [20, 4000], [25, 6000], [50, 10000]],
		"food": ["French", "Italian", "Steak", "Seafood", "Chinese"],
	},
	# Retail (#153): income is the renter's quarterly rent (Rent), not sales, so "sales" is false and
	# customers only grade the shop. Seats and the cap of 30 are unverified; the 11 kinds are named here.
	"retail": {
		"seats": 40, "linger_minutes": 15, "grade_cap": 30, "grade_a": 21, "grade_b": 15, "sales": false,
		"tiers": [[0, 0]],
		"food": ["Books", "Clothes", "Toys", "Shoes", "Jewellery", "Flowers", "Gifts", "Music", "Games", "Electronics", "Sports"],
	},
}

var _last_minute: int = -1
var _today: Dictionary = {}  ## Room id -> customers served so far today.
var _vacant: Dictionary = {}  ## Retail room id -> evaluations vacant (its renter left; absent: leased).
var _last_day: Dictionary = {}  ## Room id -> customers served in the last settled day (0 counts; absent: none settled yet).


static func is_shop(kind: String) -> bool:
	return PROFILES.has(kind)


## True if the kind sells for its own income (food); retail pays rent instead.
static func has_sales(kind: String) -> bool:
	return is_shop(kind) and bool(PROFILES[kind].get("sales", true))


## True if a retail shop's renter has left and no one has taken it yet.
func is_vacant(room: int) -> bool:
	return _vacant.has(room)


## Forgets a room that was bulldozed or replaced.
func remove_room(room: int) -> void:
	_today.erase(room)
	_last_day.erase(room)
	_vacant.erase(room)


## Which of the five kinds of food this shop sells (by room id; nothing is stored).
static func food_of(kind: String, room: int) -> String:
	var foods: Array = PROFILES[kind]["food"]
	return foods[room % foods.size()]


## Daily income in dollars for a customer count (negative is a loss).
static func income_for(kind: String, customers: int) -> int:
	var income := 0
	for tier: Array in PROFILES[kind]["tiers"]:
		if customers >= tier[0]:
			income = tier[1]
	return income


static func seats_per_meal(kind: String, window: int) -> int:
	var profile: Dictionary = PROFILES[kind]
	return int(profile["seats"]) * maxi(1, window / int(profile["linger_minutes"]))


func customers_today(room: int) -> int:
	return int(_today.get(room, 0))


## Customers in the last settled day (0 before the first).
func customers_last_day(room: int) -> int:
	return int(_last_day.get(room, 0))


## True once the shop has been through a settled day (its grade is then earned, not the new-shop B).
func has_settled(room: int) -> bool:
	return _last_day.has(room)


## GRADE_A, GRADE_B or GRADE_C by last day's customers (B before the first settled day), or
## Grades.GRADE_NONE for a room that is not a shop.
func grade(rooms: RoomsScript, room: int) -> int:
	if not rooms.has_room(room) or not is_shop(rooms.kind_of(room)):
		return GradesScript.GRADE_NONE
	if not has_settled(room):
		return GradesScript.GRADE_B
	return grade_of_customers(rooms.kind_of(room), customers_last_day(room))


static func grade_of_customers(kind: String, customers: int) -> int:
	var profile: Dictionary = PROFILES[kind]
	if customers >= int(profile["grade_a"]):
		return GradesScript.GRADE_A
	if customers >= int(profile["grade_b"]):
		return GradesScript.GRADE_B
	return GradesScript.GRADE_C


## The hook for customer grades (#151): last day's customers capped at the profile's grade_cap.
func grade_input(rooms: RoomsScript, room: int) -> int:
	if not rooms.has_room(room) or not is_shop(rooms.kind_of(room)):
		return 0
	return mini(customers_last_day(room), int(PROFILES[rooms.kind_of(room)]["grade_cap"]))


## Called once per tick after the clock. Serves meals and settles the day on the minute they pass.
func tick(clock: Clock, floors: FloorsScript, rooms: RoomsScript, grid: GridScript, people: PeopleScript, tenancy: TenancyScript, rng: Object, ledger: LedgerScript, messages: MessagesScript, at_tick: int) -> void:
	var minute := clock.minute_of_day()
	if minute == _last_minute:
		return
	# Sweep the minutes passed since the last call; a new day restarts it; the first call sweeps nothing.
	var prev := minute if _last_minute < 0 else (_last_minute if minute > _last_minute else -1)
	_last_minute = minute
	if not floors.has_lobby():
		return
	for meal: Array in MEALS:
		if _crossed(prev, minute, meal[0]):
			_serve(meal[3], meal[1], meal[2], floors, rooms, grid, people, tenancy, rng)
	if _crossed(prev, minute, SETTLE_MINUTE):
		_settle(floors, rooms, grid, tenancy, ledger, messages, at_tick)


static func _crossed(prev: int, now: int, at: int) -> bool:
	return prev < at and at <= now


func _open_shops(floors: FloorsScript, rooms: RoomsScript, grid: GridScript, tenancy: TenancyScript) -> Array[int]:
	var shops: Array[int] = []
	var entry_x := floors.lobby_span()[0]
	for id in rooms.room_ids():
		if is_shop(rooms.kind_of(id)) and not is_vacant(id) and tenancy.reachable(floors, rooms, grid, id, entry_x):
			shops.append(id)
	return shops


func _serve(kind: String, window: int, percent: int, floors: FloorsScript, rooms: RoomsScript, grid: GridScript, people: PeopleScript, tenancy: TenancyScript, rng: Object) -> void:
	var shops: Array[int] = []
	for id in _open_shops(floors, rooms, grid, tenancy):
		if rooms.kind_of(id) == kind:
			shops.append(id)
	if shops.is_empty():
		return
	var served: Dictionary = {}  # this meal, per shop
	for i in people.count():
		if people.location_of(i) == PeopleScript.NONE and people.trip_state(i) == PeopleScript.TRIP_IDLE:
			continue  # outside the tower
		var home := people.home_of(i)
		var guest := kind == "restaurant" and home != PeopleScript.NONE and rooms.has_room(home) and HotelScript.is_hotel_kind(rooms.kind_of(home))
		if rng.next_below(100) >= (GUEST_PERCENT if guest else percent):
			continue
		var shop: int = shops[rng.next_below(shops.size())]
		if int(served.get(shop, 0)) < seats_per_meal(rooms.kind_of(shop), window):
			served[shop] = int(served.get(shop, 0)) + 1
			_today[shop] = customers_today(shop) + 1


func _settle(floors: FloorsScript, rooms: RoomsScript, grid: GridScript, tenancy: TenancyScript, ledger: LedgerScript, messages: MessagesScript, at_tick: int) -> void:
	var open := _open_shops(floors, rooms, grid, tenancy)
	var net := 0
	var sellers := 0
	for id in open:
		if not has_sales(rooms.kind_of(id)):
			continue
		sellers += 1
		var amount := income_for(rooms.kind_of(id), customers_today(id))
		ledger.shop_sales(at_tick, amount, id)
		net += amount
	var counts: Dictionary = {}
	for id in rooms.room_ids():
		if is_shop(rooms.kind_of(id)) and not is_vacant(id):
			counts[id] = customers_today(id)
	_last_day = counts
	_today.clear()
	if sellers > 0:
		messages.add(at_tick, MessagesScript.DAILY_SALES, net, sellers)


## One quarter's rent from every leased retail shop (income, like office rent). Returns the total.
func collect_rent(rooms: RoomsScript, rent: RentScript, ledger: LedgerScript, at_tick: int) -> int:
	var total := 0
	for id in rooms.room_ids():
		if rooms.kind_of(id) == "retail" and not is_vacant(id):
			var amount := rent.rent_of(rooms, id)
			ledger.income(at_tick, amount, id)
			total += amount
	return total


## The rest-period check for retail (run with the tenant evaluation): a leased shop at grade C
## loses its renter (not at the lowest rent level, where renters never leave); a vacant shop is
## re-let after RELET_DAYS if the lobby reaches it. A shop before its first settled day is a B.
func evaluate(floors: FloorsScript, rooms: RoomsScript, grid: GridScript, tenancy: TenancyScript, rent: RentScript, messages: MessagesScript, at_tick: int) -> void:
	var ids := rooms.room_ids()
	ids.sort()
	var entry_x := floors.lobby_span()[0] if floors.has_lobby() else 0
	for id in ids:
		if rooms.kind_of(id) != "retail":
			continue
		if is_vacant(id):
			_vacant[id] = int(_vacant[id]) + 1
			if int(_vacant[id]) >= RELET_DAYS and floors.has_lobby() and tenancy.reachable(floors, rooms, grid, id, entry_x):
				_vacant.erase(id)
		elif grade(rooms, id) == GradesScript.GRADE_C and not rent.never_leaves(rooms, id):
			_vacant[id] = 0
			_today.erase(id)
			_last_day.erase(id)
			var run := grid.run_of(id)
			messages.add(at_tick, MessagesScript.TENANT_LEFT, CatalogueScript.IDS.find("retail"), run[0] if not run.is_empty() else 0)


func state_ints() -> Array[int]:
	var ids: Array = _today.keys()
	for id: int in _last_day.keys():
		if not ids.has(id):
			ids.append(id)
	ids.sort()
	var ints: Array[int] = [_last_minute, ids.size()]
	for id: int in ids:
		ints.append_array([id, customers_today(id), int(_last_day.get(id, -1))] as Array[int])
	var vacant: Array = _vacant.keys()
	vacant.sort()
	ints.append(vacant.size())
	for id: int in vacant:
		ints.append_array([id, int(_vacant[id])] as Array[int])
	return ints


static func valid_ints(ints: Array) -> bool:
	if ints.size() < 3 or typeof(ints[1]) != TYPE_INT or ints[1] < 0:
		return false
	var at: int = 2 + 3 * ints[1]
	if ints.size() <= at or typeof(ints[at]) != TYPE_INT or ints[at] < 0 or ints.size() != at + 1 + 2 * ints[at]:
		return false
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	for k in range(2, at, 3):
		if ints[k] < 0 or ints[k + 1] < 0 or ints[k + 2] < -1:
			return false
	for k in range(at + 1, ints.size(), 2):
		if ints[k] < 0 or ints[k + 1] < 0:
			return false
	return ints[0] >= -1 and ints[0] < Clock.MINUTES_PER_DAY


func load_ints(ints: Array) -> void:
	_last_minute = ints[0]
	_today.clear()
	_last_day.clear()
	_vacant.clear()
	var at: int = 2 + 3 * ints[1]
	for k in range(2, at, 3):
		if ints[k + 1] > 0:
			_today[ints[k]] = ints[k + 1]
		if ints[k + 2] >= 0:
			_last_day[ints[k]] = ints[k + 2]
	for k in range(at + 1, ints.size(), 2):
		_vacant[ints[k]] = ints[k + 1]
