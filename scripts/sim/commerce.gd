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
## Saved: the last minute seen, the outside visitors now inside and when they leave, and per shop the customers today and yesterday (-1: no settled day yet).

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
const SynergyScript := preload("res://scripts/sim/synergy.gd")

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
	[GYM_EARLY, GYM_EARLY_WINDOW, GYM_EARLY_PERCENT, "gym"],
	[GYM_BREAK, GYM_BREAK_WINDOW, GYM_BREAK_PERCENT, "gym"],
	[GYM_EVENING, GYM_EVENING_WINDOW, GYM_EVENING_PERCENT, "gym"],
	[DAYCARE_DROP_OFF, DAYCARE_WINDOW, DAYCARE_PERCENT, "daycare"],
	[CLINIC_MORNING, CLINIC_WINDOW, CLINIC_PERCENT, "clinic"],
	[CLINIC_AFTERNOON, CLINIC_WINDOW, CLINIC_PERCENT, "clinic"],
	[CLUB_EVENING, CLUB_WINDOW, CLUB_EVENING_PERCENT, "nightclub"],
	[CLUB_LATE, CLUB_WINDOW, CLUB_LATE_PERCENT, "nightclub"],
	[COWORK_EARLY, COWORK_WINDOW, COWORK_PERCENT, "coworking"],
	[COWORK_MID, COWORK_WINDOW, COWORK_PERCENT, "coworking"],
	[COWORK_LATE, COWORK_WINDOW, COWORK_PERCENT, "coworking"],
	[DECK_MORNING, DECK_WINDOW, DECK_PERCENT, "observation_deck"],
	[DECK_NOON, DECK_WINDOW, DECK_PERCENT, "observation_deck"],
	[DECK_AFTERNOON, DECK_WINDOW, DECK_PERCENT, "observation_deck"],
	[DECK_SUNSET, DECK_WINDOW, DECK_SUNSET_PERCENT, "observation_deck"],
	[DECK_NIGHT, DECK_WINDOW, DECK_NIGHT_PERCENT, "observation_deck"],
	[CASINO_EVENING, CASINO_EVENING_WINDOW, CASINO_PERCENT, "casino"],
	[CASINO_LATE, CASINO_LATE_WINDOW, CASINO_LATE_PERCENT, "casino"],
]

## Our own kinds (M13, #291), all unverified tunables. A gym is busy before work, at the break and
## after work. A daycare takes the children of the tower's households on weekdays only, for the working
## day. A clinic sees people whose mood is below CLINIC_MOOD_BELOW (an event, a bad room) twice a day.
## WHO names who may draw a visit: everyone inside, children, or low-mood people.
const GYM_EARLY := 420  ## 07:00.
const GYM_EARLY_WINDOW := 60
const GYM_EARLY_PERCENT := 8
const GYM_BREAK := 720  ## 12:00.
const GYM_BREAK_WINDOW := 60
const GYM_BREAK_PERCENT := 10
const GYM_EVENING := 1080  ## 18:00.
const GYM_EVENING_WINDOW := 120
const GYM_EVENING_PERCENT := 15
const DAYCARE_DROP_OFF := 480  ## 08:00; the children stay until the evening.
const DAYCARE_WINDOW := 60
const DAYCARE_PERCENT := 80
const CLINIC_MORNING := 570  ## 09:30.
const CLINIC_AFTERNOON := 930  ## 15:30.
const CLINIC_WINDOW := 120
const CLINIC_PERCENT := 40
const CLINIC_MOOD_BELOW := 60
## Batch 2 (#292), also unverified tunables. A nightclub is open 21:00 to 03:00: two waves of adults (21:00 to
## midnight, midnight to 03:00); takings after 23:00 are settled with the next day's. Co-working is an office
## rented by the desk, on weekdays only: three waves of adults arrive (07:30, 09:00, 10:30) and stay the day, so it
## fills gradually; each wave takes up to its seats, ten desks, so thirty desks in all.
const CLUB_EVENING := 1260  ## 21:00.
const CLUB_LATE := 0  ## 00:00.
const CLUB_WINDOW := 180
const CLUB_EVENING_PERCENT := 25
const CLUB_LATE_PERCENT := 12
const COWORK_EARLY := 450  ## 07:30.
const COWORK_MID := 540  ## 09:00.
const COWORK_LATE := 630  ## 10:30.
const COWORK_WINDOW := 120
const COWORK_PERCENT := 6
## The observation deck (#318): open all day, five waves, busiest at sunset and after dark (admission is the
## shop's takings). Unverified tunables.
const DECK_MORNING := 540  ## 09:00.
const DECK_NOON := 750  ## 12:30.
const DECK_AFTERNOON := 930  ## 15:30.
const DECK_SUNSET := 1110  ## 18:30.
const DECK_NIGHT := 1260  ## 21:00.
const DECK_WINDOW := 90
const DECK_PERCENT := 3
const DECK_SUNSET_PERCENT := 8
const DECK_NIGHT_PERCENT := 6
## The casino (#319): open 20:00 to 05:00 in two waves of adults; hotel guests gamble far more often than the
## tower's other people (CASINO_GUEST_PERCENT). Every gambler stakes CASINO_STAKE on an even bet he wins
## CASINO_WIN_PERCENT of the time, so the house keeps 10 percent of the stakes in the long run: the takings at
## settlement are the seeded results of the day's bets (integers); the staff are paid by the upkeep. Unverified tunables.
const CASINO_EVENING := 1200  ## 20:00.
const CASINO_EVENING_WINDOW := 240
const CASINO_LATE := 0  ## 00:00; counts for the next day, like the nightclub's second wave.
const CASINO_LATE_WINDOW := 300
const CASINO_PERCENT := 10
const CASINO_LATE_PERCENT := 8
const CASINO_GUEST_PERCENT := 35
const CASINO_STAKE := 400
const CASINO_WIN_PERCENT := 45
const CASINO_INCIDENT_PERCENT := 10
const CASINO_INCIDENT_COST := 15000
const WHO_ADULTS := "adults"
const WHO_ALL := "all"
const WHO_CHILDREN := "children"
const WHO_LOW_MOOD := "low_mood"

