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
const PoolLifeScript := preload("res://scripts/sim/pool_life.gd")
const BookingsScript := preload("res://scripts/sim/bookings.gd")

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
	[SCHOOL_DROP_OFF, SCHOOL_WINDOW, SCHOOL_PERCENT, "school"],
	[SCHOOL_PICK_UP, SCHOOL_WINDOW, SCHOOL_PERCENT, "school"],
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
	[DELI_BREAKFAST, DELI_BREAKFAST_WINDOW, DELI_BREAKFAST_PERCENT, "deli"],
	[GROCERY_MORNING, GROCERY_MORNING_WINDOW, GROCERY_MORNING_PERCENT, "grocery"],
	[DELI_MORNING, DELI_BREAK_WINDOW, DELI_MORNING_PERCENT, "deli"],
	[DELI_AFTERNOON, DELI_BREAK_WINDOW, DELI_AFTERNOON_PERCENT, "deli"],
	[GROCERY_EVENING, GROCERY_EVENING_WINDOW, GROCERY_EVENING_PERCENT, "grocery"],
	[DELI_LATE, DELI_LATE_WINDOW, DELI_LATE_PERCENT, "deli"],
	[CASINO_EVENING, CASINO_EVENING_WINDOW, CASINO_PERCENT, "casino"],
	[CASINO_LATE, CASINO_LATE_WINDOW, CASINO_LATE_PERCENT, "casino"],
	[POOL_EARLY, POOL_WINDOW, POOL_EARLY_PERCENT, "pool"],
	[POOL_LUNCH, POOL_WINDOW, POOL_LUNCH_PERCENT, "pool"],
	[POOL_EVENING, POOL_EVENING_WINDOW, POOL_EVENING_PERCENT, "pool"],
	[CAFE_MORNING, CAFE_MORNING_WINDOW, CAFE_MORNING_PERCENT, "cafe"],
	[CAFE_BREAK, CAFE_BREAK_WINDOW, CAFE_BREAK_PERCENT, "cafe"],
	[PIZZA_LUNCH, PIZZA_LUNCH_WINDOW, PIZZA_PERCENT, "pizza"],
	[SUSHI_LUNCH, PIZZA_LUNCH_WINDOW, SUSHI_LUNCH_PERCENT, "sushi"],
	[PIZZA_EVENING, PIZZA_EVENING_WINDOW, PIZZA_PERCENT, "pizza"],
	[BAR_EARLY, BAR_WINDOW, BAR_EARLY_PERCENT, "bar"],
	[SUSHI_EVENING, PIZZA_EVENING_WINDOW, SUSHI_EVENING_PERCENT, "sushi"],
	[FINE_EVENING, FINE_WINDOW, FINE_PERCENT, "fine_dining"],
	[BAR_LATE, BAR_WINDOW, BAR_LATE_PERCENT, "bar"],
	[BALLROOM_EVENING, BALLROOM_WINDOW, 100, "ballroom"],
	[CONFERENCE_MORNING, CONFERENCE_WINDOW, 100, "conference_center"],
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
## School (#370, unverified tunables): children of school age (an odd person id; the rest are daycare age
## while a school stands) go on weekdays only. They are dropped off at 08:15 and fetched at 15:15, two
## visit rows that make the school-run peaks; each row seats the school's 24 places.
const SCHOOL_DROP_OFF := 495  ## 08:15.
const SCHOOL_PICK_UP := 915  ## 15:15.
const SCHOOL_WINDOW := 45
const SCHOOL_PERCENT := 70
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
## Everyday shops (#322, our own design, unverified). A grocery serves residents (people whose home is a condo or a hotel
## room) in a morning and an after-work wave; a deli is for everyone: breakfast, two breaks and a late snack.
const GROCERY_MORNING := 480  ## 08:00.
const GROCERY_MORNING_WINDOW := 90
const GROCERY_MORNING_PERCENT := 6
const GROCERY_EVENING := 1050  ## 17:30.
const GROCERY_EVENING_WINDOW := 120
const GROCERY_EVENING_PERCENT := 20
const DELI_BREAKFAST := 390  ## 06:30.
const DELI_BREAKFAST_WINDOW := 60
const DELI_BREAKFAST_PERCENT := 10
const DELI_MORNING := 630  ## 10:30.
const DELI_MORNING_PERCENT := 8
const DELI_AFTERNOON := 900  ## 15:00.
const DELI_AFTERNOON_PERCENT := 6
const DELI_BREAK_WINDOW := 30
const DELI_LATE := 1320  ## 22:00.
const DELI_LATE_WINDOW := 60
const DELI_LATE_PERCENT := 5
const WHO_RESIDENTS := "residents"
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
## The swimming pool (#328, our own design, unverified): three waves (early lengths, lunchtime, after work), the
## evening one the longest and busiest; hotel guests swim far more often than residents (POOL_GUEST_PERCENT). Each
## swimmer pays POOL_ENTRY at the door and the day's takings are that less POOL_WAGES for the four staff, so an empty
## day loses the wages and the pool pays its way from POOL_WAGES / POOL_ENTRY swimmers. The daily cleaning
## (pool_life.gd) closes it, and a wave that starts while it is shut does not happen.
const POOL_EARLY := 390  ## 06:30.
const POOL_LUNCH := 720  ## 12:00.
const POOL_EVENING := 1050  ## 17:30.
const POOL_WINDOW := 60
const POOL_EVENING_WINDOW := 150
const POOL_EARLY_PERCENT := 6
const POOL_LUNCH_PERCENT := 10
const POOL_EVENING_PERCENT := 16
const POOL_GUEST_PERCENT := 30
const POOL_ENTRY := 120
const POOL_WAGES := 4000
## The restaurant family (#323, our own design, unverified): five kinds beside fast food and the restaurant. Waves by kind; the
## cafe serves everyone in the morning, pizza everyone at noon and early evening, sushi and the bar adults, fine dining adults
## at dinner (and 40 percent of hotel guests). Every distinct kind of the family in the tower beyond the first adds
## DINING_MIX_PERCENT to the family's sales, up to DINING_MIX_CAP.
const DINING_FAMILY: Array[String] = ["cafe", "pizza", "sushi", "fine_dining", "bar"]
const DINING_MIX_PERCENT := 4
const DINING_MIX_CAP := 16
const FINE_GUEST_PERCENT := 40
const CAFE_MORNING := 450  ## 07:30.
const CAFE_MORNING_WINDOW := 90
const CAFE_MORNING_PERCENT := 12
const CAFE_BREAK := 630  ## 10:30.
const CAFE_BREAK_WINDOW := 30
const CAFE_BREAK_PERCENT := 8
const PIZZA_LUNCH := 720  ## 12:00.
const PIZZA_LUNCH_WINDOW := 90
const PIZZA_EVENING := 1080  ## 18:00.
const PIZZA_EVENING_WINDOW := 120
const PIZZA_PERCENT := 20
const SUSHI_LUNCH := 720  ## 12:00.
const SUSHI_LUNCH_PERCENT := 12
const SUSHI_EVENING := 1140  ## 19:00.
const SUSHI_EVENING_PERCENT := 18
const FINE_EVENING := 1140  ## 19:00.
const FINE_WINDOW := 180
const FINE_PERCENT := 12
const BAR_EARLY := 1080  ## 18:00.
const BAR_LATE := 1260  ## 21:00.
const BAR_WINDOW := 180
const BAR_EARLY_PERCENT := 10
const BAR_LATE_PERCENT := 14
const WHO_ADULTS := "adults"
const WHO_ALL := "all"
const WHO_CHILDREN := "children"
const WHO_LOW_MOOD := "low_mood"

