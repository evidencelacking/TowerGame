extends RefCounted
## Hotel amenities (#359): the ballroom and the conference center. The catalogue rows (star, cost, width), the
## booking windows (weekend evenings, weekdays 09:00 to 17:00), the guest counts and income, the needs (a kitchen,
## a hotel), the synergy, outside guests not counting as population, a fixed-seed three day run and save and load.
## Our own kinds: every number is a tunable.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Commerce := preload("res://scripts/sim/commerce.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Clock := preload("res://scripts/sim/clock.gd")
const Rooms := preload("res://scripts/sim/rooms.gd")
const People := preload("res://scripts/sim/people.gd")
const Synergy := preload("res://scripts/sim/synergy.gd")
const Names := preload("res://scripts/sim/names.gd")
const Bookings := preload("res://scripts/sim/bookings.gd")

const DAY_TICKS := 2550


## A tower with the kinds placed side by side on floor 3, in order, from column 108.
static func _tower(kinds: Array[String]) -> TowerSim:
	var t := TowerSim.new(42, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 199, 2)
	t.floors.fill_span(3, 100, 199)
	var x := 108
	for kind: String in kinds:
		var refusal := t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), 3, x)
		assert(refusal == 0, "%s places, refusal %d" % [kind, refusal])
		x += int(Catalogue.field(kind, "width"))
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 1, 100)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 2, 104)
	return t


static func _room(t: TowerSim, kind: String) -> int:
	for id in t.rooms.room_ids():
		if t.rooms.kind_of(id) == kind:
			return id
	return -1


## n hotel guests of the tower's hotel room, counted as inside (on a long trip).
static func _guests(t: TowerSim, n: int) -> void:
	var hotel := _room(t, "hotel_single")
	for k in n:
		var id := t.people.add_person(hotel, People.NONE, t.rng)
		t.people.start_trip(t.people.index_of(id), 600)


static func _book(t: TowerSim, kind: String, day: int) -> void:
	var meal: Array = []
	for row: Array in Commerce.MEALS:
		if row[3] == kind:
			meal = row
	t.commerce._serve(kind, meal[1], meal[2], t.floors, t.rooms, t.grid, t.people, t.tenancy, t.rng, day, meal[0], t.life)