## Retail (#153): shoppers come at lunch and after work (percent of people inside who shop).
const SHOP_LUNCH := 750  ## 12:30.
const SHOP_LUNCH_WINDOW := 60
const SHOP_LUNCH_PERCENT := 25
const SHOP_EVENING := 1050  ## 17:30.
const SHOP_EVENING_WINDOW := 120
const SHOP_EVENING_PERCENT := 25
## Visitors from outside (#154, 6.10): per shop kind, the visitors who arrive for that kind's meal
## in each of the 6 clock periods, on a weekday (WD1, WD2) and on the weekend (WE). They enter by
## the ground lobby only (until the metro and theatre exist), pick a reachable shop of the kind at
## random and are served like anyone else (seats permitting). Weekends peak for shopping and food.
## Night periods bring none. All unverified tunables, tune by play.
const VISITORS: Dictionary = {
	"fast_food": [[0, 4, 12, 4, 0, 0], [0, 6, 20, 10, 0, 0]],
	"restaurant": [[0, 0, 0, 0, 6, 0], [0, 0, 0, 0, 14, 0]],
	"retail": [[0, 0, 4, 0, 6, 0], [0, 0, 14, 0, 24, 0]],
}
## The metro station (#325, our own design): while the tower is linked to a station, these visitors arrive in
## addition to VISITORS, per shop kind and clock period, on a weekday and on the weekend. Commuters fill the
## morning and evening, shoppers the middle of the day; they enter by the ground lobby like the rest.
const METRO_VISITORS: Dictionary = {
	"fast_food": [[0, 6, 14, 6, 4, 0], [0, 4, 12, 8, 6, 0]],
	"restaurant": [[0, 0, 2, 2, 8, 2], [0, 0, 4, 4, 14, 4]],
	"retail": [[0, 0, 6, 4, 10, 0], [0, 0, 14, 10, 20, 0]],
}
## The observation deck (#318): visitors from the city, per clock period on a weekday and on the weekend. They come
## all day and into the night (unlike VISITORS, which stop after dark), more at sunset and after dark.
const CITY_VISITORS: Dictionary = {
	"observation_deck": [[0, 6, 10, 10, 18, 12], [0, 10, 16, 16, 28, 18]],
	"casino": [[0, 0, 0, 0, 8, 6], [0, 0, 0, 0, 14, 10]],  # the city gambles after dark (#319)
}
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
	# Gym (#291): 20 machines, 45 minute sessions; the 4 staff make an empty gym lose $4,000 a day.
	"gym": {
		"seats": 20, "linger_minutes": 45, "grade_cap": 30, "grade_a": 25, "grade_b": 15,
		"tiers": [[0, -4000], [15, 2000], [25, 4000], [45, 6500]],
		"food": ["Weights", "Spin class", "Yoga", "Boxing", "Swimming"],
	},
	# Daycare (#291): 12 places for the working day (a long linger), children only, weekdays only.
	"daycare": {
		"seats": 12, "linger_minutes": 480, "grade_cap": 12, "grade_a": 10, "grade_b": 6, "who": WHO_CHILDREN, "weekdays": true,
		"tiers": [[0, -3000], [6, 1500], [10, 3500], [12, 5000]],
		"food": ["Toddlers", "Story time", "Playgroup", "Art room", "Nap room"],
	},
	# Nightclub (#292): 60 places, 90 minute stays, adults only; the 5 staff make an empty night lose $8,000.
	"nightclub": {
		"seats": 60, "linger_minutes": 90, "grade_cap": 40, "grade_a": 30, "grade_b": 18, "who": WHO_ADULTS,
		"tiers": [[0, -8000], [20, 5000], [35, 9000], [60, 15000]],
		"food": ["Disco", "Live band", "Karaoke", "Jazz night", "DJ set"],
	},
	# Co-working (#292): ten desks per arrival wave, a day-long stay, adults, weekdays only.
	"coworking": {
		"seats": 10, "linger_minutes": 480, "grade_cap": 30, "grade_a": 20, "grade_b": 10, "who": WHO_ADULTS, "weekdays": true,
		"tiers": [[0, -3000], [8, 2500], [16, 5000], [30, 8000]],
		"food": ["Hot desks", "Quiet room", "Meeting pods", "Studio", "Open floor"],
	},
	# Observation deck (#318): 50 places, 30 minute visits, everyone; the 2 staff make an empty day lose $2,000.
	"observation_deck": {
		"seats": 50, "linger_minutes": 30, "grade_cap": 40, "grade_a": 35, "grade_b": 20,
		"tiers": [[0, -2000], [20, 3000], [40, 6000], [80, 10000]],
		"food": ["Telescopes", "City view", "Sunset deck", "Night skyline", "Photo spot"],
	},
	# Casino (#319): 60 places, hour-long sessions, adults only. Its takings come from the bets (see CASINO_STAKE);
	# the tiers only grade it and price an empty night (the wages).
	"casino": {
		"seats": 60, "linger_minutes": 60, "grade_cap": 60, "grade_a": 45, "grade_b": 25, "who": WHO_ADULTS,
		"tiers": [[0, -6000], [30, 2000], [60, 8000], [120, 15000]],
		"food": ["Blackjack", "Roulette", "Poker", "Slot machines", "Baccarat"],
	},
	# Clinic (#291): 6 consulting seats, 20 minute visits; only the unwell (low mood) come.
	"clinic": {
		"seats": 6, "linger_minutes": 20, "grade_cap": 20, "grade_a": 16, "grade_b": 8, "who": WHO_LOW_MOOD,
		"tiers": [[0, -5000], [8, 2500], [16, 6000], [30, 9000]],
		"food": ["Check-ups", "Vaccines", "Physio", "Dental", "Eye tests"],
	},
}

