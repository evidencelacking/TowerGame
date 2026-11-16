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
## The grade cap (30 for fast food) is only an input for customer grades (#151): see grade_input().
## All numbers here are UNVERIFIED tunables except where marked (docs/gameplay-reference.md).
##
## Saved: the last minute seen, and per shop the customers today and yesterday.

const Clock := preload("res://scripts/sim/clock.gd")
const FloorsScript := preload("res://scripts/sim/floors.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const GridScript := preload("res://scripts/sim/grid.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")
const TenancyScript := preload("res://scripts/sim/tenancy.gd")
const LedgerScript := preload("res://scripts/sim/ledger.gd")
const MessagesScript := preload("res://scripts/sim/messages.gd")

## Meal times (minute of day), windows (minutes a meal lasts) and the percent of people inside
## the tower who buy. All tunable.
const SNACK_MORNING := 630  ## 10:30, the office break.
const LUNCH := 720  ## 12:00.
const SNACK_AFTERNOON := 900  ## 15:00.
const SNACK_WINDOW := 15
const LUNCH_WINDOW := 60
const SNACK_PERCENT := 20
const LUNCH_PERCENT := 60

const SETTLE_MINUTE := 1380  ## 23:00: the day's takings are credited.

## Per shop kind. seats and linger_minutes are tunable guesses; tiers are [customers from, daily
## income] in ascending order and are the review's tuning start (unverified); grade_cap is the
## issue's "cap 30" (a grade input only, owner ruling on #150); food is the five kinds of shop.
const PROFILES: Dictionary = {
	"fast_food": {
		"seats": 24, "linger_minutes": 30, "grade_cap": 30,
		"tiers": [[0, -3000], [20, 2000], [25, 3000], [50, 5000]],
		"food": ["Burgers", "Pizza", "Noodles", "Sandwiches", "Ice cream"],
	},
}

var _last_minute: int = -1
var _today: Dictionary = {}  ## Room id -> customers served so far today.
var _last_day: Dictionary = {}  ## Room id -> customers served in the last settled day.


static func is_shop(kind: String) -> bool:
	return PROFILES.has(kind)


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
	if _crossed(prev, minute, SNACK_MORNING):
		_serve(SNACK_WINDOW, SNACK_PERCENT, floors, rooms, grid, people, tenancy, rng)
	if _crossed(prev, minute, LUNCH):
		_serve(LUNCH_WINDOW, LUNCH_PERCENT, floors, rooms, grid, people, tenancy, rng)
	if _crossed(prev, minute, SNACK_AFTERNOON):
		_serve(SNACK_WINDOW, SNACK_PERCENT, floors, rooms, grid, people, tenancy, rng)
	if _crossed(prev, minute, SETTLE_MINUTE):
		_settle(floors, rooms, grid, tenancy, ledger, messages, at_tick)


static func _crossed(prev: int, now: int, at: int) -> bool:
	return prev < at and at <= now


func _open_shops(floors: FloorsScript, rooms: RoomsScript, grid: GridScript, tenancy: TenancyScript) -> Array[int]:
	var shops: Array[int] = []
	var entry_x := floors.lobby_span()[0]
	for id in rooms.room_ids():
		if is_shop(rooms.kind_of(id)) and tenancy.reachable(floors, rooms, grid, id, entry_x):
			shops.append(id)
	return shops


func _serve(window: int, percent: int, floors: FloorsScript, rooms: RoomsScript, grid: GridScript, people: PeopleScript, tenancy: TenancyScript, rng: Object) -> void:
	var shops := _open_shops(floors, rooms, grid, tenancy)
	if shops.is_empty():
		return
	var served: Dictionary = {}  # this meal, per shop
	for i in people.count():
		if people.location_of(i) == PeopleScript.NONE and people.trip_state(i) == PeopleScript.TRIP_IDLE:
			continue  # outside the tower
		if rng.next_below(100) >= percent:
			continue
		var shop: int = shops[rng.next_below(shops.size())]
		if int(served.get(shop, 0)) < seats_per_meal(rooms.kind_of(shop), window):
			served[shop] = int(served.get(shop, 0)) + 1
			_today[shop] = customers_today(shop) + 1


func _settle(floors: FloorsScript, rooms: RoomsScript, grid: GridScript, tenancy: TenancyScript, ledger: LedgerScript, messages: MessagesScript, at_tick: int) -> void:
	var open := _open_shops(floors, rooms, grid, tenancy)
	var net := 0
	for id in open:
		var amount := income_for(rooms.kind_of(id), customers_today(id))
		ledger.shop_sales(at_tick, amount, id)
		net += amount
	var counts: Dictionary = {}
	for id in rooms.room_ids():
		if is_shop(rooms.kind_of(id)) and customers_today(id) > 0:
			counts[id] = customers_today(id)
	_last_day = counts
	_today.clear()
	if not open.is_empty():
		messages.add(at_tick, MessagesScript.DAILY_SALES, net, open.size())


func state_ints() -> Array[int]:
	var ids: Array = _today.keys()
	for id: int in _last_day.keys():
		if not ids.has(id):
			ids.append(id)
	ids.sort()
	var ints: Array[int] = [_last_minute, ids.size()]
	for id: int in ids:
		ints.append_array([id, customers_today(id), customers_last_day(id)] as Array[int])
	return ints


static func valid_ints(ints: Array) -> bool:
	if ints.size() < 2 or typeof(ints[1]) != TYPE_INT or ints[1] < 0 or ints.size() != 2 + 3 * ints[1]:
		return false
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	for k in range(2, ints.size(), 3):
		if ints[k] < 0 or ints[k + 1] < 0 or ints[k + 2] < 0:
			return false
	return ints[0] >= -1 and ints[0] < Clock.MINUTES_PER_DAY


func load_ints(ints: Array) -> void:
	_last_minute = ints[0]
	_today.clear()
	_last_day.clear()
	for k in range(2, ints.size(), 3):
		if ints[k + 1] > 0:
			_today[ints[k]] = ints[k + 1]
		if ints[k + 2] > 0:
			_last_day[ints[k]] = ints[k + 2]