static func run(check: Callable) -> void:
	# The rows: star, cost, width, placeable, titles, appended ids.
	var ball: Dictionary = Catalogue.row("ballroom")
	var conf: Dictionary = Catalogue.row("conference_center")
	check.call(int(ball["cost"]) == 600000 and int(ball["width"]) == 32 and Catalogue.star("ballroom") == 4, "ballroom: $600,000, 32 wide, unlocks at 4 stars")
	check.call(int(conf["cost"]) == 400000 and int(conf["width"]) == 24 and Catalogue.star("conference_center") == 3, "conference center: $400,000, 24 wide, unlocks at 3 stars")
	for kind: String in Bookings.KINDS:
		check.call(Rooms.PLACEABLE.has(kind) and Commerce.is_shop(kind) and Names.TITLES.has(kind), "%s: placeable, trades like a shop, has titles" % kind)
	var n := Catalogue.IDS.size()
	check.call(Catalogue.IDS.find("conference_center") == Catalogue.IDS.find("ballroom") + 1 and Catalogue.IDS.find("ballroom") == Catalogue.IDS.find("school") + 1, "ballroom and conference center are appended to the ids, so existing saves keep their numbering")
	var rows := {}
	for meal: Array in Commerce.MEALS:
		if Bookings.is_bookable(meal[3]):
			rows[meal[3]] = meal
	check.call(rows["ballroom"][0] == 1080 and rows["ballroom"][0] + rows["ballroom"][1] == 1380, "ballroom: the window is 18:00 to 23:00")
	check.call(rows["conference_center"][0] == 540 and rows["conference_center"][0] + rows["conference_center"][1] == 1020, "conference center: the window is 09:00 to 17:00")
	check.call(Commerce.seats_per_meal("ballroom", Commerce.BALLROOM_WINDOW) == 60 and Commerce.seats_per_meal("conference_center", Commerce.CONFERENCE_WINDOW) == 40, "one booking at a time: 60 guests and 40 delegates")

	# Booking days: the ballroom on the weekend only, the conference center on weekdays only.
	var t := _tower(["ballroom", "restaurant", "conference_center", "hotel_single"])
	var b := _room(t, "ballroom")
	var c := _room(t, "conference_center")
	_book(t, "ballroom", Clock.WD1)
	_book(t, "ballroom", Clock.WD2)
	check.call(t.commerce.customers_today(b) == 0, "ballroom: no booking on a weekday")
	_book(t, "ballroom", Clock.WE)
	check.call(t.commerce.customers_today(b) == 30, "ballroom: a weekend booking with no hotel guests brings the 30 outside guests (%d)" % t.commerce.customers_today(b))
	_book(t, "conference_center", Clock.WE)
	check.call(t.commerce.customers_today(c) == 0, "conference center: no booking at the weekend")
	_book(t, "conference_center", Clock.WD1)
	check.call(t.commerce.customers_today(c) == 40, "conference center: a weekday booking brings 40 delegates (%d)" % t.commerce.customers_today(c))

	# Outside guests are visitors, not population.
	check.call(t.commerce.visitors_today() == 0 and t.commerce.visitors_inside(Commerce.BALLROOM_EVENING + 10) == 0, "outside guests are not counted in the population")

	# Guests and income: hotel guests of the tower fill the other half, up to 30; the fee follows the guest count.
	var g := _tower(["ballroom", "restaurant", "hotel_single"])
	_guests(g, 80)
	_book(g, "ballroom", Clock.WE)
	var gb := _room(g, "ballroom")
	var full := g.commerce.customers_today(gb)
	check.call(full > 30 and full <= 60, "ballroom: hotel guests join the outside crowd, never past 60 (%d)" % full)
	check.call(Commerce.income_for("ballroom", 30) == 10000 and Commerce.income_for("ballroom", 60) == 24000 and Commerce.income_for("ballroom", 0) == 0, "ballroom: paid per booking by guests, $10,000 at 30 and $24,000 at 60")
	check.call(Commerce.income_for("conference_center", 40) == 12000 and Commerce.income_for("conference_center", 0) == 0, "conference center: $12,000 for 40 delegates, nothing when not booked")
	var before := g.ledger.balance
	g.commerce._settle(g.floors, g.rooms, g.grid, g.tenancy, g.ledger, g.messages, 0, g.rng)
	var restaurant_loss := Commerce.income_for("restaurant", 0)
	check.call(g.ledger.balance - before == Commerce.income_for("ballroom", full) + restaurant_loss, "ballroom: settlement pays the booking fee (%d)" % (g.ledger.balance - before))
	before = g.ledger.balance
	g.commerce._settle(g.floors, g.rooms, g.grid, g.tenancy, g.ledger, g.messages, 0, g.rng)
	check.call(g.ledger.balance - before == restaurant_loss, "ballroom: a day with no booking earns and costs nothing")

	# Needs: the ballroom a kitchen, the conference center a hotel.
	var bare := _tower(["ballroom", "conference_center"])
	_book(bare, "ballroom", Clock.WE)
	_book(bare, "conference_center", Clock.WD1)
	check.call(bare.commerce.customers_today(_room(bare, "ballroom")) == 0 and bare.commerce.customers_today(_room(bare, "conference_center")) == 0, "needs: with no kitchen and no hotel, neither room is booked")
	check.call(not Bookings.needs_met("ballroom", bare.rooms) and not Bookings.needs_met("conference_center", bare.rooms), "needs: reported unmet")
	var fine := _tower(["ballroom", "fine_dining"])
	check.call(Bookings.needs_met("ballroom", fine.rooms), "needs: a fine dining room is a kitchen too")
	var kitchen := _tower(["ballroom", "restaurant"])
	_book(kitchen, "ballroom", Clock.WE)
	check.call(kitchen.commerce.customers_today(_room(kitchen, "ballroom")) == 30, "needs: a restaurant lets the ballroom take bookings")
	var hotel := _tower(["conference_center", "hotel_single"])
	_book(hotel, "conference_center", Clock.WD2)
	check.call(hotel.commerce.customers_today(_room(hotel, "conference_center")) == 40, "needs: a hotel room lets the conference center take bookings")
	check.call(not Bookings.needs_met("conference_center", _tower(["conference_center", "restaurant"]).rooms), "needs: a restaurant is not a hotel")

	# Synergy.
	var hotel_run := [5, 100, 4]
	var restaurant_run := [5, 100, 24]
	var ballroom_src := [["ballroom", [3, 100, 32]]]
	var conf_src := [["conference_center", [3, 100, 24]]]
	check.call(Synergy.rent_percent(conf_src) == 6, "synergy: a conference center adds 6 percent to office rents")
	check.call(Synergy.rent_percent(ballroom_src) == 0, "synergy: a ballroom does not touch rents")
	check.call(Synergy.sales_percent("restaurant", restaurant_run, ballroom_src) == 6, "synergy: a ballroom adds 6 percent to a restaurant's sales within 10 floors")
	check.call(Synergy.sales_percent("restaurant", [20, 100, 24], ballroom_src) == 0, "synergy: a ballroom 17 floors away adds nothing")
	check.call(Synergy.mood_delta("hotel_single", hotel_run, ballroom_src) == 2 and Synergy.mood_delta("hotel_single", hotel_run, conf_src) == 3, "synergy: hotel mood +2 from a ballroom and +3 from a conference center")
	check.call(Synergy.mood_delta("hotel_single", hotel_run, ballroom_src + conf_src) == 5, "synergy: the two add up")
	check.call(Synergy.rent_percent(conf_src + [["metro", [1, 100, 8]]]) == 21, "synergy: the rent lift adds to the metro's, under the cap of 30")
	check.call(Synergy.demand_percent([8, 100, 8], conf_src) == 0, "synergy: a conference center does not touch condo prices")

	# A fixed-seed three day run (WD1, WD2, WE): each room trades on its own days, and a second run agrees.
	var a := _tower(["ballroom", "restaurant", "conference_center", "hotel_single"])
	var d := _tower(["ballroom", "restaurant", "conference_center", "hotel_single"])
	var conf_days: Array[int] = []
	var ball_days: Array[int] = []
	_guests(a, 40)
	_guests(d, 40)
	a.clock.set_to_tick(0)
	d.clock.set_to_tick(0)
	for day in 3:
		for k in DAY_TICKS:
			a.step()
			d.step()
		conf_days.append(a.commerce.customers_last_day(_room(a, "conference_center")))
		ball_days.append(a.commerce.customers_last_day(_room(a, "ballroom")))
	check.call(conf_days[0] > 0 and conf_days[1] > 0 and conf_days[2] == 0, "run: the conference center trades on the weekdays only (%s)" % str(conf_days))
	check.call(ball_days[0] == 0 and ball_days[1] == 0 and ball_days[2] >= 30, "run: the ballroom trades at the weekend only (%s)" % str(ball_days))
	check.call(a.state_hash() == d.state_hash(), "run: two runs of the seeded days agree")

	# Saves still load, with the booking days kept.
	var copy := TowerSim.new(1, 1)
	check.call(copy.load_state(a.save()) and copy.state_hash() == a.state_hash(), "a tower with both rooms survives save and load")
	check.call(copy.commerce.customers_last_day(_room(copy, "ballroom")) == ball_days[2], "save: the ballroom's last day is kept")