var _last_minute: int = -1
var _visitors_in: int = 0  ## Outside visitors inside the tower now (they count toward population, 3.8).
var _visitors_until: int = 0  ## Minute of day when the latest batch of them leaves.
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


## Visitors from outside who come for this kind's meal in a clock period (1 to 6) on a day of the
## quarter (Clock.WD1, WD2 or WE).
static func visitors_for(kind: String, period: int, day: int) -> int:
	if not VISITORS.has(kind) or period < 1 or period > Clock.PERIODS:
		return 0
	var by_day: Array = VISITORS[kind]
	return int(by_day[1 if day == Clock.WE else 0][period - 1])


## Extra visitors a metro station sends for this kind's meal in a period; 0 for kinds it does not feed.
static func metro_visitors_for(kind: String, period: int, day: int) -> int:
	if not METRO_VISITORS.has(kind) or period < 1 or period > Clock.PERIODS:
		return 0
	var by_day: Array = METRO_VISITORS[kind]
	return int(by_day[1 if day == Clock.WE else 0][period - 1])


## Visitors from the city for a kind that draws them (the observation deck) in a period; 0 for other kinds.
static func city_visitors_for(kind: String, period: int, day: int) -> int:
	if not CITY_VISITORS.has(kind) or period < 1 or period > Clock.PERIODS:
		return 0
	var by_day: Array = CITY_VISITORS[kind]
	return int(by_day[1 if day == Clock.WE else 0][period - 1])