## Bookable event rooms (#359, own design, unverified; see bookings.gd). A ballroom is booked on weekend evenings
## (18:00 to 23:00), a conference center on weekdays (09:00 to 17:00), once per window, automatically while their needs
## are met. Guests: up to "tower_guests" of the tower's hotel guests (each with BOOKING_GUEST_PERCENT) plus a fixed
## "outside" crowd who arrive by the lobby. Outside guests are visitors: they are not counted in the population
## (nothing is added to _visitors_in). The fee is the tier for the guest count; a day with no booking earns and costs nothing.
const BALLROOM_EVENING := 1080  ## 18:00.
const BALLROOM_WINDOW := 300  ## to 23:00.
const CONFERENCE_MORNING := 540  ## 09:00.
const CONFERENCE_WINDOW := 480  ## to 17:00.
const BOOKING_GUEST_PERCENT := 60

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
	"pool": [[2, 0, 4, 0, 6, 0], [4, 0, 10, 0, 12, 0]],  # the neighbourhood swims at the waves (#328)
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
	"fine_dining": [[0, 0, 0, 0, 4, 0], [0, 0, 0, 0, 8, 0]],  # city VIPs, dinner only
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
	# School (#370): 24 places for a 6 hour school day, children only, weekdays only; the 4 staff make an empty day lose $4,000.
	"school": {
		"seats": 24, "linger_minutes": 360, "grade_cap": 48, "grade_a": 36, "grade_b": 20, "who": WHO_CHILDREN, "weekdays": true,
		"tiers": [[0, -4000], [12, 2000], [24, 4000], [40, 6000]],
		"food": ["Reception class", "Primary class", "Science lab", "Art room", "Library"],
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
	# Grocery (#322): 30 places, 20 minute shops, residents only; the 3 staff make an empty day lose $3,000.
	"grocery": {
		"seats": 30, "linger_minutes": 20, "grade_cap": 40, "grade_a": 30, "grade_b": 15, "who": WHO_RESIDENTS,
		"tiers": [[0, -3000], [15, 2500], [30, 5000], [60, 8000]],
		"food": ["Fresh produce", "Dairy", "Bakery", "Frozen", "Household"],
	},
	# Deli (#322): 10 places, 10 minute stops, everyone; the 1 staff make an empty day lose $1,000.
	"deli": {
		"seats": 10, "linger_minutes": 10, "grade_cap": 30, "grade_a": 20, "grade_b": 10,
		"tiers": [[0, -1000], [10, 1200], [20, 2500], [40, 4000]],
		"food": ["Breakfast rolls", "Sandwiches", "Coffee", "Snacks", "Newspapers"],
	},
	# Casino (#319): 60 places, hour-long sessions, adults only. Its takings come from the bets (see CASINO_STAKE);
	# the tiers only grade it and price an empty night (the wages).
	"casino": {
		"seats": 60, "linger_minutes": 60, "grade_cap": 60, "grade_a": 45, "grade_b": 25, "who": WHO_ADULTS,
		"tiers": [[0, -6000], [30, 2000], [60, 8000], [120, 15000]],
		"food": ["Blackjack", "Roulette", "Poker", "Slot machines", "Baccarat"],
	},
	# The restaurant family (#323): the empty-day loss is the staff at $1,000 a day.
	"cafe": {
		"seats": 16, "linger_minutes": 25, "grade_cap": 30, "grade_a": 22, "grade_b": 12,
		"tiers": [[0, -2000], [12, 1500], [25, 3000], [45, 4500]],
		"food": ["Espresso", "Pastries", "Tea", "Brunch", "Smoothies"],
	},
	"pizza": {
		"seats": 24, "linger_minutes": 40, "grade_cap": 40, "grade_a": 28, "grade_b": 16,
		"tiers": [[0, -3000], [15, 2500], [30, 5000], [55, 7500]],
		"food": ["Margherita", "Pepperoni", "Calzone", "Deep dish", "Garlic bread"],
	},
	"sushi": {
		"seats": 20, "linger_minutes": 45, "grade_cap": 40, "grade_a": 26, "grade_b": 16, "who": WHO_ADULTS,
		"tiers": [[0, -4000], [15, 3500], [25, 6500], [45, 10000]],
		"food": ["Nigiri", "Maki", "Sashimi", "Ramen", "Tempura"],
	},
	"fine_dining": {
		"seats": 20, "linger_minutes": 90, "grade_cap": 40, "grade_a": 24, "grade_b": 14, "who": WHO_ADULTS,
		"tiers": [[0, -8000], [10, 5000], [20, 11000], [40, 20000]],
		"food": ["Tasting menu", "Prime steak", "Fresh lobster", "Wine pairing", "Chef's table"],
	},
	"bar": {
		"seats": 30, "linger_minutes": 60, "grade_cap": 40, "grade_a": 28, "grade_b": 16, "who": WHO_ADULTS,
		"tiers": [[0, -3000], [15, 3000], [30, 6000], [50, 9000]],
		"food": ["Craft beer", "Cocktails", "Whiskey", "Wine bar", "Quiz night"],
	},
	# Pool (#328): 40 swimmers a wave, hour-long swims, everyone. The takings are the entry money (see POOL_ENTRY), so
	# the tiers hold only the empty-day loss that the staff cost.
	"pool": {
		"seats": 40, "linger_minutes": 60, "grade_cap": 60, "grade_a": 45, "grade_b": 25,
		"tiers": [[0, -4000]],
		"food": ["Lap lanes", "Diving board", "Family swim", "Water aerobics", "Night swim"],
	},
	# Ballroom (#359): one booking at a time on weekend evenings: up to 30 hotel guests of the tower and 30 outside guests; paid per booking.
	"ballroom": {
		"seats": 60, "linger_minutes": 300, "grade_cap": 60, "grade_a": 45, "grade_b": 25, "weekends": true,
		"booking": true, "tower_guests": 30, "outside": 30,
		"tiers": [[0, 0], [30, 10000], [45, 16000], [60, 24000]],
		"food": ["Wedding", "Gala dinner", "Charity ball", "Prom", "Anniversary"],
	},
	# Conference center (#359): a weekday booking of 40 delegates, all from outside.
	"conference_center": {
		"seats": 40, "linger_minutes": 480, "grade_cap": 40, "grade_a": 30, "grade_b": 15, "weekdays": true,
		"booking": true, "tower_guests": 0, "outside": 40,
		"tiers": [[0, 0], [20, 5000], [30, 8000], [40, 12000]],
		"food": ["Sales summit", "Trade fair", "Training day", "Board retreat", "Convention"],
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
var _visitors_today: int = 0  ## Outside visitors served since the last settle (overall population, #383).
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


## Outside visitors who came in so far today (reset at the daily settle).
func visitors_today() -> int:
	return _visitors_today


## Outside visitors in the tower at this minute of the day.
func visitors_inside(minute: int) -> int:
	return _visitors_in if minute < _visitors_until else 0


## The sales bonus percent the restaurant family earns for variety: DINING_MIX_PERCENT for each distinct kind of the
## family in the tower beyond the first, up to DINING_MIX_CAP (0 for none or one kind).
static func dining_mix_percent(rooms: RoomsScript) -> int:
	var kinds: Dictionary = {}
	for id in rooms.room_ids():
		var kind := rooms.kind_of(id)
		if DINING_FAMILY.has(kind):
			kinds[kind] = true
	return mini(DINING_MIX_CAP, maxi(0, kinds.size() - 1) * DINING_MIX_PERCENT)


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


## The percent of a hotel guest's chance to come to this kind: the restaurant takes them all, the casino and fine dining a share.
static func _guest_percent(kind: String) -> int:
	if kind == "casino":
		return CASINO_GUEST_PERCENT
	if kind == "fine_dining":
		return FINE_GUEST_PERCENT
	if kind == "pool":
		return POOL_GUEST_PERCENT
	return GUEST_PERCENT


## True when a child of this id is not for this kind (#370): school takes the odd ids (school age), and while
## a school stands the daycare keeps only the even ones, so the two share one pool without overlap.
static func school_age_split(kind: String, person_id: int, has_school: bool) -> bool:
	if kind == "school":
		return person_id % 2 == 0
	return kind == "daycare" and has_school and person_id % 2 == 1


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
		_visitors_today = 0
		_settle(floors, rooms, grid, tenancy, ledger, messages, at_tick, rng)


static func _crossed(prev: int, now: int, at: int) -> bool:
	return prev < at and at <= now


func _open_shops(floors: FloorsScript, rooms: RoomsScript, grid: GridScript, tenancy: TenancyScript) -> Array[int]:
	var shops: Array[int] = []
	var entry_x := floors.lobby_span()[0]
	for id in rooms.room_ids():
		if is_shop(rooms.kind_of(id)) and not is_vacant(id) and not rooms.is_closed_up(grid, id) and tenancy.routed(floors, rooms, grid, id, entry_x):
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
	if day != Clock.WE and bool(PROFILES[kind].get("weekends", false)):
		return
	if bool(PROFILES[kind].get("booking", false)):
		_serve_booking(kind, shops, rooms, people, rng)
		return
	if kind == PoolLifeScript.KIND and PoolLifeScript.is_cleaning(at_minute, PoolLifeScript.has_housekeeping(rooms)):
		return  # the pool is drained and being scrubbed: nobody swims
	var who: String = PROFILES[kind].get("who", WHO_ALL)
	var served: Dictionary = {}  # this meal, per shop
	var has_school := false
	if kind == "daycare":
		for id in rooms.room_ids():
			if rooms.kind_of(id) == "school":
				has_school = true
	for i in people.count():
		if people.location_of(i) == PeopleScript.NONE and people.trip_state(i) == PeopleScript.TRIP_IDLE:
			continue  # outside the tower
		if who == WHO_CHILDREN and (life == null or not life.is_child(people.id_at(i))):
			continue
		if who == WHO_CHILDREN and life != null and school_age_split(kind, people.id_at(i), has_school):
			continue
		if who == WHO_ADULTS and life != null and life.is_child(people.id_at(i)):
			continue
		if who == WHO_LOW_MOOD and people.mood_of(i) >= CLINIC_MOOD_BELOW:
			continue
		var home := people.home_of(i)
		if who == WHO_RESIDENTS and not (home != PeopleScript.NONE and rooms.has_room(home) and (rooms.kind_of(home) == "condo" or HotelScript.is_hotel_kind(rooms.kind_of(home)))):
			continue
		var guest := (kind == "restaurant" or kind == "casino" or kind == "fine_dining" or kind == "pool") and home != PeopleScript.NONE and rooms.has_room(home) and HotelScript.is_hotel_kind(rooms.kind_of(home))
		if rng.next_below(100) >= (_guest_percent(kind) if guest else percent):
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
	_visitors_today += came
	if came > 0:
		if at_minute >= _visitors_until:
			_visitors_in = 0
		_visitors_in += came
		_visitors_until = maxi(_visitors_until, at_minute + window)


## An automatic booking (#359): each open room of the kind, while its needs are met, takes its guests for the window.
## Hotel guests inside the tower come by a seeded draw up to the room's share; the outside crowd is fixed and is not
## counted as population.
func _serve_booking(kind: String, shops: Array[int], rooms: RoomsScript, people: PeopleScript, rng: Object) -> void:
	if not BookingsScript.needs_met(kind, rooms):
		return
	var profile: Dictionary = PROFILES[kind]
	var taken: Dictionary = {}
	for shop in shops:
		var guests := 0
		for i in people.count():
			if guests >= int(profile["tower_guests"]):
				break
			if taken.has(i) or (people.location_of(i) == PeopleScript.NONE and people.trip_state(i) == PeopleScript.TRIP_IDLE):
				continue
			var home := people.home_of(i)
			if home == PeopleScript.NONE or not rooms.has_room(home) or not HotelScript.is_hotel_kind(rooms.kind_of(home)):
				continue
			if rng.next_below(100) >= BOOKING_GUEST_PERCENT:
				continue
			taken[i] = true
			guests += 1
		_today[shop] = customers_today(shop) + mini(int(profile["seats"]), guests + int(profile["outside"]))


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
		if customers_today(id) == 0 and bool(PROFILES[rooms.kind_of(id)].get("booking", false)):
			amount = 0  # no booking today: the staff are paid per event (#359)
		if rooms.kind_of(id) == "casino":
			amount = casino_takings(customers_today(id), rng)
			_casino_incident(rooms, ledger, messages, at_tick, id, customers_today(id), rng)
		if rooms.kind_of(id) == PoolLifeScript.KIND:
			amount = pool_takings(customers_today(id))
		if amount > 0:  # gardens feed restaurants (synergy.gd)
			amount += amount * SynergyScript.sales_percent(rooms.kind_of(id), grid.run_of(id), sources) / 100
		if amount > 0 and DINING_FAMILY.has(rooms.kind_of(id)):  # a varied dining scene draws more
			amount += amount * dining_mix_percent(rooms) / 100
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


## The pool's takings for a day with this many swimmers: the entry money less the staff's wages (negative when empty).
static func pool_takings(swimmers: int) -> int:
	return swimmers * POOL_ENTRY - POOL_WAGES


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
		if rooms.kind_of(other) == "security" and not rooms.is_cut_off(other):
			return
	if rng.next_below(100) < CASINO_INCIDENT_PERCENT:
		ledger.payout(at_tick, CASINO_INCIDENT_COST, id)
		messages.add(at_tick, MessagesScript.CASINO_INCIDENT, id)


## One day's rent from every leased retail shop (income, like office rent; see Rent.day_share).
## Returns the total.
func collect_rent(rooms: RoomsScript, rent: RentScript, ledger: LedgerScript, at_tick: int, last_day: bool = true) -> int:
	var total := 0
	for id in rooms.room_ids():
		if rooms.kind_of(id) == "retail" and not is_vacant(id) and not rooms.is_charred(id) and not rooms.is_cut_off(id):
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
			if int(_vacant[id]) >= RELET_DAYS and floors.has_lobby() and tenancy.routed(floors, rooms, grid, id, entry_x):
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
	ints.append(_visitors_today)
	return ints


static func valid_ints(ints: Array) -> bool:
	if ints.size() < 5 or typeof(ints[3]) != TYPE_INT or ints[3] < 0:
		return false
	var at: int = 4 + 3 * ints[3]
	if ints.size() <= at or typeof(ints[at]) != TYPE_INT or ints[at] < 0 or ints.size() != at + 2 + 2 * ints[at]:
		return false
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	for k in range(4, at, 3):
		if ints[k] < 0 or ints[k + 1] < 0 or ints[k + 2] < -1:
			return false
	if ints[ints.size() - 1] < 0:
		return false
	for k in range(at + 1, ints.size() - 1, 2):
		if ints[k] < 0 or ints[k + 1] < 0:
			return false
	return ints[0] >= -1 and ints[0] < Clock.MINUTES_PER_DAY and ints[1] >= 0 and ints[2] >= 0 and ints[2] <= Clock.MINUTES_PER_DAY


func load_ints(ints: Array) -> void:
	_last_minute = ints[0]
	_visitors_in = ints[1]
	_visitors_until = ints[2]
	_visitors_today = ints[ints.size() - 1]
	_today.clear()
	_last_day.clear()
	_vacant.clear()
	var at: int = 4 + 3 * ints[3]
	for k in range(4, at, 3):
		if ints[k + 1] > 0:
			_today[ints[k]] = ints[k + 1]
		if ints[k + 2] >= 0:
			_last_day[ints[k]] = ints[k + 2]
	for k in range(at + 1, ints.size() - 1, 2):
		_vacant[ints[k]] = ints[k + 1]