## The clock period (1 to 6) a minute of the day falls in.
static func period_of_minute(minute: int) -> int:
	var found := Clock.PERIODS  # before period 1 starts, it is still the night period
	for i in Clock.PERIODS:
		if minute >= Clock.period_start(i):
			found = i + 1
	return found


## Outside visitors in the tower at this minute of the day.
func visitors_inside(minute: int) -> int:
	return _visitors_in if minute < _visitors_until else 0


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
func tick(clock: Clock, floors: FloorsScript, rooms: RoomsScript, grid: GridScript, people: PeopleScript, tenancy: TenancyScript, rng: Object, ledger: LedgerScript, messages: MessagesScript, at_tick: int, life: Object = null) -> void:
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
			_serve(meal[3], meal[1], meal[2], floors, rooms, grid, people, tenancy, rng, clock.day_of_week(), meal[0], life)
	if _crossed(prev, minute, SETTLE_MINUTE):
		_visitors_in = 0
		_visitors_until = 0
		_settle(floors, rooms, grid, tenancy, ledger, messages, at_tick, rng)


static func _crossed(prev: int, now: int, at: int) -> bool:
	return prev < at and at <= now


func _open_shops(floors: FloorsScript, rooms: RoomsScript, grid: GridScript, tenancy: TenancyScript) -> Array[int]:
	var shops: Array[int] = []
	var entry_x := floors.lobby_span()[0]
	for id in rooms.room_ids():
		if is_shop(rooms.kind_of(id)) and not is_vacant(id) and not rooms.is_closed_up(grid, id) and tenancy.reachable(floors, rooms, grid, id, entry_x):
			shops.append(id)
	return shops


func _serve(kind: String, window: int, percent: int, floors: FloorsScript, rooms: RoomsScript, grid: GridScript, people: PeopleScript, tenancy: TenancyScript, rng: Object, day: int, at_minute: int, life: Object = null) -> void:
	var shops: Array[int] = []
	for id in _open_shops(floors, rooms, grid, tenancy):
		if rooms.kind_of(id) == kind:
			shops.append(id)
	if shops.is_empty():
		return
	if day == Clock.WE and bool(PROFILES[kind].get("weekdays", false)):
		return
	var who: String = PROFILES[kind].get("who", WHO_ALL)
	var served: Dictionary = {}  # this meal, per shop
	for i in people.count():
		if people.location_of(i) == PeopleScript.NONE and people.trip_state(i) == PeopleScript.TRIP_IDLE:
			continue  # outside the tower
		if who == WHO_CHILDREN and (life == null or not life.is_child(people.id_at(i))):
			continue
		if who == WHO_ADULTS and life != null and life.is_child(people.id_at(i)):
			continue
		if who == WHO_LOW_MOOD and people.mood_of(i) >= CLINIC_MOOD_BELOW:
			continue
		var home := people.home_of(i)
		var guest := (kind == "restaurant" or kind == "casino") and home != PeopleScript.NONE and rooms.has_room(home) and HotelScript.is_hotel_kind(rooms.kind_of(home))
		if rng.next_below(100) >= ((GUEST_PERCENT if kind == "restaurant" else CASINO_GUEST_PERCENT) if guest else percent):
			continue
		var shop: int = shops[rng.next_below(shops.size())]
		if int(served.get(shop, 0)) < seats_per_meal(rooms.kind_of(shop), window):
			served[shop] = int(served.get(shop, 0)) + 1
			_today[shop] = customers_today(shop) + 1
	# Visitors from outside (#154).
	var arriving := visitors_for(kind, period_of_minute(at_minute), day)
	if METRO_VISITORS.has(kind) and tenancy.transit_linked(floors, rooms, grid):
		arriving += metro_visitors_for(kind, period_of_minute(at_minute), day)
	arriving += city_visitors_for(kind, period_of_minute(at_minute), day)
	var came := 0
	for v in arriving:
		var shop: int = shops[rng.next_below(shops.size())]
		if int(served.get(shop, 0)) < seats_per_meal(rooms.kind_of(shop), window):
			served[shop] = int(served.get(shop, 0)) + 1
			_today[shop] = customers_today(shop) + 1
			came += 1
	if came > 0:
		if at_minute >= _visitors_until:
			_visitors_in = 0
		_visitors_in += came
		_visitors_until = maxi(_visitors_until, at_minute + window)


func _settle(floors: FloorsScript, rooms: RoomsScript, grid: GridScript, tenancy: TenancyScript, ledger: LedgerScript, messages: MessagesScript, at_tick: int, rng: Object = null) -> void:
	var open := _open_shops(floors, rooms, grid, tenancy)
	var net := 0
	var sellers := 0
	var sources := SynergyScript.others_of(grid, rooms)
	for id in open:
		if not has_sales(rooms.kind_of(id)):
			continue
		sellers += 1
		var amount := income_for(rooms.kind_of(id), customers_today(id))
		if rooms.kind_of(id) == "casino":
			amount = casino_takings(customers_today(id), rng)
			_casino_incident(rooms, ledger, messages, at_tick, id, customers_today(id), rng)
		if amount > 0:  # gardens feed restaurants (synergy.gd)
			amount += amount * SynergyScript.sales_percent(rooms.kind_of(id), grid.run_of(id), sources) / 100
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


## The casino's takings for a day with this many gamblers: each stakes CASINO_STAKE and wins with probability
## CASINO_WIN_PERCENT (the house pays the stake, otherwise keeps it), with the staff paid by the room's upkeep. Seeded: it draws from the
## tower's rng. Without an rng (a bare call) it is the long-run expectation.
static func casino_takings(customers: int, rng: Object) -> int:
	var net := 0
	if rng == null:
		net = customers * CASINO_STAKE * (100 - 2 * CASINO_WIN_PERCENT) / 100
	else:
		for gambler in customers:
			net += -CASINO_STAKE if rng.next_below(100) < CASINO_WIN_PERCENT else CASINO_STAKE
	return net


## A tower with a casino and no security office gets the occasional incident (a brawl, a cheat, a theft): 10
## percent of the nights with gamblers, costing the casino $15,000 in damages and a message. Seeded.
func _casino_incident(rooms: RoomsScript, ledger: LedgerScript, messages: MessagesScript, at_tick: int, id: int, customers: int, rng: Object) -> void:
	if rng == null or customers == 0:
		return
	for other in rooms.room_ids():
		if rooms.kind_of(other) == "security":
			return
	if rng.next_below(100) < CASINO_INCIDENT_PERCENT:
		ledger.payout(at_tick, CASINO_INCIDENT_COST, id)
		messages.add(at_tick, MessagesScript.CASINO_INCIDENT, id)


## One day's rent from every leased retail shop (income, like office rent; see Rent.day_share).
## Returns the total.
func collect_rent(rooms: RoomsScript, rent: RentScript, ledger: LedgerScript, at_tick: int, last_day: bool = true) -> int:
	var total := 0
	for id in rooms.room_ids():
		if rooms.kind_of(id) == "retail" and not is_vacant(id):
			var amount := RentScript.day_share(rent.rent_of(rooms, id), last_day)
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
	var ints: Array[int] = [_last_minute, _visitors_in, _visitors_until, ids.size()]
	for id: int in ids:
		ints.append_array([id, customers_today(id), int(_last_day.get(id, -1))] as Array[int])
	var vacant: Array = _vacant.keys()
	vacant.sort()
	ints.append(vacant.size())
	for id: int in vacant:
		ints.append_array([id, int(_vacant[id])] as Array[int])
	return ints


static func valid_ints(ints: Array) -> bool:
	if ints.size() < 5 or typeof(ints[3]) != TYPE_INT or ints[3] < 0:
		return false
	var at: int = 4 + 3 * ints[3]
	if ints.size() <= at or typeof(ints[at]) != TYPE_INT or ints[at] < 0 or ints.size() != at + 1 + 2 * ints[at]:
		return false
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	for k in range(4, at, 3):
		if ints[k] < 0 or ints[k + 1] < 0 or ints[k + 2] < -1:
			return false
	for k in range(at + 1, ints.size(), 2):
		if ints[k] < 0 or ints[k + 1] < 0:
			return false
	return ints[0] >= -1 and ints[0] < Clock.MINUTES_PER_DAY and ints[1] >= 0 and ints[2] >= 0 and ints[2] <= Clock.MINUTES_PER_DAY


func load_ints(ints: Array) -> void:
	_last_minute = ints[0]
	_visitors_in = ints[1]
	_visitors_until = ints[2]
	_today.clear()
	_last_day.clear()
	_vacant.clear()
	var at: int = 4 + 3 * ints[3]
	for k in range(4, at, 3):
		if ints[k + 1] > 0:
			_today[ints[k]] = ints[k + 1]
		if ints[k + 2] >= 0:
			_last_day[ints[k]] = ints[k + 2]
	for k in range(at + 1, ints.size(), 2):
		_vacant[ints[k]] = ints[k + 1]
